-- Pairs of consecutive Reset datum auxiliary records, at most 1 hour apart, with no datum between
-- them, grouped by account owner (see NET-540). The hourly rollup counts the accumulation between
-- such a pair twice when both fall between the end of an hour and the next datum.
--
-- One row per pair, ordered by owner, node, source, and time. The reset JSON data is not included.
-- The `crosses_hour_end` column is TRUE when the pair is in the shape that is double counted: the
-- datum before the pair is in an earlier hour than the first reset, or the first reset is exactly
-- on the hour.
WITH r AS (
	SELECT stream_id
		, ts
		, updated
		, notes
		, lead(ts) OVER w AS next_ts
		, lead(updated) OVER w AS next_updated
		, lead(notes) OVER w AS next_notes
	FROM solardatm.da_datm_aux
	WHERE atype = 'Reset'::solardatm.da_datm_aux_type
	WINDOW w AS (PARTITION BY stream_id ORDER BY ts)
)
, pairs AS (
	SELECT r.*
	FROM r
	WHERE r.next_ts IS NOT NULL
		AND r.next_ts - r.ts <= INTERVAL 'PT1H'
		AND NOT EXISTS (
			SELECT 1
			FROM solardatm.da_datm d
			WHERE d.stream_id = r.stream_id
				AND d.ts > r.ts
				AND d.ts < r.next_ts
		)
)
SELECT u.id AS user_id
	, u.email
	, u.disp_name AS user_name
	, m.node_id
	, m.source_id
	, p.stream_id
	, p.ts AS reset_1_ts
	, p.next_ts AS reset_2_ts
	, p.next_ts - p.ts AS reset_gap
	, db.ts AS datum_before_ts
	, da.ts AS datum_after_ts
	, (db.ts IS NOT NULL AND date_trunc('hour', db.ts) < date_trunc('hour', p.ts))
		OR date_trunc('hour', p.ts) = p.ts AS crosses_hour_end
	, p.updated AS reset_1_updated
	, p.next_updated AS reset_2_updated
	, p.notes AS reset_1_notes
	, p.next_notes AS reset_2_notes
FROM pairs p
INNER JOIN solardatm.da_datm_meta m ON m.stream_id = p.stream_id
LEFT OUTER JOIN solaruser.user_node un ON un.node_id = m.node_id
LEFT OUTER JOIN solaruser.user_user u ON u.id = un.user_id
LEFT OUTER JOIN LATERAL (
	-- within a year, and by time alone, so only the chunks in range are scanned
	SELECT d.ts
	FROM solardatm.da_datm d
	WHERE d.stream_id = p.stream_id
		AND d.ts <= p.ts
		AND d.ts > p.ts - INTERVAL 'P1Y'
	ORDER BY d.ts DESC
	LIMIT 1
) db ON TRUE
LEFT OUTER JOIN LATERAL (
	SELECT d.ts
	FROM solardatm.da_datm d
	WHERE d.stream_id = p.stream_id
		AND d.ts >= p.next_ts
		AND d.ts < p.next_ts + INTERVAL 'P1Y'
	ORDER BY d.ts
	LIMIT 1
) da ON TRUE
ORDER BY u.email, m.node_id, m.source_id, p.ts
