# Migration scripts for Timescaledb

This folder contains Postgres SQL DDL scripts to migrate the SolarNet
database to include NET-111, NET-112, and convert the main datum tables
from `pg_partman` partitions to Timescaledb hypertables.


## Setup

First you must create a symlink to the
**/solarnetwork-central/net.solarnetwork.central.datum/defs/sql/postgres**
directory, named `init`, in this directory.

Then, you must configure access to the Postgres instance for both
the `postgres` database superuser and the `solarnet` database user
to access without needing to request a password. Typically this is
done by adding the appropriate credentials to your `~/.pgpass` file,
for example

```
sndb.host.name:5432:*:postgres:password
sndb.host.name:5432:*:solarnet:password
```


## Testing migration with reduced data

Migrating the entire database can take several hours. To test the migration
with a reduced set of data, which will then take far less time, the
`testing-truncate-data.sql` script can be executed which will delete a large
portion of the data from the database. Typically you would take a ZFS
snapshot before starting, then truncate the data, then run the migration,
and finally verify the results. If everything went according to plan, you
would rollback to the ZFS snapshot and then run the migration without first
truncating the data.


## Run migration

See the `run-migration.sh` script for an example.
