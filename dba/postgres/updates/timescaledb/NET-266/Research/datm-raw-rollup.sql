--explain analyze
SELECT * FROM solardatm.rollup_datm_for_time_span(
	'ade25d3b-faa1-4df8-8c99-bb24b58635ac'::uuid,
	'2020-05-14 13:00:00+12'::timestamptz,
	'2020-05-14 13:00:00+12'::timestamptz + INTERVAL '1 hour'
	);

/*
 NOTE ON CLOCK VS READING

 "Clock" refers to normalized clock periods, where datum rows are interpolated at exact period
 start and end value. This affects accumulating properties in that difference of accumulation
 between two rows on either side of a period transition is split proportionally to each period.

 "Reading" refers to periods where the datum included range from the latest row on or before the
 period start to the latest row before the period end. No interpolation is applied between the
 resulting rows within that range.
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
	) LANGUAGE SQL STABLE ROWS 500 AS
$$
	-- grab raw data, constrained by stream/date range
	WITH d AS (
		SELECT * FROM solardatm.find_datm_for_time_span(
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
		LEFT JOIN LATERAL unnest(d.data_i) WITH ORDINALITY AS p(val, idx) ON TRUE
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
		GROUP BY w.idx
	)
	-- join data_i and meta_i property values back into arrays
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
		LEFT JOIN LATERAL unnest(d.data_a) WITH ORDINALITY AS p(val, idx) ON TRUE
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
