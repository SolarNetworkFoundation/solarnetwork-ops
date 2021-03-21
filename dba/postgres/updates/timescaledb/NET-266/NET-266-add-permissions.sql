-- remove PUBLIC access from all objects
SELECT stmt || ';' AS stmt
FROM (SELECT unnest(ARRAY['solardatm']) AS schem) AS s,
LATERAL (SELECT * FROM public.revoke_all_public(s.schem)) AS res;

DO $$
DECLARE
	stmt text;
BEGIN
	FOR stmt IN
		SELECT res.stmt
		FROM (SELECT unnest(ARRAY['solardatm']) AS schem) AS s,
		LATERAL (SELECT format('GRANT USAGE ON SCHEMA %I TO %I', s.schem, 'solar') AS stmt) AS res
	LOOP
		EXECUTE stmt;
	END LOOP;
END;$$;

