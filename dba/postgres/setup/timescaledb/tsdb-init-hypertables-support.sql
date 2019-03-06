CREATE SCHEMA IF NOT EXISTS _timescaledb_solarnetwork;

GRANT REFERENCES ON TABLE _timescaledb_catalog.chunk TO PUBLIC;

CREATE TABLE IF NOT EXISTS _timescaledb_solarnetwork.chunk_index_maint (
	chunk_id integer NOT NULL,
	index_name name NOT NULL,
	last_reindex timestamp with time zone,
	last_cluster timestamp with time zone,
	CONSTRAINT chunk_index_maint_pkey PRIMARY KEY (chunk_id, index_name),
	CONSTRAINT chunk_index_maint_chunk_id_fk FOREIGN KEY (chunk_id)
      REFERENCES _timescaledb_catalog.chunk (id) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE CASCADE
);

CREATE OR REPLACE VIEW _timescaledb_solarnetwork.chunk_time_index_maint AS
SELECT ht.id AS hypertable_id
	, ht.schema_name AS hypertable_schema_name
	, ht.table_name AS hypertable_table_name
	, ch.id AS chunk_id, ch.schema_name AS chunk_schema_name
	, ch.table_name AS chunk_table_name
    , to_timestamp(dims.range_start::double precision / 1000000::double precision) AS chunk_lower_range
    , to_timestamp(dims.range_end::double precision / 1000000::double precision) AS chunk_upper_range
	, chi.index_name AS chunk_index_name
	, chm.last_reindex AS chunk_index_last_reindex
	, chm.last_cluster AS chunk_index_last_cluster
	, pgi.indexdef AS chunk_index_def
	, pgi.tablespace AS chunk_index_tablespace
	, pgs.n_tup_ins
	, pgs.n_tup_upd
	, pgs.n_tup_del
	, pgs.n_dead_tup
	, pgs.n_live_tup
	, ((pgs.n_dead_tup::double precision / pgs.n_live_tup::double precision) * 100)::integer AS dead_tup_percent
	, (((pgs.n_tup_ins + pgs.n_tup_upd + pgs.n_tup_del)::double precision / pgs.n_live_tup::double precision) * 100)::integer AS mod_tup_percent
FROM _timescaledb_catalog.chunk ch
INNER JOIN _timescaledb_catalog.chunk_constraint chs ON chs.chunk_id = ch.id
INNER JOIN _timescaledb_catalog.dimension dim ON ch.hypertable_id = dim.hypertable_id
INNER JOIN _timescaledb_catalog.dimension_slice dims ON dims.dimension_id = dim.id AND dims.id = chs.dimension_slice_id
INNER JOIN pg_catalog.pg_stat_user_tables pgs ON pgs.schemaname = ch.schema_name AND pgs.relname = ch.table_name
INNER JOIN _timescaledb_catalog.hypertable ht ON ht.id = ch.hypertable_id
INNER JOIN _timescaledb_catalog.chunk_index chi ON chi.chunk_id = ch.id
INNER JOIN pg_indexes pgi ON pgi.schemaname = ch.schema_name AND pgi.tablename = ch.table_name AND pgi.indexname = chi.index_name
LEFT OUTER JOIN _timescaledb_solarnetwork.chunk_index_maint chm ON chm.chunk_id = ch.id AND chm.index_name = chi.index_name
WHERE dim.column_type = 'timestamp with time zone'::regtype;


/**
 * Find all chunk indexes needing reindex OR cluster maintenance.
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
AND (
		(chunk_index_last_reindex IS NULL OR chunk_index_last_reindex < CURRENT_TIMESTAMP - reindex_min_age)
		OR (chunk_index_last_cluster IS NULL OR chunk_index_last_cluster < CURRENT_TIMESTAMP - reindex_min_age)
	)
ORDER BY chunk_id
$$;


/**
 * Find all chunk indexes needing reindex maintenance.
 *
 * @param chunk_max_age		the maximum age of a chunk to consider
 * @param chunk_min_age		the minimum age of a chunk to consider
 * @param redindex_min_age	the minimum interval before reindexing an index
 */
