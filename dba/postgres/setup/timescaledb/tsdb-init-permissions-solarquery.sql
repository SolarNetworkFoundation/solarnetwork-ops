GRANT SELECT ON TABLE solaruser.user_auth_token_login TO solarquery;
GRANT SELECT ON TABLE solaruser.user_auth_token_role TO solarquery;
GRANT SELECT ON TABLE solaruser.user_user TO solarquery;
GRANT SELECT ON TABLE solaruser.user_node TO solarquery;

-- allow updating datum audit counts on query
GRANT ALL(stream_id, ts_start, datum_q_count, flux_byte_count) ON solardatm.aud_datm_io TO solarquery;
GRANT INSERT, UPDATE ON TABLE solardatm.aud_stale_datm TO solarquery;

-- allow updating user audit counts
GRANT SELECT, INSERT, UPDATE ON TABLE solardatm.aud_user_io TO solarquery;
GRANT INSERT, UPDATE ON TABLE solardatm.aud_stale_user TO solarquery;
