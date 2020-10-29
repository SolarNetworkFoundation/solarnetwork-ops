--explain analyze
SELECT * FROM solardatm.find_datm_for_time_span_with_aux(
	'ade25d3b-faa1-4df8-8c99-bb24b58635ac'::uuid,
	'2020-05-14 13:00:00+12'::timestamptz,
	'2020-05-14 13:00:00+12'::timestamptz + INTERVAL '1 hour'
	);

CREATE OR REPLACE FUNCTION solardatm.find_datm_for_time_span_with_aux(
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
	-- find raw data for given time range
	WITH d AS (
		SELECT d.*, 0 AS rr
		FROM solardatm.find_datm_for_time_span(sid, start_ts, end_ts) d
	)
	-- find reset records for same time range, split into two rows for each record: final
	-- and starting accumulating values
	, aux AS (
		SELECT
			  m.stream_id
			, aux.ts - unnest(ARRAY['1 millisecond','0'])::interval AS ts
			, m.names_a
			, unnest(ARRAY[aux.jdata_af, aux.jdata_as]) AS jdata_a
		FROM solardatm.da_datm_aux aux
		INNER JOIN solardatm.da_datm_meta m ON m.stream_id = aux.stream_id
		WHERE aux.atype = 'Reset'::solardatum.da_datum_aux_type
			AND aux.stream_id = sid
			AND aux.ts >= start_ts - tolerance_read
			AND aux.ts <= end_ts + tolerance_read
	)
	-- convert reset record rows into datm rows by turning jdata_a JSON into data_a value array,
	-- respecting the array order defined by solardatm.da_datm_meta.names_a and excluding values
	-- not defined there
	, resets AS (
		SELECT
			  aux.stream_id
			, aux.ts
			, NULL::numeric[] AS data_i
			, array_agg(p.val::text::numeric ORDER BY array_position(aux.names_a, p.key::text))
				FILTER (WHERE array_position(aux.names_a, p.key::text) IS NOT NULL)::numeric[] AS data_a
			, NULL::text[] AS data_s
			, NULL::text[] AS data_t
			, CASE
				WHEN aux.ts < start_ts THEN -1::SMALLINT
				WHEN aux.ts >= end_ts THEN 1::SMALLINT
				ELSE 0::SMALLINT
				END AS inclusion
			, CASE
				WHEN aux.ts < start_ts THEN
					1 - EXTRACT(epoch FROM (start_ts - aux.ts)) / EXTRACT(epoch FROM (lead(aux.ts) OVER slot - aux.ts))
				WHEN aux.ts > end_ts THEN
					0
				WHEN lead(aux.ts) OVER slot > end_ts THEN
					EXTRACT(epoch FROM (end_ts - aux.ts)) / EXTRACT(epoch FROM (lead(aux.ts) OVER slot - aux.ts))
				ELSE 1
				END AS portion
			, 1 AS rr
		FROM aux
		INNER JOIN jsonb_each(aux.jdata_a) AS p(key,val) ON TRUE
		GROUP BY aux.stream_id, aux.ts
		WINDOW slot AS (ORDER BY aux.ts RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
	)
	-- combine raw datm with reset datm
	, combined AS (
		SELECT * FROM d
		UNION ALL
		SELECT * FROM resets
	)
	-- group all results by time so that reset records with the same time as a raw record
	-- override the raw record
	SELECT DISTINCT ON (ts) stream_id, ts, data_i, data_a, data_s, data_t, inclusion, portion
	FROM combined
	ORDER BY ts, rr DESC
$$;
