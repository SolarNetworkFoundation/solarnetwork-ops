CREATE OR REPLACE FUNCTION public.set_ownership(schem_name text, owner_name text)
RETURNS TABLE(objtype character, schemaname text, objname text, stmt text) LANGUAGE plpgsql VOLATILE AS
$$
BEGIN
	schemaname := schem_name;
	FOR objtype, objname, stmt IN
		(SELECT 'S' AS objtype, schem_name AS objname,
			format('ALTER SCHEMA %I OWNER TO %I', schem_name, owner_name) AS stmt)
		UNION ALL
		(SELECT 't' AS objtype, o.tablename AS objname,
			format('ALTER TABLE %I.%I OWNER TO %I', schem_name, o.tablename, owner_name) AS stmt
		FROM pg_catalog.pg_tables o
		WHERE o.schemaname = schem_name
		ORDER BY o.tablename)
		UNION ALL
		(SELECT 's' AS objtype, o.sequence_name AS objname,
			format('ALTER SEQUENCE %I.%I OWNER TO %I', schem_name, o.sequence_name, owner_name) AS stmt
		FROM information_schema.sequences o
		WHERE o.sequence_schema = schem_name
		ORDER BY o.sequence_name)
		UNION ALL
		(SELECT 'v' AS objtype, o.table_name AS objname,
			format('ALTER VIEW %I.%I OWNER TO %I', schem_name, o.table_name, owner_name) AS stmt
		FROM information_schema.views o
		WHERE o.table_schema = schem_name
		ORDER BY o.table_name)
		UNION ALL
		(SELECT 'f' AS objtype, o.proname || '(' || pg_catalog.pg_get_function_identity_arguments(o.oid) || ')' AS objname,
			format('ALTER FUNCTION %I.%I(%s) OWNER TO %I', schem_name, o.proname, pg_catalog.pg_get_function_identity_arguments(o.oid), owner_name) AS stmt
		FROM pg_catalog.pg_proc o
		JOIN pg_catalog.pg_namespace n ON n.oid = o.pronamespace
		WHERE n.nspname = schem_name
			AND o.prokind = 'f'
		ORDER BY o.proname)
		UNION ALL
		(SELECT 'a' AS objtype, o.proname || '(' || pg_catalog.pg_get_function_identity_arguments(o.oid) || ')' AS objname,
			format('ALTER AGGREGATE %I.%I(%s) OWNER TO %I', schem_name, o.proname, pg_catalog.pg_get_function_identity_arguments(o.oid), owner_name) AS stmt
		FROM pg_catalog.pg_proc o
		JOIN pg_catalog.pg_namespace n ON n.oid = o.pronamespace
		WHERE n.nspname = schem_name
			AND o.prokind = 'a'
		ORDER BY o.proname)
	LOOP
		EXECUTE stmt;
		RETURN NEXT;
	END LOOP;
	RETURN;
END
$$;

CREATE OR REPLACE FUNCTION public.revoke_all_public(schem_name text)
RETURNS TABLE(objtype character, schemaname text, objname text, stmt text) LANGUAGE plpgsql VOLATILE AS
$$
BEGIN
	schemaname := schem_name;
	FOR objtype, objname, stmt IN
		(SELECT 't' AS objtype, o.tablename AS objname,
			format('REVOKE ALL ON TABLE %I.%I FROM PUBLIC', schem_name, o.tablename) AS stmt
		FROM pg_catalog.pg_tables o
		WHERE o.schemaname = schem_name
		ORDER BY o.tablename)

		UNION ALL
		(SELECT 's' AS objtype, o.sequence_name AS objname,
			format('REVOKE ALL ON SEQUENCE %I.%I FROM PUBLIC', schem_name, o.sequence_name) AS stmt
		FROM information_schema.sequences o
		WHERE o.sequence_schema = schem_name
		ORDER BY o.sequence_name)

		UNION ALL
		(SELECT 'v' AS objtype, o.table_name AS objname,
			format('REVOKE ALL ON TABLE %I.%I FROM PUBLIC', schem_name, o.table_name) AS stmt
		FROM information_schema.views o
		WHERE o.table_schema = schem_name
		ORDER BY o.table_name)

		UNION ALL
		(SELECT 'f' AS objtype, o.proname || '(' || pg_catalog.pg_get_function_identity_arguments(o.oid) || ')' AS objname,
			format('REVOKE ALL ON FUNCTION %I.%I(%s) FROM PUBLIC', schem_name, o.proname, pg_catalog.pg_get_function_identity_arguments(o.oid)) AS stmt
		FROM pg_catalog.pg_proc o
		JOIN pg_catalog.pg_namespace n ON n.oid = o.pronamespace
		WHERE n.nspname = schem_name
		ORDER BY o.proname)
	LOOP
		EXECUTE stmt;
		RETURN NEXT;
	END LOOP;
	RETURN;
END
$$;

