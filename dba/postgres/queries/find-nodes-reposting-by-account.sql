-- show nodes for an account that are re-posting datum
WITH s AS (
	SELECT m.*
	FROM solardatm.da_datm_meta m
	INNER JOIN solaruser.user_node un ON un.node_id = m.node_id
	INNER JOIN solaruser.user_user u ON u.id = un.user_id
	WHERE u.email = '{EMAIL}'
)
SELECT DISTINCT ON (s.node_id, s.source_id) s.node_id, s.source_id, d.*
FROM s
INNER JOIN LATERAL (
	SELECT d.*
	FROM solardatm.aud_datm_io d
	WHERE d.stream_id = s.stream_id
	ORDER BY ts_start DESC
	LIMIT 50
	) d ON d.stream_id = s.stream_id
WHERE d.prop_u_count > 10
ORDER BY s.node_id, s.source_id, d.ts_start DESC
