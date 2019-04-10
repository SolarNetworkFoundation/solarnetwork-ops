-- create new tables / functions / triggers

-- \i init/updates/NET-198-mark-datum-stale.sql

-- apply production permissions

ALTER FUNCTION solaragg.find_datum_hour_slots(bigint[], text[], timestamp with time zone, timestamp with time zone) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_datum_hour_slots(bigint[], text[], timestamp with time zone, timestamp with time zone) TO solarin;
REVOKE ALL ON FUNCTION solaragg.find_datum_hour_slots(bigint[], text[], timestamp with time zone, timestamp with time zone) FROM PUBLIC;

ALTER FUNCTION solaragg.mark_datum_stale_hour_slots(bigint[], text[], timestamp with time zone, timestamp with time zone) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.mark_datum_stale_hour_slots(bigint[], text[], timestamp with time zone, timestamp with time zone) TO solarin;
REVOKE ALL ON FUNCTION solaragg.mark_datum_stale_hour_slots(bigint[], text[], timestamp with time zone, timestamp with time zone) FROM PUBLIC;
