GRANT USAGE ON SCHEMA public TO solaroscp;
GRANT USAGE ON SCHEMA solaroscp TO solaruser;
GRANT USAGE ON SCHEMA solaroscp TO solarjobs;

GRANT SELECT(user_id, node_id, archived) ON solaruser.user_node TO solaroscp;

REVOKE ALL ON TABLE solaroscp.oscp_fp_token FROM solaroscp;
REVOKE ALL ON TABLE solaroscp.oscp_fp_token FROM solaruser;

REVOKE ALL ON TABLE solaroscp.oscp_cp_token FROM solaroscp;
REVOKE ALL ON TABLE solaroscp.oscp_cp_token FROM solaruser;
GRANT SELECT ON TABLE solaroscp.oscp_cp_token TO solaroscp;

REVOKE ALL ON TABLE solaroscp.oscp_co_token FROM solaroscp;
REVOKE ALL ON TABLE solaroscp.oscp_co_token FROM solaruser;
GRANT SELECT ON TABLE solaroscp.oscp_co_token TO solaroscp;

REVOKE ALL ON FUNCTION solaroscp.create_fp_token FROM PUBLIC;
GRANT EXECUTE ON FUNCTION solaroscp.create_fp_token TO solaroscp;
GRANT EXECUTE ON FUNCTION solaroscp.create_fp_token TO solaruser;
ALTER FUNCTION solaroscp.create_fp_token(BIGINT, BIGINT) SECURITY DEFINER;

REVOKE ALL ON FUNCTION solaroscp.update_fp_token FROM PUBLIC;
REVOKE ALL ON FUNCTION solaroscp.update_fp_token FROM solaruser;
ALTER FUNCTION solaroscp.update_fp_token(BIGINT, BIGINT) SECURITY DEFINER;

REVOKE ALL ON FUNCTION solaroscp.fp_id_for_token FROM PUBLIC;
GRANT EXECUTE ON FUNCTION solaroscp.fp_id_for_token TO solaroscp;
GRANT EXECUTE ON FUNCTION solaroscp.fp_id_for_token TO solaruser;
ALTER FUNCTION solaroscp.fp_id_for_token(TEXT, BOOLEAN) SECURITY DEFINER;

REVOKE ALL ON FUNCTION solaroscp.save_cp_token FROM PUBLIC;
REVOKE ALL ON FUNCTION solaroscp.save_cp_token FROM solaruser;
ALTER FUNCTION solaroscp.save_co_token(BIGINT, BIGINT, TEXT) SECURITY DEFINER;

REVOKE ALL ON FUNCTION solaroscp.save_co_token FROM PUBLIC;
REVOKE ALL ON FUNCTION solaroscp.save_co_token FROM solaruser;
ALTER FUNCTION solaroscp.save_cp_token(BIGINT, BIGINT, TEXT) SECURITY DEFINER;

REVOKE ALL ON FUNCTION solaroscp.get_cp_token FROM PUBLIC;
REVOKE ALL ON FUNCTION solaroscp.get_cp_token FROM solaruser;
ALTER FUNCTION solaroscp.get_co_token(BIGINT, BIGINT) SECURITY DEFINER;

REVOKE ALL ON FUNCTION solaroscp.get_co_token FROM PUBLIC;
REVOKE ALL ON FUNCTION solaroscp.get_co_token FROM solaruser;
ALTER FUNCTION solaroscp.get_cp_token(BIGINT, BIGINT) SECURITY DEFINER;

REVOKE ALL ON FUNCTION solaroscp.conf_id_for_fp_id FROM PUBLIC;
REVOKE ALL ON FUNCTION solaroscp.conf_id_for_fp_id FROM solaruser;
ALTER FUNCTION solaroscp.conf_id_for_fp_id(BIGINT, BIGINT) SECURITY DEFINER;

-- allow generating datum streams from OSCP messages
GRANT INSERT, UPDATE ON solardatm.da_datm_meta TO solaroscp;
GRANT INSERT, UPDATE ON solardatm.da_datm TO solaroscp;
GRANT ALL(stream_id, ts_start, datum_count, prop_count, prop_u_count) ON solardatm.aud_datm_io TO solaroscp;
GRANT INSERT, UPDATE ON TABLE solardatm.agg_stale_datm TO solaroscp;
