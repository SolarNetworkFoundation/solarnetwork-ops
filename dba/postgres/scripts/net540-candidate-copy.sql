/* ============================================================================
 * NET-540 verification: the step 1 functions for the 15 minute aggregate, under
 * names ending in _net540, so they can be compared with the live hourly rollup
 * on production before step 1 is deployed. Used by net540-verify.sh, version 6
 * or later.
 *
 *   solardatm.rollup_datm_15m_for_hour_net540      the hour and its 15 minute
 *                                                  rows, from one pass over the
 *                                                  hour's datum: the function
 *                                                  stale processing will call
 *   solardatm.rollup_agg_data_15m_net540           the hour rolled up from those
 *                                                  15 minute rows, as days are
 *                                                  rolled up from hours
 *
 * Generated from the NET-540 step 1 setup DDL of solarnetwork-central, branch
 * feature/net-540 on commit 17b16fb98, file
 * solarnet-db-setup/postgres/postgres-init-datm-agg-query.sql:
 *
 *   - the first is rollup_datm_15m_for_hour(). The only change is its name: its
 *     body is the same text, so md5(prosrc) is the same as the real function's.
 *   - the second is rollup_agg_data_for_time_span(). The only changes are its
 *     name, the dropped "kind" argument, and that it reads the 15 minute rows of
 *     the first function instead of a table.
 *
 * It first drops the functions of the version 5 copy: the 15 minute rollup that
 * returned only the 15 minute rows, which cannot be replaced in place, and the
 * copy of the hourly rollup with the reset-pair fix. That fix is NET-543, which
 * the first function includes, so the script now compares the hour with the
 * live function directly.
 *
 * Apply it on the primary, as a superuser, in one transaction:
 *
 *   psql -1 -d solarnetwork -f net540-candidate-copy.sql
 *
 * Regenerate this file if the setup DDL changes. Nothing calls these functions,
 * and they write nothing. Remove them with:
 *
 * DROP FUNCTION solardatm.rollup_agg_data_15m_net540(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE);
 * DROP FUNCTION solardatm.rollup_datm_15m_for_hour_net540(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, INTERVAL, INTERVAL);
 * ============================================================================
 */
\set ON_ERROR_STOP on

DROP FUNCTION IF EXISTS solardatm.rollup_agg_data_15m_net540(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE);
DROP FUNCTION IF EXISTS solardatm.rollup_datm_15m_for_hour_net540(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, INTERVAL, INTERVAL);
DROP FUNCTION IF EXISTS solardatm.rollup_datm_for_time_span_net540(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, INTERVAL, INTERVAL);

/**
 * NET-540 candidate: solardatm.rollup_datm_15m_for_hour() under another name, with the
 * same body. Its own comment follows.
 *
 * Compute the rollup datm record of one hour, together with the rollup datm records of the 15
 * minute slots of that hour.
 *
 * The first eight output columns are the hour, exactly as `solardatm.rollup_datm_for_time_span()`
 * computes it for the same arguments, and no row is returned when that function returns none. The
 * `slots` column holds the hour's 15 minute rows in time order, or `NULL` when there are none.
 *
 * The slots are computed from exactly the rows, and the per-row differences and portions, that
 * the hour uses, and each contribution to the hour is given to one or two of its slots, so the
 * slots add up to the hour:
 *
 *  - clock accumulation between two rows goes to the slot of the earlier row, up to the start of
 *    the slot of the later row; the later row's slot gets the remainder of the hour's portion
 *  - a contribution that crosses the start of the hour goes to the slot of the later row, and one
 *    that crosses the end of the hour to the slot of the earlier row
 *  - a reading difference goes to the slot of its row; a row before the hour counts in the first
 *    slot holding a row, and a row exactly at the end of the hour in the last one (or the last
 *    slot of the hour, if no slot holds a row)
 *  - averages, counts, minimums, maximums, status and tags are grouped by slot
 *  - a slot whose rows have no value for an accumulating property gets NULL for it when another
 *    slot of the hour has one, and zero when none has, as the hour reports
 *
 * Slots are 15 minute buckets of UTC time, so the hour must start on a 15 minute boundary, which
 * every hour of a whole, half or quarter hour time zone does.
 *
 * NOTE the CTEs that compute the hour are a copy of the query of
 * `solardatm.rollup_datm_for_time_span()`, with only `p_ts` added to `wa`: a change there must be
 * made here too. Sharing them would make every caller of that function pay for the slots.
 *
 * @param sid 				the stream ID to find datm for
 * @param start_ts			the start of the hour (inclusive)
 * @param end_ts 			the end of the hour (exclusive)
 * @param tolerance_clock 	as for `solardatm.rollup_datm_for_time_span()`
 * @param tolerance_read 	as for `solardatm.rollup_datm_for_time_span()`
 * @see solardatm.rollup_datm_for_time_span()
 * @see solardatm.process_one_agg_stale_datm()
 */
