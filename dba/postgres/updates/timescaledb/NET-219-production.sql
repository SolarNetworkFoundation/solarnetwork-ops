ALTER FUNCTION solardatum.find_most_recent(bigint[], text[]) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_most_recent(bigint[], text[]) TO solar;

ALTER FUNCTION solaragg.find_most_recent_hourly(bigint[], text[]) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_most_recent_hourly(bigint[], text[]) TO solar;

ALTER FUNCTION solaragg.find_most_recent_daily(bigint[], text[]) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_most_recent_daily(bigint[], text[]) TO solar;

ALTER FUNCTION solaragg.find_most_recent_monthly(bigint[], text[]) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_most_recent_monthly(bigint[], text[]) TO solar;
