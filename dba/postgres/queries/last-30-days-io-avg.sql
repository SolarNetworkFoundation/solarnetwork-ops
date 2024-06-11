WITH d AS (
	SELECT ts_start
		, count(stream_id) AS stream_count
		, sum(prop_count) AS prop_in_count
		, sum(datum_count) AS datum_count
		, sum(datum_q_count) AS datum_q_count
		, sum(flux_byte_count) AS flux_byte_count
	FROM solardatm.aud_datm_daily
	WHERE ts_start >= date_trunc('hour', CURRENT_TIMESTAMP) - INTERVAL '30 days'
	GROUP BY ts_start
)
, n AS (
	SELECT ts_start
		, service AS node_service
		, sum(cnt) AS node_service_count
	FROM solardatm.aud_node_daily
	WHERE ts_start >= date_trunc('hour', CURRENT_TIMESTAMP) - INTERVAL '30 days'
	GROUP BY ts_start, service
)
, u AS (
	SELECT ts_start
		, service AS user_service
		, sum(cnt) AS user_service_count
	FROM solardatm.aud_user_daily
	WHERE ts_start >= date_trunc('hour', CURRENT_TIMESTAMP) - INTERVAL '30 days'
	GROUP BY ts_start, service
)
SELECT avg(stream_count)::BIGINT AS stream_count_avg
	, avg(prop_in_count)::BIGINT AS prop_in_count_avg
	, avg(datum_count)::BIGINT AS datum_count_avg
	, avg(datum_q_count)::BIGINT AS datum_q_count_avg
	, avg(flux_byte_count)::BIGINT AS flux_byte_count_in_avg
	, (avg(user_service_count) FILTER (WHERE user_service = 'flxo'))::BIGINT AS flux_byte_count_out_avg
	, (avg(node_service_count) FILTER (WHERE node_service = 'inst'))::BIGINT AS instr_in_avg

	, (avg(prop_in_count)/3600)::BIGINT AS prop_in_count_avg_sec
	, (avg(datum_count)/3600)::BIGINT AS datum_count_avg_sec
	, (avg(datum_q_count)/3600)::BIGINT AS datum_q_count_avg_sec
	, (avg(flux_byte_count)/3600)::BIGINT AS flux_byte_count_in_avg_sec
	, ((avg(user_service_count) FILTER (WHERE user_service = 'flxo'))/3600)::BIGINT AS flux_byte_count_out_avg_sec
	, ((avg(node_service_count) FILTER (WHERE node_service = 'inst'))/3600)::BIGINT AS instr_in_avg_sec
FROM d, n, u
