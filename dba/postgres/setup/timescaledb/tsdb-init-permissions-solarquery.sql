GRANT SELECT ON TABLE solaruser.user_auth_token_login TO solarquery;
GRANT SELECT ON TABLE solaruser.user_auth_token_role TO solarquery;
GRANT SELECT ON TABLE solaruser.user_user TO solarquery;
GRANT SELECT ON TABLE solaruser.user_node TO solarquery;

GRANT ALL(stream_id, ts_start, datum_q_count) ON solardatm.aud_datm_io TO solarquery;
