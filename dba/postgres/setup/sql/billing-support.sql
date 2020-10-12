/**
 * Get the billing price tiers for a specific point in time.
 *
 * @param ts the billing effective date; defaults to the current date if not provided
 */
CREATE OR REPLACE FUNCTION solaruser.billing_tiers(ts date DEFAULT CURRENT_DATE)
	RETURNS TABLE(
		min BIGINT,
		cost_prop_in NUMERIC,
		cost_datum_out NUMERIC,
		cost_datum_stored NUMERIC
	)
	LANGUAGE plpgsql IMMUTABLE AS
$$
BEGIN
	IF ts < '2020-06-01'::date THEN
		RETURN QUERY SELECT * FROM ( VALUES
			  (0::bigint, 		0.000009::numeric, 		0.000002::numeric, 	0.000000006::numeric)
		) AS t(min, cost_prop_in, cost_datum_out, cost_datum_stored);
	ELSE
		RETURN QUERY SELECT * FROM ( VALUES
			  (0::bigint, 		0.000009::numeric, 		0.000002::numeric, 	0.0000004::numeric)
			, (50000::bigint, 	0.000006::numeric, 		0.000001::numeric, 	0.0000002::numeric)
			, (400000::bigint, 	0.000004::numeric, 		0.0000005::numeric, 0.00000005::numeric)
			, (1000000::bigint, 0.000002::numeric, 		0.0000002::numeric, 0.000000006::numeric)
		) AS t(min, cost_prop_in, cost_datum_out, cost_datum_stored);
	END IF;
END
$$;

/**
 * Calculate the approximate costs billed for all nodes on a given month.
 *
 * This calls the solaruser.billing_tiers(date) function to determine the pricing tiers to use.
 *
 * @param ts_month the month to calculate the costs for
 * @param effective_month optional pricing date, to calculate the costs effective at that time
 */
CREATE OR REPLACE FUNCTION solaruser.billing_month(ts_month date, effective_month date DEFAULT CURRENT_DATE)
	RETURNS TABLE(
		node_id BIGINT,
		prop_in BIGINT,
		prop_in_cost NUMERIC,
		datum_stored BIGINT,
		datum_stored_cost NUMERIC,
		datum_out BIGINT,
		datum_out_cost NUMERIC,
		total_cost NUMERIC	
	) LANGUAGE sql STABLE AS
$$
	WITH tiers AS (
		SELECT * FROM solaruser.billing_tiers(effective_month)
	)
	, stored AS (
		SELECT 
			acc.node_id
			, SUM(acc.datum_count + acc.datum_hourly_count + acc.datum_daily_count + acc.datum_monthly_count) AS datum_count
		FROM solaragg.aud_acc_datum_daily acc
		INNER JOIN solarnet.node_local_time nlt ON nlt.node_id = acc.node_id
		WHERE 
			acc.ts_start AT TIME ZONE nlt.time_zone >= ts_month
			AND acc.ts_start AT TIME ZONE nlt.time_zone < (ts_month + interval '1 month')
		GROUP BY acc.node_id
	)
	, nodes AS (
		SELECT
			a.node_id
			, SUM(a.prop_count) AS prop_count
			, SUM(a.datum_q_count) AS datum_q_count
		FROM solaragg.aud_datum_monthly a
		INNER JOIN solarnet.node_local_time nlt ON nlt.node_id = a.node_id
		WHERE a.ts_start AT TIME ZONE nlt.time_zone = ts_month
		GROUP BY a.node_id
	)
	, costs AS (
		SELECT
			a.node_id
			, tiers.min
			, a.prop_count AS prop_in
			, LEAST(GREATEST(a.prop_count - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(a.prop_count - tiers.min, 0))) AS tier_prop_in
			, tiers.cost_prop_in
		
			, s.datum_count AS datum_stored
			, LEAST(GREATEST(s.datum_count - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(s.datum_count - tiers.min, 0))) AS tier_datum_stored
			, tiers.cost_datum_stored
		
			, a.datum_q_count AS datum_out
			, LEAST(GREATEST(a.datum_q_count - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(a.datum_q_count - tiers.min, 0))) AS tier_datum_out
			, tiers.cost_datum_out
		
		FROM nodes a
		LEFT OUTER JOIN stored s ON s.node_id = a.node_id
		CROSS JOIN tiers
		WINDOW win AS (PARTITION BY a.node_id ORDER BY tiers.min)
	)
	SELECT 
		node_id
		, SUM(tier_prop_in)::bigint AS prop_in
		, SUM(tier_prop_in * cost_prop_in) AS prop_in_cost
	
		, SUM(tier_datum_stored)::bigint AS datum_stored
		, SUM(tier_datum_stored * cost_datum_stored) AS datum_stored_cost
	
		, SUM(tier_datum_out)::bigint AS datum_out
		, SUM(tier_datum_out * cost_datum_out) AS datum_out_cost
	
		, ROUND(SUM(tier_prop_in * cost_prop_in) + SUM(tier_datum_stored * cost_datum_stored) + SUM(tier_datum_out * cost_datum_out), 2) AS total_cost
	FROM costs
	GROUP BY node_id
	HAVING ROUND(SUM(tier_prop_in * cost_prop_in) + SUM(tier_datum_stored * cost_datum_stored) + SUM(tier_datum_out * cost_datum_out), 2) > 0
	ORDER BY node_id
$$;

/* Example call for current date pricing:

SELECT * FROM solaruser.billing_month('2020-04-01'::date);

Example call for specific date pricing:

SELECT * FROM solaruser.billing_month('2020-04-01'::date, '2020-06-01'::date);
*/
