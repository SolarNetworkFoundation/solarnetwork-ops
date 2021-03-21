# pg_upgrade Guide on FreeBSD (Staging)

The plan is to use `pg_upgrade` with hard links. For this to be done, the database must be on a 
single ZFS dataset (and each tablespace on individual datasets). The current ZFS setup requires
some re-working to achieve this.

The cluster was originally created with user `pgsql` but has been changed to `postgres` by default
in FreeBSD. To simplify future upgrades, rename `pgsql` to `postgres`:

The current ZFS setup is:

```
NAME               USED  AVAIL  REFER  MOUNTPOINT
db                15.9G  74.2G   144K  none
db/solar93        15.8G  74.2G  1.95G  /solar93
db/solar93/index  13.9G  74.2G  13.9G  /solar93/index
db/solar93/log     524K  74.2G   524K  /solar93/log
db2               42.1G   173G    88K  none
db2/data93        42.1G   173G  42.1G  /data96
solar             21.4G   110G    20K  none
solar/wal96        843M   110G   843M  /solar93/9.6/pg_xlog
```

The ZFS dataset is OK already, as the 9.6 cluster is at `/solar93/9.6`. The new cluster will be at
`/solar93/12`.

# Script

See the [pg-upgrade-pg12-stage.sh](../scripts/pg-upgrade-pg12-stage.sh) script.


# Run upgrade

```
$ su - pgsql

$ pg_upgrade -U pgsql -k \
	-b /var/tmp/pg-upgrade/usr/local/bin \
	-d /solar93/9.6 \
	-B /usr/local/bin \
	-D /solar93/12 \
	-O "-c timescaledb.restoring='on'" \
	--check
```

To really run, remove `--check`:

```
Performing Upgrade
------------------
Analyzing all rows in the new cluster                       ok
Freezing all rows in the new cluster                        ok
Deleting files from new pg_xact                             ok
Copying old pg_clog to new server                           ok
Setting next transaction ID and epoch for new cluster       ok
Deleting files from new pg_multixact/offsets                ok
Copying old pg_multixact/offsets to new server              ok
Deleting files from new pg_multixact/members                ok
Copying old pg_multixact/members to new server              ok
Setting next multixact ID and offset for new cluster        ok
Resetting WAL archives                                      ok
Setting frozenxid and minmxid counters in new cluster       ok
Restoring global objects in the new cluster                 ok
Restoring database schemas in the new cluster
                                                            ok
Adding ".old" suffix to old global/pg_control               ok

If you want to start the old cluster, you will need to remove
the ".old" suffix from /solar93/9.6/global/pg_control.old.
Because "link" mode was used, the old cluster cannot be safely
started once the new cluster has been started.

Linking user relation files
                                                            ok
Setting next OID for new cluster                            ok
Sync data directory to disk                                 ok
Creating script to analyze new cluster                      ok
Creating script to delete old cluster                       ok
Checking for hash indexes                                   ok

Upgrade Complete
----------------
Optimizer statistics are not transferred by pg_upgrade so,
once you start the new server, consider running:
    ./analyze_new_cluster.sh

Running this script will delete the old cluster's data files:
    ./delete_old_cluster.sh
```

# Configure postgresql.conf

```sh
cp -a /solar93/9.6/tls /solar93/12/
```

```
# diff postgresql.conf.default postgresql.conf
59c59
< #listen_addresses = 'localhost'               # what IP address(es) to listen on;
---
> listen_addresses = '*'                # what IP address(es) to listen on;
169,170c169,170
< #bgwriter_lru_maxpages = 100          # max buffers written/round, 0 disables
< #bgwriter_lru_multiplier = 2.0                # 0-10.0 multiplier on buffers scanned/round
---
> bgwriter_lru_maxpages = 200           # max buffers written/round, 0 disables
> bgwriter_lru_multiplier = 3.0         # 0-10.0 multiplier on buffers scanned/round
175,176c175,176
< #effective_io_concurrency = 1         # 1-1000; 0 disables prefetching
< #max_worker_processes = 8             # (change requires restart)
---
> effective_io_concurrency = 2          # 1-1000; 0 disables prefetching
> max_worker_processes = 12             # (change requires restart)
178c178
< #max_parallel_workers_per_gather = 2  # taken from max_parallel_workers
---
> max_parallel_workers_per_gather = 3   # taken from max_parallel_workers
193c193
< #wal_level = replica                  # minimal, replica, or logical
---
> wal_level = replica                   # minimal, replica, or logical
198c198
< #synchronous_commit = on              # synchronization level;
---
> synchronous_commit = off              # synchronization level;
207c207
< #full_page_writes = on                        # recover from partial page writes
---
> full_page_writes = off                        # recover from partial page writes
213c213
< #wal_buffers = -1                     # min 32kB, -1 sets based on shared_buffers
---
> wal_buffers = 16MB                    # min 32kB, -1 sets based on shared_buffers
218c218
< #commit_delay = 0                     # range 0-100000, in microseconds
---
> commit_delay = 100                    # range 0-100000, in microseconds
223,226c223,226
< #checkpoint_timeout = 5min            # range 30s-1d
< max_wal_size = 1GB
< min_wal_size = 80MB
< #checkpoint_completion_target = 0.5   # checkpoint target duration, 0.0 - 1.0
---
> checkpoint_timeout = 30min            # range 30s-1d
> max_wal_size = 9GB
> min_wal_size = 4GB
> checkpoint_completion_target = 0.9    # checkpoint target duration, 0.0 - 1.0
369c369
< #random_page_cost = 4.0                       # same scale as above
---
> random_page_cost = 1.1                        # same scale as above
419,420c419
< log_destination = 'syslog'
< #log_destination = 'stderr'           # Valid values are combinations of
---
> log_destination = 'stderr'            # Valid values are combinations of
426c425
< #logging_collector = off              # Enable capturing of stderr and csvlog
---
> logging_collector = on                # Enable capturing of stderr and csvlog
585c584
< #autovacuum_max_workers = 3           # max number of autovacuum subprocesses
---
> autovacuum_max_workers = 10           # max number of autovacuum subprocesses
679c678
< #shared_preload_libraries = ''
---
> shared_preload_libraries = 'timescaledb,pg_stat_statements'
753c752,764
< # Add settings for extensions here
---
> #------------------------------------------------------------------------------
> # pg_stat_statements
> #------------------------------------------------------------------------------
> 
> pg_stat_statements.track = all
> pg_stat_statements.track_utility = off
> 
> #------------------------------------------------------------------------------
> # timescaledb
> #------------------------------------------------------------------------------
> 
> timescaledb.max_background_workers = 4
> 
```

# Cleanup

```
zfs destroy wal96/wal96
rm -rf /var/tmp/pg-upgrade
su - pgsql
/var/db/postgres/delete_old_cluster.sh
vacuumdb -p 5496 -U pgsql --all --analyze-only
```
