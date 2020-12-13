-- remove PUBLIC access from all objects
SELECT stmt || ';' AS stmt
FROM (SELECT unnest(ARRAY['_timescaledb_solarnetwork', 'quartz', 'solarbill', 'solardatm', 'solarev', 'solarnet', 'solaruser']) AS schem) AS s,
LATERAL (SELECT * FROM public.revoke_all_public(s.schem)) AS res;

DO $$
DECLARE
	stmt text;
BEGIN
	FOR stmt IN
		SELECT res.stmt
		FROM (SELECT unnest(ARRAY['solarbill', 'solarcommon', 'solardatm', 'solarev', 'solarnet', 'solaruser']) AS schem) AS s,
		LATERAL (SELECT format('GRANT USAGE ON SCHEMA %I TO %I', s.schem, 'solar') AS stmt) AS res
	LOOP
		EXECUTE stmt;
	END LOOP;
END;$$;

GRANT SELECT ON TABLE solarcommon.messages TO solar;

\i tsdb-init-permissions-solarauthn.sql
\i tsdb-init-permissions-solarinput.sql
\i tsdb-init-permissions-solarquery.sql
\i tsdb-init-permissions-solarjobs.sql
