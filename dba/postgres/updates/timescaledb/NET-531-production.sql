/* Production-only DDL for NET-531. Run the migration FIRST, from the central repo, then this
 * script:
 *
 *     cd solarnetwork-central/solarnet-db-setup/postgres
 *     psql -1 -d solarnetwork -f migrations/migrate-<date>.sql
 *
 *     cd solarnetwork-ops/dba/postgres/updates/timescaledb
 *     psql -1 -d solarnetwork -f NET-531-production.sql
 *
 * where migrate-<date>.sql is the migration that includes updates/NET-531-consolidated-invoicing.sql.
 *
 * The grants match the ones every other solarbill object has in a freshly built database. They
 * are given explicitly because the solarbill default privileges only apply to objects created
 * by the role that registered them.
 */

ALTER INDEX solarbill.bill_consol_invoice_pkey SET TABLESPACE solarindex;
ALTER INDEX solarbill.bill_consol_invoice_acct_date_idx SET TABLESPACE solarindex;
ALTER INDEX solarbill.bill_consol_invoice_member_pkey SET TABLESPACE solarindex;
ALTER INDEX solarbill.bill_consol_invoice_member_inv_idx SET TABLESPACE solarindex;

GRANT ALL ON TABLE solarbill.bill_consol_invoice TO solarjobs;
GRANT ALL ON TABLE solarbill.bill_consol_invoice_member TO solarjobs;
GRANT ALL ON TABLE solarbill.bill_consol_invoice_info TO solarjobs;
GRANT SELECT ON TABLE solarbill.bill_consol_invoice TO solaruser;
GRANT SELECT ON TABLE solarbill.bill_consol_invoice_member TO solaruser;
GRANT SELECT ON TABLE solarbill.bill_consol_invoice_info TO solaruser;

REVOKE ALL ON FUNCTION solarbill.add_consol_invoice_payments(BIGINT, NUMERIC,
	CHARACTER VARYING, CHARACTER VARYING, SMALLINT, TIMESTAMP WITH TIME ZONE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION solarbill.add_consol_invoice_payments(BIGINT, NUMERIC,
	CHARACTER VARYING, CHARACTER VARYING, SMALLINT, TIMESTAMP WITH TIME ZONE) TO solarjobs;
GRANT EXECUTE ON FUNCTION solarbill.add_consol_invoice_payments(BIGINT, NUMERIC,
	CHARACTER VARYING, CHARACTER VARYING, SMALLINT, TIMESTAMP WITH TIME ZONE) TO solaruser;
