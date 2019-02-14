-- create new tables / functions / triggers

-- \i init/updates/NET-183-readings-agg.sql

-- apply production permissions

ALTER FUNCTION solarcommon.jsonb_diffsum_jdata_finalfunc(jsonb) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solarcommon.jsonb_diffsum_jdata_finalfunc(jsonb) TO solar;

ALTER FUNCTION solardatum.calculate_datum_diff_over(bigint, text, timestamptz, timestamptz, interval) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.calculate_datum_diff_over(bigint, text, timestamptz, timestamptz, interval) TO solar;
