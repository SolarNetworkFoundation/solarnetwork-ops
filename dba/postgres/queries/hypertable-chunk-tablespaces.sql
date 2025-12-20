WITH chunks AS (
	SELECT oid, oid::TEXT AS chunk_tablename
	FROM show_chunks('solardatm.da_datm'::REGCLASS/*, older_than => INTERVAL '5 years', newer_than => INTERVAL '100 years'*/) SHOW (oid)
)
, chunk_det AS (
	SELECT 
		  chunk_schema || '.' || chunk_name AS chunk_tablename
		, *
	FROM chunks_detailed_size('solardatm.da_datm'::REGCLASS)
)
, d AS (
	SELECT
		  c.oid
		, s.chunk_name
		, ch.range_start
		, ch.range_end
		, t.spcname AS tablespace
		, s.table_bytes
		, s.index_bytes
		, pg_size_pretty(s.table_bytes) AS table_size
		, pg_size_pretty(s.index_bytes) AS index_size
	FROM chunks
	INNER JOIN chunk_det s ON s.chunk_tablename = chunks.chunk_tablename
	INNER JOIN pg_namespace n ON n.nspname = s.chunk_schema
	INNER JOIN pg_class c ON c.relnamespace = n.oid AND c.relname::TEXT = s.chunk_name
	INNER JOIN timescaledb_information.chunks ch ON ch.chunk_schema || '.' || ch.chunk_name = chunks.chunk_tablename
	LEFT JOIN pg_tablespace t ON t.oid = c.reltablespace
)
SELECT * FROM d
UNION ALL
SELECT NULL AS oid
	, '-' AS chunk_name
	, NULL AS range_start
	, NULL AS range_end
	, '-' AS tablespace
	, SUM(table_bytes) AS table_bytes
	, SUM(index_bytes) AS index_bytes
	, pg_size_pretty(SUM(table_bytes)) AS table_size
	, pg_size_Pretty(SUM(index_bytes)) AS index_size
FROM d
;
