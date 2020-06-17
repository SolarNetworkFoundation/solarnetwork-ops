-- TODO: check if these are used in SolarQuery
--GRANT EXECUTE ON FUNCTION solaruser.find_most_recent_datum_for_user(users bigint[]) TO solar;
--GRANT EXECUTE ON FUNCTION solaruser.find_most_recent_datum_for_user_direct(users bigint[]) TO solar;

-- this function should only be for specific users that need it
--GRANT EXECUTE ON FUNCTION solaruser.snws2_find_verified_token_details(token_id text, req_date timestamp with time zone, host text, path text, signature text) TO solar;

GRANT ALL ON TABLE solaragg.agg_stale_datum TO solaruser;
GRANT ALL ON TABLE solardatum.da_datum_aux TO solaruser;
GRANT EXECUTE ON FUNCTION solaragg.find_datum_hour_slots(bigint[], text[], timestamp with time zone, timestamp with time zone) TO solaruser;
GRANT EXECUTE ON FUNCTION solaragg.mark_datum_stale_hour_slots(bigint[], text[], timestamp with time zone, timestamp with time zone) TO solaruser;
GRANT EXECUTE ON FUNCTION solardatum.move_datum_aux(timestamp with time zone, bigint, character varying, solardatum.da_datum_aux_type, timestamp with time zone, bigint, character varying, solardatum.da_datum_aux_type, text, text, text, text) TO solaruser;
GRANT EXECUTE ON FUNCTION solardatum.store_datum_aux(timestamp with time zone, bigint, character varying, solardatum.da_datum_aux_type, text, text, text, text) TO solaruser;

-- perhaps these functions belong in solarcommon, as they are basic utilities
GRANT EXECUTE ON FUNCTION solaruser.snws2_canon_request_data(req_date timestamp with time zone, host text, path text) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_signature(signature_data text, sign_key bytea) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_signature_data(req_date timestamp with time zone, canon_request_data text) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_signing_key(sign_date date, secret text) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_signing_key_hex(sign_date date, secret text) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_validated_request_date(req_date timestamp with time zone, tolerance interval) TO solar;
