/* ============================================================================
 * NET-539 verification: copies of the NET-539 version of
 * solardatm.find_datm_for_time_slot(), and of the two functions that call it,
 * under names ending in _net539, so the change can be compared with the live
 * functions on production before it is deployed. Used by net539-verify.sh.
 *
 *   solardatm.find_datm_for_time_slot_net539            the NET-539 function
 *   solardatm.rollup_datm_for_time_span_net539          the live hourly rollup,
 *                                                       calling the copy above
 *   solardatm.rollup_datm_for_time_span_slots_net539    the live sub-hour rollup,
 *                                                       calling the copy above
 *
 * Generated from solarnetwork-central at commit d521040fb, from
 * solarnet-db-setup/postgres/postgres-init-datm-agg-query.sql. The only changes
 * are the three function names and the two calls to the first function.
 * Regenerate this file if the NET-539 function changes. Nothing calls these
 * functions. Remove them with:
 *
 * DROP FUNCTION solardatm.rollup_datm_for_time_span_slots_net539(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, INTEGER, INTERVAL);
 * DROP FUNCTION solardatm.rollup_datm_for_time_span_net539(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, INTERVAL, INTERVAL);
 * DROP FUNCTION solardatm.find_datm_for_time_slot_net539(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, INTERVAL, INTERVAL);
 * ============================================================================
 */

CREATE OR REPLACE FUNCTION solardatm.find_datm_for_time_slot_net539(
		sid 		UUID,
		start_ts 	TIMESTAMP WITH TIME ZONE,
		end_ts 		TIMESTAMP WITH TIME ZONE,
		tolerance 	INTERVAL DEFAULT INTERVAL 'P3M',
		target_agg 	INTERVAL DEFAULT INTERVAL 'PT1H'
	) RETURNS SETOF solardatm.datm_rec LANGUAGE SQL STABLE ROWS 200 AS
