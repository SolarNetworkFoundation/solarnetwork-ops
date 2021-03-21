-- convert datm-aux to datm
WITH aux AS (
	SELECT
		  m.stream_id
		, m.names_a
		, aux.ts - unnest(ARRAY['1 millisecond','0'])::interval AS ts
		, m.node_id
		, m.source_id
		, unnest(ARRAY[aux.jdata_af, aux.jdata_as]) AS jdata_a
	FROM solardatm.da_datm_meta m
	INNER JOIN solardatm.da_datm_aux aux ON aux.stream_id = m.stream_id
	WHERE aux.atype = 'Reset'::solardatum.da_datum_aux_type
		AND m.node_id = ANY(ARRAY[363])
		AND m.source_id = ANY(ARRAY['/G3/CH/CH/GEN/1'])
		AND aux.ts >= '2015-03-12 10:00:00+13'::timestamptz
		AND aux.ts <= '2015-03-12 11:00:00+13'::timestamptz + INTERVAL '1 hour'
)
SELECT
	  aux.stream_id
	, aux.ts
	, min(aux.node_id) AS node_id
	, min(aux.source_id) AS source_id
	, array_agg(p.val ORDER BY array_position(aux.names_a, p.key::text))
		FILTER (WHERE array_position(aux.names_a, p.key::text) IS NOT NULL)  AS data_a
FROM aux
INNER JOIN jsonb_each(aux.jdata_a) AS p(key,val) ON TRUE
GROUP BY aux.stream_id, aux.ts
;

-- update an aux record based on node/source IDs
UPDATE solardatm.da_datm_aux SET
	jdata_af = '{"wattHours": 120834200,"foo":1,"wattHoursReverse":123}'::jsonb
	, jdata_as = '{"wattHours": 133140200,"foo":2,"wattHoursReverse":12300}'::jsonb
FROM solardatm.da_datm_meta
WHERE da_datm_meta.node_id = 363
	AND da_datm_meta.source_id = '/G3/CH/CH/GEN/1'
	AND da_datm_meta.stream_id = da_datm_aux.stream_id
	AND da_datm_aux.atype = 'Reset'::solardatum.da_datum_aux_type
	AND da_datm_aux.ts = '2015-03-12 10:35:00+13'::timestamptz
;
