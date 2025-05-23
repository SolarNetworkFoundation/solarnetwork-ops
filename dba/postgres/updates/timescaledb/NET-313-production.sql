CREATE SCHEMA IF NOT EXISTS solaroscp;

-- solaroscp
ALTER DEFAULT PRIVILEGES IN SCHEMA solaroscp REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA solaroscp REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA solaroscp REVOKE ALL ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA solaroscp REVOKE ALL ON TYPES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES IN SCHEMA solaroscp GRANT ALL ON TABLES TO solaroscp;
ALTER DEFAULT PRIVILEGES IN SCHEMA solaroscp GRANT ALL ON SEQUENCES TO solaroscp;
ALTER DEFAULT PRIVILEGES IN SCHEMA solaroscp GRANT ALL ON FUNCTIONS TO solaroscp;
ALTER DEFAULT PRIVILEGES IN SCHEMA solaroscp GRANT ALL ON TYPES TO solaroscp;

ALTER DEFAULT PRIVILEGES IN SCHEMA solaroscp GRANT ALL ON TABLES TO solaruser;

\i init/updates/NET-313-oscp-fp.sql

\i ../../setup/timescaledb/tsdb-init-permissions-solaroscp.sql
