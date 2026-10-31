/* Production-only DDL for NET-176. Run the migration FIRST, from the central repo, then this
 * script straight after:
 *
 *     cd solarnetwork-central/solarnet-db-setup/postgres
 *     psql -1 -d solarnetwork -f migrations/migrate-20261102.sql
 *
 *     cd solarnetwork-ops/dba/postgres/updates/timescaledb
 *     psql -1 -d solarnetwork -f NET-176-cross-account-source-aliases-production.sql
 *
 * The migration replaces solardatm.da_datm_alias_allowed(), which clears SECURITY DEFINER. Until
 * that is restored here, roles other than solaruser and solarjobs cannot read the grant table, so
 * any aliased datum query fails.
 *
 * The grants match the ones the same kind of solaruser object has in a freshly built database.
 * They are given explicitly because the solaruser default privileges only apply to objects
 * created by the role that registered them.
 */

ALTER INDEX solaruser.da_datm_alias_grant_pk SET TABLESPACE solarindex;
ALTER INDEX solaruser.da_datm_alias_grant_grantee_idx SET TABLESPACE solarindex;

ALTER FUNCTION solardatm.da_datm_alias_allowed(BIGINT, TEXT, BIGINT) SECURITY DEFINER;

GRANT ALL ON TABLE solaruser.da_datm_alias_grant TO solaruser;
GRANT SELECT ON TABLE solaruser.da_datm_alias_grant TO solarjobs;
