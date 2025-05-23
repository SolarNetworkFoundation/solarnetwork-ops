-- total datum ingested over calendar year (UTC)
SELECT
	  SUM(prop_count) AS prop_count
	, SUM(datum_count) AS datum_count
	, SUM(datum_q_count) AS datum_q_count
	, SUM(flux_byte_count) AS flux_byte_count
	, pg_size_pretty(SUM(prop_count)) AS prop_cnt
	, pg_size_pretty(SUM(datum_count)) AS datum_cnt
	, pg_size_pretty(SUM(datum_q_count)) AS datum_q_cnt
	, pg_size_pretty(SUM(flux_byte_count)) AS flux_byte_cnt
FROM solardatm.aud_datm_io d
WHERE d.ts_start >= '2022-01-01 00:00Z'::TIMESTAMPTZ
	AND d.ts_start < '2023-01-01 00:00Z'::TIMESTAMPTZ

