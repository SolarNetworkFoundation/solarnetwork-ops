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
