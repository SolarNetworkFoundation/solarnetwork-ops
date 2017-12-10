# Migration scripts for Timescaledb

This folder contains Postgres SQL DDL scripts to migrate the SolarNet
database to include NET-111, NET-112, and convert the main datum tables
to Timescaledb hypertables.

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

## Run migration

