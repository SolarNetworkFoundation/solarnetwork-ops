GRANT ALL ON FUNCTION solaruser.claim_datum_delete_job() TO solar;
GRANT ALL ON FUNCTION solaruser.expire_datum_for_policy(userid bigint, jpolicy jsonb, age interval) TO solar;
GRANT ALL ON FUNCTION solaruser.find_most_recent_datum_for_user(users bigint[]) TO solar;
GRANT ALL ON FUNCTION solaruser.find_most_recent_datum_for_user_direct(users bigint[]) TO solar;
GRANT ALL ON FUNCTION solaruser.preview_expire_datum_for_policy(userid bigint, jpolicy jsonb, age interval) TO solar;
GRANT ALL ON FUNCTION solaruser.purge_completed_datum_delete_jobs(older_date timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaruser.purge_completed_user_adhoc_export_tasks(older_date timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaruser.purge_completed_user_export_tasks(older_date timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaruser.snws2_canon_request_data(req_date timestamp with time zone, host text, path text) TO solar;
GRANT ALL ON FUNCTION solaruser.snws2_find_verified_token_details(token_id text, req_date timestamp with time zone, host text, path text, signature text) TO solar;
GRANT ALL ON FUNCTION solaruser.snws2_signature(signature_data text, sign_key bytea) TO solar;
GRANT ALL ON FUNCTION solaruser.snws2_signature_data(req_date timestamp with time zone, canon_request_data text) TO solar;
GRANT ALL ON FUNCTION solaruser.snws2_signing_key(sign_date date, secret text) TO solar;
GRANT ALL ON FUNCTION solaruser.snws2_signing_key_hex(sign_date date, secret text) TO solar;
GRANT ALL ON FUNCTION solaruser.snws2_validated_request_date(req_date timestamp with time zone, tolerance interval) TO solar;
GRANT ALL ON FUNCTION solaruser.store_adhoc_export_task(usr bigint, sched character, ex_date timestamp with time zone, cfg text) TO solar;
GRANT ALL ON FUNCTION solaruser.store_export_task(usr bigint, sched character, ex_date timestamp with time zone, cfg_id bigint, cfg text) TO solar;

REVOKE ALL ON FUNCTION solaruser.purge_resolved_situations(older_date timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION solaruser.purge_resolved_situations(older_date timestamp with time zone) TO solarinput;

REVOKE ALL ON FUNCTION solaruser.store_user_data(user_id bigint, json_obj jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION solaruser.store_user_data(user_id bigint, json_obj jsonb) TO solarinput;

REVOKE ALL ON FUNCTION solaruser.store_user_meta(cdate timestamp with time zone, userid bigint, jdata text) FROM PUBLIC;
GRANT ALL ON FUNCTION solaruser.store_user_meta(cdate timestamp with time zone, userid bigint, jdata text) TO solarinput;

REVOKE ALL ON FUNCTION solaruser.store_user_node_cert(created timestamp with time zone, node bigint, userid bigint, stat character, request text, keydata bytea) FROM PUBLIC;
GRANT ALL ON FUNCTION solaruser.store_user_node_cert(created timestamp with time zone, node bigint, userid bigint, stat character, request text, keydata bytea) TO solar;

REVOKE ALL ON FUNCTION solaruser.store_user_node_xfer(node bigint, userid bigint, recip character varying) FROM PUBLIC;
GRANT ALL ON FUNCTION solaruser.store_user_node_xfer(node bigint, userid bigint, recip character varying) TO solarinput;
