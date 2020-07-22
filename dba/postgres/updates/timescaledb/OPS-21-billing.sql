CREATE SCHEMA IF NOT EXISTS solarbill;

ALTER DEFAULT PRIVILEGES IN SCHEMA solarbill REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarbill REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarbill REVOKE ALL ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarbill REVOKE ALL ON TYPES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES IN SCHEMA solarbill GRANT ALL ON TABLES TO solaruser;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarbill GRANT ALL ON SEQUENCES TO solaruser;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarbill GRANT ALL ON FUNCTIONS TO solaruser;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarbill GRANT ALL ON TYPES TO solaruser;

ALTER DEFAULT PRIVILEGES IN SCHEMA solarbill GRANT ALL ON TABLES TO solarjobs;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarbill GRANT ALL ON SEQUENCES TO solarjobs;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarbill GRANT ALL ON FUNCTIONS TO solarjobs;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarbill GRANT ALL ON TYPES TO solarjobs;

CREATE SEQUENCE IF NOT EXISTS solarbill.bill_seq;

-- table to store billing address records, so invoices can maintain immutable
-- reference to billing address used at invoice generation time
CREATE TABLE IF NOT EXISTS solarbill.bill_address (
	id				BIGINT NOT NULL DEFAULT nextval('solarbill.bill_seq'),
	created 		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	disp_name		CHARACTER VARYING(128) NOT NULL,
	email			citext NOT NULL,
	country			CHARACTER VARYING(2) NOT NULL,
	time_zone		CHARACTER VARYING(64) NOT NULL,
	region			CHARACTER VARYING(128),
	state_prov		CHARACTER VARYING(128),
	locality		CHARACTER VARYING(128),
	postal_code		CHARACTER VARYING(32),
	address			CHARACTER VARYING(256)[],
	CONSTRAINT bill_address_pkey PRIMARY KEY (id)
);

