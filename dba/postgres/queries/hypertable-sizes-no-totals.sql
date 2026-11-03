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
		, t.spcname AS chunk_tablespace
		, COALESCE(ch.range_start, to_timestamp(ch.range_start_integer / 1000000)) AS range_start
		, COALESCE(ch.range_end, to_timestamp(ch.range_end_integer / 1000000)) AS range_end
		, table_bytes AS tab_bytes, index_bytes AS idx_bytes, total_bytes AS tot_bytes
		, tab_size, idx_size, tot_size
	FROM d
	INNER JOIN timescaledb_information.chunks ch ON ch.chunk_name = d.chunk_name
	INNER JOIN pg_namespace n ON n.nspname = d.chunk_schema
	INNER JOIN pg_class c ON c.relnamespace = n.oid AND c.relname::TEXT = d.chunk_name
	LEFT JOIN pg_tablespace t ON t.oid = c.reltablespace
)
(
SELECT *
FROM g
ORDER BY table_name, range_end
)
;
