--explain analyze
SELECT * FROM solardatm.find_datm_for_time_span_with_aux(
	'ade25d3b-faa1-4df8-8c99-bb24b58635ac'::uuid,
	'2020-05-14 13:00:00+12'::timestamptz,
	'2020-05-14 13:00:00+12'::timestamptz + INTERVAL '1 hour'
	);

CREATE OR REPLACE FUNCTION solardatm.find_datm_for_time_span_with_aux(
		sid uuid,
		start_ts TIMESTAMP WITH TIME ZONE,
		end_ts TIMESTAMP WITH TIME ZONE,
		tolerance_clock INTERVAL DEFAULT interval '1 hour',
		tolerance_read INTERVAL DEFAULT interval '3 months'
	) RETURNS TABLE(
		stream_id 	UUID,
		ts 			TIMESTAMP WITH TIME ZONE,
		data_i		NUMERIC[],
		data_a		NUMERIC[],
		data_s		TEXT[],
		data_t		TEXT[],
		inclusion	SMALLINT,
		portion		DOUBLE PRECISION
	) LANGUAGE SQL STABLE ROWS 2000 AS
$$
	WITH b AS (
		(
		-- latest on/before start
		SELECT d.stream_id, d.ts
		FROM solardatm.da_datm d
		WHERE d.stream_id = sid
			AND d.ts <= start_ts
			AND d.ts > start_ts - tolerance_read
		ORDER BY d.stream_id, d.ts DESC
		LIMIT 1
		)
		UNION ALL
		(
		-- earliest on/after end
		SELECT d.stream_id, d.ts
		FROM solardatm.da_datm d
		WHERE d.stream_id = sid
			AND d.ts >= end_ts
			AND d.ts < end_ts + tolerance_clock
		ORDER BY d.stream_id, d.ts
		LIMIT 1
		)
	)
	, r AS (
		SELECT
			stream_id
			, COALESCE(min(ts), start_ts) AS range_start
			, COALESCE(max(ts), end_ts) AS range_end
		FROM b
		GROUP BY stream_id
	)
	, d AS (
		SELECT
			  d.stream_id
			, d.ts
			, d.data_i
			, d.data_a
			, d.data_s
			, d.data_t
			, CASE
				WHEN d.ts < start_ts THEN -1::SMALLINT
				WHEN d.ts >= end_ts THEN 1::SMALLINT
				ELSE 0::SMALLINT
				END AS inclusion
			, CASE
				WHEN d.ts < start_ts THEN
					1 - EXTRACT(epoch FROM (start_ts - d.ts)) / EXTRACT(epoch FROM (lead(d.ts) OVER slot - d.ts))
				WHEN d.ts > end_ts THEN
					0
				WHEN lead(d.ts) OVER slot > end_ts THEN
					EXTRACT(epoch FROM (end_ts - d.ts)) / EXTRACT(epoch FROM (lead(d.ts) OVER slot - d.ts))
				ELSE 1
				END AS portion
			, 0 AS rr
		FROM r
		INNER JOIN solardatm.da_datm d ON d.stream_id = r.stream_id
		WHERE d.ts >= r.range_start
			AND d.ts <= r.range_end
		WINDOW slot AS (PARTITION BY d.stream_id ORDER BY d.ts RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
	)
	, aux AS (
		SELECT
			  m.stream_id
			, aux.ts - unnest(ARRAY['1 millisecond','0'])::interval AS ts
			, m.names_a
			, unnest(ARRAY[aux.jdata_af, aux.jdata_as]) AS jdata_a
		FROM solardatm.da_datm_aux aux
		INNER JOIN solardatm.da_datm_meta m ON m.stream_id = aux.stream_id
		WHERE aux.atype = 'Reset'::solardatum.da_datum_aux_type
			AND aux.stream_id = sid
			AND aux.ts >= start_ts - tolerance_read
			AND aux.ts <= end_ts + tolerance_read
	)
	, resets AS (
		SELECT
			  aux.stream_id
			, aux.ts
			, NULL AS data_i
			, array_agg(p.val::text::numeric ORDER BY array_position(aux.names_a, p.key::text))
				FILTER (WHERE array_position(aux.names_a, p.key::text) IS NOT NULL)  AS data_a
			, NULL AS data_s
			, NULL AS data_t
			, CASE
				WHEN aux.ts < start_ts THEN -1::SMALLINT
				WHEN aux.ts >= end_ts THEN 1::SMALLINT
				ELSE 0::SMALLINT
				END AS inclusion
			, CASE
				WHEN aux.ts < start_ts THEN
					1 - EXTRACT(epoch FROM (start_ts - aux.ts)) / EXTRACT(epoch FROM (lead(aux.ts) OVER slot - aux.ts))
				WHEN aux.ts > end_ts THEN
					0
				WHEN lead(aux.ts) OVER slot > end_ts THEN
					EXTRACT(epoch FROM (end_ts - aux.ts)) / EXTRACT(epoch FROM (lead(aux.ts) OVER slot - aux.ts))
				ELSE 1
				END AS portion
			, 1 AS rr
		FROM aux
		INNER JOIN jsonb_each(aux.jdata_a) AS p(key,val) ON TRUE
		GROUP BY aux.stream_id, aux.ts
		WINDOW slot AS (PARTITION BY aux.stream_id ORDER BY aux.ts RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
	)
	, combined AS (
		SELECT * FROM d
		UNION ALL
		SELECT * FROM resets
	)
	-- add order by rr so that when datum & reset have equivalent ts, reset has priority
	SELECT DISTINCT ON (stream_id, ts) stream_id, ts, data_i, data_a, data_s, data_t, inclusion, portion
	FROM combined
	ORDER BY stream_id, ts, rr DESC
$$;
