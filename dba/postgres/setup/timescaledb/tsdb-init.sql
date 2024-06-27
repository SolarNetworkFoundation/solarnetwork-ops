/* ============================================================================
 * psql script to execute all initialization SQL scripts.
 *
 * All database roles are assumed to be created already (see tsdb-init-roles.sql)
 * and all necessary extensions are assumed to be installed already.
 * ============================================================================
 */

\i tsdb-init-utilities.sql
\i init/postgres-init-common-schema.sql
\i tsdb-init-common-schema.sql
\i init/postgres-init-common.sql
\i init/postgres-init-core-schema.sql
\i tsdb-init-core-schema.sql
\i init/postgres-init-core.sql
\i init/postgres-init-instructor.sql
\i init/postgres-init-datm-schema.sql
\i tsdb-init-datm-schema.sql
\i init/postgres-init-datm-core.sql
\i init/postgres-init-datm-util.sql
\i init/postgres-init-datm-query.sql
\i init/postgres-init-datm-agg-query.sql
\i init/postgres-init-datm-agg.sql
\i init/postgres-init-datm-agg-util.sql
\i init/postgres-init-datm-audit-query.sql
\i init/postgres-init-datm-audit.sql
\i init/postgres-init-datm-delete.sql
\i init/postgres-init-datm-in.sql
\i init/postgres-init-datm-in-loc.sql
\i init/postgres-init-datm-query-agg.sql
\i init/postgres-init-datm-query-diff.sql
\i init/postgres-init-datum-export.sql
\i init/postgres-init-user-schema.sql
\i tsdb-init-user-schema.sql
\i init/postgres-init-users.sql
\i init/postgres-init-user-alerts.sql
\i init/postgres-init-user-datum-export.sql
\i init/postgres-init-user-datum-expire.sql
\i init/postgres-init-user-datum-flux.sql
\i init/postgres-init-user-datum-import.sql
\i init/postgres-init-user-event-hook.sql
\i init/postgres-init-user-events.sql
\i init/postgres-init-ocpp-schema.sql
\i tsdb-init-ocpp-schema.sql
\i init/postgres-init-ocpp.sql
\i init/postgres-init-oscp-schema.sql
\i tsdb-init-oscp-schema.sql
\i init/postgres-init-oscp.sql
\i init/postgres-init-din-schema.sql
\i tsdb-init-din-schema.sql
\i init/postgres-init-din.sql
\i init/postgres-init-dnp3-schema.sql
\i tsdb-init-dnp3-schema.sql
\i init/postgres-init-dnp3.sql
\i init/postgres-init-billing-schema.sql
\i tsdb-init-billing-schema.sql
\i init/postgres-init-billing.sql

\i tsdb-init-hypertables-support.sql
