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
 * Calculate the costs associated with billing tiers fora given user on a given month.
 *
 * This calls the `solarbill.billing_tiers()` function to determine the pricing tiers to use
 * at the given `effective_date`.
 *
 * @param userid the ID of the user to calculate the billing information for
 * @param ts_min the start date to calculate the costs for (inclusive)
 * @param ts_max the end date to calculate the costs for (exclusive)
 * @param effective_date optional pricing date, to calculate the costs effective at that time
 */
CREATE OR REPLACE FUNCTION solarbill.billing_usage_tier_details(userid BIGINT, ts_min TIMESTAMP, ts_max TIMESTAMP, effective_date date DEFAULT CURRENT_DATE)
	RETURNS TABLE(
		min BIGINT,
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
	, usage AS (
		SELECT
			  SUM(prop_in)::BIGINT AS prop_in
			, SUM(datum_stored)::BIGINT AS datum_stored
			, SUM(datum_out)::BIGINT AS datum_out
		FROM solarbill.billing_usage(userid, ts_min, ts_max)
	)
	, costs AS (
		SELECT
			  tiers.min
			, n.prop_in
			, LEAST(GREATEST(n.prop_in - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(n.prop_in - tiers.min, 0))) AS tier_prop_in
			, tiers.cost_prop_in

			, n.datum_stored
			, LEAST(GREATEST(n.datum_stored - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(n.datum_stored - tiers.min, 0))) AS tier_datum_stored
			, tiers.cost_datum_stored

			, n.datum_out
			, LEAST(GREATEST(n.datum_out - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(n.datum_out - tiers.min, 0))) AS tier_datum_out
			, tiers.cost_datum_out
		FROM usage n
		CROSS JOIN tiers
		WINDOW win AS (ORDER BY tiers.min)
	)
	SELECT
		  min
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
		prop_in BIGINT,
		prop_in_cost NUMERIC,
		prop_in_tiers NUMERIC[],
		prop_in_tiers_cost NUMERIC[],
		datum_stored BIGINT,
		datum_stored_cost NUMERIC,
		datum_stored_tiers NUMERIC[],
		datum_stored_tiers_cost NUMERIC[],
		datum_out BIGINT,
		datum_out_cost NUMERIC,
		datum_out_tiers NUMERIC[],
		datum_out_tiers_cost NUMERIC[],
		total_cost NUMERIC,
		total_tiers_cost NUMERIC[]
	) LANGUAGE sql STABLE AS
$$
	SELECT
		  SUM(tier_prop_in)::BIGINT AS prop_in
		, SUM(tier_prop_in * cost_prop_in) AS prop_in_cost
		, ARRAY_AGG(tier_prop_in::NUMERIC) AS prop_in_tiers
		, ARRAY_AGG(tier_prop_in * cost_prop_in) AS prop_in_tiers_cost

		, SUM(tier_datum_stored)::BIGINT AS datum_stored
		, SUM(tier_datum_stored * cost_datum_stored) AS datum_stored_cost
		, ARRAY_AGG(tier_datum_stored::NUMERIC) AS datum_stored_tiers
		, ARRAY_AGG(tier_datum_stored * cost_datum_stored) AS datum_stored_tiers_cost

		, SUM(tier_datum_out)::BIGINT AS datum_out
		, SUM(tier_datum_out * cost_datum_out) AS datum_out_cost
		, ARRAY_AGG(tier_datum_out::NUMERIC) AS datum_out_tiers
		, ARRAY_AGG(tier_datum_out * cost_datum_out) AS datum_out_tiers_cost

		, ROUND(SUM(tier_prop_in * cost_prop_in) + SUM(tier_datum_stored * cost_datum_stored) + SUM(tier_datum_out * cost_datum_out), 2) AS total_cost
		, ARRAY_AGG((tier_prop_in * cost_prop_in) + (tier_datum_stored * cost_datum_stored) + (tier_datum_out * cost_datum_out)) AS total_tiers_cost
	FROM solarbill.billing_usage_tier_details(userid, ts_min, ts_max, effective_date) costs
	HAVING ROUND(SUM(tier_prop_in * cost_prop_in) + SUM(tier_datum_stored * cost_datum_stored) + SUM(tier_datum_out * cost_datum_out), 2) > 0
