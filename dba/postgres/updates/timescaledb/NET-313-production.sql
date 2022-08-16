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

GRANT USAGE ON SCHEMA public TO solaroscp;
GRANT USAGE ON SCHEMA solaroscp TO solaroscp;
GRANT USAGE ON SCHEMA solaruser TO solaroscp;

GRANT SELECT(user_id, node_id, archived) ON solaruser.user_node TO solaroscp;

REVOKE ALL ON TABLE solaroscp.oscp_fp_token FROM solaroscp;
REVOKE ALL ON TABLE solaroscp.oscp_fp_token FROM solaruser;

REVOKE ALL ON TABLE solaroscp.oscp_cp_token FROM solaroscp;
REVOKE ALL ON TABLE solaroscp.oscp_cp_token FROM solaruser;
GRANT SELECT ON TABLE solaroscp.oscp_cp_token TO solaroscp;

REVOKE ALL ON TABLE solaroscp.oscp_co_token FROM solaroscp;
REVOKE ALL ON TABLE solaroscp.oscp_co_token FROM solaruser;
GRANT SELECT ON TABLE solaroscp.oscp_co_token TO solaroscp;

ALTER FUNCTION solaroscp.create_fp_token(BIGINT, BIGINT) SECURITY DEFINER;
ALTER FUNCTION solaroscp.create_cp_token(BIGINT, BIGINT) SECURITY DEFINER;
ALTER FUNCTION solaroscp.create_co_token(BIGINT, BIGINT) SECURITY DEFINER;
ALTER FUNCTION solaroscp.fp_id_for_token(TEXT) SECURITY DEFINER;
