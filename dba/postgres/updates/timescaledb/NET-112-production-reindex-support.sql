\echo `date` Creating chunk reindex support...

\c solarnetwork postgres
GRANT REFERENCES ON TABLE _timescaledb_catalog.chunk TO public;
\c solarnetwork solarnet

CREATE SCHEMA IF NOT EXISTS _timescaledb_solarnetwork;

CREATE TABLE _timescaledb_solarnetwork.chunk_index_maint (
	chunk_id integer NOT NULL,
	index_name name NOT NULL,
	last_reindex timestamp with time zone,
	CONSTRAINT chunk_index_maint_pkey PRIMARY KEY (chunk_id, index_name),
	CONSTRAINT chunk_index_maint_chunk_id_fk FOREIGN KEY (chunk_id)
      REFERENCES _timescaledb_catalog.chunk (id) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE CASCADE
);

INSERT INTO _timescaledb_solarnetwork.chunk_index_maint
	(chunk_id, index_name, last_reindex)
SELECT cidx.chunk_id, cidx.index_name, CURRENT_TIMESTAMP
FROM _timescaledb_catalog.chunk_index cidx;

CREATE OR REPLACE VIEW _timescaledb_solarnetwork.chunk_time_index_maint AS
SELECT ht.id AS hypertable_id
	, ht.schema_name AS hypertable_schema_name
	, ht.table_name AS hypertable_table_name
	, ch.id AS chunk_id, ch.schema_name AS chunk_schema_name
	, ch.table_name AS chunk_table_name
	, to_timestamp(upper(chs.ranges[1])::double precision / 1000000) AS chunk_upper_range
	, chi.index_name AS chunk_index_name
	, chm.last_reindex AS chunk_index_last_reindex
	, pgi.indexdef AS chunk_index_def
	, pgi.tablespace AS chunk_index_tablespace
FROM _timescaledb_catalog.chunk ch
INNER JOIN _timescaledb_catalog.hypertable ht ON ht.id = ch.hypertable_id
INNER JOIN chunk_relation_size(ht.schema_name::text||'.'||ht.table_name::text) chs ON chs.chunk_id = ch.id
INNER JOIN _timescaledb_catalog.chunk_index chi ON chi.chunk_id = ch.id
INNER JOIN pg_indexes pgi ON pgi.schemaname = ch.schema_name AND pgi.tablename = ch.table_name AND pgi.indexname = chi.index_name
LEFT OUTER JOIN _timescaledb_solarnetwork.chunk_index_maint chm ON chm.chunk_id = ch.id AND chm.index_name = chi.index_name
WHERE chs.partitioning_column_types[1] = 'timestamp with time zone'::regtype;

/* Example query to find chunk indexes to reindex...
-- select chunks that end more than 1 month ago, but less than 1 year ago as we don't expect to update old data, and haven't been reindexed within the last 3 months
SELECT * FROM _timescaledb_solarnetwork.chunk_time_index_maint
WHERE chunk_upper_range BETWEEN CURRENT_TIMESTAMP - interval '1 year' AND CURRENT_TIMESTAMP - interval '1 month'
	AND (chunk_index_last_reindex IS NULL OR chunk_index_last_reindex < CURRENT_TIMESTAMP - interval '3 months')
*/
