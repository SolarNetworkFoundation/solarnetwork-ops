-- create new tables / functions / triggers

-- \i init/updates/NET-167-datum-delete.sql

-- apply production permissions

ALTER TABLE solaruser.user_datum_delete_job OWNER TO solarnet;
GRANT SELECT ON TABLE solaruser.user_datum_delete_job TO solar;
GRANT ALL ON TABLE solaruser.user_datum_delete_job TO solarinput;

ALTER FUNCTION solarcommon.json_array_to_bigint_array(json) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solarcommon.json_array_to_bigint_array(json) TO public;

ALTER FUNCTION solarcommon.jsonb_array_to_bigint_array(jsonb) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solarcommon.jsonb_array_to_bigint_array(jsonb) TO public;

ALTER FUNCTION solarnet.node_source_time_ranges_local(bigint[], text[], timestamp, timestamp) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solarnet.node_source_time_ranges_local(bigint[], text[], timestamp, timestamp) TO solar;

ALTER FUNCTION solardatum.datum_record_counts(bigint[], text[], timestamp, timestamp) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.datum_record_counts(bigint[], text[], timestamp, timestamp) TO solar;

ALTER FUNCTION solardatum.datum_record_counts_for_filter(jsonb) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.datum_record_counts_for_filter(jsonb) TO solar;

ALTER FUNCTION solardatum.delete_datum(bigint[], text[], timestamp, timestamp) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.delete_datum(bigint[], text[], timestamp, timestamp) TO solar;

ALTER FUNCTION solardatum.delete_datum_for_filter(jsonb) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.delete_datum_for_filter(jsonb) TO solar;

ALTER FUNCTION solaruser.claim_datum_delete_job() OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaruser.claim_datum_delete_job() TO solar;

ALTER FUNCTION solaruser.purge_completed_datum_delete_jobs(timestamp with time zone) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaruser.purge_completed_datum_delete_jobs(timestamp with time zone) TO solar;
