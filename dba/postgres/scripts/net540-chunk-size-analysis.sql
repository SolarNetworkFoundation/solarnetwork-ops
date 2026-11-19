-- per stream: datum, 15m slots and hours with data, classed by cadence
WITH s AS (
	SELECT stream_id
		, count(*) AS datum
		, count(DISTINCT time_bucket('15 minutes', ts)) AS slots
		, count(DISTINCT time_bucket('1 hour', ts)) AS hours
	FROM solardatm.da_datm
	WHERE ts >= :'day'::timestamptz AND ts < :'day'::timestamptz + interval '1 day'
	GROUP BY stream_id
)
SELECT CASE
		WHEN datum::numeric / hours > 4 THEN '1: under 15 min'
		WHEN datum::numeric / hours > 1 THEN '2: 15 to 60 min'
		ELSE '3: 60 min or more' END AS cadence
	, count(*) AS streams, sum(datum) AS datum, sum(slots) AS rows_15m, sum(hours) AS rows_hourly
FROM s GROUP BY 1 ORDER BY 1;

-- gaps between consecutive datum, which is what D1 turns on
SELECT count(*) FILTER (WHERE gap <= interval '15 minutes') AS le_15m
	, count(*) FILTER (WHERE gap > interval '15 minutes' AND gap <= interval '1 hour') AS le_1h
	, count(*) FILTER (WHERE gap > interval '1 hour') AS gt_1h
FROM (
	SELECT ts - lag(ts) OVER (PARTITION BY stream_id ORDER BY ts) AS gap
	FROM solardatm.da_datm
	WHERE ts >= :'day'::timestamptz AND ts < :'day'::timestamptz + interval '1 day'
) g;

-- bytes per aggregate row; a 15m row has the same columns as an hourly row
SELECT count(*) AS row_count, avg(pg_column_size(d.*))::int AS avg_row_bytes
FROM solardatm.agg_datm_hourly d
WHERE ts_start >= :'day'::timestamptz AND ts_start < :'day'::timestamptz + interval '1 day';
