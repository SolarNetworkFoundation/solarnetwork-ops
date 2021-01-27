# NET-266 Migration Guide

TODO

## Prep

On both `solardb-0` and `solardb-a`, as `root`:

```sh
zfs set recordsize=128K dat/9.6/home/logs
zfs set recordsize=8K dat
zfs set recordsize=8K idx
```

## Stage 1

Disk space is a little tight for making a copy of all the data. So plan is to free some space
from indexes that are duplicates solely for query speed. Query performance may decrease, but
once migration is complete it won't matter.

```sql
-- drop reorder policies
WITH t AS (
	SELECT schema_name || '.' || table_name AS hypertable_name
	FROM _timescaledb_catalog.hypertable
	WHERE schema_name IN ('solardatum', 'solaragg')
	ORDER BY id
)
SELECT remove_reorder_policy(t.hypertable_name, if_exists => true)
FROM t;

-- drop implicit cluster
ALTER TABLE solardatum.da_datum SET WITHOUT CLUSTER;

-- free up disk space from less-used raw data index (da_datum_reverse_pkey)
DROP INDEX IF EXISTS solardatum.da_datum_pkey;
```

Temporarily disable datum import permission:

```sql
-- see NET-266-temp-roles-disable.sql

UPDATE solaruser.user_role SET role_name = '_ROLE_IMPORT' WHERE role_name = 'ROLE_IMPORT';
```

The `~/.pgpass` file for the `postgres` user has been configured with the necessary passwords
for the scripts to use.

Execute the stage 1 migration scripts:

```sh
timescale-add-datm-support.sh -v -h 127.0.0.1
timescale-migrate-datum-to-datm-by-chunk.sh -h 127.0.0.1
```

## Stage 2

TODO

Execute the stage 2 migration scripts:

```sh
timescale-migrate-datum-to-datm-by-chunk.sh -h localhost -2
```

## Stage 3

**Now all SolarNetwork applications must be shut down.**

Execute the stage 3 migration scripts:

```sh
timescale-migrate-datum-to-datm-by-chunk.sh -h localhost -3
```

Execute the remaining migration scripts:

```sh
timescale-migrate-datum-meta.sh -h localhost
timescale-migrate-agg-datum-to-datm-by-chunk.sh -h localhost
timescale-migrate-audit-acc-datum-datm.sh -h localhost
timescale-migrate-audit-datum-datm.sh -h localhost
timescale-migrate-audit-datum-aux.sh -h localhost
```

Execute the final SQL DDL changes:

```sh
psql -h localhost -d solarnetwork -f NET-266-billing.sql -f NET-266-add-hypertable-reorder-policy.sql
```

## Final cleanup

The `solardatum` and `solaragg` schemas can be dropped, and the `plv8` extension removed.

TODO
