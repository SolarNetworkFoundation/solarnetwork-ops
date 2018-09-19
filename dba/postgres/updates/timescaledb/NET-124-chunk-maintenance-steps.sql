ALTER TABLE _timescaledb_solarnetwork.chunk_index_maint ADD COLUMN last_cluster timestamp with time zone;

UPDATE _timescaledb_solarnetwork.chunk_index_maint
SET last_cluster = last_reindex
where last_reindex IS NOT NULL;

DROP VIEW _timescaledb_solarnetwork.chunk_time_index_maint;

CREATE OR REPLACE VIEW _timescaledb_solarnetwork.chunk_time_index_maint AS
SELECT ht.id AS hypertable_id
	, ht.schema_name AS hypertable_schema_name
	, ht.table_name AS hypertable_table_name
	, ch.id AS chunk_id, ch.schema_name AS chunk_schema_name
	, ch.table_name AS chunk_table_name
	, to_timestamp(upper(chs.ranges[1])::double precision / 1000000) AS chunk_upper_range
	, chi.index_name AS chunk_index_name
	, chm.last_reindex AS chunk_index_last_reindex
	, chm.last_cluster AS chunk_index_last_cluster
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

ALTER FUNCTION _timescaledb_solarnetwork.perform_one_chunk_reindex_maintenance(text, text, text, boolean)
  OWNER TO solarnet;

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

ALTER FUNCTION _timescaledb_solarnetwork.perform_one_chunk_cluster_maintenance(text, text, text, boolean)
  OWNER TO solarnet;

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

ALTER FUNCTION _timescaledb_solarnetwork.find_chunk_index_need_maint(interval, interval, interval)
  OWNER TO solarnet;


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

ALTER FUNCTION _timescaledb_solarnetwork.find_chunk_index_need_reindex_maint(interval, interval, interval)
  OWNER TO solarnet;

CREATE OR REPLACE FUNCTION _timescaledb_solarnetwork.find_chunk_index_need_cluster_maint(
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
AND (chunk_index_last_cluster IS NULL OR chunk_index_last_cluster < CURRENT_TIMESTAMP - reindex_min_age)
ORDER BY chunk_id
$$;

ALTER FUNCTION _timescaledb_solarnetwork.find_chunk_index_need_cluster_maint(interval, interval, interval)
  OWNER TO solarnet;
