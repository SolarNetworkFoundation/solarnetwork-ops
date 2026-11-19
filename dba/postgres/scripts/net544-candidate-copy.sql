/* ============================================================================
 * NET-544 verification: the candidate day and month rollup, under a name ending
 * in _net544, so it can be compared with the live one on production before
 * NET-544 is deployed. Used by net544-verify.sh.
 *
 *   solardatm.rollup_agg_data_for_time_span_net544   rollup_agg_data_for_time_span()
 *                                                    taking each property's start
 *                                                    and end readings from the
 *                                                    first and last row that has
 *                                                    them
 *
 * Generated from solarnetwork-central, branch feature/net-540-prefixes (base
 * commit fd1a39f05), from
 * solarnet-db-setup/postgres/updates/NET-544-day-month-agg-reading-start-end.sql.
 * The only change is the name: the body is that script's, character for
 * character, so md5(prosrc) is the same for both (7ae308c50b55b4b7ac4dade8c995f610).
 *
 * Regenerate this file if the update script or the live function changes.
 * Nothing calls this function, and it writes nothing. Remove it with:
 *
 * DROP FUNCTION solardatm.rollup_agg_data_for_time_span_net544(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, CHARACTER);
 * ============================================================================
 */

/**
 * NET-544 candidate: solardatm.rollup_agg_data_for_time_span(), taking the start
 * and end readings of each accumulating property from the first and last row that
 * has them, preferring rows whose accumulation is not NULL.
 *
 * @param sid 				the stream ID to find datm for
 * @param start_ts			the minimum date (inclusive)
 * @param end_ts 			the maximum date (exclusive)
 * @param kind 				the aggregate kind of the rows to roll up: 'h' (for a day) or 'd' (for a month)
 * @see solardatm.find_agg_datm_for_time_span()
 */
CREATE OR REPLACE FUNCTION solardatm.rollup_agg_data_for_time_span_net544(
		sid 			UUID,
		start_ts 		TIMESTAMP WITH TIME ZONE,
		end_ts 			TIMESTAMP WITH TIME ZONE,
		kind 			CHARACTER
	) RETURNS SETOF solardatm.agg_datm LANGUAGE SQL STABLE ROWS 500 AS
$$
	WITH d AS (
		SELECT * FROM solardatm.find_agg_datm_for_time_span(
			sid,
			start_ts,
			end_ts,
			kind
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
