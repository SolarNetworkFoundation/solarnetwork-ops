--explain analyze
SELECT * FROM solardatm.find_datm_for_time_span(
	'ade25d3b-faa1-4df8-8c99-bb24b58635ac'::uuid,
	'2020-05-14 13:00:00+12'::timestamptz,
	'2020-05-14 13:00:00+12'::timestamptz + INTERVAL '1 hour'
	);

CREATE OR REPLACE FUNCTION solardatm.find_datm_for_time_span(
		sid uuid,
		start_ts TIMESTAMP WITH TIME ZONE,
		end_ts TIMESTAMP WITH TIME ZONE,
		tolerance_clock INTERVAL DEFAULT interval '1 hour',
		tolerance_read INTERVAL DEFAULT interval '3 months'
	) RETURNS TABLE(
		stream_id 	UUID,
		ts 			TIMESTAMP WITH TIME ZONE,
		data_i		NUMERIC[],
		data_a		NUMERIC[],
		data_s		TEXT[],
		data_t		TEXT[],
		inclusion	SMALLINT,
		portion		DOUBLE PRECISION
	) LANGUAGE SQL STABLE ROWS 2000 AS
$$
	-- first find boundary datum (least, greatest) for given time range that satisfies both the
	-- clock and reading aggregate time windows
	WITH b AS (
		(
		-- latest on/before start
		SELECT d.stream_id, d.ts
		FROM solardatm.da_datm d
		WHERE d.stream_id = sid
			AND d.ts <= start_ts
			AND d.ts > start_ts - tolerance_read
		ORDER BY d.stream_id, d.ts DESC
		LIMIT 1
		)
		UNION ALL
		(
		-- earliest on/after end
		SELECT d.stream_id, d.ts
		FROM solardatm.da_datm d
		WHERE d.stream_id = sid
			AND d.ts >= end_ts
			AND d.ts < end_ts + tolerance_clock
		ORDER BY d.stream_id, d.ts
		LIMIT 1
		)
	)
	-- combine boundary rows into single range row with start/end columns
	, r AS (
		SELECT
			stream_id
			, COALESCE(min(ts), start_ts) AS range_start
			, COALESCE(max(ts), end_ts) AS range_end
		FROM b
		GROUP BY stream_id
	)
	-- query for raw datum using the boundary range previously found
	SELECT
		  d.stream_id
		, d.ts
		, d.data_i
		, d.data_a
		, d.data_s
		, d.data_t
		, CASE
			WHEN d.ts < start_ts THEN -1::SMALLINT
			WHEN d.ts >= end_ts THEN 1::SMALLINT
			ELSE 0::SMALLINT
			END AS inclusion
		, CASE
			WHEN d.ts < start_ts THEN
				1 - EXTRACT(epoch FROM (start_ts - d.ts)) / EXTRACT(epoch FROM (lead(d.ts) OVER slot - d.ts))
			WHEN d.ts > end_ts THEN
				0
			WHEN lead(d.ts) OVER slot > end_ts THEN
				EXTRACT(epoch FROM (end_ts - d.ts)) / EXTRACT(epoch FROM (lead(d.ts) OVER slot - d.ts))
			ELSE 1
			END AS portion
	FROM r
	INNER JOIN solardatm.da_datm d ON d.stream_id = r.stream_id
	WHERE d.ts >= r.range_start
		AND d.ts <= r.range_end
	WINDOW slot AS (ORDER BY d.ts RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
$$;
