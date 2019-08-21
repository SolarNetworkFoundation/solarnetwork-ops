ALTER FUNCTION solarnet.node_source_time_rounded(bigint[], text[], text, timestamptz) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solarnet.node_source_time_rounded(bigint[], text[], text, timestamptz) TO solar;

ALTER FUNCTION solardatum.find_earliest_after(bigint[], text[], timestamptz) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_earliest_after(bigint[], text[], timestamptz) TO solar;

ALTER FUNCTION solardatum.find_latest_before(bigint[], text[], timestamptz) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_latest_before(bigint[], text[], timestamptz) TO solar;

ALTER FUNCTION solardatum.calculate_datum_diff_within_close(bigint[], text[], timestamptz, timestamptz) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.calculate_datum_diff_within_close(bigint[], text[], timestamptz, timestamptz) TO solar;

ALTER FUNCTION solardatum.calculate_datum_diff_within_far(bigint[], text[], timestamptz, timestamptz) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.calculate_datum_diff_within_far(bigint[], text[], timestamptz, timestamptz) TO solar;

ALTER FUNCTION solardatum.calculate_datum_diff_within(bigint[], text[], timestamptz, timestamptz) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.calculate_datum_diff_within(bigint[], text[], timestamptz, timestamptz) TO solar;

ALTER FUNCTION solardatum.calculate_datum_diff_within_local_close(bigint[], text[], timestamp, timestamp) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.calculate_datum_diff_within_local_close(bigint[], text[], timestamp, timestamp) TO solar;

ALTER FUNCTION solardatum.calculate_datum_diff_within_local_far(bigint[], text[], timestamp, timestamp) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.calculate_datum_diff_within_local_far(bigint[], text[], timestamp, timestamp) TO solar;

ALTER FUNCTION solardatum.calculate_datum_diff_within_local(bigint[], text[], timestamp, timestamp) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.calculate_datum_diff_within_local(bigint[], text[], timestamp, timestamp) TO solar;
