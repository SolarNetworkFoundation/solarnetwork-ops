/* ============================================================================
 * psql script to execute all initialization SQL scripts.
 *
 * All database roles are assumed to be created already (see tsdb-init-roles.sql)
 * and all necessary extensions are assumed to be installed already.
 *
 * The init/postgres-init-plv8.sql script should be run PRIOR to running this.
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
\i init/postgres-init-generic-datum-schema.sql
\i tsdb-init-generic-datum-schema.sql
\i init/postgres-init-generic-datum.sql
\i init/postgres-init-generic-datum-agg-functions.sql
\i init/postgres-init-generic-datum-agg-triggers.sql
\i init/postgres-init-generic-loc-datum.sql
\i init/postgres-init-generic-loc-datum-agg-functions.sql
\i init/postgres-init-generic-loc-datum-agg-triggers.sql
\i init/postgres-init-generic-datum-x-functions.sql
\i init/postgres-init-generic-loc-datum-x-functions.sql
\i init/postgres-init-datum-export.sql
\i init/postgres-init-user-schema.sql
\i tsdb-init-user-schema.sql
\i init/postgres-init-users.sql
\i init/postgres-init-user-alerts.sql
\i init/postgres-init-user-datum-export.sql
\i init/postgres-init-user-datum-expire.sql
\i init/postgres-init-user-datum-import.sql
\i init/postgres-init-controls.sql
\i init/postgres-init-quartz-schema.sql
\i tsdb-init-quartz-schema.sql
\i init/postgres-init-quartz.sql

\i tsdb-init-hypertables.sql
\i tsdb-init-hypertables-support.sql
