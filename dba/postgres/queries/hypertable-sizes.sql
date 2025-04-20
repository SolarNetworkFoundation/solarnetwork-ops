WITH h AS (
	SELECT hypertable_schema || '.' || hypertable_name AS table_name
	FROM timescaledb_information.hypertables
)
, d AS (
	SELECT *
		, pg_size_pretty(table_bytes) AS tab_size
		, pg_size_pretty(index_bytes) AS idx_size
		, pg_size_pretty(total_bytes) AS tot_size
	FROM h, chunks_detailed_size(h.table_name)
	ORDER BY chunk_name, node_name
)
, g AS (
	SELECT table_name, d.chunk_name
		, COALESCE(ch.range_start, to_timestamp(ch.range_start_integer / 1000000)) AS range_start
		, COALESCE(ch.range_end, to_timestamp(ch.range_end_integer / 1000000)) AS range_end
		, tab_size, idx_size, tot_size
		, table_bytes AS tab_bytes, index_bytes AS idx_bytes, total_bytes AS tot_bytes
	FROM d
	INNER JOIN timescaledb_information.chunks ch ON ch.chunk_name = d.chunk_name
	UNION ALL
	SELECT table_name AS table_name
		, 'TOTAL' AS chunk_name
		, MIN(COALESCE(ch.range_start, to_timestamp(ch.range_start_integer / 1000000))) AS range_start
		, MAX(COALESCE(ch.range_end, to_timestamp(ch.range_end_integer / 1000000))) AS range_end
		, pg_size_pretty(SUM(table_bytes)) AS tab_size
		, pg_size_pretty(SUM(index_bytes)) AS idx_size
		, pg_size_pretty(SUM(total_bytes)) AS tot_size
		, SUM(table_bytes) AS tab_bytes
		, SUM(index_bytes) AS idx_bytes
		, SUM(total_bytes) AS tot_bytes
	FROM d
	INNER JOIN timescaledb_information.chunks ch ON ch.chunk_name = d.chunk_name
	GROUP BY table_name
)
(
SELECT *
FROM g
ORDER BY table_name
	-- for TOTAL row sort last via Very Large Date
	, CASE WHEN chunk_name = 'TOTAL' THEN '9999-01-01+00'::timestamptz ELSE range_end END
)

UNION ALL

SELECT 'TOTAL' AS table_name
	, 'TOTAL' AS chunk_name
	, NULL AS range_start
	, NULL AS range_end
	, pg_size_pretty(SUM(table_bytes)) AS tab_size
	, pg_size_pretty(SUM(index_bytes)) AS idx_size
	, pg_size_pretty(SUM(total_bytes)) AS tot_size
	, SUM(table_bytes) AS tab_bytes
	, SUM(index_bytes) AS idx_bytes
	, SUM(total_bytes) AS tot_bytes
FROM d
;
