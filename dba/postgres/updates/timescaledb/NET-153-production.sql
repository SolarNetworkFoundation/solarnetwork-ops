-- create new tables / functions / triggers

-- \i init/updates/NET-153-refactor-agg-processing.sql

-- apply production permissions

ALTER FUNCTION solaragg.calc_datum_time_slots(bigint, text[], timestamp with time zone, interval, integer, interval) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.calc_datum_time_slots(bigint,text[],timestamp with time zone,interval,integer,interval) TO solar;
ALTER FUNCTION solaragg.calc_agg_datum_agg(bigint, text[], timestamp with time zone, timestamp with time zone, character) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.calc_agg_datum_agg(bigint,text[],timestamp with time zone,timestamp with time zone,char) TO solar;

ALTER FUNCTION solaragg.calc_loc_datum_time_slots(bigint, text[], timestamp with time zone, interval, integer, interval) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.calc_loc_datum_time_slots(bigint,text[],timestamp with time zone,interval,integer,interval) TO solar;
ALTER FUNCTION solaragg.calc_agg_loc_datum_agg(bigint, text[], timestamp with time zone, timestamp with time zone, character) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.calc_agg_loc_datum_agg(bigint,text[],timestamp with time zone,timestamp with time zone,char) TO solar;
