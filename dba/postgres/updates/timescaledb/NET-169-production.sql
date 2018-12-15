-- create new tables / functions / triggers

-- \i init/updates/NET-169-solarflux.sql

-- apply production permissions
--
-- NOTE: must be run as superuser for CREATE USER

ALTER TABLE solaruser.user_auth_token_node_ids OWNER TO solarnet;
GRANT SELECT ON TABLE solaruser.user_auth_token_node_ids TO solar;
GRANT ALL ON TABLE solaruser.user_auth_token_node_ids TO solarinput;

CREATE ROLE solarauth WITH
  LOGIN
  NOSUPERUSER
  INHERIT
  NOCREATEDB
  NOCREATEROLE
  NOREPLICATION;
COMMENT ON ROLE solarauth IS 'SolarNetwork role for performing authentication against user tokens.';

GRANT CONNECT ON DATABASE solarnetwork TO solarauth;
GRANT USAGE ON SCHEMA public TO solarauth;
GRANT USAGE ON SCHEMA solaruser TO solarauth;

ALTER FUNCTION solaruser.snws2_find_verified_token_details(text, timestamp with time zone, text, text, text) SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION solaruser.snws2_find_verified_token_details(text, timestamp with time zone, text, text, text) TO solarauth;

GRANT SELECT(auth_token, user_id, status, token_type, jpolicy) ON solaruser.user_auth_token TO solarauth;
GRANT SELECT(user_id, node_id, archived) ON solaruser.user_node TO solarauth;
GRANT SELECT ON TABLE solaruser.user_auth_token_node_ids TO solarauth;
