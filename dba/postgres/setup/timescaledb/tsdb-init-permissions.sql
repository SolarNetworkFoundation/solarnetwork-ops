-- remove PUBLIC access from all objects
SELECT stmt || ';' AS stmt
FROM (SELECT unnest(ARRAY['_timescaledb_solarnetwork', 'quartz', 'solaragg', 'solarcommon', 'solardatum', 'solarnet', 'solaruser']) AS schem) AS s,
LATERAL (SELECT * FROM public.revoke_all_public(s.schem)) AS res;

\i tsdb-init-permissions-solarauthn.sql
\i tsdb-init-permissions-solarjobs.sql
