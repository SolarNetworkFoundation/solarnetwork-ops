GRANT USAGE ON SCHEMA public TO solaroscp;
GRANT USAGE ON SCHEMA solaruser TO solaroscp;

GRANT SELECT(user_id, node_id, archived) ON solaruser.user_node TO solaroscp;

REVOKE ALL ON TABLE solaroscp.oscp_fp_token FROM solaruser;
REVOKE ALL ON TABLE solaroscp.oscp_cp_token FROM solaruser;
REVOKE ALL ON TABLE solaroscp.oscp_co_token FROM solaruser;

ALTER FUNCTION solaroscp.create_fp_token(text) SECURITY DEFINER;
ALTER FUNCTION solaroscp.fp_id_for_token(TEXT) SECURITY DEFINER;
