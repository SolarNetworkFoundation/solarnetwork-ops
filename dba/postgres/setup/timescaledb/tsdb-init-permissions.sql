-- remove PUBLIC access from all objects
SELECT stmt || ';' AS stmt
FROM (SELECT unnest(ARRAY['_timescaledb_solarnetwork', 'solarbill', 'solardatm', 'solardin', 'solardnp3', 'solarev', 'solarnet', 'solaroscp', 'solaruser']) AS schem) AS s,
LATERAL (SELECT * FROM public.revoke_all_public(s.schem)) AS res;

DO $$
DECLARE
	stmt text;
BEGIN
	FOR stmt IN
		SELECT res.stmt
		FROM (SELECT unnest(ARRAY['solarbill', 'solarcommon', 'solardatm', 'solardin', 'solardnp3', 'solarev', 'solarnet', 'solaroscp', 'solaruser']) AS schem) AS s,
		LATERAL (SELECT format('GRANT USAGE ON SCHEMA %I TO %I', s.schem, 'solar') AS stmt) AS res
	LOOP
		EXECUTE stmt;
	END LOOP;
END;$$;

GRANT SELECT ON TABLE solarcommon.messages TO solar;

\i tsdb-init-permissions-solarauthn.sql
\i tsdb-init-permissions-solardin.sql
\i tsdb-init-permissions-solardnp3.sql
\i tsdb-init-permissions-solarinput.sql
\i tsdb-init-permissions-solaroscp.sql
\i tsdb-init-permissions-solarquery.sql
\i tsdb-init-permissions-solarjobs.sql
\i tsdb-init-permissions-solaruser.sql
