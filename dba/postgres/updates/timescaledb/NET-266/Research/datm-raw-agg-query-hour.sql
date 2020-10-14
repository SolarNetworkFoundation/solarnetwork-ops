-- grab raw data, constrained by stream/date range
WITH d AS (
	SELECT *
	FROM solardatm.da_datm d
	/*WHERE d.stream_id = ANY(ARRAY['b213ffef-35c9-4a5f-b935-88c7a735aba0'::uuid])
		AND d.ts >= '2020-10-12 16:00:00+13'::timestamptz
		AND d.ts < '2020-10-12 17:00:00+13'::timestamptz
*/)
-- aggregate data_i values per property
, di AS (
	SELECT d.stream_id
		, date_trunc('hour', d.ts) AS ts_start, to_char(avg(p.val), 'FM999999999999999999990.999999999')::numeric AS val, p.idx AS idx, count(p.val) AS cnt
	FROM d
	LEFT JOIN LATERAL unnest(d.data_i) WITH ORDINALITY AS p(val, idx) ON TRUE
	GROUP BY d.stream_id, p.idx, date_trunc('hour', d.ts)
)
-- join data_i property values back into array
, di_ary AS (
	SELECT d.stream_id, d.ts_start, array_agg(d.val ORDER BY d.idx) AS data_i, array_agg(cnt ORDER BY d.idx) AS cnt_i
	FROM di d
	GROUP BY d.stream_id, d.ts_start
	
)
-- aggregate data_a values per property
, da AS (
	SELECT d.stream_id
		, date_trunc('hour', d.ts) AS ts_start, to_char(avg(p.val), 'FM999999999999999999990.999999999')::numeric AS val, p.idx AS idx, count(p.val) AS cnt
	FROM d
	LEFT JOIN LATERAL unnest(d.data_a) WITH ORDINALITY AS p(val, idx) ON TRUE
	GROUP BY d.stream_id, p.idx, date_trunc('hour', d.ts)
)
-- join data_a property values back into array
, da_ary AS (
	SELECT d.stream_id, d.ts_start, array_agg(d.val ORDER BY d.idx) AS data_a, array_agg(cnt ORDER BY d.idx) AS cnt_a
	FROM da d
	GROUP BY d.stream_id, d.ts_start
	
)
SELECT COALESCE(di_ary.stream_id, da_ary.stream_id) AS stream_id
	, COALESCE(di_ary.ts_start, da_ary.ts_start) AS ts_start
	, di_ary.data_i
	, di_ary.cnt_i
	, da_ary.data_a
	, da_ary.cnt_a
FROM di_ary
FULL OUTER JOIN da_ary ON 
	da_ary.stream_id = di_ary.stream_id 
	AND da_ary.ts_start = di_ary.ts_start
;
