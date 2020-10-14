-- convert datm to datum component form
--EXPLAIN ANALYZE
SELECT d.stream_id
	, d.ts
	, jsonb_object_agg(r.name_i, r.data_i) FILTER (WHERE r.name_i IS NOT NULL AND r.data_i IS NOT NULL) as jdata_i
	, jsonb_object_agg(r.name_a, r.data_a) FILTER (WHERE r.name_a IS NOT NULL AND r.data_a IS NOT NULL) as jdata_a
	, jsonb_object_agg(r.name_s, r.data_s) FILTER (WHERE r.name_s IS NOT NULL AND r.data_s IS NOT NULL) as jdata_s
	, d.data_t
FROM solardatm.da_datm d
INNER JOIN solardatm.da_datm_meta m ON m.stream_id = d.stream_id
LEFT JOIN unnest(m.names_i, d.data_i, m.names_a, d.data_a, m.names_s, d.data_s) r(name_i, data_i, name_a, data_a, name_s, data_s) ON TRUE
WHERE m.node_id = 1101
	AND d.ts >= '2020-05-14 12:00:03.002+12'::timestamptz
	AND d.ts < '2020-05-14 12:08:03.001+12'::timestamptz
GROUP BY d.stream_id, d.ts
ORDER BY d.stream_id, d.ts
;

-- convert datm to datum form
--EXPLAIN ANALYZE
SELECT d.stream_id
	, d.ts
	, solarcommon.jdata_from_components(
		jsonb_object_agg(r.name_i, r.data_i) FILTER (WHERE r.name_i IS NOT NULL AND r.data_i IS NOT NULL)
		, jsonb_object_agg(r.name_a, r.data_a) FILTER (WHERE r.name_a IS NOT NULL AND r.data_a IS NOT NULL)
		, jsonb_object_agg(r.name_s, r.data_s) FILTER (WHERE r.name_s IS NOT NULL AND r.data_s IS NOT NULL)
		, d.data_t
	) AS jdata
FROM solardatm.da_datm d
INNER JOIN solardatm.da_datm_meta m ON m.stream_id = d.stream_id
LEFT JOIN unnest(m.names_i, d.data_i, m.names_a, d.data_a, m.names_s, d.data_s) r(name_i, data_i, name_a, data_a, name_s, data_s) ON TRUE
WHERE m.node_id = 1101
	AND d.ts >= '2020-05-14 12:00:03.002+12'::timestamptz
	AND d.ts < '2020-05-14 12:08:03.001+12'::timestamptz
GROUP BY d.stream_id, d.ts
ORDER BY d.stream_id, d.ts
;
