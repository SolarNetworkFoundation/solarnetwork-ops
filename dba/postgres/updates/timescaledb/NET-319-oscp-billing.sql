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
	ELSIF ts < '2022-10-01'::DATE THEN
		RETURN QUERY SELECT *, '2021-06-01'::DATE FROM ( VALUES
			  ('datum-props-in', 		0::BIGINT, 				0.000005::NUMERIC)
			, ('datum-props-in', 		500000::BIGINT, 		0.000003::NUMERIC)
			, ('datum-props-in', 		10000000::BIGINT, 		0.0000008::NUMERIC)
			, ('datum-props-in', 		500000000::BIGINT, 		0.0000002::NUMERIC)

			, ('datum-out',				0::BIGINT, 				0.0000001::NUMERIC)
			, ('datum-out',				10000000::BIGINT, 		0.00000004::NUMERIC)
			, ('datum-out',				1000000000::BIGINT, 	0.000000004::NUMERIC)
			, ('datum-out',				100000000000::BIGINT, 	0.000000001::NUMERIC)

			, ('datum-days-stored', 	0::BIGINT, 				0.00000005::NUMERIC)
			, ('datum-days-stored', 	10000000::BIGINT, 		0.00000001::NUMERIC)
			, ('datum-days-stored', 	1000000000::BIGINT, 	0.000000003::NUMERIC)
			, ('datum-days-stored', 	100000000000::BIGINT,	0.000000002::NUMERIC)
		) AS t(min, meter_key, cost);
	ELSE
		RETURN QUERY SELECT *, '2022-10-01'::DATE FROM ( VALUES
			  ('datum-props-in', 		0::BIGINT, 				0.000005::NUMERIC)
			, ('datum-props-in', 		500000::BIGINT, 		0.000003::NUMERIC)
			, ('datum-props-in', 		10000000::BIGINT, 		0.0000008::NUMERIC)
			, ('datum-props-in', 		500000000::BIGINT, 		0.0000002::NUMERIC)

			, ('datum-out',				0::BIGINT, 				0.0000001::NUMERIC)
			, ('datum-out',				10000000::BIGINT, 		0.00000004::NUMERIC)
			, ('datum-out',				1000000000::BIGINT, 	0.000000004::NUMERIC)
			, ('datum-out',				100000000000::BIGINT, 	0.000000001::NUMERIC)

			, ('datum-days-stored', 	0::BIGINT, 				0.00000005::NUMERIC)
			, ('datum-days-stored', 	10000000::BIGINT, 		0.00000001::NUMERIC)
			, ('datum-days-stored', 	1000000000::BIGINT, 	0.000000003::NUMERIC)
			, ('datum-days-stored', 	100000000000::BIGINT,	0.000000002::NUMERIC)

			, ('ocpp-chargers', 		0::BIGINT, 				2::NUMERIC)
			, ('ocpp-chargers', 		250::BIGINT, 			1::NUMERIC)
			, ('ocpp-chargers', 		12500::BIGINT, 			0.5::NUMERIC)
			, ('ocpp-chargers', 		500000::BIGINT, 		0.3::NUMERIC)

			, ('oscp-cap-groups', 		0::BIGINT, 				18::NUMERIC)
			, ('oscp-cap-groups', 		100::BIGINT, 			9::NUMERIC)
			, ('oscp-cap-groups', 		1000::BIGINT, 			5::NUMERIC)
			, ('oscp-cap-groups', 		10000::BIGINT, 			3::NUMERIC)
		) AS t(min, meter_key, cost);
	END IF;