$$;


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
	, usage AS (
		SELECT
			  node_id
			, SUM(prop_in)::BIGINT AS prop_in
			, SUM(datum_stored)::BIGINT AS datum_stored
			, SUM(datum_out)::BIGINT AS datum_out
		FROM solarbill.billing_usage(userid, ts_min, ts_max)
		GROUP BY node_id
	)
	, costs AS (
		SELECT
			  n.node_id
			, tiers.min
			, n.prop_in
			, LEAST(GREATEST(n.prop_in - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(n.prop_in - tiers.min, 0))) AS tier_prop_in
			, tiers.cost_prop_in

			, n.datum_stored
			, LEAST(GREATEST(n.datum_stored - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(n.datum_stored - tiers.min, 0))) AS tier_datum_stored
			, tiers.cost_datum_stored

			, n.datum_out
			, LEAST(GREATEST(n.datum_out - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(n.datum_out - tiers.min, 0))) AS tier_datum_out
			, tiers.cost_datum_out
		FROM usage n
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
	WHERE (tier_prop_in > 0 OR tier_datum_stored > 0 OR tier_datum_out > 0)
$$;

CREATE OR REPLACE FUNCTION solarbill.billing_details(userid BIGINT, ts_min TIMESTAMP, ts_max TIMESTAMP, effective_date date DEFAULT CURRENT_DATE)
	RETURNS TABLE(
		node_id BIGINT,
		prop_in BIGINT,
		prop_in_cost NUMERIC,
		prop_in_tiers NUMERIC[],
		prop_in_tiers_cost NUMERIC[],
		datum_stored BIGINT,
		datum_stored_cost NUMERIC,
		datum_stored_tiers NUMERIC[],
		datum_stored_tiers_cost NUMERIC[],
		datum_out BIGINT,
		datum_out_cost NUMERIC,
		datum_out_tiers NUMERIC[],
		datum_out_tiers_cost NUMERIC[],
		total_cost NUMERIC,
		total_tiers_cost NUMERIC[]
	) LANGUAGE sql STABLE AS
$$
	SELECT
		  node_id
		, SUM(tier_prop_in)::bigint AS prop_in
		, SUM(tier_prop_in * cost_prop_in) AS prop_in_cost
		, ARRAY_AGG(tier_prop_in::NUMERIC) AS prop_in_tiers
		, ARRAY_AGG(tier_prop_in * cost_prop_in) AS prop_in_tiers_cost

		, SUM(tier_datum_stored)::bigint AS datum_stored
		, SUM(tier_datum_stored * cost_datum_stored) AS datum_stored_cost
		, ARRAY_AGG(tier_datum_stored::NUMERIC) AS datum_stored_tiers
		, ARRAY_AGG(tier_datum_stored * cost_datum_stored) AS datum_stored_tiers_cost

		, SUM(tier_datum_out)::bigint AS datum_out
		, SUM(tier_datum_out * cost_datum_out) AS datum_out_cost
		, ARRAY_AGG(tier_datum_out::NUMERIC) AS datum_out_tiers
		, ARRAY_AGG(tier_datum_out * cost_datum_out) AS datum_out_tiers_cost

		, ROUND(SUM(tier_prop_in * cost_prop_in) + SUM(tier_datum_stored * cost_datum_stored) + SUM(tier_datum_out * cost_datum_out), 2) AS total_cost
		, ARRAY_AGG((tier_prop_in * cost_prop_in) + (tier_datum_stored * cost_datum_stored) + (tier_datum_out * cost_datum_out)) AS total_tiers_cost
	FROM solarbill.billing_tier_details(userid, ts_min, ts_max, effective_date) costs
	GROUP BY node_id
	HAVING (SUM(tier_prop_in) > 0 OR SUM(tier_datum_stored) > 0 OR SUM(tier_datum_out) > 0)
$$;
