\echo `date` Starting

\c solarnetwork postgres
\i NET-112-production-setup-hypertable-hooks.sql
\c solarnetwork solarnet

\i init/updates/NET-111-remove-domains-start-extra.sql

\i NET-112-production-create-hypertables.sql

\i init/updates/NET-112-jsonb-common.sql
\i init/updates/NET-112-jsonb-core.sql
--\i init/updates/NET-112-jsonb-add-datum-component-cols.sql
\i init/updates/NET-112-jsonb-generic-datum.sql
\i init/updates/NET-112-jsonb-generic-datum-agg-functions.sql
\i init/updates/NET-112-jsonb-generic-datum-new.sql
\i init/updates/NET-112-jsonb-generic-loc-datum.sql
\i init/updates/NET-112-jsonb-generic-loc-datum-agg-functions.sql
\i init/updates/NET-112-jsonb-generic-loc-datum-new.sql
\i init/updates/NET-112-jsonb-generic-datum-x-functions.sql
\i init/updates/NET-112-jsonb-generic-loc-datum-x-functions.sql
\i init/updates/NET-112-jsonb-users.sql
--\i init/updates/NET-112-jsonb-migrate-data.sql
--\i init/updates/NET-112-jsonb-drop.sql

\i NET-111-production-permissions.sql
\i NET-112-production-permissions.sql

\i init/postgres-init-user-extra.sql

\i NET-112-production-migrate-data.sql

\i NET-112-production-finish-hypertables.sql
\i NET-112-production-reindex-support.sql
\i NET-112-production-drop-old-tables.sql

\echo `date` Ended
