DROP FUNCTION IF EXISTS solarbill.billing_tiers(effective_date date);
DROP FUNCTION IF EXISTS solarbill.billing_tier_details(userid BIGINT, ts_min TIMESTAMP, ts_max TIMESTAMP, effective_date date);
DROP FUNCTION IF EXISTS solarbill.billing_details(userid BIGINT, ts_min TIMESTAMP, ts_max TIMESTAMP, effective_date date);

-- table to store billing invoice usage records
CREATE TABLE IF NOT EXISTS solarbill.bill_invoice_node_usage (
	inv_id			BIGINT NOT NULL,
	node_id			BIGINT NOT NULL,
	created 		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    prop_count 		BIGINT NOT NULL DEFAULT 0,
    datum_q_count 	BIGINT NOT NULL DEFAULT 0,
    datum_s_count	BIGINT NOT NULL DEFAULT 0,
	CONSTRAINT bill_invoice_usage_pkey PRIMARY KEY (inv_id, node_id),
	CONSTRAINT bill_invoice_usage_inv_fk FOREIGN KEY (inv_id)
		REFERENCES solarbill.bill_invoice (id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE NO ACTION
);

/**
 * Get the billing price tiers for a specific point in time.
 *
 * @param ts the billing effective date; defaults to the current date if not provided
 */
CREATE OR REPLACE FUNCTION solarbill.billing_usage_tiers(ts date DEFAULT CURRENT_DATE)
	RETURNS TABLE(
		meter_key TEXT,
		min BIGINT,
		cost NUMERIC,
		effective_date DATE
	)
	LANGUAGE plpgsql IMMUTABLE AS
$$
BEGIN
	IF ts < '2020-06-01'::DATE THEN
		RETURN QUERY SELECT *, '2008-01-01'::DATE AS effective_date FROM ( VALUES
			  ('datum-props-in', 		0::BIGINT, 	0.000009::NUMERIC)
			, ('datum-out', 			0::BIGINT, 	0.000002::NUMERIC)
			, ('datum-days-stored', 	0::BIGINT, 	0.000000006::NUMERIC)
		) AS t(min, meter_key, cost);
	ELSIF ts < '2021-06-01'::DATE THEN
		RETURN QUERY SELECT *, '2020-06-01'::DATE FROM ( VALUES
			  ('datum-props-in', 		0::BIGINT, 			0.000009::NUMERIC)
			, ('datum-props-in', 		50000::BIGINT, 		0.000006::NUMERIC)
			, ('datum-props-in', 		400000::BIGINT, 	0.000004::NUMERIC)
			, ('datum-props-in', 		1000000::BIGINT, 	0.000002::NUMERIC)

			, ('datum-out',				0::BIGINT, 			0.000002::NUMERIC)
			, ('datum-out',				50000::BIGINT, 		0.000001::NUMERIC)
			, ('datum-out',				400000::BIGINT, 	0.0000005::NUMERIC)
			, ('datum-out',				1000000::BIGINT, 	0.0000002::NUMERIC)

			, ('datum-days-stored', 	0::BIGINT, 			0.0000004::NUMERIC)
			, ('datum-days-stored', 	50000::BIGINT, 		0.0000002::NUMERIC)
			, ('datum-days-stored', 	400000::BIGINT, 	0.00000005::NUMERIC)
			, ('datum-days-stored', 	1000000::BIGINT, 	0.000000006::NUMERIC)
		) AS t(min, meter_key, cost);
	ELSE
		RETURN QUERY SELECT *, '2021-06-01'::DATE FROM ( VALUES
			  ('datum-props-in', 		0::BIGINT, 				0.000005::NUMERIC)
			, ('datum-props-in', 		500000::BIGINT, 		0.000003::NUMERIC)
			, ('datum-props-in', 		10000000::BIGINT, 		0.0000008::NUMERIC)
			, ('datum-props-in', 		500000000::BIGINT, 		0.0000002::NUMERIC)

			, ('datum-out',				0::BIGINT, 				0.0000005::NUMERIC)
			, ('datum-out',				1000000::BIGINT, 		0.0000001::NUMERIC)
			, ('datum-out',				100000000::BIGINT, 		0.00000004::NUMERIC)
			, ('datum-out',				10000000000::BIGINT, 	0.00000001::NUMERIC)

			, ('datum-days-stored', 	0::BIGINT, 				0.00000005::NUMERIC)
			, ('datum-days-stored', 	10000000::BIGINT, 		0.00000002::NUMERIC)
			, ('datum-days-stored', 	1000000000::BIGINT, 	0.000000005::NUMERIC)
			, ('datum-days-stored', 	100000000000::BIGINT,	0.0000000008::NUMERIC)
		) AS t(min, meter_key, cost);
	END IF;
END
$$;

/**
 * Calculate the metered usage amounts for an account over a billing period, by node.
 *
 * @param userid the ID of the user to calculate the billing information for
 * @param ts_min the start date to calculate the usage for (inclusive)
 * @param ts_max the end date to calculate the usage for (exclusive)
 */
CREATE OR REPLACE FUNCTION solarbill.billing_usage(userid BIGINT, ts_min TIMESTAMP, ts_max TIMESTAMP)
	RETURNS TABLE(
		node_id BIGINT,
		prop_in BIGINT,
		datum_stored BIGINT,
		datum_out BIGINT
	) LANGUAGE sql STABLE AS
$$
	WITH nodes AS (
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
	SELECT
		COALESCE(s.node_id, a.node_id) AS node_id
		, COALESCE(a.prop_count, 0)::BIGINT AS prop_in
		, COALESCE(s.datum_count, 0)::BIGINT AS datum_stored
		, COALESCE(datum_q_count, 0)::BIGINT AS datum_out
	FROM stored s
	FULL OUTER JOIN datum a ON a.node_id = s.node_id
$$;

/**
 * Calculate the usage associated with billing tiers for a given user on a given month, by node.
 *
 * This calls the `solarbill.billing_usage_tiers()` function to determine the pricing tiers to use
 * at the given `effective_date`.
 *
 * @param userid the ID of the user to calculate the billing information for
 * @param ts_min the start date to calculate the costs for (inclusive)
 * @param ts_max the end date to calculate the costs for (exclusive)
 * @param effective_date optional pricing date, to calculate the tiers effective at that time
 */
CREATE OR REPLACE FUNCTION solarbill.billing_node_tier_details(userid BIGINT, ts_min TIMESTAMP, ts_max TIMESTAMP, effective_date date DEFAULT CURRENT_DATE)
	RETURNS TABLE(
		node_id		BIGINT,
		meter_key 	TEXT,
		tier_min 	BIGINT,
		tier_count 	BIGINT
	) LANGUAGE sql STABLE AS
$$
	WITH tiers AS (
		SELECT * FROM solarbill.billing_usage_tiers(effective_date)
	)
	, usage AS (
		SELECT
			  node_id
			, prop_in
			, datum_stored
			, datum_out
		FROM solarbill.billing_usage(userid, ts_min, ts_max)
		WHERE prop_in > 0 OR datum_stored > 0 OR datum_out > 0
	)
	SELECT
		  n.node_id
		, tiers.meter_key
		, tiers.min AS tier_min
		, LEAST(GREATEST(CASE meter_key
			WHEN 'datum-props-in' THEN n.prop_in
			WHEN 'datum-days-stored' THEN n.datum_stored
			WHEN 'datum-out' THEN n.datum_out
			ELSE NULL END - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(CASE meter_key
			WHEN 'datum-props-in' THEN n.prop_in
			WHEN 'datum-days-stored' THEN n.datum_stored
			WHEN 'datum-out' THEN n.datum_out
			ELSE NULL END - tiers.min, 0))) AS tier_count
	FROM usage n
	CROSS JOIN tiers
	WINDOW win AS (PARTITION BY n.node_id, tiers.meter_key ORDER BY tiers.min)
$$;

/**
 * Calculate the usage associated with billing tiers for a given user on a given month, by node.
 *
 * This calls the `solarbill.billing_node_tier_details()` function to determine the pricing tiers to use
 * at the given `effective_date`.
 *
 * @param userid the ID of the user to calculate the billing information for
 * @param ts_min the start date to calculate the costs for (inclusive)
 * @param ts_max the end date to calculate the costs for (exclusive)
 * @param effective_date optional pricing date, to calculate the costs effective at that time
 */
CREATE OR REPLACE FUNCTION solarbill.billing_node_details(userid BIGINT, ts_min TIMESTAMP, ts_max TIMESTAMP, effective_date date DEFAULT CURRENT_DATE)
	RETURNS TABLE(
		node_id 				BIGINT,
		prop_in 				BIGINT,
		prop_in_tiers 			NUMERIC[],
		datum_stored 			BIGINT,
		datum_stored_tiers 		NUMERIC[],
		datum_out 				BIGINT,
		datum_out_tiers 		NUMERIC[]
	) LANGUAGE sql STABLE AS
$$
	WITH tiers AS (
		SELECT * FROM solarbill.billing_node_tier_details(userid, ts_min, ts_max, effective_date)
	)
	, counts AS (
		SELECT
			  node_id
			, meter_key
			, SUM(tier_count)::BIGINT AS total_count
			, ARRAY_AGG(tier_count::NUMERIC) AS tier_counts
		FROM tiers
		WHERE tier_count > 0
		GROUP BY node_id, meter_key
	)
	SELECT
		  node_id
		, SUM(CASE meter_key WHEN 'datum-props-in' THEN total_count ELSE NULL END)::BIGINT AS prop_in
		, solarcommon.first(CASE meter_key WHEN 'datum-props-in' THEN tier_counts ELSE NULL END) AS prop_in_tiers

		, SUM(CASE meter_key WHEN 'datum-days-stored' THEN total_count ELSE NULL END)::BIGINT AS datum_stored
		, solarcommon.first(CASE meter_key WHEN 'datum-days-stored' THEN tier_counts ELSE NULL END) AS datum_stored_tiers

		, SUM(CASE meter_key WHEN 'datum-out' THEN total_count ELSE NULL END)::BIGINT AS datum_out
		, solarcommon.first(CASE meter_key WHEN 'datum-out' THEN tier_counts ELSE NULL END) AS datum_out_tiers
	FROM counts
	GROUP BY node_id
$$;


/**
 * Calculate the costs associated with billing tiers fora given user on a given month.
 *
 * This calls the `solarbill.billing_usage_tiers()` function to determine the pricing tiers to use
 * at the given `effective_date`.
 *
 * @param userid the ID of the user to calculate the billing information for
 * @param ts_min the start date to calculate the costs for (inclusive)
 * @param ts_max the end date to calculate the costs for (exclusive)
 * @param effective_date optional pricing date, to calculate the costs effective at that time
 */
CREATE OR REPLACE FUNCTION solarbill.billing_usage_tier_details(userid BIGINT, ts_min TIMESTAMP, ts_max TIMESTAMP, effective_date date DEFAULT CURRENT_DATE)
	RETURNS TABLE(
		meter_key 	TEXT,
		tier_min 	BIGINT,
		tier_count 	BIGINT,
		tier_rate 	NUMERIC,
		tier_cost 	NUMERIC
	) LANGUAGE sql STABLE AS
$$
	WITH tiers AS (
		SELECT * FROM solarbill.billing_usage_tiers(effective_date)
	)
	, usage AS (
		SELECT
			  SUM(prop_in)::BIGINT AS prop_in
			, SUM(datum_stored)::BIGINT AS datum_stored
			, SUM(datum_out)::BIGINT AS datum_out
		FROM solarbill.billing_usage(userid, ts_min, ts_max)
	)
	SELECT
		  tiers.meter_key
		, tiers.min AS tier_min
		, LEAST(GREATEST(CASE meter_key
			WHEN 'datum-props-in' THEN n.prop_in
			WHEN 'datum-days-stored' THEN n.datum_stored
			WHEN 'datum-out' THEN n.datum_out
			ELSE NULL END - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(CASE meter_key
			WHEN 'datum-props-in' THEN n.prop_in
			WHEN 'datum-days-stored' THEN n.datum_stored
			WHEN 'datum-out' THEN n.datum_out
			ELSE NULL END - tiers.min, 0))) AS tier_count
		, tiers.cost AS tier_rate
		, LEAST(GREATEST(CASE meter_key
			WHEN 'datum-props-in' THEN n.prop_in
			WHEN 'datum-days-stored' THEN n.datum_stored
			WHEN 'datum-out' THEN n.datum_out
			ELSE NULL END - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(CASE meter_key
			WHEN 'datum-props-in' THEN n.prop_in
			WHEN 'datum-days-stored' THEN n.datum_stored
			WHEN 'datum-out' THEN n.datum_out
			ELSE NULL END - tiers.min, 0))) * tiers.cost AS tier_cost
	FROM usage n
	CROSS JOIN tiers
	WINDOW win AS (PARTITION BY tiers.meter_key ORDER BY tiers.min)
$$;

/**
 * Calculate the costs associated with billing tiers for a given user on a given month,
 * with tiers aggregated.
 *
 * This calls the `solarbill.billing_usage_tier_details()` function to determine the pricing tiers to use
 * at the given `effective_date`.
 *
 * @param userid the ID of the user to calculate the billing information for
 * @param ts_min the start date to calculate the costs for (inclusive)
 * @param ts_max the end date to calculate the costs for (exclusive)
 * @param effective_date optional pricing date, to calculate the costs effective at that time
 */
CREATE OR REPLACE FUNCTION solarbill.billing_usage_details(userid BIGINT, ts_min TIMESTAMP, ts_max TIMESTAMP, effective_date date DEFAULT CURRENT_DATE)
	RETURNS TABLE(
		prop_in 					BIGINT,
		prop_in_cost 				NUMERIC,
		prop_in_tiers 				NUMERIC[],
		prop_in_tiers_cost 			NUMERIC[],
		datum_stored 				BIGINT,
		datum_stored_cost 			NUMERIC,
		datum_stored_tiers 			NUMERIC[],
		datum_stored_tiers_cost 	NUMERIC[],
		datum_out 					BIGINT,
		datum_out_cost 				NUMERIC,
		datum_out_tiers 			NUMERIC[],
		datum_out_tiers_cost 		NUMERIC[],
		total_cost 					NUMERIC
	) LANGUAGE sql STABLE AS
$$
	WITH tier_costs AS (
		SELECT * FROM solarbill.billing_usage_tier_details(userid, ts_min, ts_max, effective_date)
	)
	, costs AS (
		SELECT
			  meter_key
			, SUM(tier_count)::BIGINT AS total_count
			, SUM(tier_cost) AS total_cost
			, ARRAY_AGG(tier_count::NUMERIC) AS tier_counts
			, ARRAY_AGG(tier_cost) AS tier_costs
		FROM tier_costs
		WHERE tier_count > 0
		GROUP BY meter_key
	)
	SELECT
		  SUM(CASE meter_key WHEN 'datum-props-in' THEN total_count ELSE NULL END)::BIGINT AS prop_in
		, SUM(CASE meter_key WHEN 'datum-props-in' THEN total_cost ELSE NULL END) AS prop_in_cost
		, solarcommon.first(CASE meter_key WHEN 'datum-props-in' THEN tier_counts ELSE NULL END) AS prop_in_tiers
		, solarcommon.first(CASE meter_key WHEN 'datum-props-in' THEN tier_costs ELSE NULL END) AS prop_in_tiers_cost

		, SUM(CASE meter_key WHEN 'datum-days-stored' THEN total_count ELSE NULL END)::BIGINT AS datum_stored
		, SUM(CASE meter_key WHEN 'datum-days-stored' THEN total_cost ELSE NULL END) AS datum_stored_cost
		, solarcommon.first(CASE meter_key WHEN 'datum-days-stored' THEN tier_counts ELSE NULL END) AS datum_stored_tiers
		, solarcommon.first(CASE meter_key WHEN 'datum-days-stored' THEN tier_costs ELSE NULL END) AS datum_stored_cost


		, SUM(CASE meter_key WHEN 'datum-out' THEN total_count ELSE NULL END)::BIGINT AS datum_out
		, SUM(CASE meter_key WHEN 'datum-out' THEN total_cost ELSE NULL END) AS datum_out_cost
		, solarcommon.first(CASE meter_key WHEN 'datum-out' THEN tier_counts ELSE NULL END) AS datum_out_tiers
		, solarcommon.first(CASE meter_key WHEN 'datum-out' THEN tier_costs ELSE NULL END) AS datum_out_cost

		, SUM(total_cost) AS total_cost
	FROM costs
	HAVING
		SUM(CASE meter_key WHEN 'datum-props-in' THEN total_count ELSE NULL END)::BIGINT > 0 OR
		SUM(CASE meter_key WHEN 'datum-days-stored' THEN total_count ELSE NULL END)::BIGINT > 0 OR
		SUM(CASE meter_key WHEN 'datum-out' THEN total_count ELSE NULL END)::BIGINT > 0
$$;
