GRANT REFERENCES ON TABLE _timescaledb_catalog.chunk TO public;

ALTER SCHEMA _timescaledb_solarnetwork OWNER TO solarnet;

CREATE TABLE IF NOT EXISTS _timescaledb_solarnetwork.chunk_index_maint (
	chunk_id integer NOT NULL,
	index_name name NOT NULL,
	last_reindex timestamp with time zone,
	CONSTRAINT chunk_index_maint_pkey PRIMARY KEY (chunk_id, index_name),
	CONSTRAINT chunk_index_maint_chunk_id_fk FOREIGN KEY (chunk_id)
      REFERENCES _timescaledb_catalog.chunk (id) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE CASCADE
);

ALTER TABLE _timescaledb_solarnetwork.chunk_index_maint
  OWNER TO solarnet;

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

ALTER TABLE _timescaledb_solarnetwork.chunk_time_index_maint
  OWNER TO solarnet;


/**
 * Find all chunk indexes needing maintenance.
 *
 * @param chunk_max_age		the maximum age of a chunk to consider
 * @param chunk_min_age		the minimum age of a chunk to consider
 * @param redindex_min_age	the minimum interval before reindexing an index
 */
CREATE OR REPLACE FUNCTION _timescaledb_solarnetwork.find_chunk_index_need_maint(
    chunk_max_age interval DEFAULT interval '24 weeks',
    chunk_min_age interval DEFAULT interval '1 week',
    reindex_min_age interval DEFAULT interval '11 weeks'
    )
	RETURNS TABLE(schema_name name, table_name name, index_name name) LANGUAGE sql STABLE AS
$$
SELECT
	chunk_schema_name,
	chunk_table_name,
	chunk_index_name
FROM _timescaledb_solarnetwork.chunk_time_index_maint
WHERE chunk_upper_range BETWEEN CURRENT_TIMESTAMP - chunk_max_age AND CURRENT_TIMESTAMP - chunk_min_age
AND (chunk_index_last_reindex IS NULL OR chunk_index_last_reindex < CURRENT_TIMESTAMP - reindex_min_age)
$$;

ALTER FUNCTION _timescaledb_solarnetwork.find_chunk_index_need_maint(interval, interval, interval)
  OWNER TO solarnet;


/**
 * Perform maintenance on one specific chunk table.
 *
 * @param chunk_schema		the name of the schema of the chunk
 * @param chunk_table		the name of the chunk table
 * @param chunk_index		the name of the chunk index
 * @param not_dry_run		when false, do not perform actual maintenance, just return the indexes that match
 */
CREATE OR REPLACE FUNCTION _timescaledb_solarnetwork.perform_one_chunk_reindex_maintenance(
    chunk_schema text,
    chunk_table text,
    chunk_index text,
    not_dry_run boolean DEFAULT FALSE
    )
    RETURNS SETOF _timescaledb_solarnetwork.chunk_index_maint LANGUAGE plpgsql AS
$$
DECLARE
    rec _timescaledb_solarnetwork.chunk_index_maint%rowtype;
    mtn _timescaledb_solarnetwork.chunk_time_index_maint%rowtype;
BEGIN
	FOR mtn IN
		SELECT * FROM _timescaledb_solarnetwork.chunk_time_index_maint
		WHERE
			chunk_schema_name = chunk_schema::name
			AND chunk_table_name = chunk_table::name
			AND chunk_index_name = chunk_Index::name
	LOOP
		IF not_dry_run THEN
			RAISE NOTICE 'Reindexing chunk index % on table %', mtn.chunk_index_name, mtn.chunk_table_name;

			EXECUTE 'REINDEX INDEX ' || quote_ident(mtn.chunk_schema_name) || '.' || quote_ident(mtn.chunk_index_name);

			RAISE NOTICE 'Clustering chunk table %', mtn.chunk_table_name;

			EXECUTE 'CLUSTER ' || quote_ident(mtn.chunk_schema_name) || '.' || quote_ident(mtn.chunk_table_name);

			RAISE NOTICE 'Analyzing chunk table %', mtn.chunk_table_name;

			EXECUTE 'ANALYZE ' || quote_ident(mtn.chunk_schema_name) || '.' || quote_ident(mtn.chunk_table_name);

			EXECUTE 'INSERT INTO _timescaledb_solarnetwork.chunk_index_maint (chunk_id, index_name, last_reindex)'
				|| ' VALUES ($1, $2, $3) ON CONFLICT (chunk_id, index_name)'
				|| ' DO UPDATE SET last_reindex = EXCLUDED.last_reindex'
			USING mtn.chunk_id, mtn.chunk_index_name, CURRENT_TIMESTAMP;

			rec.last_reindex := CURRENT_TIMESTAMP;
		ELSE
			rec.last_reindex := mtn.chunk_index_last_reindex;
		END IF;

		rec.chunk_id := mtn.chunk_id;
		rec.index_name := mtn.chunk_index_name;
		RETURN NEXT rec;
	END LOOP;
	RETURN;
END
$$;

ALTER FUNCTION _timescaledb_solarnetwork.perform_one_chunk_reindex_maintenance(text, text, text, boolean)
  OWNER TO solarnet;


/**
 * Find all chunk indexes needing maintenance and perform the maintenance on them.
 *
 * @param chunk_max_age		the maximum age of a chunk to consider
 * @param chunk_min_age		the minimum age of a chunk to consider
 * @param redindex_min_age	the minimum interval before reindexing an index
 * @param not_dry_run		when false, do not perform actual maintenance, just return the indexes that match
 */
CREATE OR REPLACE FUNCTION _timescaledb_solarnetwork.perform_chunk_reindex_maintenance(
    chunk_max_age interval DEFAULT interval '24 weeks',
    chunk_min_age interval DEFAULT interval '1 week',
    reindex_min_age interval DEFAULT interval '11 weeks',
    not_dry_run boolean DEFAULT FALSE
    )
    RETURNS TABLE(schema_name name, table_name name, index_name name) LANGUAGE plpgsql AS
$$
DECLARE
    mtn RECORD;
BEGIN
	FOR mtn IN
		SELECT * FROM _timescaledb_solarnetwork.find_chunk_index_need_maint(chunk_max_age, chunk_min_age, reindex_min_age)
	LOOP
		EXECUTE 'SELECT _timescaledb_solarnetwork.perform_one_chunk_reindex_maintenance($1,$2,$3)'
		USING mtn.schema_name, mtn.table_name, mtn.index_name;

		schema_name := mtn.schema_name;
		table_name := mtn.table_name;
		index_name := mtn.index_name;
		RETURN NEXT;
	END LOOP;
	RETURN;
END
$$;

ALTER FUNCTION _timescaledb_solarnetwork.perform_chunk_reindex_maintenance(interval, interval, interval, boolean)
  OWNER TO solarnet;

/* Example call:

SELECT * FROM _timescaledb_solarnetwork.perform_chunk_reindex_maintenance(
	chunk_max_age => interval '3 months',
	chunk_min_age => interval '1 week',
	reindex_min_age => interval '1 day',
	not_dry_run => TRUE);
*/
