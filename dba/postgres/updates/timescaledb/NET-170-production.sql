-- create new tables / functions / triggers

-- \i init/updates/NET-170-reading-difference.sql

-- apply production permissions

CREATE UNIQUE INDEX IF NOT EXISTS da_datum_reverse_pkey ON solardatum.da_datum (node_id, ts DESC, source_id)
TABLESPACE solarindex;

ALTER FUNCTION solardatum.find_earliest_before(bigint[], text[], timestamptz) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_earliest_before(bigint[], text[], timestamptz) TO solar;

ALTER FUNCTION solardatum.find_latest_before(bigint[], text[], timestamptz) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_latest_before(bigint[], text[], timestamptz) TO solar;

ALTER FUNCTION solardatum.find_earliest_after(bigint[], text[], timestamptz) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_earliest_after(bigint[], text[], timestamptz) TO solar;

ALTER FUNCTION solardatum.calculate_datum_diff_over_local(bigint[], text[], timestamp, timestamp) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.calculate_datum_diff_over_local(bigint[], text[], timestamp, timestamp) TO solar;
