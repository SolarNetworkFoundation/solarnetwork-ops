# pgBackRest Setup

# Setup envdir

Created `~postgres/pgbackrest.d/env` directory with files:

```
PGBACKREST_ARCHIVE_ASYNC
PGBACKREST_COMPRESS_TYPE
PGBACKREST_LOG_PATH
PGBACKREST_PG1_PATH
PGBACKREST_PG1_PORT
PGBACKREST_PROCESS_MAX
PGBACKREST_REPO1_PATH
PGBACKREST_REPO1_RETENTION_DIFF
PGBACKREST_REPO1_RETENTION_FULL
PGBACKREST_REPO1_S3_BUCKET
PGBACKREST_REPO1_S3_ENDPOINT
PGBACKREST_REPO1_S3_KEY
PGBACKREST_REPO1_S3_KEY_SECRET
PGBACKREST_REPO1_S3_REGION
PGBACKREST_REPO1_TYPE
PGBACKREST_SPOOL_PATH
PGBACKREST_STANZA
```

Each file contains the associated value. The `PATH`, `S3_BUCKET`, `S3_ENDPOINT`, and `S3_REGION` are

```
/backups/postgres/12/pgbr
snf-internal
s3.us-west-2.amazonaws.com
us-west-2
```

The `SPOOL_PATH` is set so the root filesystem does not fill up and run out of space; currently this
is set to `/sndb/home/tmp`.


# Postgres integration

In `postgresql.conf` configured the following settings:

```
archive_command = 'envdir ~/pgbackrest.d/env pgbackrest archive-push %p'
restore_command = 'envdir ~/pgbackrest.d/env pgbackrest archive-get %f %p'
```

# Cron schedule

Automated backups are scheduled via the `postgres` user's crontab, so full backups are performed
monthly, differential weekly, and incremental daily:

```
# create full backup 1st of every month
0 3 1 * * /usr/local/bin/envdir /var/db/postgres/pgbackrest.d/env /usr/local/bin/pgbackrest --type=full backup

# create incremental backup daily
0 2 * * * /usr/local/bin/envdir /var/db/postgres/pgbackrest.d/env /usr/local/bin/pgbackrest --type=incr backup

# create differential backup weekly
0 6 * * Mon /usr/local/bin/envdir /var/db/postgres/pgbackrest.d/env /usr/local/bin/pgbackrest --type=diff backup
```

# Restore

Here's an example restoring to a development VM, remapping the WAL and tablespace directories to
work with the VM:

```sh
envdir ~/pgbackrest.d/env pgbackrest --link-all --process-max=4 \
	--tablespace-map=16400=/tsdb/solar96 \
	--tablespace-map=16401=/tsdb/index96 \
	--link-map=pg_wal=/tsdb/wal/12 \
	restore
```
