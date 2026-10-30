/* Production-only DDL for NET-176. Run the migration FIRST, from the central repo, then this
 * script:
 *
 *     cd solarnetwork-central/solarnet-db-setup/postgres
 *     psql -1 -d solarnetwork -f migrations/migrate-<date>.sql
 *
 *     cd solarnetwork-ops/dba/postgres/updates/timescaledb
 *     psql -1 -d solarnetwork -f NET-176-alias-stream-access-production.sql
 *
 * where migrate-<date>.sql is the migration that includes updates/NET-176-alias-stream-access.sql.
 *
 * The grants match the ones the same kind of solardatm object has in a freshly built database.
 * They are given explicitly because the solardatm default privileges only apply to objects
 * created by the role that registered them.
 */

ALTER INDEX solardatm.da_datm_alias_del_pk SET TABLESPACE solarindex;
ALTER INDEX solardatm.da_datm_alias_del_alias_node_idx SET TABLESPACE solarindex;

ALTER FUNCTION solardatm.da_datm_alias_allowed(BIGINT, TEXT, BIGINT) SECURITY DEFINER;

REVOKE ALL ON FUNCTION solardatm.da_datm_alias_allowed(BIGINT, TEXT, BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION solardatm.find_metadata_for_stream_all(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION solardatm.da_datm_alias_validate_stream_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION solardatm.da_datm_alias_record_delete() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION solardatm.da_datm_alias_allowed(BIGINT, TEXT, BIGINT) TO solar;
GRANT EXECUTE ON FUNCTION solardatm.find_metadata_for_stream_all(UUID) TO solar;
GRANT EXECUTE ON FUNCTION solardatm.da_datm_alias_validate_stream_id() TO solar;
GRANT EXECUTE ON FUNCTION solardatm.da_datm_alias_record_delete() TO solar;

GRANT SELECT ON TABLE solardatm.da_datm_meta_aliased_all TO solar;

GRANT SELECT ON TABLE solardatm.da_datm_alias_del TO solar;
GRANT ALL ON TABLE solardatm.da_datm_alias_del TO solaruser;
GRANT ALL ON TABLE solardatm.da_datm_alias_del TO solarjobs;
