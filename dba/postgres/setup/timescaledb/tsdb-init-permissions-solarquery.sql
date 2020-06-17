GRANT SELECT ON TABLE solaruser.user_auth_token_login TO solarquery;
GRANT SELECT ON TABLE solaruser.user_auth_token_role TO solarquery;
GRANT SELECT ON TABLE solaruser.user_user TO solarquery;
GRANT SELECT ON TABLE solaruser.user_node TO solarquery;

GRANT ALL(ts_start, node_id, source_id, datum_q_count) ON solaragg.aud_datum_hourly TO solarquery;
