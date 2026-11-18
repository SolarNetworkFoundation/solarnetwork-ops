/* ============================================================================
 * NET-540 verification: candidate functions for the 15 minute aggregate, under
 * names ending in _net540, so they can be compared with the live hourly rollup
 * on production before any of NET-540 is deployed. Used by net540-verify.sh.
 *
 *   solardatm.rollup_datm_for_time_span_net540     the live hourly rollup, with
 *                                                  the fix for two reset records
 *                                                  after the end of the hour
 *   solardatm.rollup_datm_15m_for_hour_net540      the 15 minute rows of one
 *                                                  hour, from the same rows,
 *                                                  differences and portions as
 *                                                  the function above
 *   solardatm.rollup_agg_data_15m_net540           the hour rolled up from those
 *                                                  15 minute rows, as days are
 *                                                  rolled up from hours
 *
 * Generated from solarnetwork-central at commit fd1a39f05:
 *
 *   - the first is rollup_datm_for_time_span() from
 *     solarnet-db-setup/postgres/postgres-init-datm-agg-query.sql. The only
 *     changes are its name and one added WHEN branch in the portion CASE.
 *   - the second is the prototype described in the NET-540 plan, with the same
 *     WHEN branch. Its CTEs m, d and wa are those of the first function.
 *   - the third is rollup_agg_data_for_time_span() from the same file. The only
 *     changes are its name, the dropped "kind" argument, and that it reads the
 *     rows of the second function instead of a table.
 *
 * Regenerate this file if the live functions change. Nothing calls these
 * functions, and they write nothing. Remove them with:
 *
 * DROP FUNCTION solardatm.rollup_agg_data_15m_net540(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE);
 * DROP FUNCTION solardatm.rollup_datm_15m_for_hour_net540(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, INTERVAL, INTERVAL);
 * DROP FUNCTION solardatm.rollup_datm_for_time_span_net540(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, INTERVAL, INTERVAL);
 * ============================================================================
 */

/**
 * NET-540 candidate: solardatm.rollup_datm_for_time_span() with one added branch,
 * so that a difference between two rows that are both at or after the end of the
 * slot is not counted in this slot.
 */
CREATE OR REPLACE FUNCTION solardatm.rollup_datm_for_time_span_net540(
		sid 			UUID,
		start_ts 		TIMESTAMP WITH TIME ZONE,
		end_ts 			TIMESTAMP WITH TIME ZONE,
		tolerance_clock INTERVAL DEFAULT INTERVAL 'PT1H',
		tolerance_read 	INTERVAL DEFAULT INTERVAL 'P1Y'
	) RETURNS SETOF solardatm.agg_datm LANGUAGE SQL STABLE ROWS 500 AS