END
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
	, ocpp AS (
		SELECT count(*) AS ocpp_charger_count
		FROM solarev.ocpp_charge_point
		WHERE user_id = userid
			AND enabled = TRUE
	)
	, oscp AS (
		SELECT count(*) AS oscp_cap_group_count
		FROM solaroscp.oscp_cg_conf
		WHERE user_id = userid
			AND enabled = TRUE
	)
	SELECT
		  tiers.meter_key
		, tiers.min AS tier_min
		, LEAST(GREATEST(CASE meter_key
			WHEN 'datum-props-in' THEN n.prop_in
			WHEN 'datum-days-stored' THEN n.datum_stored
			WHEN 'datum-out' THEN n.datum_out
			WHEN 'ocpp-chargers' THEN ocpp.ocpp_charger_count
			WHEN 'oscp-cap-groups' THEN oscp.oscp_cap_group_count
			ELSE NULL END - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(CASE meter_key
			WHEN 'datum-props-in' THEN n.prop_in
			WHEN 'datum-days-stored' THEN n.datum_stored
			WHEN 'datum-out' THEN n.datum_out
			WHEN 'ocpp-chargers' THEN ocpp.ocpp_charger_count
			WHEN 'oscp-cap-groups' THEN oscp.oscp_cap_group_count
			ELSE NULL END - tiers.min, 0))) AS tier_count
		, tiers.cost AS tier_rate
		, LEAST(GREATEST(CASE meter_key
			WHEN 'datum-props-in' THEN n.prop_in
			WHEN 'datum-days-stored' THEN n.datum_stored
			WHEN 'datum-out' THEN n.datum_out
			WHEN 'ocpp-chargers' THEN ocpp.ocpp_charger_count
			WHEN 'oscp-cap-groups' THEN oscp.oscp_cap_group_count
			ELSE NULL END - tiers.min, 0), COALESCE(LEAD(tiers.min) OVER win - tiers.min, GREATEST(CASE meter_key
			WHEN 'datum-props-in' THEN n.prop_in
			WHEN 'datum-days-stored' THEN n.datum_stored
			WHEN 'datum-out' THEN n.datum_out
			WHEN 'ocpp-chargers' THEN ocpp.ocpp_charger_count
			WHEN 'oscp-cap-groups' THEN oscp.oscp_cap_group_count
			ELSE NULL END - tiers.min, 0))) * tiers.cost AS tier_cost
	FROM usage n, ocpp, oscp
	CROSS JOIN tiers
	WINDOW win AS (PARTITION BY tiers.meter_key ORDER BY tiers.min)
$$;

DROP FUNCTION solarbill.billing_usage_details(userid BIGINT, ts_min TIMESTAMP, ts_max TIMESTAMP, effective_date DATE);

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
CREATE OR REPLACE FUNCTION solarbill.billing_usage_details(userid BIGINT, ts_min TIMESTAMP, ts_max TIMESTAMP, effective_date DATE DEFAULT CURRENT_DATE)
	RETURNS TABLE(
		total_cost 					NUMERIC,
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
		ocpp_chargers				BIGINT,
		ocpp_chargers_cost			NUMERIC,
		ocpp_chargers_tiers			NUMERIC[],
		ocpp_chargers_tiers_cost	NUMERIC[],
		oscp_cap_groups				BIGINT,
		oscp_cap_groups_cost		NUMERIC,
		oscp_cap_groups_tiers		NUMERIC[],
		oscp_cap_groups_tiers_cost	NUMERIC[]
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
		  SUM(total_cost) AS total_cost

		, SUM(CASE meter_key WHEN 'datum-props-in' THEN total_count ELSE NULL END)::BIGINT AS prop_in
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

		, SUM(CASE meter_key WHEN 'ocpp-chargers' THEN total_count ELSE NULL END)::BIGINT AS ocpp_chargers
		, SUM(CASE meter_key WHEN 'ocpp-chargers' THEN total_cost ELSE NULL END) AS ocpp_chargers_cost
		, solarcommon.first(CASE meter_key WHEN 'ocpp-chargers' THEN tier_counts ELSE NULL END) AS ocpp_chargers_tiers
		, solarcommon.first(CASE meter_key WHEN 'ocpp-chargers' THEN tier_costs ELSE NULL END) AS ocpp_chargers_cost

		, SUM(CASE meter_key WHEN 'oscp-cap-groups' THEN total_count ELSE NULL END)::BIGINT AS oscp_cap_groups
		, SUM(CASE meter_key WHEN 'oscp-cap-groups' THEN total_cost ELSE NULL END) AS oscp_cap_groups_cost
		, solarcommon.first(CASE meter_key WHEN 'oscp-cap-groups' THEN tier_counts ELSE NULL END) AS oscp_cap_groups_tiers
		, solarcommon.first(CASE meter_key WHEN 'oscp-cap-groups' THEN tier_costs ELSE NULL END) AS oscp_cap_groups_cost

	FROM costs
	HAVING
		SUM(CASE meter_key WHEN 'datum-props-in' THEN total_count ELSE NULL END)::BIGINT > 0 OR
		SUM(CASE meter_key WHEN 'datum-days-stored' THEN total_count ELSE NULL END)::BIGINT > 0 OR
		SUM(CASE meter_key WHEN 'datum-out' THEN total_count ELSE NULL END)::BIGINT > 0 OR
		SUM(CASE meter_key WHEN 'ocpp-chargers' THEN total_count ELSE NULL END)::BIGINT > 0 OR
		SUM(CASE meter_key WHEN 'oscp-cap-groups' THEN total_count ELSE NULL END)::BIGINT > 0
$$;
