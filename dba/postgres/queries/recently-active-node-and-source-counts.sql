WITH streams AS (
	SELECT DISTINCT stream_id
	FROM solardatm.aud_datm_daily
	WHERE ts_start >= CURRENT_DATE - INTERVAL '21 days'
)
, nodes AS (
	SELECT DISTINCT node_id
	FROM solardatm.da_datm_meta
	INNER JOIN streams ON streams.stream_id = da_datm_meta.stream_id
), sources AS (
	SELECT DISTINCT node_id, source_id
	FROM solardatm.da_datm_meta
	INNER JOIN streams ON streams.stream_id = da_datm_meta.stream_id
)
SELECT
	(SELECT count(*) AS nodes FROM nodes) AS nodes,
	(SELECT count(*) AS sources FROM sources) AS sources
