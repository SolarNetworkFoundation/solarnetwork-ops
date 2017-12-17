CREATE EXTENSION IF NOT EXISTS timescaledb WITH SCHEMA public;
/*
\echo `date` Creating event trigger to move hypertable chunk index tablespace on demand..

CREATE OR REPLACE FUNCTION update_chunk_index_tablespace_oncreate()
	RETURNS event_trigger LANGUAGE plpgsql AS $$
DECLARE
    r record;
    irow record;
BEGIN
    FOR r IN SELECT * FROM pg_event_trigger_ddl_commands()
    LOOP
		--RAISE NOTICE '% % on %; oid %', r.command_tag, r.object_type, r.object_identity, r.objid;
		FOR irow IN  SELECT n.nspname AS schemaname,
			c.relname AS tablename,
			i.relname AS indexname,
			t.spcname AS tablespace,
			pg_get_indexdef(i.oid) AS indexdef
		FROM pg_index x
		JOIN pg_class c ON c.oid = x.indrelid
		JOIN pg_class i ON i.oid = x.indexrelid
		LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
		LEFT JOIN pg_tablespace t ON t.oid = i.reltablespace
		WHERE (c.relkind = ANY (ARRAY['r'::"char", 'm'::"char"])) AND i.relkind = 'i'::"char"
			AND n.nspname = '_timescaledb_internal' AND t.spcname IS NULL
		LOOP
			RAISE NOTICE 'Moving chunk index % on table %.% to tablespace solarindex',
				irow.indexname, irow.schemaname, irow.tablename;
			EXECUTE format('ALTER INDEX %s.%s SET TABLESPACE solarindex',
				quote_ident(irow.schemaname), quote_ident(irow.indexname));
		END LOOP;
    END LOOP;
END
$$;

DROP EVENT TRIGGER IF EXISTS update_chunk_index_tablespace_oncreate;
CREATE EVENT TRIGGER update_chunk_index_tablespace_oncreate
   ON ddl_command_end WHEN TAG IN ('CREATE TABLE', 'ALTER TABLE')
   EXECUTE PROCEDURE update_chunk_index_tablespace_oncreate();
*/
