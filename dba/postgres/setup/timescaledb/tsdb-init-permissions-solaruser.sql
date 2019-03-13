-- TODO: check if these are used in SolarQuery
--GRANT EXECUTE ON FUNCTION solaruser.find_most_recent_datum_for_user(users bigint[]) TO solar;
--GRANT EXECUTE ON FUNCTION solaruser.find_most_recent_datum_for_user_direct(users bigint[]) TO solar;

-- this function should only be for specific users that need it
--GRANT EXECUTE ON FUNCTION solaruser.snws2_find_verified_token_details(token_id text, req_date timestamp with time zone, host text, path text, signature text) TO solar;

-- perhaps these functions belong in solarcommon, as they are basic utilities
GRANT EXECUTE ON FUNCTION solaruser.snws2_canon_request_data(req_date timestamp with time zone, host text, path text) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_signature(signature_data text, sign_key bytea) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_signature_data(req_date timestamp with time zone, canon_request_data text) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_signing_key(sign_date date, secret text) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_signing_key_hex(sign_date date, secret text) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_validated_request_date(req_date timestamp with time zone, tolerance interval) TO solar;