-- table to store billing account information, with reference to current address
CREATE TABLE IF NOT EXISTS solarbill.bill_account (
	id				BIGINT NOT NULL DEFAULT nextval('solarbill.bill_seq'),
	created 		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	user_id			BIGINT NOT NULL,
	addr_id			BIGINT NOT NULL,
	currency		CHARACTER VARYING(3) NOT NULL,
	locale			CHARACTER VARYING(5) NOT NULL,
	CONSTRAINT bill_account_pkey PRIMARY KEY (id),
	CONSTRAINT bill_account_address_fk FOREIGN KEY (addr_id)
		REFERENCES solarbill.bill_address (id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE NO ACTION
);

CREATE UNIQUE INDEX IF NOT EXISTS bill_account_user_idx ON solarbill.bill_account (user_id);

-- table to store immutable invoice information
CREATE TABLE IF NOT EXISTS solarbill.bill_invoice (
	id				uuid NOT NULL,
	created 		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	acct_id			BIGINT NOT NULL,
	addr_id			BIGINT NOT NULL,
	date_start 		DATE NOT NULL,
	date_end 		DATE NOT NULL,
	currency		CHARACTER VARYING(3) NOT NULL,
	CONSTRAINT bill_invoice_pkey PRIMARY KEY (id),
	CONSTRAINT bill_invoice_acct_fk FOREIGN KEY (acct_id)
		REFERENCES solarbill.bill_account (id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE NO ACTION,
	CONSTRAINT bill_invoice_address_fk FOREIGN KEY (addr_id)
		REFERENCES solarbill.bill_address (id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE NO ACTION
);

CREATE INDEX IF NOT EXISTS bill_invoice_acct_idx ON solarbill.bill_invoice (acct_id);

CREATE INDEX IF NOT EXISTS bill_invoice_date_start_idx ON solarbill.bill_invoice (date_start);

CREATE INDEX IF NOT EXISTS bill_invoice_date_end_idx ON solarbill.bill_invoice (date_end);

-- table to store immutable invoice item information
CREATE TABLE IF NOT EXISTS solarbill.bill_invoice_item (
	id				uuid NOT NULL,
	created 		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	inv_id			uuid NOT NULL,
	item_type		SMALLINT NOT NULL DEFAULT 0,
	amount			NUMERIC(11,2) NOT NULL,
	quantity		NUMERIC NOT NULL,
	jmeta			jsonb,
	CONSTRAINT bill_invoice_item_pkey PRIMARY KEY (inv_id, id),
	CONSTRAINT bill_invoice_item_inv_fk FOREIGN KEY (inv_id)
		REFERENCES solarbill.bill_invoice (id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE NO ACTION
);

-- table to store bill payment and credit information
-- pay_type specifies what type of payment, i.e. payment vs credit
CREATE TABLE IF NOT EXISTS solarbill.bill_payment (
	id				uuid NOT NULL,
	created 		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	inv_id			uuid,
	pay_type		SMALLINT NOT NULL DEFAULT 0,
	amount			NUMERIC(11,2) NOT NULL,
	CONSTRAINT bill_payment_pkey PRIMARY KEY (id),
	CONSTRAINT bill_payment_inv_fk FOREIGN KEY (inv_id)
		REFERENCES solarbill.bill_invoice (id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE NO ACTION
);

CREATE INDEX IF NOT EXISTS bill_payment_item_inv_idx ON solarbill.bill_payment (inv_id);


-- table to hold asynchronous account tasks
CREATE TABLE IF NOT EXISTS solarbill.bill_account_task (
	id				uuid NOT NULL,
	acct_id			BIGINT NOT NULL,
	task_type		SMALLINT NOT NULL DEFAULT 0,
	created 		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	jdata			jsonb,
	CONSTRAINT bill_account_task_pkey PRIMARY KEY (id),
	CONSTRAINT bill_account_task_acct_fk FOREIGN KEY (acct_id)
		REFERENCES solarbill.bill_account (id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS bill_account_task_created_idx 
ON solarbill.bill_account_task (created);

/**
 * "Claim" an account task, so it may be processed by some external job. This function must be
 * called within a transaction. The returned row will be locked, so that the external job can
 * delete it once complete. The oldest available row is returned.
 */
CREATE OR REPLACE FUNCTION solarbill.claim_bill_acount_task()
  RETURNS solarbill.bill_account_task LANGUAGE SQL VOLATILE AS
$$
	SELECT * FROM solarbill.bill_account_task
	ORDER BY created
	LIMIT 1
	FOR UPDATE SKIP LOCKED
$$;

/**
 * Get the billing price tiers for a specific point in time.
 *
 * @param ts the billing effective date; defaults to the current date if not provided
 */
CREATE OR REPLACE FUNCTION solarbill.billing_tiers(ts date DEFAULT CURRENT_DATE)
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

CREATE OR REPLACE FUNCTION solarbill.billing_details(userid BIGINT, ts_min TIMESTAMP, ts_max TIMESTAMP, effective_date date DEFAULT CURRENT_DATE)
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
			acc.node_id
			, SUM(acc.datum_count + acc.datum_hourly_count + acc.datum_monthly_count) AS datum_count
		FROM nodes nodes
		INNER JOIN solaragg.aud_acc_datum_daily acc ON acc.node_id = ANY(nodes.nodes)
			AND acc.ts_start >= nodes.sdate AND acc.ts_start < nodes.edate
		GROUP BY acc.node_id
	)
	, datum AS (
		SELECT
			a.node_id
			, SUM(a.prop_count) AS prop_count
			, SUM(a.datum_q_count) AS datum_q_count
		FROM nodes nodes
		INNER JOIN solaragg.aud_datum_monthly a ON a.node_id = ANY(nodes.nodes)
			AND a.ts_start >= nodes.sdate AND a.ts_start < nodes.edate
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
		
		FROM datum a
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
