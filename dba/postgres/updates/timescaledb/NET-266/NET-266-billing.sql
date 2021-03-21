CREATE OR REPLACE FUNCTION solarbill.billing_tier_details(userid BIGINT, ts_min TIMESTAMP, ts_max TIMESTAMP, effective_date date DEFAULT CURRENT_DATE)
	RETURNS TABLE(
		node_id BIGINT,
		min	BIGINT,
		prop_in BIGINT,
		tier_prop_in BIGINT,
		cost_prop_in NUMERIC,
		prop_in_cost NUMERIC,
		datum_stored BIGINT,
		tier_datum_stored BIGINT,
		cost_datum_stored NUMERIC,
		datum_stored_cost NUMERIC,
		datum_out BIGINT,
		tier_datum_out BIGINT,
		cost_datum_out NUMERIC,
		datum_out_cost NUMERIC,
		total_cost NUMERIC
	) LANGUAGE sql STABLE AS
$$
	WITH tiers AS (
		SELECT * FROM solarbill.billing_tiers(effective_date)
	)
	, nodes AS (
		SELECT nlt.time_zone,
			ts_min AT TIME ZONE nlt.time_zone AS sdate,
			ts_max AT TIME ZONE nlt.time_zone AS edate,
			array_agg(DISTINCT nlt.node_id) AS nodes
		FROM solarnet.node_local_time nlt
		INNER JOIN solaruser.user_node un ON un.node_id = nlt.node_id
		WHERE un.user_id = userid
		GROUP BY nlt.time_zone
	)
	, stored AS (
		SELECT
			meta.node_id
			, SUM(acc.datum_count + acc.datum_hourly_count + acc.datum_daily_count + acc.datum_monthly_count) AS datum_count
		FROM nodes nodes
		INNER JOIN solardatm.da_datm_meta meta ON meta.node_id = ANY(nodes.nodes)
		INNER JOIN solardatm.aud_acc_datm_daily acc ON acc.stream_id = meta.stream_id
			AND acc.ts_start >= nodes.sdate AND acc.ts_start < nodes.edate
		GROUP BY meta.node_id
	)
	, datum AS (
		SELECT
			meta.node_id
			, SUM(a.prop_count)::bigint AS prop_count
			, SUM(a.datum_q_count)::bigint AS datum_q_count
		FROM nodes nodes
		INNER JOIN solardatm.da_datm_meta meta ON meta.node_id = ANY(nodes.nodes)
		INNER JOIN solardatm.aud_datm_monthly a ON a.stream_id = meta.stream_id
			AND a.ts_start >= nodes.sdate AND a.ts_start < nodes.edate
		GROUP BY meta.node_id
	)
	, n AS (
		SELECT UNNEST(nodes) AS node_id FROM nodes
	)
	, costs AS (
		SELECT
			n.node_id
			, tiers.min
			, COALESCE(a.prop_count, 0) AS prop_in
			, LEAST(GREATEST(a.prop_count - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(a.prop_count - tiers.min, 0))) AS tier_prop_in
			, tiers.cost_prop_in

			, s.datum_count AS datum_stored
			, LEAST(GREATEST(s.datum_count - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(s.datum_count - tiers.min, 0))) AS tier_datum_stored
			, tiers.cost_datum_stored

			, COALESCE(a.datum_q_count, 0) AS datum_out
			, LEAST(GREATEST(a.datum_q_count - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(a.datum_q_count - tiers.min, 0))) AS tier_datum_out
			, tiers.cost_datum_out
		FROM n
		LEFT OUTER JOIN stored s ON s.node_id = n.node_id
		LEFT OUTER JOIN datum a ON a.node_id = n.node_id
		CROSS JOIN tiers
		WINDOW win AS (PARTITION BY n.node_id ORDER BY tiers.min)
	)
	SELECT
		node_id
		, min
		, prop_in
		, tier_prop_in
		, cost_prop_in
		, (tier_prop_in * cost_prop_in) AS prop_in_cost

		, datum_stored
		, tier_datum_stored
		, cost_datum_stored
		, (tier_datum_stored * cost_datum_stored) AS datum_stored_cost

		, datum_out
		, tier_datum_out
		, cost_datum_out
		, (tier_datum_out * cost_datum_out) AS datum_out_cost

		, ROUND((tier_prop_in * cost_prop_in) + (tier_datum_stored * cost_datum_stored) + (tier_datum_out * cost_datum_out), 2) AS total_cost
	FROM costs
	WHERE ROUND((tier_prop_in * cost_prop_in) + (tier_datum_stored * cost_datum_stored) + (tier_datum_out * cost_datum_out), 2) > 0
	ORDER BY node_id
$$;
