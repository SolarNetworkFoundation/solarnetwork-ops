-- Gaps and Islands problem: find contiguous ranges within datum streams,
-- based on a maximum time threshold between time-adjacent datum rows
WITH m AS (
	SELECT stream_id ,node_id, source_id
	FROM solardatm.da_datm_meta
	WHERE node_id = 108
		AND source_id = 'DB'
)
, diff AS (
	SELECT d.stream_id
		, d.ts
		, EXTRACT('epoch' FROM d.ts - lag(d.ts, 1, d.ts) OVER slot) AS ts_diff
		
		-- assign a "gap" flag to each row, set to 1 if the time difference between this and
		-- the previous row is too large
		, CASE
			WHEN d.ts - lag(d.ts, 1, d.ts) OVER slot > INTERVAL '5 minutes' 
			THEN 1 
			ELSE 0
		  END AS gap
	FROM solardatm.da_datm d
	INNER JOIN m ON m.stream_id = d.stream_id
	WINDOW slot AS (PARTITION BY d.stream_id ORDER BY d.ts)
)
, slots AS (
	SELECT d.stream_id
		, d.ts
		, d.ts_diff
		, d.gap
		
		-- assign an "island" ID to each row
    	, ROW_NUMBER() OVER slot1 - ROW_NUMBER() OVER slot2 AS island_id
	FROM diff d	
	WINDOW slot1 AS (PARTITION BY d.stream_id ORDER BY d.ts)
		, slot2 AS (PARTITION BY d.stream_id, d.gap ORDER BY d.ts)
)

-- derive stats from "islands" by filtering out gap rows and grouping by island ID
SELECT d.stream_id
	, solarcommon.first(m.node_id) AS node_id
	, solarcommon.first(m.source_id) AS source_id
	, min(ts) AS ts_start
	, max(ts) AS ts_end
	, max(ts) - min(ts) AS duration
	, avg(ts_diff) AS avg_freq
	, count(*) AS total_count
FROM slots d
INNER JOIN m ON m.stream_id = d.stream_id
WHERE gap = 0
GROUP BY d.stream_id, island_id
HAVING count(*) >= 288
ORDER BY node_id, source_id, ts_start