$$
	-- find if stream even has accumulating properties, to avoid costly scan
	WITH meta AS (
		SELECT COALESCE(CARDINALITY(names_a) = 0, TRUE) AS has_no_a
 		FROM solardatm.find_metadata_for_stream(sid)
	)
	-- Find min/max datum date within slot; if no actual data in this slot we get a
	-- result row with NULL values.
	-- Note that an INCLUSIVE end date it used to pick up a "gap" slot that could occur
	-- leading up to the end time slot (see NET-469).
	, drange AS (
		SELECT *
		FROM (
			-- force a result row
			VALUES (TRUE)
		) AS c(t)
		LEFT OUTER JOIN (
			-- find minimum datum date within slot
			SELECT ts, COALESCE(CARDINALITY(data_a) > 0, FALSE)
			FROM solardatm.da_datm
			WHERE stream_id = sid
				AND ts >= start_ts
				AND ts <= end_ts
			ORDER BY ts
			LIMIT 1
		) AS l(min_ts, min_has_a) ON TRUE
		LEFT OUTER JOIN (
			-- find maximum datum date within slot
			SELECT ts
			FROM solardatm.da_datm
			WHERE stream_id = sid
				AND ts >= start_ts
				AND ts <= end_ts
			ORDER BY ts DESC
			LIMIT 1
		) AS r(max_ts) ON TRUE
	)

	-- find next datum date after maximum within slot (or exact end of slot) REQUIRING accumulating;
	-- the next datum only contributes to the clock accumulation that crosses the end of the slot,
	-- which is ignored beyond the 1 hour clock tolerance, so limiting the search to that keeps
	-- REQUIRING accumulating fast even when no such datum exists (see NET-537)
	, nrange AS (
		SELECT (
			SELECT CASE
				WHEN d.ts IS NULL THEN drange.max_ts
				WHEN drange.max_ts = end_ts THEN drange.max_ts
				ELSE d.ts
			END
			FROM meta, drange, solardatm.find_time_after_ts(sid, drange.max_ts, end_ts + LEAST(tolerance, INTERVAL 'PT1H'), TRUE, meta.has_no_a) AS d(ts)
		) AS max_ts
	)

	-- decide if the prior datum is needed, which is only when something returned can be
	-- differenced against it; otherwise its search is skipped, as that reads every row back to
	-- the datum it finds, or its whole window when there is none (see NET-539)
	, prior AS (
		-- a stream without accumulating properties has no prior datum to find
		SELECT NOT COALESCE((SELECT has_no_a FROM meta), TRUE) AND (
				-- the first datum in the slot has accumulating properties, which decides it for
				-- most streams without another lookup
				COALESCE(drange.min_has_a, FALSE)

				-- the next datum after the slot is returned, so the clock accumulation from the
				-- prior datum to it crosses the slot
				OR COALESCE(nrange.max_ts > drange.max_ts, FALSE)

				-- any datum in the slot has accumulating properties, counting one exactly at the
				-- end of the slot (see NET-469)
				OR EXISTS (
					SELECT 1
					FROM solardatm.da_datm d
					WHERE d.stream_id = sid
						AND d.ts >= start_ts
						AND d.ts <= end_ts
						AND d.data_a IS NOT NULL
				)

				-- a reset record is in the slot, counting one exactly at its start or end: its final
				-- reading is differenced against the prior datum, which also limits the search for
				-- reset records in reset_range below
				OR EXISTS (
					SELECT 1
					FROM solardatm.da_datm_aux aux
					WHERE aux.atype = 'Reset'::solardatm.da_datm_aux_type
						AND aux.stream_id = sid
						AND aux.ts >= start_ts
						AND aux.ts <= end_ts
				)
			) AS needed
		FROM drange, nrange
	)

	-- find prior/next datum date range to provide for clock and reading input
	, srange AS (
		SELECT COALESCE(t.min_ts, drange.min_ts, start_ts) AS min_ts, COALESCE(nrange.max_ts, drange.max_ts, end_ts) AS max_ts
		FROM drange, nrange, (
			-- search for the prior datum only when it is needed; not searching gives the same
			-- result as a search that finds nothing (see NET-539)
			SELECT CASE WHEN prior.needed THEN COALESCE(
				(
					-- find prior datum date before minimum within slot (or exact start of slot) REQUIRING accumulating
					-- but use forced shorter tolerance because REQUIRING accumulating too expensive
					SELECT CASE
						WHEN d.ts IS NULL THEN drange.min_ts
						WHEN drange.min_ts = start_ts AND drange.min_has_a THEN drange.min_ts
						ELSE d.ts
					END
					FROM meta, drange, solardatm.find_time_before_ts(sid, COALESCE(drange.min_ts, start_ts), start_ts - LEAST(tolerance, INTERVAL 'P14D'), TRUE, meta.has_no_a) AS d(ts)
				),
				(
					-- expand search past 14d slow search:
					-- find prior datum date before minimum within slot (or exact start of slot) NOT REQUIRING accumulating
					-- using full tolerance because index-only scan possible and thus fast enough
					WITH way_back AS (
						SELECT CASE
							WHEN d.ts IS NULL THEN drange.min_ts
							WHEN drange.min_ts = start_ts AND drange.min_has_a THEN drange.min_ts
							ELSE d.ts
						END
						FROM meta, drange, solardatm.find_time_before_ts(
							  sid
							, CASE WHEN drange.min_has_a THEN drange.min_ts ELSE start_ts END - LEAST(tolerance, INTERVAL 'P14D')
							, start_ts - tolerance
							, FALSE
							, meta.has_no_a
							) AS d(ts)
					)
					-- find datum with way_back time, to see if has accumulating properties
					, way_back_d AS (
						SELECT d.ts, d.has_a
						FROM way_back, solardatm.datm_has_accumulating_at(sid, way_back.ts) AS d
					)
					SELECT COALESCE(
						(
							-- if way-back datum has accumulating properties, use it
							SELECT ts
							FROM way_back_d
							WHERE has_a
						),
						(
							-- otherwise try short slow search before way-back datum for accumulating
							-- properties, within the tolerance, unless stream has none (see NET-538)
							SELECT d.ts
							FROM meta, way_back_d, solardatm.find_time_before_ts(
								  sid
								, way_back_d.ts
								, GREATEST(way_back_d.ts - LEAST(tolerance, INTERVAL 'P14D'), start_ts - tolerance)
								, TRUE
								, meta.has_no_a
							) AS d(ts)
							WHERE NOT meta.has_no_a
						)
					)
				)
			) END AS min_ts
			FROM prior
		) t
	)

	-- find date range for resets
	, reset_range AS (
		SELECT MIN(aux.ts) AS min_ts, MAX(aux.ts) AS max_ts
		FROM srange, solardatm.da_datm_aux aux
		WHERE aux.atype = 'Reset'::solardatm.da_datm_aux_type
			AND aux.stream_id = sid
			AND aux.ts >= CASE
					WHEN srange.min_ts <= start_ts THEN srange.min_ts
					ELSE start_ts - tolerance
				END
			AND aux.ts <= CASE
				WHEN srange.max_ts >= end_ts THEN srange.max_ts
				ELSE end_ts + tolerance
			END
	)

	-- get combined range for datum + resets
	, combined_srange AS (
		SELECT CASE
				-- if datum falls exactly on start, only include prior datum if it is more than
				-- one agg slot away; otherwise that datum will be included in prior slot
				WHEN t.min_ts IS NULL OR (
						drange.min_ts = start_ts
						AND drange.min_has_a
						AND (start_ts - t.min_ts) < target_agg
					)
					THEN drange.min_ts
				ELSE t.min_ts
			END AS min_ts
			, CASE
				WHEN t.max_ts IS NULL OR drange.max_ts = end_ts THEN drange.max_ts
				ELSE t.max_ts
			END AS max_ts
		FROM drange, (
			SELECT CASE
					-- start < reset < datum: reset is min
					WHEN reset_range.min_ts < srange.min_ts
						AND reset_range.min_ts >= start_ts
						THEN reset_range.min_ts

					-- datum < reset < start: reset is min
					WHEN reset_range.min_ts > srange.min_ts
						AND reset_range.min_ts <= start_ts
						THEN reset_range.min_ts

					-- no datum but reset: reset is min
					WHEN drange.min_ts IS NULL
						AND reset_range.min_ts IS NOT NULL
						THEN LEAST(srange.min_ts, reset_range.min_ts)

					-- no datum
					WHEN drange.min_ts IS NULL THEN start_ts

					-- otherwise: datum is min (or null)
					ELSE srange.min_ts
				END AS min_ts
				, CASE
					-- datum < reset < end: reset is max
					WHEN reset_range.max_ts > srange.max_ts
						AND reset_range.max_ts <= end_ts
						THEN reset_range.max_ts

					-- end < reset < datum: reset is max (or null)
					WHEN reset_range.max_ts < srange.max_ts
						AND reset_range.max_ts >= end_ts
						THEN reset_range.max_ts

					-- no datum but reset: reset is max (or null)
					WHEN drange.max_ts IS NULL
						AND reset_range.max_ts IS NOT NULL
						THEN LEAST(srange.max_ts, reset_range.max_ts)

					-- no datum
					WHEN drange.max_ts IS NULL THEN end_ts

					-- otherwise: datum is max (or null)
					ELSE srange.max_ts
				END AS max_ts
			FROM drange, srange, reset_range
		) t
		-- a NULL argument gives no rows, as for a STRICT function (see NET-538)
		WHERE num_nulls(sid, start_ts, end_ts, tolerance, target_agg) = 0
	)

	-- return combined datum + resets
	SELECT d.stream_id
		, d.ts
		, d.data_i
		, d.data_a
		, d.data_s
		, d.data_t
		, 0::SMALLINT AS rtype
	FROM combined_srange, solardatm.find_datm_between(sid, combined_srange.min_ts, combined_srange.max_ts) d

	UNION ALL

	SELECT
		  aux.stream_id
		, aux.ts
		, NULL::numeric[] AS data_i
		, aux.data_a
		, NULL::text[] AS data_s
		, NULL::text[] AS data_t
		, aux.rtype AS rtype
	FROM combined_srange, solardatm.find_datm_aux_for_time_span(
		sid,
		combined_srange.min_ts,
		combined_srange.max_ts
	) aux
