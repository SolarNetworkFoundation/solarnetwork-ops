CREATE TABLE IF NOT EXISTS solarcommon.messages (
	vers			TIMESTAMP WITH TIME ZONE NOT NULL,
	bundle			CHARACTER VARYING(128) NOT NULL,
	locale			CHARACTER VARYING(8) NOT NULL,
	msg_key			CHARACTER VARYING(128) NOT NULL,
	msg_val			TEXT,
	CONSTRAINT messages_pkey PRIMARY KEY (bundle,locale,vers,msg_key)
);

--DROP SCHEMA IF EXISTS solarbill CASCADE;
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
CREATE SEQUENCE IF NOT EXISTS solarbill.bill_inv_seq MINVALUE 1000 INCREMENT BY 1;


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
	id				BIGINT NOT NULL DEFAULT nextval('solarbill.bill_inv_seq'),
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

CREATE INDEX IF NOT EXISTS bill_invoice_acct_date_idx ON solarbill.bill_invoice (acct_id, date_start DESC);

-- table to store immutable invoice item information
CREATE TABLE IF NOT EXISTS solarbill.bill_invoice_item (
	id				uuid NOT NULL DEFAULT uuid_generate_v4(),
	created 		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	inv_id			BIGINT NOT NULL,
	item_type		SMALLINT NOT NULL DEFAULT 0,
	amount			NUMERIC(11,2) NOT NULL,
	quantity		NUMERIC NOT NULL,
	item_key		CHARACTER VARYING(64) NOT NULL,
	jmeta			jsonb,
	CONSTRAINT bill_invoice_item_pkey PRIMARY KEY (inv_id, id),
	CONSTRAINT bill_invoice_item_inv_fk FOREIGN KEY (inv_id)
		REFERENCES solarbill.bill_invoice (id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE NO ACTION
);

CREATE INDEX IF NOT EXISTS bill_invoice_item_inv_idx ON solarbill.bill_invoice_item (inv_id);

-- table to keep track of account payment status
-- there is no currency tracked here, just charges and payments to know the account status
CREATE TABLE IF NOT EXISTS solarbill.bill_account_balance (
	acct_id			BIGINT NOT NULL,
	charge_total	NUMERIC(19,2) NOT NULL,
	payment_total	NUMERIC(19,2) NOT NULL,
	CONSTRAINT bill_account_balance_pkey PRIMARY KEY (acct_id),
	CONSTRAINT bill_account_balance_acct_fk FOREIGN KEY (acct_id)
		REFERENCES solarbill.bill_account (id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE NO ACTION
);

/**
 * Trigger function to add/subtract from bill_account_balance as invoice items 
 * are updated.
 */
CREATE OR REPLACE FUNCTION solarbill.maintain_bill_account_balance()
	RETURNS "trigger"  LANGUAGE 'plpgsql' VOLATILE AS $$
DECLARE
	diff NUMERIC(19,2) := 0;
	acct BIGINT;
BEGIN
	SELECT acct_id FROM solarbill.bill_invoice
	WHERE id = (CASE
					WHEN TG_OP IN ('INSERT', 'UPDATE') THEN NEW.inv_id
					ELSE OLD.inv_id
				END)
	INTO acct;
	CASE TG_OP 
		WHEN 'INSERT' THEN
			diff := NEW.amount;
		WHEN 'UPDATE' THEN
			diff := NEW.amount - OLD.amount;
		ELSE
			diff := -OLD.amount;
	END CASE;
	IF (diff < 0::NUMERIC(19,2)) OR (diff > 0::NUMERIC(19,2)) THEN
		INSERT INTO solarbill.bill_account_balance (acct_id, charge_total, payment_total)
		VALUES (acct, diff, 0)
		ON CONFLICT (acct_id) DO UPDATE 
			SET charge_total = 
				solarbill.bill_account_balance.charge_total + EXCLUDED.charge_total;
	END IF;

	CASE TG_OP
		WHEN 'INSERT', 'UPDATE' THEN
			RETURN NEW;
		ELSE
			RETURN OLD;
	END CASE;
END;
$$;

CREATE TRIGGER bill_account_balance_tracker
    BEFORE INSERT OR DELETE OR UPDATE 
    ON solarbill.bill_invoice_item
    FOR EACH ROW
    EXECUTE PROCEDURE solarbill.maintain_bill_account_balance();

-- table to store bill payment and credit information
-- pay_type specifies what type of payment, i.e. payment vs credit
CREATE TABLE IF NOT EXISTS solarbill.bill_payment (
	id				UUID NOT NULL DEFAULT uuid_generate_v4(),
	created 		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	inv_id			BIGINT,
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
	id				uuid NOT NULL DEFAULT uuid_generate_v4(),
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
CREATE OR REPLACE FUNCTION solarbill.claim_bill_account_task()
  RETURNS solarbill.bill_account_task LANGUAGE SQL VOLATILE AS
$$
	SELECT * FROM solarbill.bill_account_task
	ORDER BY created
	LIMIT 1
	FOR UPDATE SKIP LOCKED
$$;

/**
 * Table to hold tax rates over time that are applied to specific invoice items for accounts in
 * specific "tax zones". Zones are like geographic constructs like countries, states, cities, etc.
 */
CREATE TABLE IF NOT EXISTS solarbill.bill_tax_code (
	id				BIGINT NOT NULL DEFAULT nextval('solarbill.bill_seq'),
	created 		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	tax_zone 		VARCHAR(36) NOT NULL,
	item_key	 	VARCHAR(64) NOT NULL,
	tax_code 		VARCHAR(255) NOT NULL,
	tax_rate 		NUMERIC(15,9) NOT NULL,
	valid_from 		TIMESTAMP WITH TIME ZONE NOT NULL,
	valid_to 		TIMESTAMP WITH TIME ZONE,
	CONSTRAINT bill_tax_codes_pkey PRIMARY KEY (id)
);

CREATE INDEX bill_tax_code_item_idx ON solarbill.bill_tax_code (tax_zone, item_key, tax_code);

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
		cost_datum_stored NUMERIC,
		effective_date date
	)
	LANGUAGE plpgsql IMMUTABLE AS
$$
BEGIN
	IF ts < '2020-06-01'::date THEN
		RETURN QUERY SELECT * FROM ( VALUES
			  (0::bigint, 		0.000009::numeric, 		0.000002::numeric, 	0.000000006::numeric, '2008-01-01'::date)
		) AS t(min, cost_prop_in, cost_datum_out, cost_datum_stored, effective_date);
	ELSE
		RETURN QUERY SELECT * FROM ( VALUES
			  (0::bigint, 		0.000009::numeric, 		0.000002::numeric, 	0.0000004::numeric, '2020-06-01'::date)
			, (50000::bigint, 	0.000006::numeric, 		0.000001::numeric, 	0.0000002::numeric, '2020-06-01'::date)
			, (400000::bigint, 	0.000004::numeric, 		0.0000005::numeric, 0.00000005::numeric, '2020-06-01'::date)
			, (1000000::bigint, 0.000002::numeric, 		0.0000002::numeric, 0.000000006::numeric, '2020-06-01'::date)
		) AS t(min, cost_prop_in, cost_datum_out, cost_datum_stored, effective_date);
	END IF;
END
$$;

/**
 * Calculate the costs associated with billing tiers for all nodes for a given user on a given month.
 *
 * This calls the `solarbill.billing_tiers()` function to determine the pricing tiers to use
 * at the given `effective_date`.
 *
 * @param userid the ID of the user to calculate the billing information for
 * @param ts_min the start date to calculate the costs for (inclusive)
 * @param ts_max the end date to calculate the costs for (exclusive)
 * @param effective_date optional pricing date, to calculate the costs effective at that time
 */
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
			acc.node_id
			, SUM(acc.datum_count + acc.datum_hourly_count + acc.datum_daily_count + acc.datum_monthly_count) AS datum_count
		FROM nodes nodes
		INNER JOIN solaragg.aud_acc_datum_daily acc ON acc.node_id = ANY(nodes.nodes)
			AND acc.ts_start >= nodes.sdate AND acc.ts_start < nodes.edate
		GROUP BY acc.node_id
	)
	, datum AS (
		SELECT
			a.node_id
			, SUM(a.prop_count)::bigint AS prop_count
			, SUM(a.datum_q_count)::bigint AS datum_q_count
		FROM nodes nodes
		INNER JOIN solaragg.aud_datum_monthly a ON a.node_id = ANY(nodes.nodes)
			AND a.ts_start >= nodes.sdate AND a.ts_start < nodes.edate
		GROUP BY a.node_id
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

/**
 * Calculate the costs associated with billing tiers for all nodes for a given user on a given month,
 * with tiers aggregated per node.
 *
 * This calls the `solarbill.billing_tier_details()` function to determine the pricing tiers to use
 * at the given `effective_date`.
 *
 * @param userid the ID of the user to calculate the billing information for
 * @param ts_min the start date to calculate the costs for (inclusive)
 * @param ts_max the end date to calculate the costs for (exclusive)
 * @param effective_date optional pricing date, to calculate the costs effective at that time
 */
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
	HAVING ROUND(SUM(tier_prop_in * cost_prop_in) + SUM(tier_datum_stored * cost_datum_stored) + SUM(tier_datum_out * cost_datum_out), 2) > 0
	ORDER BY node_id
$$;
