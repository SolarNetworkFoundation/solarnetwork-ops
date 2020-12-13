-- query for streams, assigning virtual stream IDs based on "combining" input
-- e.g. virtual node mapping 123456789:11,108; source mapping V:DB,Main
--
-- Since the streams could have property data stored in different orders, or
-- different properties even, when aggregating them together the properties
-- are grouped by name. Thus the real stream metadata is used to decode each
-- property value index into a name, then grouping is done based on that.

-- query for real stream metadata, and assign node/source IDs based on
-- virtual mappings
WITH rs AS (
	SELECT
		s.stream_id
		, CASE
			WHEN array_position(ARRAY[11,108]::BIGINT[], s.node_id) IS NOT NULL THEN 123456789
			ELSE s.node_id
			END AS obj_id
		, COALESCE(array_position(ARRAY[11,108]::BIGINT[], s.node_id), 0) AS obj_rank
		, CASE
			WHEN array_position(ARRAY['DB','Main']::CHARACTER VARYING[], s.source_id) IS NOT NULL THEN 'V'
			ELSE s.source_id
			END AS source_id
		, COALESCE(array_position(ARRAY['DB','Main']::CHARACTER VARYING[], s.source_id), 0) AS source_rank
		, s.names_i
		, s.names_a
	FROM solardatm.da_datm_meta s
	WHERE s.node_id = ANY(ARRAY[11,108,388])
		AND s.source_id ~ ANY(ARRAY(SELECT solarcommon.ant_pattern_to_regexp(unnest(ARRAY['DB','Main','A']))))
)

-- assign each real stream a virtual stream ID based on mappings of object/source IDs
, s AS (
	SELECT
		solardatm.virutal_stream_id(obj_id, source_id) AS vstream_id
		, *
	FROM rs
)
, d AS (
	SELECT
		  s.vstream_id AS stream_id 		-- creating virtual streams to aggregate
		, s.obj_rank 						-- for aggregate sorting
		, s.source_rank 	   				-- for aggregate sorting
		, s.names_i
		, s.names_a
		, d.ts_start
		, d.data_i
		, d.data_a
		, d.data_s
		, d.data_t
		, d.stat_i
		, d.read_a
	FROM s
	INNER JOIN solardatm.agg_datm_daily d ON d.stream_id = s.stream_id
	WHERE d.ts_start >= '2017-07-01T00:00'::timestamptz
		AND ts_start < '2017-07-07T00:00'::timestamptz
)

-- calculate instantaneous values per date + property NAME (to support joining different streams with different index orders)
-- ordered by object/source ranking defined by query metadata
, wi AS (
	SELECT
		  d.stream_id
		, d.ts_start
		, p.val
		, rank() OVER slot as prank
		, d.names_i[p.idx] AS pname -- assume names are unique per stream
		, d.stat_i[p.idx][1] AS cnt
		, d.stat_i[p.idx][2] AS min
		, d.stat_i[p.idx][3] AS max
		, sum(d.stat_i[p.idx][1]) OVER slot AS tot_cnt
	FROM d
	INNER JOIN unnest(d.data_i) WITH ORDINALITY AS p(val, idx) ON TRUE
	WHERE p.val IS NOT NULL
	WINDOW slot AS (PARTITION BY d.stream_id, d.ts_start, d.names_i[p.idx] ORDER BY d.obj_rank, d.source_rank RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
	ORDER BY d.stream_id, d.ts_start, d.names_i[p.idx], d.obj_rank, d.source_rank
)

-- calculate instantaneous statistics
, di AS (
	SELECT
		  stream_id
		, ts_start
		, pname
		, to_char(sum(val * cnt / tot_cnt), 'FM999999999999999999990.999999999')::numeric 										AS val_avg
		, to_char(sum(val), 'FM999999999999999999990.999999999')::numeric 														AS val_sum
		-- for SUB the ORDER BY prank is used to subtract property values from the first available value
		, to_char(sum(CASE prank WHEN 1 THEN val ELSE -val END ORDER BY prank), 'FM999999999999999999990.999999999')::numeric 	AS val_sub
		, sum(cnt) AS cnt
		, min(min) AS val_min
		, max(max) AS val_max
	FROM wi
	GROUP BY stream_id, ts_start, pname
	ORDER BY stream_id, ts_start, pname
)

-- join property data back into arrays; no stat_i for virtual stream
, di_ary AS (
	SELECT
		  stream_id
		, ts_start
		, array_agg(val_avg ORDER BY pname) AS data_i_avg
		, array_agg(val_sum ORDER BY pname) AS data_i_sum
		, array_agg(val_sub ORDER BY pname) AS data_i_sub
		, array_agg(pname ORDER BY pname) AS names_i
	FROM di
	GROUP BY stream_id, ts_start
	ORDER BY stream_id, ts_start
)


-- calculate accumulating values per date + property NAME (to support joining different streams with different index orders)
-- ordered by object/source ranking defined by query metadata
, wa AS (
	SELECT
		  d.stream_id
		, d.ts_start
		, p.val
		, rank() OVER slot as prank
		, d.names_a[p.idx] AS pname -- assume names are unique per stream
		, first_value(d.read_a[p.idx][1]) OVER slot AS rstart
		, last_value(d.read_a[p.idx][2]) OVER slot AS rend
		, d.read_a[p.idx][3] AS rdiff
	FROM d
	INNER JOIN unnest(d.data_a) WITH ORDINALITY AS p(val, idx) ON TRUE
	WHERE p.val IS NOT NULL
	WINDOW slot AS (PARTITION BY d.stream_id, d.ts_start, d.names_a[p.idx] ORDER BY d.obj_rank, d.source_rank RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
	ORDER BY d.stream_id, d.ts_start, d.names_a[p.idx], d.obj_rank, d.source_rank
)

-- calculate accumulating statistics
, da AS (
	SELECT
		  stream_id
		, ts_start
		, pname
		, to_char(avg(val), 'FM999999999999999999990.999999999')::numeric 														AS val_avg
		, to_char(sum(val), 'FM999999999999999999990.999999999')::numeric 														AS val_sum
		-- for SUB the ORDER BY prank is used to subtract property values from the first available value
		, to_char(sum(CASE prank WHEN 1 THEN val ELSE -val END ORDER BY prank), 'FM999999999999999999990.999999999')::numeric 	AS val_sub

		, to_char(sum(rdiff), 'FM999999999999999999990.999999999')::numeric 														AS rdiff_sum
		-- for SUB the ORDER BY prank is used to subtract property values from the first available value
		, to_char(sum(CASE prank WHEN 1 THEN rdiff ELSE -rdiff END ORDER BY prank), 'FM999999999999999999990.999999999')::numeric 	AS rdiff_sub
	FROM wa
	GROUP BY stream_id, ts_start, pname
	ORDER BY stream_id, ts_start, pname
)

-- join property data back into arrays; only read_a.diff for virtual stream
--, da_ary AS (
	SELECT
		  stream_id
		, ts_start
		, array_agg(val_avg ORDER BY pname) AS data_a_avg
		, array_agg(val_sum ORDER BY pname) AS data_a_sum
		, array_agg(val_sub ORDER BY pname) AS data_a_sub
		, array_agg(pname ORDER BY pname) AS names_a
		, array_agg(
			ARRAY[NULL, NULL, rdiff_sum] ORDER BY pname
		) AS read_a_sum
		, array_agg(
			ARRAY[NULL, NULL, rdiff_sub] ORDER BY pname
		) AS read_a_sub
	FROM da
	GROUP BY stream_id, ts_start
	ORDER BY stream_id, ts_start
;--)
