-- TODO: check if these are used in SolarQuery
--GRANT EXECUTE ON FUNCTION solaruser.find_most_recent_datum_for_user(users bigint[]) TO solar;
--GRANT EXECUTE ON FUNCTION solaruser.find_most_recent_datum_for_user_direct(users bigint[]) TO solar;

-- this function should only be for specific users that need it
--GRANT EXECUTE ON FUNCTION solaruser.snws2_find_verified_token_details(token_id text, req_date timestamp with time zone, host text, path text, signature text) TO solar;

GRANT ALL ON TABLE solardatm.agg_stale_datm TO solaruser;
GRANT ALL ON TABLE solardatm.da_datm_aux TO solaruser;
GRANT INSERT ON TABLE solaruser.user_event_log TO solar;

-- allow updating node datum stream metadata
GRANT INSERT(stream_id, node_id, source_id, jdata, updated) ON solardatm.da_datm_meta TO solaruser;
GRANT UPDATE(node_id, source_id, jdata, updated) ON solardatm.da_datm_meta TO solaruser;

-- GRANT EXECUTE ON FUNCTION solaragg.find_datum_hour_slots(bigint[], text[], timestamp with time zone, timestamp with time zone) TO solaruser;
-- MAYBE? FUNCTION solardatm.find_datm_hours(uuid, timestamp with time zone, timestamp with time zone)
--GRANT EXECUTE ON FUNCTION solardatm.mark_stale_datm_hours(uuid, timestamp with time zone, timestamp with time zone) TO solaruser;
--GRANT EXECUTE ON FUNCTION solardatm.move_datum_aux(uuid, timestamp with time zone, solardatm.da_datm_aux_type, uuid, timestamp with time zone, solardatm.da_datm_aux_type, text, jsonb, jsonb, jsonb) TO solaruser;
--GRANT EXECUTE ON FUNCTION solardatm.store_datum_aux(uuid, timestamp with time zone, solardatm.da_datm_aux_type, text, jsonb, jsonb, jsonb) TO solaruser;

-- perhaps these functions belong in solarcommon, as they are basic utilities
GRANT EXECUTE ON FUNCTION solaruser.snws2_canon_request_data(req_date timestamp with time zone, host text, path text) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_signature(signature_data text, sign_key bytea) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_signature_data(req_date timestamp with time zone, canon_request_data text) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_signing_key(sign_date date, secret text) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_signing_key_hex(sign_date date, secret text) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_validated_request_date(req_date timestamp with time zone, tolerance interval) TO solar;
