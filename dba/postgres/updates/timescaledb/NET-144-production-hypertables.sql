-- create new tables / functions / triggers

-- \i updates/NET-140-snws2-auth-support.sql
-- \i init/updates/NET-144-storage-auditing.sql

-- apply production permissions

GRANT EXECUTE ON FUNCTION solaragg.process_one_aud_datum_daily_stale(char) TO solar;

GRANT SELECT ON TABLE solaragg.aud_datum_daily_stale TO solar;
GRANT ALL ON TABLE solaragg.aud_datum_daily_stale TO solarinput;

GRANT SELECT ON TABLE solaragg.aud_datum_daily TO solar;
GRANT ALL ON TABLE solaragg.aud_datum_daily TO solarinput;

GRANT SELECT ON TABLE solaragg.aud_datum_monthly TO solar;
GRANT ALL ON TABLE solaragg.aud_datum_monthly TO solarinput;

GRANT EXECUTE ON FUNCTION solarcommon.ant_pattern_to_regexp(text) TO solar;
GRANT EXECUTE ON FUNCTION solarcommon.components_from_jdata(jsonb) TO solar;
GRANT EXECUTE ON FUNCTION solarcommon.jdata_from_components(jsonb, jsonb, jsonb, text[]) TO solar;
GRANT EXECUTE ON FUNCTION solarcommon.json_array_to_text_array(json) TO solar;
GRANT EXECUTE ON FUNCTION solarcommon.json_array_to_text_array(jsonb) TO solar;
GRANT EXECUTE ON FUNCTION solarcommon.jsonb_avg_finalfunc(jsonb) TO solar;
GRANT EXECUTE ON FUNCTION solarcommon.jsonb_avg_object_finalfunc(jsonb) TO solar;
GRANT EXECUTE ON FUNCTION solarcommon.jsonb_avg_object_sfunc(jsonb, jsonb) TO solar;
GRANT EXECUTE ON FUNCTION solarcommon.jsonb_avg_sfunc(jsonb, jsonb) TO solar;
GRANT EXECUTE ON FUNCTION solarcommon.jsonb_sum_object_sfunc(jsonb, jsonb) TO solar;
GRANT EXECUTE ON FUNCTION solarcommon.jsonb_sum_sfunc(jsonb, jsonb) TO solar;
GRANT EXECUTE ON FUNCTION solarcommon.reduce_dim(anyarray) TO solar;
GRANT EXECUTE ON FUNCTION solarcommon.to_rfc1123_utc(timestamp with time zone) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_available_sources(bigint[]) TO solar;
GRANT EXECUTE ON FUNCTION solaragg.find_available_sources(bigint[], timestamp with time zone, timestamp with time zone) TO solar;
GRANT EXECUTE ON FUNCTION solaragg.find_available_sources_before(bigint[], timestamp with time zone) TO solar;
GRANT EXECUTE ON FUNCTION solaragg.find_available_sources_since(bigint[], timestamp with time zone) TO solar;
GRANT EXECUTE ON FUNCTION solaragg.jdata_from_datum(solaragg.agg_datum_daily) TO solar;
GRANT EXECUTE ON FUNCTION solaragg.jdata_from_datum(solaragg.agg_datum_hourly) TO solar;
GRANT EXECUTE ON FUNCTION solaragg.jdata_from_datum(solaragg.agg_datum_monthly) TO solar;
GRANT EXECUTE ON FUNCTION solaragg.jdata_from_datum(solaragg.agg_loc_datum_daily) TO solar;
GRANT EXECUTE ON FUNCTION solaragg.jdata_from_datum(solaragg.agg_loc_datum_hourly) TO solar;
GRANT EXECUTE ON FUNCTION solaragg.jdata_from_datum(solaragg.agg_loc_datum_monthly) TO solar;

GRANT EXECUTE ON FUNCTION solaruser.snws2_canon_request_data(timestamp with time zone, text, text) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_find_verified_token_details(text, timestamp with time zone, text, text, text) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_signature(text, bytea) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_signature_data(timestamp with time zone, text) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.snws2_validated_request_date(timestamp with time zone, interval) TO solar;

-- move indexes to right tablespace and convert from PRIMARY KEY to UNIQUE INDEX
-- so hypertable remembers tablespace in chunk tables

ALTER TABLE solaragg.aud_datum_daily DROP CONSTRAINT aud_datum_daily_pkey;

CREATE UNIQUE INDEX aud_datum_daily_pkey
	ON solaragg.aud_datum_daily (node_id, ts_start, source_id)
	TABLESPACE solarindex;

ALTER TABLE solaragg.aud_datum_monthly DROP CONSTRAINT aud_datum_monthly_pkey;

CREATE UNIQUE INDEX aud_datum_monthly_pkey
	ON solaragg.aud_datum_monthly (node_id, ts_start, source_id)
	TABLESPACE solarindex;

-- create hypertables

SELECT public.create_hypertable('solaragg.aud_datum_daily'::regclass, 'ts_start'::name,
	chunk_time_interval => interval '1 years',
	create_default_indexes => FALSE);

SELECT public.create_hypertable('solaragg.aud_datum_monthly'::regclass, 'ts_start'::name,
	chunk_time_interval => interval '5 years',
	create_default_indexes => FALSE);