$$
	WITH m AS (
		SELECT COALESCE(array_length(names_i, 1), 0) AS len_i
			 , COALESCE(array_length(names_a, 1), 0) AS len_a
		FROM solardatm.find_metadata_for_stream(sid)
	)
	-- grab raw data + reset records, constrained by stream/date range
	, d AS (
		SELECT
			  stream_id
			, ts
			, pad_vec(data_i, len_i) AS data_i
			, pad_vec(data_a, len_a) AS data_a
			, data_s
			, data_t
			, rtype
			, (ts >= start_ts AND ts < end_ts) AS inc
		FROM m, solardatm.find_datm_for_time_slot(
			sid,
			start_ts,
			end_ts,
			tolerance_read
		)
	)
	-- calculate instantaneous statistis per property
	, di_ary AS (
		SELECT
			  vec_trim_scale(vec_agg_mean(d.data_i)) AS data_i
			, solarcommon.array_transpose2d(ARRAY[
				  vec_agg_count(d.data_i)::numeric[]
				, vec_agg_min(d.data_i)
				, vec_agg_max(d.data_i)
			  ]) AS stat_i
		FROM d
		WHERE d.inc
	)
	-- calculate clock accumulation for data_a values per property
	-- NOTE "unnest() WITH ORDINALITY" not used because of possible sparse array slice
	, wa AS (
		SELECT
			  p.idx
			, d.data_a[p.idx] AS val
			, d.ts
			, d.rtype
			, COALESCE(CASE
				WHEN rtype <> 2 THEN d.data_a[p.idx] - lag(d.data_a[p.idx]) OVER slot
				ELSE 0::numeric
				END, 0)::numeric AS diff
			, CASE
				-- too much time between rows for clock diff, or no time passed
				WHEN d.ts - lag(d.ts) OVER slot > tolerance_clock OR d.ts = lag(d.ts) OVER slot
					THEN 0

				-- before bounds
				WHEN d.ts < start_ts
					THEN 0

				-- crossing start of slot; allocate only end portion of accumulation within this slot
				WHEN lag(d.ts) OVER slot < start_ts
					THEN EXTRACT('epoch' FROM d.ts - start_ts) / EXTRACT('epoch' FROM d.ts - lag(d.ts) OVER slot)

				-- crossing end of slot; allocate only start portion of accumulation within this slot
				WHEN d.ts > end_ts AND lag(d.ts) OVER slot < end_ts
					THEN EXTRACT('epoch' FROM end_ts - lag(d.ts) OVER slot) / EXTRACT('epoch' FROM d.ts - lag(d.ts) OVER slot)

				-- both rows at or after the end of the slot: the difference belongs to a later slot
				-- (two reset records after the end, before the next datum; see NET-540)
				WHEN lag(d.ts) OVER slot >= end_ts
					THEN 0

				ELSE 1
				END as portion
			, (ts < end_ts AND NOT (ts <= start_ts AND rtype = 1)
				OR (ts = end_ts AND rtype < 2)) AS rinc
		FROM d
		INNER JOIN generate_series(1, array_upper(d.data_a, 1)) AS p(idx) ON TRUE
		WINDOW slot AS (PARTITION BY p.idx ORDER BY CASE WHEN d.data_a[p.idx] IS NULL THEN 1 ELSE 0 END, d.ts, d.rtype
			RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
	)
	-- calculate accumulating statistics
	, da AS (
		SELECT
			  idx
			, sum(diff * portion::numeric) AS cdiff
			, sum(diff) FILTER (WHERE rinc) AS rdiff
			, solarcommon.first(val ORDER BY ts, rtype) FILTER (WHERE rinc) AS rstart
			, solarcommon.first(val ORDER BY ts DESC, rtype DESC) FILTER (WHERE rinc) AS rend
		FROM wa
		GROUP BY idx
	)
	-- join accumulating property values back into arrays
	, da_ary AS (
		SELECT
			  vec_trim_scale(array_agg(cdiff ORDER BY idx)) AS data_a
			, array_agg(
				ARRAY[rdiff, rstart, rend] ORDER BY idx
			) AS read_a
		FROM da
	)
	-- calculate status for data_s values per property
	-- NOTE "unnest() WITH ORDINALITY" not used because of possible sparse array slice
	, ws AS (
		SELECT
			  p.idx AS idx
			, d.data_s[p.idx] AS val
		FROM d
		INNER JOIN generate_series(1, array_upper(d.data_s, 1)) AS p(idx) ON TRUE
		WHERE d.data_s IS NOT NULL AND d.inc
	)
	-- calculate status statistics, as most-frequent status values
	, ds AS (
		SELECT
			  ws.idx
			, mode() WITHIN GROUP (ORDER BY ws.val) AS val
		FROM ws
		GROUP BY ws.idx
	)
	-- join data_s property values back into arrays
	, ds_ary AS (
		SELECT
			  array_agg(d.val ORDER BY d.idx) AS data_s
		FROM ds d
	)
	-- join data_t property values into mega array
	, dt_ary AS (
		SELECT
			  array_agg(DISTINCT p.val) AS data_t
		FROM d
		INNER JOIN unnest(d.data_t) AS p(val) ON TRUE
		WHERE d.data_t IS NOT NULL AND d.inc
	)
	SELECT
		sid AS stream_id
		, start_ts AS ts_start
		, di_ary.data_i
		, da_ary.data_a
		, ds_ary.data_s
		, dt_ary.data_t
		, di_ary.stat_i
		, da_ary.read_a
	FROM di_ary, da_ary, ds_ary, dt_ary
	WHERE data_i IS NOT NULL OR data_a IS NOT NULL OR data_s IS NOT NULL OR data_t IS NOT NULL
$$;


/**
 * NET-540 candidate: compute the 15 minute rollup rows of one hour, from exactly
 * the rows and the per-row differences and portions that the hourly rollup above
 * uses for that hour.
 *
 * Each contribution to the hour is given to one or two of the hour's slots, so the
 * slots add up to the hour:
 *
 *  - clock accumulation between two rows goes to the slot of the earlier row, up to
 *    the start of the slot of the later row; the later row's slot gets the remainder
 *    of the hour's portion
 *  - a contribution that crosses the start of the hour goes to the slot of the later
 *    row, and one that crosses the end of the hour to the slot of the earlier row
 *  - a reading difference goes to the slot of its row; a row exactly at the end of
 *    the hour counts in the last slot holding a row (or the last slot of the hour
 *    if none does)
 *
 * @param sid 				the stream ID to find datm for
 * @param start_ts			the start of the hour (inclusive)
 * @param end_ts 			the end of the hour (exclusive)
 * @param tolerance_clock 	as for the hourly rollup
 * @param tolerance_read 	as for the hourly rollup
 */
CREATE OR REPLACE FUNCTION solardatm.rollup_datm_15m_for_hour_net540(
		sid 			UUID,
		start_ts 		TIMESTAMP WITH TIME ZONE,
		end_ts 			TIMESTAMP WITH TIME ZONE,
		tolerance_clock INTERVAL DEFAULT INTERVAL 'PT1H',
		tolerance_read 	INTERVAL DEFAULT INTERVAL 'P1Y'
	) RETURNS SETOF solardatm.agg_datm LANGUAGE SQL STABLE ROWS 4 AS
$$
	WITH m AS (
		SELECT COALESCE(array_length(names_i, 1), 0) AS len_i
			 , COALESCE(array_length(names_a, 1), 0) AS len_a
		FROM solardatm.find_metadata_for_stream(sid)
	)
	, d AS (
		SELECT
			  stream_id
			, ts
			, pad_vec(data_i, len_i) AS data_i
			, pad_vec(data_a, len_a) AS data_a
			, data_s
			, data_t
			, rtype
			, (ts >= start_ts AND ts < end_ts) AS inc
		FROM m, solardatm.find_datm_for_time_slot(
			sid,
			start_ts,
			end_ts,
			tolerance_read
		)
	)
	-- slots of the hour holding a datum or reset record
	, occ AS (
		SELECT DISTINCT time_bucket(INTERVAL 'PT15M', d.ts) AS slot
		FROM d
		WHERE d.inc
	)
	, edge AS (
		SELECT COALESCE(min(slot), end_ts - INTERVAL 'PT15M') AS first_slot
			 , COALESCE(max(slot), end_ts - INTERVAL 'PT15M') AS last_slot
		FROM occ
	)
	, di_ary AS (
		SELECT
			  time_bucket(INTERVAL 'PT15M', d.ts) AS slot
			, vec_trim_scale(vec_agg_mean(d.data_i)) AS data_i
			, solarcommon.array_transpose2d(ARRAY[
				  vec_agg_count(d.data_i)::numeric[]
				, vec_agg_min(d.data_i)
				, vec_agg_max(d.data_i)
			  ]) AS stat_i
		FROM d
		WHERE d.inc
		GROUP BY 1
	)
	, wa AS (
		SELECT
			  p.idx
			, d.data_a[p.idx] AS val
			, d.ts
			, d.rtype
			, COALESCE(CASE
				WHEN rtype <> 2 THEN d.data_a[p.idx] - lag(d.data_a[p.idx]) OVER slot
				ELSE 0::numeric
				END, 0)::numeric AS diff
			, CASE
				WHEN d.ts - lag(d.ts) OVER slot > tolerance_clock OR d.ts = lag(d.ts) OVER slot
					THEN 0
				WHEN d.ts < start_ts
					THEN 0
				WHEN lag(d.ts) OVER slot < start_ts
					THEN EXTRACT('epoch' FROM d.ts - start_ts) / EXTRACT('epoch' FROM d.ts - lag(d.ts) OVER slot)
				WHEN d.ts > end_ts AND lag(d.ts) OVER slot < end_ts
					THEN EXTRACT('epoch' FROM end_ts - lag(d.ts) OVER slot) / EXTRACT('epoch' FROM d.ts - lag(d.ts) OVER slot)
				WHEN lag(d.ts) OVER slot >= end_ts
					THEN 0
				ELSE 1
				END as portion
			, (ts < end_ts AND NOT (ts <= start_ts AND rtype = 1)
				OR (ts = end_ts AND rtype < 2)) AS rinc
			, lag(d.ts) OVER slot AS p_ts
		FROM d
		INNER JOIN generate_series(1, array_upper(d.data_a, 1)) AS p(idx) ON TRUE
		WINDOW slot AS (PARTITION BY p.idx ORDER BY CASE WHEN d.data_a[p.idx] IS NULL THEN 1 ELSE 0 END, d.ts, d.rtype
			RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
	)
	-- the slots of each row and of the row before it, when they are within the hour
	, wb AS (
		SELECT wa.*
			, wa.portion::numeric AS hp
			, CASE WHEN wa.ts >= start_ts AND wa.ts < end_ts THEN time_bucket(INTERVAL 'PT15M', wa.ts) END AS c_slot
			, CASE WHEN wa.p_ts >= start_ts AND wa.p_ts < end_ts THEN time_bucket(INTERVAL 'PT15M', wa.p_ts) END AS p_slot
		FROM wa
	)
	-- the earlier row's share of the hour's portion, when the two rows are in different slots of the hour
	, wc AS (
		SELECT wb.*
			, CASE
				WHEN p_slot IS NOT NULL AND c_slot IS NOT NULL AND c_slot > p_slot
					THEN (EXTRACT('epoch' FROM c_slot - p_ts) / EXTRACT('epoch' FROM ts - p_ts))::numeric
				END AS p_share
		FROM wb
		WHERE hp <> 0
	)
	, alloc AS (
		-- to the slot of the earlier row
		SELECT idx, p_slot AS slot, diff * COALESCE(p_share, hp) AS amt
		FROM wc
		WHERE p_slot IS NOT NULL AND (c_slot IS NULL OR c_slot > p_slot)

		UNION ALL

		-- to the slot of the later row: everything, or the remainder after the earlier row's share
		SELECT idx, c_slot AS slot, diff * (hp - COALESCE(p_share, 0)) AS amt
		FROM wc
		WHERE c_slot IS NOT NULL

		UNION ALL

		-- neither row is within the hour
		SELECT idx, edge.last_slot AS slot, diff * hp AS amt
		FROM wc, edge
		WHERE p_slot IS NULL AND c_slot IS NULL
	)
	, ca AS (
		SELECT idx, slot, sum(amt) AS cdiff
		FROM alloc
		GROUP BY idx, slot
	)
	, rd AS (
		SELECT wa.idx
			, CASE
				WHEN wa.ts < start_ts THEN edge.first_slot
				WHEN wa.ts < end_ts THEN time_bucket(INTERVAL 'PT15M', wa.ts)
				ELSE edge.last_slot
				END AS slot
			, wa.val
			, wa.diff
			, wa.ts
			, wa.rtype
		FROM wa, edge
		WHERE wa.rinc
	)
	, ra AS (
		SELECT idx, slot
			, sum(diff) AS rdiff
			, solarcommon.first(val ORDER BY ts, rtype) AS rstart_first
			, solarcommon.first(val - diff ORDER BY ts, rtype) AS rstart_later
			, solarcommon.first(val ORDER BY ts DESC, rtype DESC) AS rend
			, slot = min(slot) OVER (PARTITION BY idx) AS is_first
		FROM rd
		GROUP BY idx, slot
	)
	, slots AS (
		SELECT slot FROM occ
		UNION
		SELECT slot FROM ca
		UNION
		SELECT slot FROM ra
	)
	, da_ary AS (
		SELECT s.slot
			, CASE WHEN count(ca.idx) + count(ra.idx) > 0 THEN
				vec_trim_scale(array_agg(
					CASE WHEN ca.cdiff IS NOT NULL THEN ca.cdiff WHEN ra.rend IS NOT NULL THEN 0 END
					ORDER BY p.idx))
				END AS data_a
			, CASE WHEN count(ra.idx) > 0 THEN
				array_agg(ARRAY[
					  ra.rdiff
					, CASE WHEN ra.is_first THEN ra.rstart_first ELSE ra.rstart_later END
					, ra.rend
				] ORDER BY p.idx)
				END AS read_a
		FROM slots s
		CROSS JOIN m
		CROSS JOIN generate_series(1, m.len_a) AS p(idx)
		LEFT OUTER JOIN ca ON ca.slot = s.slot AND ca.idx = p.idx
		LEFT OUTER JOIN ra ON ra.slot = s.slot AND ra.idx = p.idx
		GROUP BY s.slot
	)
	, ws AS (
		SELECT
			  time_bucket(INTERVAL 'PT15M', d.ts) AS slot
			, p.idx AS idx
			, d.data_s[p.idx] AS val
		FROM d
		INNER JOIN generate_series(1, array_upper(d.data_s, 1)) AS p(idx) ON TRUE
		WHERE d.data_s IS NOT NULL AND d.inc
	)
	, ds AS (
		SELECT ws.slot, ws.idx, mode() WITHIN GROUP (ORDER BY ws.val) AS val
		FROM ws
		GROUP BY ws.slot, ws.idx
	)
	, ds_ary AS (
		SELECT slot, array_agg(val ORDER BY idx) AS data_s
		FROM ds
		GROUP BY slot
	)
	, dt_ary AS (
		SELECT time_bucket(INTERVAL 'PT15M', d.ts) AS slot
			, array_agg(DISTINCT p.val) AS data_t
		FROM d
		INNER JOIN unnest(d.data_t) AS p(val) ON TRUE
		WHERE d.data_t IS NOT NULL AND d.inc
		GROUP BY 1
	)
	SELECT
		  sid AS stream_id
		, slots.slot AS ts_start
		, di_ary.data_i
		, da_ary.data_a
		, ds_ary.data_s
		, dt_ary.data_t
		, di_ary.stat_i
		, da_ary.read_a
	FROM slots
	LEFT OUTER JOIN di_ary ON di_ary.slot = slots.slot
	LEFT OUTER JOIN da_ary ON da_ary.slot = slots.slot
	LEFT OUTER JOIN ds_ary ON ds_ary.slot = slots.slot
	LEFT OUTER JOIN dt_ary ON dt_ary.slot = slots.slot
	WHERE di_ary.data_i IS NOT NULL OR da_ary.data_a IS NOT NULL
		OR ds_ary.data_s IS NOT NULL OR dt_ary.data_t IS NOT NULL
$$;


/**
 * NET-540 candidate: the hour rolled up from its 15 minute rows, with the logic of
 * solardatm.rollup_agg_data_for_time_span().
 *
 * @param sid 				the stream ID to find datm for
 * @param start_ts			the start of the hour (inclusive)
 * @param end_ts 			the end of the hour (exclusive)
 */
CREATE OR REPLACE FUNCTION solardatm.rollup_agg_data_15m_net540(
		sid 			UUID,
		start_ts 		TIMESTAMP WITH TIME ZONE,
		end_ts 			TIMESTAMP WITH TIME ZONE
	) RETURNS SETOF solardatm.agg_datm LANGUAGE SQL STABLE ROWS 500 AS
$$
	WITH d AS (
		SELECT * FROM solardatm.rollup_datm_15m_for_hour_net540(
			sid,
			start_ts,
			end_ts
		)
	)
	-- calculate instantaneous values per property
	, wi AS (
		SELECT
			  p.idx
			, d.data_i[p.idx] AS val
			, d.stat_i[p.idx][1] AS cnt
			, d.stat_i[p.idx][2] AS min
			, d.stat_i[p.idx][3] AS max
		FROM d
		INNER JOIN generate_series(1, array_upper(d.data_i, 1)) AS p(idx) ON TRUE
	)
	-- calculate instantaneous statistics
	, di AS (
		SELECT
			idx
			, sum(val * cnt) AS val
			, sum(cnt) AS cnt
			, min(min) AS val_min
			, max(max) AS val_max
		FROM wi
		GROUP BY idx
	)
	-- join data_i and stat_i property values back into arrays
	, di_ary AS (
		SELECT
			  vec_trim_scale(array_agg(val / cnt ORDER BY idx)) AS data_i
			, array_agg(
				ARRAY[cnt, val_min, val_max] ORDER BY idx
			) AS stat_i
		FROM di
	)
	-- calculate accumulating values per property
	, wa AS (
		SELECT
			  p.idx
			, d.data_a[p.idx] AS val
			, d.read_a[p.idx][1] AS rdiff
			, first_value(d.read_a[p.idx][2]) OVER slot_start AS rstart
			, first_value(d.read_a[p.idx][3]) OVER slot_end AS rend
		FROM d
		INNER JOIN generate_series(1, array_upper(d.data_a, 1)) AS p(idx) ON TRUE
		WINDOW slot_start AS (PARTITION BY p.idx ORDER BY CASE WHEN d.data_a[p.idx] IS NULL THEN 1 ELSE 0 END, d.ts_start
				RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING),
			slot_end AS (PARTITION BY p.idx ORDER BY CASE WHEN d.data_a[p.idx] IS NULL THEN 1 ELSE 0 END, d.ts_start DESC
				RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
	)
	-- calculate accumulating statistics
	, da AS (
		SELECT
			idx
			, sum(val) AS val
			, sum(rdiff) AS rdiff
			, min(rstart) AS rstart
			, min(rend) AS rend
		FROM wa
		GROUP BY idx
	)
	-- join data_a and read_a property values back into arrays
	, da_ary AS (
		SELECT
			  vec_trim_scale(array_agg(val ORDER BY idx)) AS data_a
			, array_agg(
				ARRAY[rdiff, rstart, rend] ORDER BY idx
			) AS read_a
		FROM da
	)
	-- calculate status for data_s values per property
	, ws AS (
		SELECT
			  p.idx AS idx,
			  d.data_s[p.idx] AS val
		FROM d
		INNER JOIN generate_series(1, array_upper(d.data_s, 1)) AS p(idx) ON TRUE
		WHERE d.data_s IS NOT NULL
	)
	-- calculate status statistics, as most-frequent status values
	, ds AS (
		SELECT
			  ws.idx
			, mode() WITHIN GROUP (ORDER BY ws.val) AS val
		FROM ws
		GROUP BY ws.idx
	)
	-- join data_s property values back into arrays
	, ds_ary AS (
		SELECT
			  array_agg(val ORDER BY idx) AS data_s
		FROM ds
	)
	-- join data_t property values into mega array
	, dt_ary AS (
		SELECT
			  array_agg(DISTINCT p.val) AS data_t
		FROM d
		INNER JOIN unnest(d.data_t) AS p(val) ON TRUE
		WHERE d.data_t IS NOT NULL
	)
	SELECT
		sid AS stream_id,
		start_ts AS ts_start
		, di_ary.data_i
		, da_ary.data_a
		, ds_ary.data_s
		, dt_ary.data_t
		, di_ary.stat_i
		, da_ary.read_a
	FROM di_ary, da_ary, ds_ary, dt_ary
	WHERE data_i IS NOT NULL OR data_a IS NOT NULL OR data_s IS NOT NULL OR data_t IS NOT NULL
$$;
