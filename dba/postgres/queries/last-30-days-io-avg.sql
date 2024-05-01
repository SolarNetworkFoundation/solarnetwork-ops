WITH hours AS (
SELECT ts_start
	, count(stream_id) AS stream_count
	, sum(prop_count) AS prop_in_count
	, sum(datum_count) AS datum_count
	, sum(datum_q_count) AS datum_q_count
	, sum(flux_byte_count) AS flux_byte_count
FROM solardatm.aud_datm_io
WHERE ts_start >= date_trunc('hour', CURRENT_TIMESTAMP) - INTERVAL '30 days'
GROUP BY ts_start
)
SELECT avg(stream_count)::BIGINT AS stream_count_avg_hour
	, avg(prop_in_count)::BIGINT AS prop_in_count_avg_hour
	, avg(datum_count)::BIGINT AS datum_count_avg_hour
	, avg(datum_q_count)::BIGINT AS datum_q_count_avg_hour
	, avg(flux_byte_count)::BIGINT AS flux_byte_count_avg_hour

	, (avg(prop_in_count)/3600)::BIGINT AS prop_in_count_avg_sec
	, (avg(datum_count)/3600)::BIGINT AS datum_count_avg_sec
	, (avg(datum_q_count)/3600)::BIGINT AS datum_q_count_avg_sec
	, (avg(flux_byte_count)/3600)::BIGINT AS flux_byte_count_avg_sec
FROM hours
