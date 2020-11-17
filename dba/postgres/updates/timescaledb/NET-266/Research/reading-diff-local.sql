-- generate list of stream IDs based on filter of node/source/user etc
WITH s AS (
	SELECT meta.stream_id, meta.node_id, meta.source_id, meta.names_i, meta.names_a, meta.names_s, meta.jdata, l.time_zone
	FROM solardatm.da_datm_meta meta
	INNER JOIN solaruser.user_node un ON un.node_id = meta.node_id
	LEFT OUTER JOIN solarnet.sn_node n ON n.node_id = meta.node_id
	LEFT OUTER JOIN solarnet.sn_loc l ON l.id = n.loc_id
	WHERE meta.node_id = ANY(ARRAY[30,108,126,374]::bigint[])
		AND meta.source_id = ANY(ARRAY['Main','Inverter3','/DE/G1/B600/GEN/1'])
		AND un.user_id = ANY(ARRAY[161,185,385]::bigint[])
)
-- then use solardatm.find_datm_diff_rows() per stream, to find the first/last rows (plus any resets)
-- and aggregate with solardatm.diff_datm() to calculate the actual difference
, d AS (
	SELECT (solardatm.diff_datm(d ORDER BY d.ts, d.rtype)).*
	FROM s
	INNER JOIN solardatm.find_datm_diff_rows(s.stream_id
		-- note local times are used for each stream
		, '2015-03-01'::timestamp AT TIME ZONE s.time_zone
		, '2015-04-01'::timestamp AT TIME ZONE s.time_zone) d ON TRUE
	GROUP BY s.stream_id
)
-- this adds the time zone to the final results for demonstration
SELECT d.*, s.time_zone, d.ts_start AT TIME ZONE s.time_zone AS ts_start_local
FROM d
INNER JOIN s ON s.stream_id = d.stream_id
