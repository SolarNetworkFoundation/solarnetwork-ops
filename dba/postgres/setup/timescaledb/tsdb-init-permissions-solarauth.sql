GRANT CONNECT ON DATABASE solarnetwork TO solarauth;
GRANT USAGE ON SCHEMA public TO solarauth;
GRANT USAGE ON SCHEMA solaruser TO solarauth;

GRANT SELECT(auth_token, user_id, status, token_type, jpolicy) ON solaruser.user_auth_token TO solarauth;
GRANT SELECT(user_id, node_id, archived) ON solaruser.user_node TO solarauth;
GRANT SELECT ON TABLE solaruser.user_auth_token_node_ids TO solarauth;

ALTER FUNCTION solaruser.snws2_find_verified_token_details(text, timestamp with time zone, text, text, text) SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION solaruser.snws2_find_verified_token_details(text, timestamp with time zone, text, text, text) TO solarauth;
