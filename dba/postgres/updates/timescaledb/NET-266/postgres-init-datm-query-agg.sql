/*
 NOTE ON CLOCK VS READING

 "Clock" refers to normalized clock periods, where datum rows are interpolated at exact period
 start and end value. This affects accumulating properties in that difference of accumulation
 between two rows on either side of a period transition is split proportionally to each period.

 "Reading" refers to periods where the datum included range from the latest row on or before the
 period start to the latest row before the period end. No interpolation is applied between the
 resulting rows within that range.

 Unless otherwise noted, these functions assume that "reading" tolerance values are larger than
 "clock" tolerance values. The assumption stems from the idea that the "clock" aggregates are
 designed for charting purposes while "reading" for billing.
*/

/**
 * Find datm records for an aggregate time range, supporting both "clock" and "reading" spans.
 *
 * The output `inclusion` column will be -1, 0, or 1 depending on if the row's ts is less than,
 * within, or greater than the `start_ts` and `end_ts` range.
 *
 * The output `portion` column will contain a number between 0 and 1 (inclusive) that represents
 * the portion of that row that is within the `start_ts` - `end_ts` range when compared to an
 * adjacent row outside that range. In other words, it can be used for "clock" periods to
 * normalize data across the time range boundaries.
 *
 * @param sid 				the stream ID to find datm for
 * @param start_ts			the minimum date (inclusive)
 * @param end_ts 			the maximum date (exclusive)
 * @param tolerance_clock 	the maximum time to look forward/backward for adjacent datm within
 *                          the "clock" period
 * @param tolerance_read 	the maximum time to look forward/backward for adjacent datm within
 *                          the "reading" period
 */
