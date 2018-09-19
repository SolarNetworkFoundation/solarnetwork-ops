-- create new tables / functions / triggers

-- \i init/updates/NET-155-reading-at.sql

-- apply production permissions

ALTER FUNCTION solarcommon.first_sfunc (anyelement, anyelement) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solarcommon.first_sfunc (anyelement, anyelement) TO solar;

ALTER FUNCTION solarcommon.jsonb_diff_object_sfunc(jsonb, jsonb) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solarcommon.jsonb_diff_object_sfunc(jsonb, jsonb) TO solar;
ALTER FUNCTION solarcommon.jsonb_diff_object_finalfunc(jsonb) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solarcommon.jsonb_diff_object_finalfunc(jsonb) TO solar;

ALTER FUNCTION solarcommon.jsonb_weighted_proj_object_sfunc(jsonb, jsonb, float8) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solarcommon.jsonb_weighted_proj_object_sfunc(jsonb, jsonb, float8) TO solar;
ALTER FUNCTION solarcommon.jsonb_weighted_proj_object_finalfunc(jsonb) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solarcommon.jsonb_weighted_proj_object_finalfunc(jsonb) TO solar;

ALTER FUNCTION solardatum.calculate_datum_at(bigint[], text[], timestamptz, interval) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.calculate_datum_at(bigint[], text[], timestamptz, interval) TO solar;

ALTER FUNCTION solardatum.calculate_datum_at_local(bigint[], text[], timestamp, interval) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.calculate_datum_at_local(bigint[], text[], timestamp, interval) TO solar;

ALTER FUNCTION solardatum.calculate_datum_diff_local(bigint, text, timestamptz, timestamptz, interval) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.calculate_datum_diff_local(bigint, text, timestamptz, timestamptz, interval) TO solar;

ALTER FUNCTION solardatum.calculate_datum_diff_local(bigint[], text[], timestamp, timestamp, interval) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.calculate_datum_diff_local(bigint[], text[], timestamp, timestamp, interval) TO solar;
