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

-- table to keep track of account payment status
-- there is no currency tracked here, just charges and payments to know the account status
CREATE TABLE IF NOT EXISTS solarbill.bill_account_balance (
	acct_id			BIGINT NOT NULL,
	created 		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	charge_total	NUMERIC(19,2) NOT NULL,
	payment_total	NUMERIC(19,2) NOT NULL,
	avail_credit	NUMERIC(11,2) NOT NULL DEFAULT 0,
	CONSTRAINT bill_account_balance_pkey PRIMARY KEY (acct_id),
	CONSTRAINT bill_account_balance_acct_fk FOREIGN KEY (acct_id)
		REFERENCES solarbill.bill_account (id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE NO ACTION
);

/**
 * Trigger function to add/subtract from bill_account_balance as invoice items
 * are updated.
 */
CREATE OR REPLACE FUNCTION solarbill.maintain_bill_account_balance_charge()
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
			diff := CASE NEW.item_key WHEN 'account-credit-add' THEN 0 ELSE NEW.amount END;
		WHEN 'UPDATE' THEN
			diff := CASE NEW.item_key WHEN 'account-credit-add' THEN 0 ELSE NEW.amount - OLD.amount END;
		ELSE
			diff := CASE NEW.item_key WHEN 'account-credit-add' THEN 0 ELSE -OLD.amount END;
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

CREATE TRIGGER bill_account_balance_charge_tracker
    AFTER INSERT OR DELETE OR UPDATE
    ON solarbill.bill_invoice_item
    FOR EACH ROW
    EXECUTE PROCEDURE solarbill.maintain_bill_account_balance_charge();

/**
 * Claim a portion of the available credit in a bill_account_balance record.
 *
 * This will never claim more than the available credit in the account balance. Thus the returned
 * amount might be less than the requested amount.
 *
 * @param accountid the ID of the account to claim credit from
 * @param max_claim the maximum amount to claim, or `NULL` for the full amount available
 */
CREATE OR REPLACE FUNCTION solarbill.claim_account_credit(
	accountid BIGINT,
	max_claim NUMERIC(11,2) DEFAULT NULL
) RETURNS NUMERIC(11,2) LANGUAGE SQL VOLATILE AS
$$
	WITH claim AS (
		SELECT GREATEST(0::NUMERIC(11,2), LEAST(avail_credit, COALESCE(max_claim, avail_credit))) AS claim
		FROM solarbill.bill_account_balance
		WHERE acct_id = accountid
		FOR UPDATE
	)
	UPDATE solarbill.bill_account_balance
	SET avail_credit = avail_credit - claim.claim
	FROM claim
	WHERE acct_id = accountid
	RETURNING COALESCE(claim.claim, 0::NUMERIC(11,2))
$$;

-- table to store bill payment and credit information
-- pay_type specifies what type of payment, i.e. payment vs credit
CREATE TABLE IF NOT EXISTS solarbill.bill_payment (
	id				UUID NOT NULL DEFAULT uuid_generate_v4(),
	created 		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	acct_id			BIGINT NOT NULL,
	pay_type		SMALLINT NOT NULL DEFAULT 0,
	amount			NUMERIC(11,2) NOT NULL,
	currency		CHARACTER VARYING(3) NOT NULL,
	ext_key			CHARACTER VARYING(64),
	ref				TEXT,
	CONSTRAINT bill_payment_pkey PRIMARY KEY (acct_id, id),
	CONSTRAINT bill_payment_account_fk FOREIGN KEY (acct_id)
		REFERENCES solarbill.bill_account (id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE NO ACTION
);

CREATE INDEX IF NOT EXISTS bill_payment_account_created_idx
ON solarbill.bill_payment (acct_id, created DESC);

/**
 * Trigger function to add/subtract from bill_account_balance as invoice items
 * are updated.
 */
CREATE OR REPLACE FUNCTION solarbill.maintain_bill_account_balance_payment()
	RETURNS "trigger"  LANGUAGE 'plpgsql' VOLATILE AS $$
DECLARE
	diff NUMERIC(19,2) := 0;
	acct BIGINT;
BEGIN
	CASE TG_OP
		WHEN 'INSERT' THEN
			diff := NEW.amount;
			acct := NEW.acct_id;
		WHEN 'UPDATE' THEN
			diff := NEW.amount - OLD.amount;
			acct := NEW.acct_id;
		ELSE
			diff := -OLD.amount;
			acct := OLD.acct_id;
	END CASE;
	IF (diff < 0::NUMERIC(19,2)) OR (diff > 0::NUMERIC(19,2)) THEN
		INSERT INTO solarbill.bill_account_balance (acct_id, charge_total, payment_total)
		VALUES (acct, 0, diff)
		ON CONFLICT (acct_id) DO UPDATE
			SET payment_total =
				solarbill.bill_account_balance.payment_total + EXCLUDED.payment_total;
	END IF;

	CASE TG_OP
		WHEN 'INSERT', 'UPDATE' THEN
			RETURN NEW;
		ELSE
			RETURN OLD;
	END CASE;
END;
$$;

CREATE TRIGGER bill_account_balance_payment_tracker
    AFTER INSERT OR DELETE OR UPDATE
    ON solarbill.bill_payment
    FOR EACH ROW
    EXECUTE PROCEDURE solarbill.maintain_bill_account_balance_payment();

-- table to track payments associated with invoices
CREATE TABLE IF NOT EXISTS solarbill.bill_invoice_payment (
	id				UUID NOT NULL DEFAULT uuid_generate_v4(),
	created 		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	acct_id			BIGINT NOT NULL,
	pay_id			UUID NOT NULL,
	inv_id			BIGINT NOT NULL,
	amount			NUMERIC(11,2) NOT NULL,
	CONSTRAINT bill_invoice_payment_pkey PRIMARY KEY (id),
	CONSTRAINT bill_invoice_payment_payment_fk FOREIGN KEY (pay_id, acct_id)
		REFERENCES solarbill.bill_payment (id, acct_id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE NO ACTION,
	CONSTRAINT bill_invoice_payment_invoice_fk FOREIGN KEY (inv_id)
		REFERENCES solarbill.bill_invoice (id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE NO ACTION
);

CREATE INDEX IF NOT EXISTS bill_invoice_payment_acct_inv_idx
ON solarbill.bill_invoice_payment (acct_id,inv_id);

CREATE INDEX IF NOT EXISTS bill_invoice_payment_pay_idx
ON solarbill.bill_invoice_payment (pay_id);

/**
 * Trigger function to prevent invoice payments from exceeding the payment amount.
 */
CREATE OR REPLACE FUNCTION solarbill.validate_bill_invoice_payment()
	RETURNS "trigger"  LANGUAGE 'plpgsql' VOLATILE AS $$
DECLARE
	avail 	NUMERIC(19,2) := 0;
	ded_tot	NUMERIC(19,2) := 0;
	app_tot NUMERIC(19,2) := 0;
	chg_tot	NUMERIC(19,2) := 0;
BEGIN
	SELECT amount FROM solarbill.bill_payment
	WHERE acct_id = NEW.acct_id AND id = NEW.pay_id
	INTO avail;

	-- verify all invoice payments referencing this payment don't exceed funds
	-- and all invoice payments don't exceed invoice charge total
	-- by tracking sum of invoice payments deducted from this payment
	-- and the sum of invoice payments applied to this invoice
	SELECT
		SUM(CASE pay_id WHEN NEW.pay_id THEN amount ELSE 0 END)::NUMERIC(19,2),
		SUM(CASE inv_id WHEN NEW.inv_id THEN amount ELSE 0 END)::NUMERIC(19,2)
	FROM solarbill.bill_invoice_payment
	WHERE acct_id = NEW.acct_id AND (pay_id = NEW.pay_id OR inv_id = NEW.inv_id)
	INTO ded_tot, app_tot;

	SELECT SUM(amount)::NUMERIC(19,2) FROM solarbill.bill_invoice_item
	WHERE inv_id = NEW.inv_id
	INTO chg_tot;

	IF (ded_tot > avail) THEN
		RAISE EXCEPTION 'Invoice payments total amount % exceeds payment % amount %', ded_tot, NEW.pay_id, avail
		USING ERRCODE = 'integrity_constraint_violation',
			SCHEMA = 'solarbill',
			TABLE = 'bill_invoice_payment',
			COLUMN = 'amount',
			HINT = 'Sum of invoice payments must not exceed the solarbill.bill_payment.amount they relate to.';
	ELSIF (app_tot > chg_tot) THEN
		RAISE EXCEPTION 'Applied invoice payments total amount % exceeds invoice % amount %', app_tot, NEW.inv_id, chg_tot
		USING ERRCODE = 'integrity_constraint_violation',
			SCHEMA = 'solarbill',
			TABLE = 'bill_invoice_payment',
			COLUMN = 'amount',
			HINT = 'Sum of invoice payments must not exceed the sum of solarbill.bill_invoice_item.amount they relate to.';
	END IF;
	RETURN NULL;
END;
$$;

CREATE TRIGGER bill_invoice_payment_checker
    AFTER INSERT OR UPDATE
    ON solarbill.bill_invoice_payment
    FOR EACH ROW
    EXECUTE PROCEDURE solarbill.validate_bill_invoice_payment();

/**
 * Trigger function to prevent payment modifications from going under total invoice payments amount.
 */
CREATE OR REPLACE FUNCTION solarbill.validate_bill_payment()
	RETURNS "trigger"  LANGUAGE 'plpgsql' VOLATILE AS $$
DECLARE
	avail 	NUMERIC(19,2) := NEW.amount;
	inv_tot	NUMERIC(19,2) := 0;
BEGIN
	SELECT SUM(amount)::NUMERIC(19,2) FROM solarbill.bill_invoice_payment
	WHERE acct_id = NEW.acct_id AND pay_id = NEW.id
	INTO inv_tot;

	IF (inv_tot > avail) THEN
		RAISE EXCEPTION 'Invoice payments total amount % exceeds payment % amount %', inv_tot, NEW.id, avail
		USING ERRCODE = 'integrity_constraint_violation',
			SCHEMA = 'solarbill',
			TABLE = 'bill_payment',
			COLUMN = 'amount',
			HINT = 'Sum of invoice payments must not exceed the solarbill.bill_payment.amount they relate to.';
	END IF;
	RETURN NULL;
END;
$$;

CREATE TRIGGER bill_payment_checker
    AFTER UPDATE
    ON solarbill.bill_payment
    FOR EACH ROW
    EXECUTE PROCEDURE solarbill.validate_bill_payment();

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

/**
 * Make a payment, optionally adding an invoice payment.
 *
 * For example, to pay an invoice:
 *
 *     SELECT * FROM solarbill.add_payment(
 *           accountid => 123
 *         , pay_amount => '2.34'::NUMERIC
 *         , pay_ref => 345::TEXT
 *         , pay_date => CURRENT_TIMESTAMP
 *     );
 *
 * @param accountid 	the account ID to add the payment to
 * @param pay_amount 	the payment amount
 * @param pay_ext_key	the optional payment external key
 * @param pay_ref		the optional invoice payment reference; if an invoice ID then apply
 * 						the payment to the given invoice
 * @param pay_type		the payment type; the payment type
 * @param pay_date		the payment date; defaults to current time
 */
CREATE OR REPLACE FUNCTION solarbill.add_payment(
		  accountid 	BIGINT
		, pay_amount 	NUMERIC(11,2)
		, pay_ext_key 	CHARACTER VARYING(64) DEFAULT NULL
		, pay_ref 		CHARACTER VARYING(64) DEFAULT NULL
		, pay_type 		SMALLINT DEFAULT 1
		, pay_date 		TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
	)
	RETURNS solarbill.bill_payment
	LANGUAGE plpgsql VOLATILE AS
$$
DECLARE
	invid	BIGINT := solarcommon.to_bigint(pay_ref);
	pay_rec solarbill.bill_payment;
BEGIN

	INSERT INTO solarbill.bill_payment (created,acct_id,pay_type,amount,currency,ext_key,ref)
	SELECT pay_date, a.id, pay_type, pay_amount, a.currency, pay_ext_key,
		CASE invid WHEN NULL THEN pay_ref ELSE NULL END AS ref
	FROM solarbill.bill_account a
	WHERE a.id = accountid
	RETURNING *
	INTO pay_rec;

	IF invid IS NOT NULL THEN
		WITH tot AS (
			SELECT SUM(ip.amount) AS total
			FROM solarbill.bill_invoice_payment ip WHERE ip.inv_id = invid
		)
		INSERT INTO solarbill.bill_invoice_payment (created,acct_id, pay_id, inv_id, amount)
		SELECT pay_date, pay_rec.acct_id, pay_rec.id, invid, LEAST(pay_amount, tot.total)
		FROM tot;
	END IF;

	RETURN pay_rec;
END
$$;

/**
 * View to show invoice details including account information, total amount, and paid amount.
 */
CREATE OR REPLACE VIEW solarbill.bill_invoice_info AS
	SELECT
		  inv.id
		, 'INV-' || solarcommon.to_baseX(inv.id, 36) AS inv_num
		, inv.created
		, inv.acct_id
		, inv.addr_id
		, inv.date_start
		, inv.currency
		, act.user_id
		, adr.email
		, adr.disp_name
		, adr.country
		, adr.time_zone
		, itm.item_count
		, itm.total_amount
		, pay.paid_amount
	FROM solarbill.bill_invoice inv
	INNER JOIN solarbill.bill_account act ON act.id = inv.acct_id
	INNER JOIN solarbill.bill_address adr ON adr.id = inv.addr_id
	LEFT JOIN LATERAL (
		SELECT
			  COUNT(itm.id) AS item_count
			, SUM(itm.amount) AS total_amount
		FROM solarbill.bill_invoice_item itm
		WHERE itm.inv_id = inv.id
		)  itm ON TRUE
	LEFT JOIN LATERAL (
		SELECT SUM(pay.amount) AS paid_amount
		FROM solarbill.bill_invoice_payment pay
		WHERE pay.inv_id = inv.id
		) pay ON TRUE;

/**
 * View to show account details including address information and balance..
 */
CREATE OR REPLACE VIEW solarbill.bill_account_info AS
	SELECT
		  act.id
		, act.created
		, act.user_id
		, act.currency
		, act.locale
		, act.addr_id
		, adr.email
		, adr.disp_name
		, adr.country
		, adr.time_zone
		, bal.charge_total
		, bal.payment_total
		, bal.avail_credit
	FROM solarbill.bill_account act
	INNER JOIN solarbill.bill_address adr ON adr.id = act.addr_id
	LEFT OUTER JOIN solarbill.bill_account_balance bal ON bal.acct_id = act.id;

/**
 * Make a payment against a set of invoices.
 *
 * The payment is applied to invoices such that the full invoice amount is applied
 * going in oldest to newest invoice order, to up an overall maximum amount of the
 * payment amount.
 *
 * For example, to pay an invoice:
 *
 *     SELECT * FROM solarbill.add_invoice_payments(
 *           accountid => 123
 *         , pay_amount => '2.34'::NUMERIC
 *         , pay_date => CURRENT_TIMESTAMP
 *         , inv_ids => ARRAY[1,2,3]
 *     );
 *
 * @param accountid 	the account ID to add the payment to
 * @param pay_amount 	the payment amount
 * @param inv_ids		the invoice IDs to apply payments to
 * @param pay_ext_key	the optional payment external key
 * @param pay_ref		the optional invoice payment reference; if an invoice ID then apply
 * 						the payment to the given invoice
 * @param pay_type		the payment type; the payment type
 * @param pay_date		the payment date; defaults to current time
 */
CREATE OR REPLACE FUNCTION solarbill.add_invoice_payments(
		  accountid 	BIGINT
		, pay_amount 	NUMERIC(11,2)
		, inv_ids		BIGINT[]
		, pay_ext_key 	CHARACTER VARYING(64) DEFAULT NULL
		, pay_ref 		CHARACTER VARYING(64) DEFAULT NULL
		, pay_type 		SMALLINT DEFAULT 1
		, pay_date 		TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
	)
	RETURNS solarbill.bill_payment
	LANGUAGE plpgsql VOLATILE AS
$$
DECLARE
	pay_rec 		solarbill.bill_payment;
BEGIN

	INSERT INTO solarbill.bill_payment (created,acct_id,pay_type,amount,currency,ext_key,ref)
	SELECT pay_date, a.id, pay_type, pay_amount, a.currency, pay_ext_key, pay_ref
	FROM solarbill.bill_account a
	WHERE a.id = accountid
	RETURNING *
	INTO pay_rec;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'Account % not found.', accountid
		USING ERRCODE = 'integrity_constraint_violation',
			SCHEMA = 'solarbill',
			TABLE = 'bill_account',
			COLUMN = 'id';
    END IF;

	IF inv_ids IS NOT NULL THEN
		WITH payment AS (
			SELECT pay_amount AS payment
		)
		, invoice_payments AS (
			SELECT
				inv.id AS inv_id
				, inv.total_amount - COALESCE(inv.paid_amount, 0::NUMERIC(11,2)) AS due
				, GREATEST(0, LEAST(
					inv.total_amount - COALESCE(inv.paid_amount, 0::NUMERIC(11,2))
					, pay.payment - COALESCE(SUM(inv.total_amount - COALESCE(inv.paid_amount, 0::NUMERIC(11,2))) OVER win))) AS applied
			FROM solarbill.bill_invoice_info inv, payment pay
			WHERE id = ANY(inv_ids) AND acct_id = accountid
			WINDOW win AS (ORDER BY inv.id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
		)
		, applied_payments AS (
			SELECT * FROM invoice_payments
			WHERE applied > 0
		)
		INSERT INTO solarbill.bill_invoice_payment (created,acct_id, pay_id, inv_id, amount)
		SELECT pay_date, pay_rec.acct_id, pay_rec.id, applied_payments.inv_id, applied_payments.applied
		FROM applied_payments;

		IF NOT FOUND THEN
			RAISE EXCEPTION 'Invoice(s) % not found for account % payment %.', inv_ids, accountid, pay_amount
			USING ERRCODE = 'integrity_constraint_violation',
				SCHEMA = 'solarbill',
				TABLE = 'bill_invoice_payment',
				COLUMN = 'inv_id',
				HINT = 'The specified invoice(s) may not exist, might be for a different account, or might be fully paid already.';
		END IF;
	END IF;

	RETURN pay_rec;
END
$$;
