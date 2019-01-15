-- create new tables / functions / triggers

-- \i init/updates/NET-171-reading-absolute.sql

-- apply production permissions

ALTER FUNCTION solardatum.calculate_datum_diff(bigint[], text[], timestamptz, timestamptz, interval) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.calculate_datum_diff(bigint[], text[], timestamptz, timestamptz, interval) TO solar;

ALTER FUNCTION solardatum.calculate_datum_diff_over(bigint[], text[], timestamptz, timestamptz) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.calculate_datum_diff_over(bigint[], text[], timestamptz, timestamptz) TO solar;
