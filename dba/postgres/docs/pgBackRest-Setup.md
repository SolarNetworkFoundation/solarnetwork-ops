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

Each file contains the associated value. The `S3_BUCKET`, `S3_ENDPOINT`, and `S3_REGION` are

```
snf-internal
s3.us-west-2.amazonaws.com
us-west-2
```

The `SPOOL_PATH` is set so the root filesystem does not fill up and run out of space; currently this
is set to `FIXME`.


# Postgres integration

In `postgresql.conf` configured the following settings:

```
archive_command = 'envdir ~/pgbackrest.d/env pgbackrest archive-push %p'
restore_command = 'envdir ~/pgbackrest.d/env pgbackrest archive-get %f %p'
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
