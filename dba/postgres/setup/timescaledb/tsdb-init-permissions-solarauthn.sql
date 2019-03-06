GRANT USAGE ON SCHEMA public TO solarauthn;
GRANT USAGE ON SCHEMA solaruser TO solarauthn;

GRANT SELECT(auth_token, user_id, status, token_type, jpolicy) ON solaruser.user_auth_token TO solarauthn;
GRANT SELECT(user_id, node_id, archived) ON solaruser.user_node TO solarauthn;
GRANT SELECT ON TABLE solaruser.user_auth_token_node_ids TO solarauthn;

ALTER FUNCTION solaruser.snws2_find_verified_token_details(text, timestamp with time zone, text, text, text) SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION solaruser.snws2_find_verified_token_details(text, timestamp with time zone, text, text, text) TO solarauthn;