$$;


CREATE OR REPLACE FUNCTION solardatm.rollup_datm_for_time_span_net539(
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
		FROM m, solardatm.find_datm_for_time_slot_net539(
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


CREATE OR REPLACE FUNCTION solardatm.rollup_datm_for_time_span_slots_net539(
		sid 			UUID,
		start_ts 		TIMESTAMP WITH TIME ZONE,
		end_ts 			TIMESTAMP WITH TIME ZONE,
		secs			INTEGER DEFAULT 600,
		tolerance_clock INTERVAL DEFAULT interval '1 hour'
	) RETURNS SETOF solardatm.agg_datm LANGUAGE SQL STABLE ROWS 500 AS
$$
	-- grab array column lenghts for pad_vec() and fill_array() later
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
		FROM m, solardatm.find_datm_for_time_slot_net539(
			sid,
			start_ts,
			end_ts,
			tolerance_clock
		)
	)
	-- calculate instantaneous statistis per property
	, di_ary AS (
		SELECT
			  time_bucket((secs||' seconds')::interval, d.ts) AS ts_start
			, vec_trim_scale(vec_agg_mean(d.data_i)) AS data_i
			, solarcommon.array_transpose2d(ARRAY[
				  vec_agg_count(d.data_i)::numeric[]
				, vec_agg_min(d.data_i)
				, vec_agg_max(d.data_i)
			  ]) AS stat_i
		FROM d
		GROUP BY time_bucket((secs||' seconds')::interval, d.ts)
	)
	-- calculate clock accumulation for data_a values per property
	, wa AS (
		SELECT
			 time_bucket((secs||' seconds')::interval, d.ts) AS ts_start
			, d.data_a
			, COALESCE(vec_sub(d.data_a, lag(d.data_a) OVER win), array_fill(0, ARRAY[m.len_a])) AS diff_before
			, COALESCE(vec_sub(lead(d.data_a) OVER win, d.data_a), array_fill(0, ARRAY[m.len_a])) AS diff_after
			, CASE
				-- reset record
				WHEN rtype = 2
					THEN 0

				-- start of slot; allocate only end portion of accumulation within this slot
				WHEN rank() OVER slot = 1
					THEN COALESCE(EXTRACT('epoch' FROM d.ts - time_bucket((secs||' seconds')::interval, d.ts)) / EXTRACT('epoch' FROM d.ts - lag(d.ts) OVER win), 0)

				ELSE 1
				END as portion_before
			, CASE
				-- reset record
				WHEN rtype = 2
					THEN 0

				-- end of slot; allocate only start portion of accumulation within this slot
				WHEN rank() OVER rslot = 1
					THEN COALESCE(EXTRACT('epoch' FROM time_bucket((secs||' seconds')::interval, lead(d.ts) OVER win) - d.ts) / EXTRACT('epoch' FROM lead(d.ts) OVER win - d.ts), 0)

				ELSE 0
				END as portion_after
		FROM d, m
		WINDOW slot AS (PARTITION BY time_bucket((secs||' seconds')::interval, d.ts) ORDER BY CASE WHEN d.data_a IS NULL THEN 1 ELSE 0 END, d.ts, d.rtype
						RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
			, rslot AS (PARTITION BY time_bucket((secs||' seconds')::interval, d.ts) ORDER BY CASE WHEN d.data_a IS NULL THEN 1 ELSE 0 END DESC, d.ts DESC, d.rtype DESC
						RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
			, win AS (ORDER BY CASE WHEN d.data_a IS NULL THEN 1 ELSE 0 END, d.ts, d.rtype
						RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
	)
	-- calculate accumulating statistics
	, da_ary AS (
		SELECT
			  ts_start
			, vec_trim_scale(vec_to_sum(vec_add(vec_mul(diff_before, portion_before::numeric), vec_mul(diff_after, portion_after::numeric)))) AS data_a
		FROM wa
		GROUP BY ts_start
	)
	-- calculate status for data_s values per property
	-- NOTE "unnest() WITH ORDINALITY" not used because of possible sparse array slice
	, ws AS (
		SELECT
			  p.idx AS idx
			, d.data_s[p.idx] AS val
			, time_bucket((secs||' seconds')::interval, d.ts) AS ts_start
		FROM d
		INNER JOIN generate_series(1, array_upper(d.data_s, 1)) AS p(idx) ON TRUE
		WHERE d.inc
	)
	-- calculate status statistics, as most-frequent status values
	, ds AS (
		SELECT
			  ws.idx
			, ws.ts_start
			, mode() WITHIN GROUP (ORDER BY ws.val) AS val
		FROM ws
		GROUP BY ws.idx, ws.ts_start
	)
	-- join data_s property values back into arrays
	, ds_ary AS (
		SELECT
			  ts_start
			, array_agg(val ORDER BY idx) AS data_s
		FROM ds
		GROUP BY ts_start
	)
	-- join data_t property values into mega array
	, dt_ary AS (
		SELECT
			time_bucket((secs||' seconds')::interval, d.ts) AS ts_start
			, array_agg(DISTINCT p.val) AS data_t
		FROM d
		INNER JOIN unnest(d.data_t) AS p(val) ON TRUE
		WHERE d.data_t IS NOT NULL AND d.inc
		GROUP BY time_bucket((secs||' seconds')::interval, d.ts)
	)
	, slots AS (
		SELECT DISTINCT time_bucket((secs||' seconds')::interval, d.ts) AS ts_start
		FROM d
		WHERE inc
	)
	SELECT
		  sid AS stream_id
		, slots.ts_start
		, di_ary.data_i
		, da_ary.data_a
		, ds_ary.data_s
		, dt_ary.data_t
		, di_ary.stat_i
		, NULL::NUMERIC[][] AS read_a
	FROM slots
	LEFT OUTER JOIN di_ary ON di_ary.ts_start = slots.ts_start
	LEFT OUTER JOIN da_ary ON da_ary.ts_start = slots.ts_start
	LEFT OUTER JOIN ds_ary ON ds_ary.ts_start = slots.ts_start
	LEFT OUTER JOIN dt_ary ON dt_ary.ts_start = slots.ts_start
	WHERE data_i IS NOT NULL OR data_a IS NOT NULL OR data_s IS NOT NULL OR data_t IS NOT NULL
$$;


