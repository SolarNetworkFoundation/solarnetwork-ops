-- create new tables / functions / triggers

-- \i init/updates/NET-162-year-aggregate-query.sql

-- apply production permissions

ALTER FUNCTION solarnet.node_source_time_rounded(bigint[], text[], text , timestamp, timestamp) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solarnet.node_source_time_rounded(bigint[], text[], text , timestamp, timestamp) TO solar;

ALTER FUNCTION solaragg.datum_agg_agg_sfunc(jsonb, jsonb) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.datum_agg_agg_sfunc(jsonb, jsonb) TO solar;

ALTER FUNCTION solaragg.datum_agg_agg_finalfunc(jsonb) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.datum_agg_agg_finalfunc(jsonb) TO solar;