CREATE OR REPLACE FUNCTION solardatm.rollup_datm_15m_for_hour_net540(
		sid 			UUID,
		start_ts 		TIMESTAMP WITH TIME ZONE,
		end_ts 			TIMESTAMP WITH TIME ZONE,
		tolerance_clock INTERVAL DEFAULT INTERVAL 'PT1H',
		tolerance_read 	INTERVAL DEFAULT INTERVAL 'P1Y'
	) RETURNS TABLE (
		stream_id	UUID,
		ts_start	TIMESTAMP WITH TIME ZONE,
		data_i		NUMERIC[],
		data_a		NUMERIC[],
		data_s		TEXT[],
		data_t		TEXT[],
		stat_i		NUMERIC[][],
		read_a		NUMERIC[][],
		slots		solardatm.agg_datm[]
	) LANGUAGE SQL STABLE ROWS 1 AS
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
			-- the time of the row before, for the 15 minute slots
			, lag(d.ts) OVER slot AS p_ts
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

	-- the 15 minute slots of the hour, from here on

	-- slots of the hour holding a datum or reset record
	, occ AS (
		SELECT DISTINCT time_bucket(INTERVAL 'PT15M', d.ts) AS slot
		FROM d
		WHERE d.inc
	)
	-- the first and last of those slots, or the last slot of the hour if there are none
	, edge AS (
		SELECT COALESCE(min(slot), end_ts - INTERVAL 'PT15M') AS first_slot
			 , COALESCE(max(slot), end_ts - INTERVAL 'PT15M') AS last_slot
		FROM occ
	)
	-- instantaneous statistics per slot
	, slot_di_ary AS (
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
	-- the slots of each row and of the row before it, when they are within the hour
	, wb AS (
		SELECT wa.*
			, wa.portion::numeric AS hp
			, CASE WHEN wa.ts >= start_ts AND wa.ts < end_ts THEN time_bucket(INTERVAL 'PT15M', wa.ts) END AS c_slot
			, CASE WHEN wa.p_ts >= start_ts AND wa.p_ts < end_ts THEN time_bucket(INTERVAL 'PT15M', wa.p_ts) END AS p_slot
		FROM wa
	)
	-- the earlier row's share of the hour's portion, when the two rows are in different slots of the hour;
	-- rows without a value for the property have no difference to share out
	, wc AS (
		SELECT wb.*
			, CASE
				WHEN p_slot IS NOT NULL AND c_slot IS NOT NULL AND c_slot > p_slot
					THEN (EXTRACT('epoch' FROM c_slot - p_ts) / EXTRACT('epoch' FROM ts - p_ts))::numeric
				END AS p_share
		FROM wb
		WHERE hp <> 0 AND val IS NOT NULL
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
	-- clock accumulation per slot
	, ca AS (
		SELECT idx, slot, sum(amt) AS cdiff
		FROM alloc
		GROUP BY idx, slot
	)
	-- the rows the hour's readings count, each in its slot
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
	-- readings per slot
	, ra0 AS (
		SELECT idx, slot
			, sum(diff) AS rdiff
			, solarcommon.first(val ORDER BY ts, rtype) AS rstart_first
			, solarcommon.first(val - diff ORDER BY ts, rtype) AS rstart_later
			, solarcommon.first(val ORDER BY ts DESC, rtype DESC) AS rend
		FROM rd
		GROUP BY idx, slot
	)
	-- for each property: whether any slot of the hour has a value for it, and the first slot that does
	, ra AS (
		SELECT ra0.*
			, bool_or(ra0.rend IS NOT NULL) OVER (PARTITION BY ra0.idx) AS hour_has
			, ra0.slot = min(ra0.slot) FILTER (WHERE ra0.rend IS NOT NULL) OVER (PARTITION BY ra0.idx) AS is_first
		FROM ra0
	)
	, slot_ts AS (
		SELECT slot FROM occ
		UNION
		SELECT slot FROM ca
		UNION
		SELECT slot FROM ra
	)
	-- A slot whose rows have no value for a property gets NULL for it when another slot of the hour
	-- has one, so that rolling the slots up takes the hour's first and last readings from slots that
	-- have them. When no slot has a value the hourly rollup reports zero, and so does each slot.
	, slot_da_ary AS (
		SELECT s.slot
			, CASE WHEN count(ca.idx) + count(ra.idx) > 0 THEN
				vec_trim_scale(array_agg(
					CASE
						WHEN ra.rend IS NOT NULL OR ca.cdiff <> 0 THEN COALESCE(ca.cdiff, 0)
						WHEN ra.hour_has THEN NULL
						WHEN ra.idx IS NOT NULL THEN 0
						END
					ORDER BY p.idx))
				END AS data_a
			, CASE WHEN count(ra.idx) > 0 THEN
				array_agg(ARRAY[
					  ra.rdiff
					, CASE WHEN ra.is_first THEN ra.rstart_first ELSE ra.rstart_later END
					, ra.rend
				] ORDER BY p.idx)
				END AS read_a
		FROM slot_ts s
		CROSS JOIN m
		CROSS JOIN generate_series(1, m.len_a) AS p(idx)
		LEFT OUTER JOIN ca ON ca.slot = s.slot AND ca.idx = p.idx
		LEFT OUTER JOIN ra ON ra.slot = s.slot AND ra.idx = p.idx
		GROUP BY s.slot
	)
	-- status per slot, as most-frequent status values
	, slot_ws AS (
		SELECT
			  time_bucket(INTERVAL 'PT15M', d.ts) AS slot
			, p.idx AS idx
			, d.data_s[p.idx] AS val
		FROM d
		INNER JOIN generate_series(1, array_upper(d.data_s, 1)) AS p(idx) ON TRUE
		WHERE d.data_s IS NOT NULL AND d.inc
	)
	, slot_ds AS (
		SELECT slot_ws.slot, slot_ws.idx, mode() WITHIN GROUP (ORDER BY slot_ws.val) AS val
		FROM slot_ws
		GROUP BY slot_ws.slot, slot_ws.idx
	)
	, slot_ds_ary AS (
		SELECT slot, array_agg(val ORDER BY idx) AS data_s
		FROM slot_ds
		GROUP BY slot
	)
	-- tags per slot
	, slot_dt_ary AS (
		SELECT time_bucket(INTERVAL 'PT15M', d.ts) AS slot
			, array_agg(DISTINCT p.val) AS data_t
		FROM d
		INNER JOIN unnest(d.data_t) AS p(val) ON TRUE
		WHERE d.data_t IS NOT NULL AND d.inc
		GROUP BY 1
	)
	-- the slot rows, in time order
	, slot_ary AS (
		SELECT array_agg(ROW(
				  sid
				, slot_ts.slot
				, slot_di_ary.data_i
				, slot_da_ary.data_a
				, slot_ds_ary.data_s
				, slot_dt_ary.data_t
				, slot_di_ary.stat_i
				, slot_da_ary.read_a
			)::solardatm.agg_datm ORDER BY slot_ts.slot) AS slots
		FROM slot_ts
		LEFT OUTER JOIN slot_di_ary ON slot_di_ary.slot = slot_ts.slot
		LEFT OUTER JOIN slot_da_ary ON slot_da_ary.slot = slot_ts.slot
		LEFT OUTER JOIN slot_ds_ary ON slot_ds_ary.slot = slot_ts.slot
		LEFT OUTER JOIN slot_dt_ary ON slot_dt_ary.slot = slot_ts.slot
		WHERE slot_di_ary.data_i IS NOT NULL OR slot_da_ary.data_a IS NOT NULL
			OR slot_ds_ary.data_s IS NOT NULL OR slot_dt_ary.data_t IS NOT NULL
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
		, slot_ary.slots
	FROM di_ary, da_ary, ds_ary, dt_ary, slot_ary
	WHERE data_i IS NOT NULL OR data_a IS NOT NULL OR data_s IS NOT NULL OR data_t IS NOT NULL
$$;


/**
 * NET-540 candidate: the hour rolled up from the 15 minute rows of
 * solardatm.rollup_datm_15m_for_hour_net540(), with the logic of
 * solardatm.rollup_agg_data_for_time_span(), which stale processing uses to roll days up
 * from hours. Its start and end readings are those of the first and last row that has them,
 * preferring rows whose accumulation is not NULL (NET-544).
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
		SELECT s.*
		FROM solardatm.rollup_datm_15m_for_hour_net540(sid, start_ts, end_ts) h
		INNER JOIN LATERAL unnest(h.slots) AS s ON TRUE
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
			, d.ts_start
			, d.data_a[p.idx] AS val
			, d.read_a[p.idx][1] AS rdiff
			, d.read_a[p.idx][2] AS rstart
			, d.read_a[p.idx][3] AS rend
		FROM d
		INNER JOIN generate_series(1, array_upper(d.data_a, 1)) AS p(idx) ON TRUE
	)
	-- calculate accumulating statistics; the start and end readings are those of the first and
	-- last row that has them, taking rows whose accumulation is not NULL first (see NET-544)
	, da AS (
		SELECT
			idx
			, sum(val) AS val
			, sum(rdiff) AS rdiff
			, (array_agg(rstart ORDER BY val IS NULL, ts_start) FILTER (WHERE rstart IS NOT NULL))[1] AS rstart
			, (array_agg(rend ORDER BY val IS NULL, ts_start DESC) FILTER (WHERE rend IS NOT NULL))[1] AS rend
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
