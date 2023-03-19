CREATE SCHEMA IF NOT EXISTS _timescaledb_solarnetwork;

/**
 * Change a normal table into a hypertable, following specific conventions.
 *
 * If the table has a primary key named `{table_name}_pkey` then the primary key constraint will be
 * dropped and a new unique index named `{table_name}_pkey` will be created, in `index_tblespace`
 * if provided.
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
		AND EXISTS (SELECT 1 FROM pg_catalog.pg_index WHERE indrelid = c.oid AND indisprimary)
		AND a.attnum > 0
		AND NOT a.attisdropped;

	IF pkey_cols IS NOT NULL THEN
		EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I', schem_name, table_name, pkey_name);

		stmt := format('CREATE UNIQUE INDEX %I ON %I.%I (%s)', pkey_name, schem_name, table_name, pkey_cols);
		IF NOT index_tblspace IS NULL THEN
			stmt := stmt || format(' TABLESPACE %I', index_tblspace);
		END IF;

		EXECUTE stmt;
	END IF;

	stmt := format('SELECT public.create_hypertable(%s::regclass, %s::name, chunk_time_interval => interval %s, create_default_indexes => FALSE)',
		quote_literal(schem_name || '.' || table_name), quote_literal(ts_col_name), quote_literal(chunk_interval));

	RAISE NOTICE '%', stmt;
	EXECUTE stmt;
END
$$;