CREATE OR REPLACE FUNCTION _timescaledb_solarnetwork.find_chunk_index_need_reindex_maint(
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
ORDER BY chunk_id
$$;


/**
 * Find all chunk indexes needing cluster maintenance.
 *
 * This will cluster chunks by their FIRST index, where indexes are ordered alphabetically by name.
 * The mod_threshold factor applies to any chunk older than chunk_min_age.
 *
 * @param chunk_max_age		the maximum age of a chunk to consider
 * @param chunk_min_age		the minimum age of a chunk to consider
 * @param redindex_min_age	the minimum interval before reindexing an index
 * @param mod_threshold		the minimum modification threshold (dead tuples)
 */
CREATE OR REPLACE FUNCTION _timescaledb_solarnetwork.find_chunk_index_need_cluster_maint(
    chunk_max_age interval DEFAULT interval '24 weeks',
    chunk_min_age interval DEFAULT interval '1 week',
    reindex_min_age interval DEFAULT interval '11 weeks',
    mod_threshold integer DEFAULT 50
    )
	RETURNS TABLE(schema_name name, table_name name, index_name name) LANGUAGE sql STABLE AS
$$
WITH ranked AS (
	SELECT DISTINCT ON (chunk_id)
		chunk_id,
		chunk_schema_name,
		chunk_table_name,
		chunk_index_name,
		chunk_upper_range,
		chunk_index_last_cluster,
		n_dead_tup
	FROM _timescaledb_solarnetwork.chunk_time_index_maint
	ORDER BY chunk_id, chunk_index_name
)
SELECT
	chunk_schema_name,
	chunk_table_name,
	chunk_index_name
FROM ranked
WHERE (chunk_upper_range BETWEEN CURRENT_TIMESTAMP - chunk_max_age AND CURRENT_TIMESTAMP - chunk_min_age
		AND (chunk_index_last_cluster IS NULL OR chunk_index_last_cluster < CURRENT_TIMESTAMP - reindex_min_age))
	OR (chunk_upper_range < CURRENT_TIMESTAMP - chunk_min_age AND n_dead_tup >= mod_threshold)
ORDER BY chunk_id
$$;


/**
 * Perform reindex maintenance on one specific chunk table.
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
			AND chunk_index_name = chunk_index::name
	LOOP
		IF not_dry_run THEN
			RAISE NOTICE 'Reindexing chunk index % on table %', mtn.chunk_index_name, mtn.chunk_table_name;

			EXECUTE 'REINDEX INDEX ' || quote_ident(mtn.chunk_schema_name) || '.' || quote_ident(mtn.chunk_index_name);

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


/**
 * Perform cluster maintenance on one specific chunk table.
 *
 * @param chunk_schema		the name of the schema of the chunk
 * @param chunk_table		the name of the chunk table
 * @param chunk_index		the name of the chunk index
 * @param not_dry_run		when false, do not perform actual maintenance, just return the indexes that match
 */
CREATE OR REPLACE FUNCTION _timescaledb_solarnetwork.perform_one_chunk_cluster_maintenance(
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
			AND chunk_index_name = chunk_index::name
	LOOP
		IF not_dry_run THEN
			RAISE NOTICE 'Clustering chunk table %', mtn.chunk_table_name;

			EXECUTE 'CLUSTER ' || quote_ident(mtn.chunk_schema_name) || '.' || quote_ident(mtn.chunk_table_name)
				|| ' USING ' || quote_ident(mtn.chunk_index_name);

			RAISE NOTICE 'Analyzing chunk table %', mtn.chunk_table_name;

			EXECUTE 'ANALYZE ' || quote_ident(mtn.chunk_schema_name) || '.' || quote_ident(mtn.chunk_table_name);

			EXECUTE 'INSERT INTO _timescaledb_solarnetwork.chunk_index_maint (chunk_id, index_name, last_cluster)'
				|| ' VALUES ($1, $2, $3) ON CONFLICT (chunk_id, index_name)'
				|| ' DO UPDATE SET last_cluster = EXCLUDED.last_cluster'
			USING mtn.chunk_id, mtn.chunk_index_name, CURRENT_TIMESTAMP;

			rec.last_cluster := CURRENT_TIMESTAMP;
		ELSE
			rec.last_cluster := mtn.chunk_index_last_cluster;
		END IF;

		rec.chunk_id := mtn.chunk_id;
		rec.index_name := mtn.chunk_index_name;
		RETURN NEXT rec;
	END LOOP;
	RETURN;
END
$$;


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


/* Example call:

SELECT * FROM _timescaledb_solarnetwork.perform_chunk_reindex_maintenance(
	chunk_max_age => interval '3 months',
	chunk_min_age => interval '1 week',
	reindex_min_age => interval '1 day',
	not_dry_run => TRUE);
*/

/**
 * Change a normal table into a hypertable, following specific conventions.
 *
 * The conventions required by this function are:
 * 
 *  * The table must have a primary key named `{table_name}_pkey`
 *  * A new unique index named `{table_name}_pkey` will be created, in `index_tblespace` if provided
 * 
 * @param schem_name the table schema name
 * @param table_name the table name
 * @param ts_col_name the timestamp column name to use with the hypertable
 * @param chunk_interval the chunk interval to use, e.g. '6 months'
 * @param index_tblspace if provided, the tablespace to use for the created unique index
 */
CREATE OR REPLACE FUNCTION _timescaledb_solarnetwork.change_to_hypertable(
	schem_name text,
	table_name text,
	ts_col_name text,
	chunk_interval text,
	index_tblspace text DEFAULT NULL
    )
    RETURNS VOID LANGUAGE plpgsql AS
$$
DECLARE
	stmt text;
	pkey_name text := table_name || '_pkey';
	pkey_cols text;
BEGIN
	SELECT array_to_string(array_agg(pg_catalog.pg_get_indexdef(a.attrelid, a.attnum, TRUE) ORDER BY a.attnum), ',')
	INTO pkey_cols
	FROM pg_catalog.pg_class c
	INNER JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
	INNER JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid
	WHERE n.nspname = schem_name
		AND c.relname = pkey_name
		AND a.attnum > 0
		AND NOT a.attisdropped;
	
	EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I', schem_name, table_name, pkey_name);

	stmt := format('CREATE UNIQUE INDEX %I ON %I.%I (%s)', pkey_name, schem_name, table_name, pkey_cols);
	IF NOT index_tblspace IS NULL THEN
		stmt := stmt || format(' TABLESPACE %I', index_tblspace);
	END IF;
	
	EXECUTE stmt;
	
	stmt := format('SELECT public.create_hypertable(%s::regclass, %s::name, chunk_time_interval => interval %s, create_default_indexes => FALSE)',
		quote_literal(schem_name || '.' || table_name), quote_literal(ts_col_name), quote_literal(chunk_interval));
	
	RAISE NOTICE '%', stmt;
	EXECUTE stmt;
END
$$;
