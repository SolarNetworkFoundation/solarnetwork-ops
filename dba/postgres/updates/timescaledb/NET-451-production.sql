/* Production-only DDL for NET-451. Run the migration FIRST, from the central repo, then this
 * script:
 *
 *     cd solarnetwork-central/solarnet-db-setup/postgres
 *     psql -1 -d solarnetwork -f migrations/migrate-20260924.sql
 *
 *     cd solarnetwork-ops/dba/postgres/updates/timescaledb
 *     psql -1 -d solarnetwork -f NET-451-production.sql
 *
 * The migration is not included here with \i: the nested \i in migrate-20260924.sql resolves
 * relative to psql's working directory, not to the including file, so it only finds
 * updates/ when run from the central postgres directory. Running the two separately also
 * keeps a failure here -- a missing or full tablespace -- from rolling back the schema change.
 *
 * No ACL statements are needed: since OPS-49 the solarnet and solaruser default privileges
 * are registered for the solarnet role, so functions this migration replaces inherit their
 * group grants.
 */

ALTER INDEX solarnet.sn_datum_export_task_user_idx SET TABLESPACE solarindex;