CREATE OR REPLACE FUNCTION solardatm.find_datm_for_time_span(
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
	-- first find boundary datum (least, greatest) for given time range that satisfies both the
	-- clock and reading aggregate time windows
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
	-- combine boundary rows into single range row with start/end columns
	, r AS (
		SELECT
			stream_id
			, COALESCE(min(ts), start_ts) AS range_start
			, COALESCE(max(ts), end_ts) AS range_end
		FROM b
		GROUP BY stream_id
	)
	-- query for raw datum using the boundary range previously found
	SELECT
		  d.stream_id
		, d.ts
		-- only include data_i in output when within clock tolerance
		, CASE
			WHEN d.ts < start_ts - tolerance_clock THEN NULL::numeric[]
			ELSE d.data_i
			END AS data_i
		, d.data_a
		, d.data_s
		, d.data_t
		, CASE
			WHEN d.ts < start_ts THEN -1::SMALLINT
			WHEN d.ts >= end_ts THEN 1::SMALLINT
			ELSE 0::SMALLINT
			END AS inclusion
		-- calculate "clock" portion
		, CASE
			-- in case reading span includes extra rows beyond clock period, ignore this portion
			-- or this before clock tolerance or this after clock period
			WHEN lead(d.ts) OVER slot < start_ts OR d.ts < start_ts - tolerance_clock OR d.ts > end_ts THEN
				0
			-- when this timestamp is before clock period allocate portion within clock period
			WHEN d.ts < start_ts THEN
				EXTRACT(epoch FROM (COALESCE(lead(d.ts) OVER slot, start_ts) - start_ts)) / EXTRACT(epoch FROM (COALESCE(lead(d.ts) OVER slot, start_ts) - d.ts))
			-- when next timestamp is after clock period allocate portion within clock period
			WHEN lead(d.ts) OVER slot > end_ts THEN
				EXTRACT(epoch FROM (end_ts - d.ts)) / EXTRACT(epoch FROM (lead(d.ts) OVER slot - d.ts))
			-- otherwise fully within clock period
			ELSE 1
			END AS portion
	FROM r
	INNER JOIN solardatm.da_datm d ON d.stream_id = r.stream_id
	WHERE d.ts >= r.range_start
		AND d.ts <= r.range_end
	WINDOW slot AS (ORDER BY d.ts RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
$$;


/**
 * Find datm records for an aggregate time range, supporting both "clock" and "reading" spans,
 * including "reset" auxiliary records.
 *
 * The output `inclusion` column will be -1, 0, or 1 depending on if the row's ts is less than,
 * within, or greater than the `start_ts` and `end_ts` range.
 *
 * The output `portion` column will contain a number between 0 and 1 (inclusive) that represents
 * the portion of that row that is within the `start_ts` - `end_ts` range when compared to an
 * adjacent row outside that range. In other words, it can be used for "clock" periods to
 * normalize data across the time range boundaries.
 *
 * @param sid 				the stream ID to find datm for
 * @param start_ts			the minimum date (inclusive)
 * @param end_ts 			the maximum date (exclusive)
 * @param tolerance_clock 	the maximum time to look forward/backward for adjacent datm within
 *                          the "clock" period
 * @param tolerance_read 	the maximum time to look forward/backward for adjacent datm within
 *                          the "reading" period
 * @see solardatm.find_datm_for_time_span()
 */
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
	-- find raw data for given time range
	WITH d AS (
		SELECT d.*, 0 AS rr
		FROM solardatm.find_datm_for_time_span(sid, start_ts, end_ts) d
	)
	-- find reset records for same time range, split into two rows for each record: final
	-- and starting accumulating values
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
	-- convert reset record rows into datm rows by turning jdata_a JSON into data_a value array,
	-- respecting the array order defined by solardatm.da_datm_meta.names_a and excluding values
	-- not defined there
	, resets AS (
		SELECT
			  aux.stream_id
			, aux.ts
			, NULL::numeric[] AS data_i
			, array_agg(p.val::text::numeric ORDER BY array_position(aux.names_a, p.key::text))
				FILTER (WHERE array_position(aux.names_a, p.key::text) IS NOT NULL)::numeric[] AS data_a
			, NULL::text[] AS data_s
			, NULL::text[] AS data_t
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
		WINDOW slot AS (ORDER BY aux.ts RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
	)
	-- combine raw datm with reset datm
	, combined AS (
		SELECT * FROM d
		UNION ALL
		SELECT * FROM resets
	)
	-- group all results by time so that reset records with the same time as a raw record
	-- override the raw record
	SELECT DISTINCT ON (ts) stream_id, ts, data_i, data_a, data_s, data_t, inclusion, portion
	FROM combined
	ORDER BY ts, rr DESC
$$;


/**
 * Compute a rollup datm record for an aggregate time range, including "reset" auxiliary records.
 *
 * The `data_i` output column contains the average values for the raw `data_i` properties within
 * the "clock" period.
 *
 * The `stat_i` output column contains a tuple of [count, min, max] values for the raw `data_i`
 * properties within the "clock" period.
 *
 * The `data_a` output column contains the accumulated difference of the raw `data_a` properties
 * within the "clock" period.
 *
 * The `read_a` output column contains a tuple of [start, finish, difference] values for the raw
 * `data_a` properties within the "reading" period.
 *
 * @param sid 				the stream ID to find datm for
 * @param start_ts			the minimum date (inclusive)
 * @param end_ts 			the maximum date (exclusive)
 * @param tolerance_clock 	the maximum time to look forward/backward for adjacent datm within
 *                          the "clock" period
 * @param tolerance_read 	the maximum time to look forward/backward for adjacent datm within
 *                          the "reading" period
 * @see solardatm.find_datm_for_time_span_with_aux()
 */
CREATE OR REPLACE FUNCTION solardatm.rollup_datm_for_time_span(
		sid 			UUID,
		start_ts 		TIMESTAMP WITH TIME ZONE,
		end_ts 			TIMESTAMP WITH TIME ZONE,
		tolerance_clock INTERVAL DEFAULT interval '1 hour',
		tolerance_read 	INTERVAL DEFAULT interval '3 months'
	) RETURNS TABLE(
		stream_id 	UUID,
		ts_start	TIMESTAMP WITH TIME ZONE,
		data_i		NUMERIC[],					-- array of instantaneous property average values
		stat_i		NUMERIC[][],				-- array of instantaneous property [count,min,max] statistic tuples
		data_a		NUMERIC[],					-- array of accumulating property clock difference values
		read_a		NUMERIC[][]					-- array of accumulating property reading [start,finish,diff] tuples
		--data_s		TEXT[],
		--data_t		TEXT[],
		--inclusion	SMALLINT,
		--portion		DOUBLE PRECISION
	) LANGUAGE SQL STABLE ROWS 500 AS
$$
	-- grab raw data + reset records, constrained by stream/date range
	WITH d AS (
		SELECT * FROM solardatm.find_datm_for_time_span_with_aux(
			sid,
			start_ts,
			end_ts,
			tolerance_clock,
			tolerance_read
		)
	)
	-- calculate time-weights for data_i values per property
	, wi AS (
		SELECT
			p.idx AS idx
			, p.val AS val
			, ((p.val + lead(p.val) OVER slot) / 2) * (EXTRACT(epoch FROM (lead(d.ts) OVER slot - d.ts)) / EXTRACT(epoch FROM (end_ts - start_ts)) * d.portion) AS wval
		FROM d
		INNER JOIN unnest(d.data_i) WITH ORDINALITY AS p(val, idx) ON TRUE
		WINDOW slot AS (PARTITION BY p.idx ORDER BY d.ts)
	)
	-- calculate instantaneous statistics
	, di AS (
		SELECT
			w.idx
			, to_char(sum(w.wval), 'FM999999999999999999990.999999999')::numeric AS val
			, count(w.wval) AS cnt
			, min(val) AS val_min
			, max(val) AS val_max
		FROM wi w
		WHERE w.wval IS NOT NULL
		GROUP BY w.idx
	)
	-- join data_i and stat_i property values back into arrays
	, di_ary AS (
		SELECT
			  array_agg(d.val ORDER BY d.idx) AS data_i
			, array_agg(
				ARRAY[d.cnt, d.val_min, d.val_max] ORDER BY d.idx
			) AS stat_i
		FROM di d
	)
	-- calculate clock accumulation for data_a values per property
	, wa AS (
		SELECT
			p.idx AS idx
			, p.val AS val
			, (lead(p.val) OVER slot - p.val) * d.portion AS cdiff
			, CASE
				WHEN lead(d.ts) OVER slot < end_ts THEN (lead(p.val) OVER slot - p.val)
				ELSE 0
				END AS rdiff
			, first_value(p.val) OVER slot AS rstart
			, CASE
				WHEN row_number() OVER slot = row_number() OVER reading THEN last_value(p.val) OVER reading
				ELSE NULL
				END AS rend
		FROM d
		INNER JOIN unnest(d.data_a) WITH ORDINALITY AS p(val, idx) ON TRUE
		WINDOW slot AS (PARTITION BY p.idx ORDER BY d.ts RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
				, reading AS (PARTITION BY p.idx, CASE WHEN d.ts < end_ts THEN 0 ELSE 1 END ORDER BY d.ts RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
	)
	-- calculate accumulating statistics
	, da AS (
		SELECT
			w.idx
			, to_char(sum(w.cdiff), 'FM999999999999999999990.999999999')::numeric AS val
			, to_char(sum(w.rdiff), 'FM999999999999999999990.999999999')::numeric AS diff
			, min(w.rstart) AS rstart
			, min(w.rend) AS rend
		FROM wa w
		WHERE w.wval IS NOT NULL
		GROUP BY w.idx
	)
	-- join data_i and meta_i property values back into arrays
	, da_ary AS (
		SELECT
			  array_agg(d.val ORDER BY d.idx) AS data_a
			, array_agg(
				ARRAY[d.diff, d.rstart, d.rend] ORDER BY d.idx
			) AS read_a
		FROM da d
	)
	SELECT
		sid AS stream_id
		, start_ts AS ts_start
		, di_ary.data_i
		, di_ary.stat_i
		, da_ary.data_a
		, da_ary.read_a
	FROM di_ary, da_ary
$$;
