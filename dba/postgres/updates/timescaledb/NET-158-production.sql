-- create new tables / functions / triggers

-- \i init/updates/NET-158-available-sources-add-node-ids.sql

-- apply production permissions

ALTER FUNCTION solaragg.find_available_sources(bigint[]) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_available_sources(bigint[]) TO solar;

ALTER FUNCTION solaragg.find_available_sources_since(bigint[], timestamp with time zone) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_available_sources_since(bigint[], timestamp with time zone) TO solar;

ALTER FUNCTION solaragg.find_available_sources_before(bigint[], timestamp with time zone) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_available_sources_before(bigint[], timestamp with time zone) TO solar;

ALTER FUNCTION solaragg.find_available_sources(bigint[], timestamp with time zone, timestamp with time zone) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_available_sources(bigint[], timestamp with time zone, timestamp with time zone) TO solar;
