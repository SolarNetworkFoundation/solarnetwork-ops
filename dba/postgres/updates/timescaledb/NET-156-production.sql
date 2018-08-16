-- create new tables / functions / triggers

-- \i init/updates/NET-156-running-total-nodes.sql

-- apply production permissions

ALTER FUNCTION solaragg.calc_running_datum_total(bigint[], text[], timestamp with time zone) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.calc_running_datum_total(bigint[], text[], timestamp with time zone) TO solar;

ALTER FUNCTION solaragg.calc_running_loc_datum_total(bigint[], text[], timestamp with time zone) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.calc_running_loc_datum_total(bigint[], text[], timestamp with time zone) TO solar;