CREATE OR REPLACE FUNCTION public.grant_role_all(schem_name text, role_name text)
RETURNS TABLE(objtype character, schemaname text, objname text, stmt text) LANGUAGE plpgsql VOLATILE AS
$$
BEGIN
	FOR objtype, schemaname, objname, stmt IN
		SELECT * FROM public.revoke_all_public(schem_name)
	LOOP
		RETURN NEXT;
	END LOOP;

	schemaname := schem_name;
	FOR objtype, objname, stmt IN
		(SELECT 'S' AS objtype, schem_name AS objname,
			format('GRANT USAGE ON SCHEMA %I TO %I', schem_name, role_name) AS stmt
		)

		UNION ALL
		(SELECT 't' AS objtype, o.tablename AS objname,
			format('GRANT ALL ON TABLE %I.%I TO %I', schem_name, o.tablename, role_name) AS stmt
		FROM pg_catalog.pg_tables o
		WHERE o.schemaname = schem_name
		ORDER BY o.tablename)

		UNION ALL
		(SELECT 's' AS objtype, o.sequence_name AS objname,
			format('GRANT ALL ON SEQUENCE %I.%I TO %I', schem_name, o.sequence_name, role_name) AS stmt
		FROM information_schema.sequences o
		WHERE o.sequence_schema = schem_name
		ORDER BY o.sequence_name)

		UNION ALL
		(SELECT 'v' AS objtype, o.table_name AS objname,
			format('GRANT ALL ON TABLE %I.%I TO %I', schem_name, o.table_name, role_name) AS stmt
		FROM information_schema.views o
		WHERE o.table_schema = schem_name
		ORDER BY o.table_name)

		UNION ALL
		(SELECT 'f' AS objtype, o.proname || '(' || pg_catalog.pg_get_function_identity_arguments(o.oid) || ')' AS objname,
			format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO %I', schem_name, o.proname, pg_catalog.pg_get_function_identity_arguments(o.oid), role_name) AS stmt
		FROM pg_catalog.pg_proc o
		JOIN pg_catalog.pg_namespace n ON n.oid = o.pronamespace
		WHERE n.nspname = schem_name
		ORDER BY o.proname)
	LOOP
		EXECUTE stmt;
		RETURN NEXT;
	END LOOP;
	RETURN;
END
$$;

CREATE OR REPLACE FUNCTION public.grant_role_read(schem_name text, role_name text)
RETURNS TABLE(objtype character, schemaname text, objname text, stmt text) LANGUAGE plpgsql VOLATILE AS
$$
BEGIN
	schemaname := schem_name;
	FOR objtype, objname, stmt IN
		(SELECT 'S' AS objtype, schem_name AS objname,
			format('GRANT USAGE ON SCHEMA %I TO %I', schem_name, role_name) AS stmt
		)

		UNION ALL
		(SELECT 't' AS objtype, o.tablename AS objname,
			format('GRANT SELECT ON TABLE %I.%I TO %I', schem_name, o.tablename, role_name) AS stmt
		FROM pg_catalog.pg_tables o
		WHERE o.schemaname = schem_name
		ORDER BY o.tablename)

		UNION ALL
		(SELECT 's' AS objtype, o.sequence_name AS objname,
			format('GRANT SELECT ON SEQUENCE %I.%I TO %I', schem_name, o.sequence_name, role_name) AS stmt
		FROM information_schema.sequences o
		WHERE o.sequence_schema = schem_name
		ORDER BY o.sequence_name)

		UNION ALL
		(SELECT 'v' AS objtype, o.table_name AS objname,
			format('GRANT SELECT ON TABLE %I.%I TO %I', schem_name, o.table_name, role_name) AS stmt
		FROM information_schema.views o
		WHERE o.table_schema = schem_name
		ORDER BY o.table_name)

		UNION ALL
		(SELECT 'f' AS objtype, o.proname || '(' || pg_catalog.pg_get_function_identity_arguments(o.oid) || ')' AS objname,
			format('GRANT EXECUTE ON FUNCTION %I.%I(%s) TO %I', schem_name, o.proname, pg_catalog.pg_get_function_identity_arguments(o.oid), role_name) AS stmt
		FROM pg_catalog.pg_proc o
		JOIN pg_catalog.pg_namespace n ON n.oid = o.pronamespace
		WHERE n.nspname = schem_name
		ORDER BY o.proname)
	LOOP
		EXECUTE stmt;
		RETURN NEXT;
	END LOOP;
	RETURN;
END
$$;

CREATE OR REPLACE FUNCTION public.set_index_tablespace(schem_name text, tblspace_name text)
RETURNS TABLE(schemaname text, objname text, stmt text) LANGUAGE plpgsql VOLATILE AS
$$
BEGIN
	schemaname := schem_name;
	FOR objname, stmt IN
		(SELECT o.indexname AS objname,
			format('ALTER INDEX %I.%I SET TABLESPACE %I', schem_name, o.indexname, tblspace_name) AS stmt
		FROM pg_catalog.pg_indexes o
		WHERE o.schemaname = schem_name
		ORDER BY o.indexname)
	LOOP
		EXECUTE stmt;
		RETURN NEXT;
	END LOOP;
	RETURN;
END
$$;
