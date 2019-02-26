-- create new tables / functions / triggers

-- \i init/updates/NET-186-most-recent.sql

-- apply production permissions

ALTER TABLE solardatum.da_datum_range OWNER TO solarnet;
GRANT SELECT ON TABLE solardatum.da_datum_range TO solar;
GRANT ALL ON TABLE solardatum.da_datum_range TO solarinput;

ALTER FUNCTION solardatum.update_datum_range_dates(bigint, character varying(64), timestamp with time zone) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.update_datum_range_dates(bigint, character varying(64), timestamp with time zone) TO solar;

ALTER FUNCTION solardatum.store_datum(timestamp with time zone, bigint, text, timestamp with time zone,  text, boolean) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.store_datum(timestamp with time zone, bigint, text, timestamp with time zone,  text, boolean) TO solarin;
REVOKE ALL ON FUNCTION solardatum.store_datum(timestamp with time zone, bigint, text, timestamp with time zone, text, boolean) FROM public;

ALTER FUNCTION solardatum.find_least_recent_direct(bigint) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_least_recent_direct(bigint) TO solar;

ALTER FUNCTION solardatum.find_most_recent_direct(bigint) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_most_recent_direct(bigint) TO solar;

ALTER FUNCTION solardatum.find_most_recent(bigint) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_most_recent(bigint) TO solar;

ALTER FUNCTION solardatum.find_most_recent_direct(bigint, text[]) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_most_recent_direct(bigint, text[]) TO solar;

ALTER FUNCTION solardatum.find_most_recent(bigint, text[]) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_most_recent(bigint, text[]) TO solar;

ALTER FUNCTION solardatum.find_most_recent_direct(bigint[]) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_most_recent_direct(bigint[]) TO solar;

ALTER FUNCTION solardatum.find_most_recent(bigint[]) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_most_recent(bigint[]) TO solar;

ALTER FUNCTION solaruser.find_most_recent_datum_for_user_direct(bigint[]) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaruser.find_most_recent_datum_for_user_direct(bigint[]) TO solar;

ALTER FUNCTION solaruser.find_most_recent_datum_for_user(bigint[]) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaruser.find_most_recent_datum_for_user(bigint[]) TO solar;

ALTER FUNCTION solardatum.find_reportable_interval(bigint, text) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_reportable_interval(bigint, text) TO solar;

ALTER FUNCTION solardatum.find_reportable_intervals(bigint[]) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_reportable_intervals(bigint[]) TO solar;

ALTER FUNCTION solardatum.find_reportable_intervals(bigint[], text[]) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_reportable_intervals(bigint[], text[]) TO solar;

ALTER FUNCTION solardatum.find_available_sources(bigint[]) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_available_sources(bigint[]) TO solar;

ALTER FUNCTION solardatum.find_available_sources(bigint, timestamp with time zone, timestamp with time zone) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_available_sources(bigint, timestamp with time zone, timestamp with time zone) TO solar;

ALTER FUNCTION solaragg.find_available_sources(bigint[]) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_available_sources(bigint[]) TO solar;
