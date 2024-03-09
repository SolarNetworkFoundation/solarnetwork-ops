/*
CREATE ROLE solardin WITH
  NOLOGIN
  NOSUPERUSER
  INHERIT
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION;
GRANT solar TO solardin;
*/

CREATE SCHEMA IF NOT EXISTS solardin;

\i ../../setup/timescaledb/tsdb-init-din-schema.sql

\i init/updates/NET-365-datum-input.sql

\i ../../setup/timescaledb/tsdb-init-permissions-solardin.sql

SELECT stmt || ';' FROM (SELECT unnest(ARRAY['solardin']) AS schem) AS s,
LATERAL (SELECT * FROM public.set_index_tablespace(s.schem, 'solarindex')) AS res \gexec
