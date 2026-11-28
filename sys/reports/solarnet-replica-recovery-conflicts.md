# SolarNet replica recovery conflicts: analysis and tuning

- **Date:** 2026-11-28 (revisions 1 and 2: 2026-11-27)
- **Revision:** 4, adding the first backup with `start-fast`, and production's `db-timeout`,
  which left the 2026-11-27 backup 12 minutes to spare, not the 20 s that revision 3 gave
  (section 9.3). Revision 3 added a run away from the daily backup (section 9.4), and revision 2
  the first results after the change.
- **Scope:** why SolarQuery's queries on the production streaming replica are cancelled by
  recovery conflicts, and how to have fewer of them without costing the primary much
- **Data:** an hour of samples on each server in three runs. The collector's output folders are
  kept outside this repo:
  - before the change, 2026-11-26 21:40–22:41 UTC: `replica-conflicts-primary-20261126T214044Z/`
    and `replica-conflicts-replica-20261126T214014Z/`, with the replica's log from 2026-11-25
    01:04 to 2026-11-26 22:38 UTC
  - after it, 2026-11-27 01:50–02:51 UTC: `replica-conflicts-primary-20261127T015032Z/` and
    `replica-conflicts-replica-20261127T015019Z/`, with the replica's log to 01:38 UTC
  - and 2026-11-27 18:14–19:15 UTC: `replica-conflicts-primary-20261127T181438Z/` and
    `replica-conflicts-replica-20261127T181434Z/`
- **Tools:** `dba/postgres/scripts/replica-conflicts-collect.sh`, and `replica-conflicts.sql`,
  `replica-long-statements.sql` and `primary-xmin-horizon.sql` in `dba/postgres/queries/`, on
  solarnetwork-ops `develop` (commits `35f3c9d` and `48311fe`)
- **Status:** the change recommended in section 7 was made on 2026-11-27, shortly before the
  second runs started at 01:50 UTC, and `transaction_timeout` was added before the third, at
  18:14. The replica has had no conflicts since, and the primary's cost is as expected.
  pgBackRest has had `start-fast` since 04:54 UTC, and the first backup with it, at 02:00 UTC
  on 2026-11-28, started in 2 s rather than 33 minutes (section 9.3). Section 9.5 has what is
  left to watch.

## 1. Summary

**Recommendation: turn on `hot_standby_feedback` on the replica, and cap how long SolarQuery's
statements can run with a `statement_timeout` for the `solarquest` role.** Keep
`max_standby_streaming_delay` and `max_standby_archive_delay` at 60 s. This was done on
2026-11-27, and it works (section 9).

- **The cancellations are snapshot conflicts.** Since the replica started on 2025-05-02 it has
  counted 349,888 of them, against 18 lock and 177 buffer-pin conflicts: about 25 an hour.
- **They come from page pruning on the primary that never stops.** Counter rows in
  `solardatm.aud_datm_io` are updated all the time, and whenever a page with dead versions is
  read, the dead versions are pruned and the prune is logged. Those versions died only seconds
  before, so the record conflicts with any replica query older than a few seconds. There is no
  quiet period to schedule around, and no job or maintenance script to change.
- **Replay lag multiplies them.** Replay waits up to 60 s for the conflicting queries, and all
  of replay stops meanwhile. Once it is 60 s behind, it cancels conflicting queries at once, so
  short queries and ones that have only just started are cancelled too. In the hour sampled, 12
  of the 20 cancels came at once.
- **The cost to the primary is small, and the timeout bounds it.** The primary's own work
  already holds its xmin horizon back by up to 105 s. With a 5-minute cap, the most the replica
  could add is about 73,000 dead row versions waiting to be removed, across all tables.
- **The change works.** The replica has had no conflicts of any kind since it was made: its
  counters did not move from 01:50 to 19:15 UTC on 2026-11-27. In the two hours measured,
  replay never waited, its lag never passed 0.4 s, and diff queries that used to be cancelled at
  about 60 s ran to the end. Feedback holds the primary's horizon about 3 s past its own, and up
  to 145 s past while the hourly diff queries run, about 37,600 extra dead row versions at the
  peak, in line with the estimate. The queue work shows no slowdown that can be put down to it
  (section 9).
- **The daily backup held the primary's horizon back far longer than the replica can.** The
  02:00 UTC pgBackRest backup held it for 33 minutes, keeping about 466,000 dead row versions,
  while `pg_backup_start` waited for a spread checkpoint. On some days that wait could also run
  past pgBackRest's 45-minute `db-timeout` and fail the backup. With `start-fast=y`, the backup
  now asks for an immediate checkpoint, and on 2026-11-28 its start took 2 s (section 9.3).

## 2. Setup

- One primary and one streaming replica, both PostgreSQL 17.4 with TimescaleDB 2.19.3, on
  FreeBSD. All SolarQuery APIs read from the replica, as `solarquest`.
- On the replica, before the change: `hot_standby_feedback = off` (the default),
  `max_standby_streaming_delay` and `max_standby_archive_delay` 60 s,
  `wal_receiver_status_interval` 10 s, `deadlock_timeout` 1 s, and no replication slot.
  `log_recovery_conflict_waits` was turned on for this work, at about 2026-11-26 21:27 UTC.
- Before the change, no role or database setting gave `solarquest` a timeout, and both servers'
  own `statement_timeout` is 0. The only role settings were
  `idle_in_transaction_session_timeout = 0` for `solarjobs` and `solarworker`.
- Most SolarQuery queries should finish well under 60 s, but `/datum/stream/*` allows unlimited
  results and may reasonably run longer.

## 3. How a conflict cancels a query

Replaying WAL on the replica sometimes has to remove row versions, or take a lock, that a query
running there still needs. Replay then waits for the query, and cancels it once
`max_standby_streaming_delay` has passed since that WAL arrived from the primary: "canceling
statement due to conflict with recovery", SQLSTATE 40001. A session idle in a transaction is
ended instead.

- A **snapshot conflict** comes from a record that removes row versions: VACUUM, or the pruning
  a page gets when it is read with dead versions on it. Every query in the database whose
  snapshot could still see the removed versions conflicts, whatever table it reads.
- **The 60 s allowance is shared.** It runs from when the WAL arrived, not from when replay
  reached it, and all of replay waits meanwhile. Once replay is 60 s behind, the next conflict
  has no allowance left and cancels at once. While replay catches up, the WAL ahead of it is
  newer than even the snapshots of queries that have only just started, so short queries
  conflict too.
- **`hot_standby_feedback`** has the replica tell the primary, at least every
  `wal_receiver_status_interval`, how old the oldest snapshot its queries hold is. The primary
  then keeps the row versions that snapshot can see, so it does not log prunes that conflict.
  It costs the primary only while the replica's oldest snapshot is older than the primary's own
  oldest. It does nothing for lock or buffer-pin conflicts.

## 4. What was measured

The collector ran for an hour on each server, sampling every 5 s (720 samples), before the
change and again after it (section 9). On the replica it sampled replay's state and wait event,
the sessions holding snapshots and their locks, and the conflict counts. On the primary it
sampled the oldest snapshot or transaction holding back the xmin horizon, ACCESS EXCLUSIVE
locks, and maintenance in progress. It also took the table and statement statistics at the start
and end of each run, and on the replica it read the log, where `log_recovery_conflict_waits`
names the WAL record and table that each wait was for.

The first replica run's `summary.txt` lacks its samples and log sections, because FreeBSD's awk
rejected part of the summary programs. That is fixed in `48311fe`, and
`replica-conflicts-replica-20261126T214014Z/summary-rebuilt.txt` is the complete summary,
rebuilt from the same data with the fixed programs. The runs after the change used the fixed
collector, and their summaries are complete.

## 5. Findings

### 5.1 Conflicts by kind

| Kind | Since 2025-05-02 | In the hour sampled |
|:-----|-----:|-----:|
| snapshot | 349,888 | 20 |
| lock | 18 | 0 |
| bufferpin | 177 | 0 |
| deadlock, tablespace, logicalslot | 0 | 0 |

The log has 1,158 statements cancelled and 19 sessions ended, all for snapshot conflicts, at
between 7 and 106 an hour. The busiest hours were 2026-11-26 02:00 UTC (106) and 2026-11-25
12:00 UTC (75). No ACCESS EXCLUSIVE locks were seen on the primary, and no TimescaleDB jobs ran
during the hour.

### 5.2 What replay waited on

In the 71 minutes with wait logging on, replay waited longer than `deadlock_timeout` 92 times on
snapshot conflicts, 575 s in all, and once on a buffer pin, for 7.4 s. 68 of the snapshot waits
lasted under 5 s, and 3 lasted 45 s or more, the longest 60.3 s. A wait came about every 45 s.

| Waits | WAL record | Table |
|-----:|:-----|:-----|
| 61 | Heap2/PRUNE_ON_ACCESS | `solardatm.aud_datm_io` (chunk `_hyper_18_2134_chunk`) |
| 8 | Heap2/PRUNE_ON_ACCESS | `net540_backfill.probe` |
| 8 | Heap2/PRUNE_ON_ACCESS | `solardatm.agg_stale_datm` |
| 5 | Heap2/PRUNE_ON_ACCESS | `solardatm.agg_datm_15m` |
| 5 | Heap2/PRUNE_ON_ACCESS | `solardatm.agg_datm_hourly` |
| 2 | Heap2/VISIBLE | `solardatm.agg_stale_datm` |
| 1 | Heap2/PRUNE_ON_ACCESS | `solarcommon.bucket_2` |
| 1 | Heap2/PRUNE_ON_ACCESS | `solardatm.da_datm` |
| 1 | Heap2/PRUNE_VACUUM_SCAN | `solarcommon.bucket_1` |
| 1 (buffer pin) | Heap2/PRUNE_ON_ACCESS | `solardatm.da_datm_meta` |

89 of the 92 snapshot waits were for on-access pruning, and only 3 for VACUUM's records. The
`aud_datm_io` rows are audit counters that two upserts increment all the time on the primary:
`solarin`'s datum counts (1.49 billion calls since `pg_stat_statements` was reset on 2025-04-26)
and `solarquest`'s own query counts (445 million). 96% of the updates are HOT, so the dead
versions are pruned as pages are read, not by VACUUM, which did not run on the table during the
hour.

### 5.3 How the cancels bunch up

All 20 cancels in the hour came in four sets: at 22:03:19 (4), 22:04:37–39 (8), 22:05:41 (4) and
22:07:01 (4) UTC.

- The heavy diff query (query ID `-6825769441821458313`, `solardatm.diff_datm` over
  `find_datm_diff_within_rows`) ran in groups of 2–4 copies, starting at 22:02:55, 22:03:37,
  22:04:40, 22:05:02, 22:06:12 and 22:07:40. New groups started 2–39 s after each set of
  cancels, which looked like retries. But the diff query's long runs come this way at the start
  of every hour, cancelled or not (section 9.1). Two connections were cancelled twice within
  2 s, at 22:04:37–39: their next query was cancelled almost as soon as it started.
- Copies ran for up to 59 s, mostly waiting on reads (`IO/DataFileRead`, `IPC/BufferIo`).
  Replay waited on them in six runs of 15–61 s between 22:02 and 22:08, and its lag climbed in
  a sawtooth to 59 s, with up to 22 MB of received WAL not yet replayed.
- 8 of the cancels came at the end of a wait, when the 60 s ran out. The other 12 came at once,
  because replay was already about 60 s behind. One of them was the collector's own sample
  round, at 22:03:19, which is the run's one sample with an error.
- The primary's own horizon stayed under 1 s throughout, so with feedback on, the replica's
  queries alone would have set the cost.

### 5.4 Which statements are cancelled

Of the 1,177 statements cancelled and sessions ended in the log, 850 (72%) were the diff query.
Most of the rest were datum count, list and stream metadata queries. Short statements are among
them too, such as auth token and node lookups, `SHOW server_version` and `SET application_name`.
These were most likely cancelled because replay was already 60 s behind, as a short statement
would otherwise finish well within the allowance. 22 were NET-540 research queries (`net540_*`,
`net540tmp.measure`), which are temporary.

On the replica, the diff query used 62% of the hour's execution time: 473 calls, 1.2 s on
average. Its longest finished run since it first appeared on 2026-11-17 took 127 s. The
heaviest list and count statements average 18–37 s a call. `pg_stat_statements` counts only
runs that finished, so cancelled runs are missing from these figures.

### 5.5 Replay lag and snapshot ages

| Seconds | p50 | p90 | p99 | max |
|:-----|-----:|-----:|-----:|-----:|
| Replay lag | 0.2 | 3.9 | 49.3 | 59.4 |
| The replica's oldest client snapshot | 0 | 2.9 | 47.8 | 58.5 |
| The primary's own horizon | 0.2 | 0.7 | 69.8 | 105.3 |

Replay was caught up and waiting for WAL in 83% of samples, and waiting on a snapshot conflict
in 15%. While it waits, SolarQuery reads data that much older. No replica snapshot reached 60 s,
because the cancels end them first.

### 5.6 The primary's horizon and dead rows

The primary's own work held its horizon back at least 60 s in 1.2% of samples. The longest
holders were an autovacuum ANALYZE of a chunk (105 s), and `solarmgmnt`'s queries on
`solaruser.user_event_log` (35–43 s). The primary uses about 199 transaction IDs a second, and
makes 244.8 dead row versions a second across all tables:

| Table | Dead per s | HOT % | Autovacuums in the hour |
|:-----|-----:|-----:|-----:|
| `solardatm.aud_datm_io` | 48.5 | 96 | 0 |
| `solardatm.agg_stale_datm` | 45.4 | – | 130 |
| `solardatm.aud_stale_datm` | 31.0 | – | 56 |
| `solardatm.aud_datm_daily` | 27.2 | 100 | 0 |
| `solardatm.agg_datm_hourly` | 26.7 | 94 | 0 |
| `solardatm.agg_datm_15m` | 19.7 | 92 | 1 |
| All tables | 244.8 | | |

The queue tables `agg_stale_datm` and `aud_stale_datm` are the ones to watch. They are small and
vacuumed every 30–65 s, and every poll of the queue reads them, so dead entries kept there slow
the queue first.

## 6. Options

| Option | Cancellations | Cost |
|:-----|:-----|:-----|
| **`hot_standby_feedback = on`, with a timeout for `solarquest`** | Snapshot conflicts end, so replay stops waiting and lag stays near zero | The primary keeps the row versions the replica's queries can see, bounded by the timeout (section 7.2) |
| Raise `max_standby_streaming_delay`, say to 5 min | Fewer, as queries of up to 5 min can finish | Replay stalls for minutes whenever a long query runs, so SolarQuery serves data minutes old. The immediate cancels return whenever lag reaches the new limit |
| Fewer updates of the audit counters | A few fewer | Changes to SolarIn and SolarQuery. The pruned versions would still be seconds old, so long queries would still conflict |
| A faster diff query | Fewer long queries, so fewer waits and bursts | Development work. Conflicts continue |
| Feedback through a replication slot | As for feedback, and it survives reconnects | The primary keeps WAL for the replica while it is down. Not needed here |

## 7. Recommended change

### 7.1 Steps

1. Cap SolarQuery's statements. On the **primary**, as role settings replicate and a replica
   cannot change them:

   ```sql
   ALTER ROLE solarquest SET statement_timeout = '5min';
   ```

   It applies to new connections, so restart SolarQuery or let its pool replace its
   connections. It applies on the primary too, where `solarquest` runs only its short
   audit-counter calls.
2. If `/datum/stream/*` reads through a cursor (a JDBC fetch size with autocommit off),
   `statement_timeout` restarts with every fetch, so it does not bound the whole read. In that
   case also set PG 17's `transaction_timeout` for the role, say `'15min'`. It ends the whole
   session, rather than cancelling the statement.
3. On the **replica**, set `hot_standby_feedback = on` in `postgresql.conf` and reload
   (`SELECT pg_reload_conf();`). No restart is needed, and a primary ignores the setting, so a
   config shared by both can carry it.
4. Leave `max_standby_streaming_delay` and `max_standby_archive_delay` at 60 s, for lock and
   buffer-pin conflicts.

Steps 1, 3 and 4 were done on 2026-11-27, shortly before 01:50 UTC, and step 2 later that day,
before 18:14 UTC, with `transaction_timeout = 15min`. The role settings are recorded in
`dba/postgres/setup/timescaledb/example/tsdb-init-users.sql` (commit `6f4ae68`).

Why 5 minutes: today a query on the replica rarely gets past 60–120 s before a conflict cancels
it, and the heaviest statements average 18–37 s. So the cap allows far longer queries than now,
and still bounds the primary's cost.

To undo the change, set `hot_standby_feedback = off` and reload. The replica tells the primary
at once, and the primary's horizon is released. `ALTER ROLE solarquest RESET statement_timeout;`
removes the cap.

### 7.2 Expected cost

With feedback on, while the replica's oldest snapshot is T seconds older than the primary's
own, the primary keeps about 244.8 × T extra dead row versions. They are removed once that
query ends. Meanwhile the tables grow by about what they hold, and that space is reused
afterwards.

| Replica's snapshot older than the primary's by | Extra dead row versions | In the two queue tables |
|:-----|-----:|-----:|
| 2 s (typical: replica p90 2.9 s, primary p90 0.7 s) | about 500 | about 150 |
| 1 minute | about 14,700 | about 4,600 |
| 2 minutes (a long diff query) | about 29,400 | about 9,200 |
| 5 minutes (the cap) | about 73,400 | about 22,900 |

For comparison, the primary's own work already holds back about 17,000 at its p99 (70 s), and
about 26,000 at its maximum (105 s). Before it used `start-fast`, the daily backup held back
about 466,000 (section 9.3). After the change, a 145 s query was measured holding back about
37,600 (section 9.4).

## 8. Checking the change

Run the collector again on both servers for an hour, as before, with `-l` and the replica's log
on the replica (section 9 has two such runs). Expect:

- on the replica, almost no snapshot conflicts or samples of replay waiting on one, and replay
  lag of about a second at p99;
- on the primary, the walsender holding a snapshot in nearly every sample. Its age is that of
  the replica's oldest query.

After that, watch:

- the replica's feedback, on the primary:
  `SELECT application_name, backend_xmin, age(backend_xmin) FROM pg_stat_replication;`
- dead rows and autovacuums on `agg_stale_datm` and `aud_stale_datm` (the second result of
  `primary-xmin-horizon.sql`);
- the mean time of `solardatm.process_one_agg_stale_datm` in `pg_stat_statements`, which would
  slow first if the queue tables bloat.

## 9. Results after the change

The collector ran again on both servers from 2026-11-27 01:50 to 02:51 UTC, with feedback on and
the 5-minute cap in place, and a third time from 18:14 to 19:15 UTC (section 9.4). The replica's
log has its last conflict wait ending at 01:38:26 UTC, and its last cancel at 01:07:42.

### 9.1 The replica

| | Before: 2026-11-26 21:40 UTC | After: 2026-11-27 01:50 UTC |
|:-----|-----:|-----:|
| Conflicts in the hour | 20 | 0 |
| Samples with replay waiting on a conflict | 15% | 0 |
| Replay lag, p99 / max | 49.3 / 59.4 s | 0.4 / 0.4 s |
| Most WAL received but not yet replayed | 22 MB | 150 kB |
| Oldest client snapshot, p99 / max | 47.8 / 58.5 s | 127.2 / 162.5 s |
| Client transactions seen running 60 s or more | 0 | 5, all finished |
| Statement execution time in the hour | 917 s | 1,899 s |
| Diff query: calls, mean, share of execution time | 473, 1.2 s, 62% | 488, 2.7 s, 69% |

- The conflict counters did not move during the hour: 349,931 snapshot conflicts at both ends.
- The diff query now runs to the end. Two copies that started at 02:02:56–57 ran for 162 s, and
  three that started at 02:04:07–09 for 95–97 s. Nothing came near the 5-minute cap.
- The replica does more work than before, because queries that used to be cancelled now finish
  and are counted. `pg_stat_statements` counts only finished runs, so the earlier mean of 1.2 s
  left the long runs out.
- The diff query's long runs come in a burst at the start of each hour. In this hour they ran in
  groups of 2–4 copies from 02:02 to 02:07, and none was cancelled. In the replica's log up to
  the change, 790 of the diff query's 891 cancels (89%) came in the first 10 minutes of an hour,
  and each of the 49 hours with any had some there. The groups in section 5.3 were this pattern
  rather than retries.

### 9.2 The primary

The walsender held a snapshot in all 720 samples, so the replica's feedback was in effect
throughout. The daily backup (section 9.3) held the primary's own horizon from 02:00 to 02:33,
which splits the hour in two:

| | Outside the backup | During the backup |
|:-----|-----:|-----:|
| Samples | 330 | 390 |
| The primary's own horizon, p50 | 51 transaction IDs, about 0.2 s | 204,840, about 17 minutes |
| Samples in which feedback held the horizon further back | 322 | 2 |
| How much further, p50 / p90 / max | 3.0 / 12.2 / 29.7 s | 0.3 s |
| Extra dead row versions, p50 / p90 / max | about 700 / 2,900 / 7,000 | about 70 |

- Outside the backup, most of the typical 3–4 s is the feedback interval, not queries. The
  replica reports at most every `wal_receiver_status_interval` (10 s), so the primary's copy of
  its oldest snapshot is several seconds old even when the replica is idle. Setting the interval
  to 1–2 s on the replica would trim that, but would save only a couple of thousand rows at most.
- During the backup, the primary's own horizon was far older than any replica snapshot, so the
  replica added nothing. The long diff queries all ran in that window, so this hour does not show
  what a long replica query costs at other times. By section 7.2, a 162 s query would keep about
  40,000 extra dead row versions. Section 9.4 measures it.
- The primary made 235.8 dead row versions a second, against 244.8 in the hour before the change.

The queue statements, the hour before the change against the hour after:

| Statement | Before: calls, mean | After: calls, mean |
|:-----|-----:|-----:|
| `solardatm.process_one_agg_stale_datm` | 166,114, 22.9 ms | 156,907, 25.2 ms |
| `solardatm.process_one_aud_stale_datm` | 113,442, 4.4 ms | 121,418, 5.6 ms |
| Dequeue from `agg_stale_datm` (a `DELETE` of rows locked `FOR UPDATE SKIP LOCKED`) | 166,114, 0.55 ms | 156,911, 0.59 ms |
| Dequeue from `aud_stale_datm` | 113,442, 1.14 ms | 121,419, 1.20 ms |

The queue work ran 5–26% slower, but the two hours are not alike. The second had the backup's
33-minute hold and a different hour's workload: `aud_acc_datm_daily` inserts doubled, and the
primary's statements ran for 13,941 s against 11,365 s. The dequeue statements, which feel dead
rows in the queue tables first, slowed only 5–7%. So the slowdown can neither be put down to
feedback nor ruled out from this hour. Section 9.4 has a run away from the backup.

### 9.3 The daily backup

- pgBackRest's incremental backup runs from cron at 02:00 UTC every day
  (`dba/postgres/freebsd/crontab-postgres-db0.txt`, line 12), as well as a differential at 06:00
  on Sundays and a full backup every three months.
- Its session called `pg_backup_start(..., false)` at 02:00:01. The `false` asks for a spread
  checkpoint, and a requested checkpoint first waits for any checkpoint in progress to finish.
  The session waited about 6 minutes for its checkpoint to start (`IPC/CheckpointStart`), and
  about 27 for it to finish (`IPC/CheckpointDone`), as `checkpoint_timeout` is 30 minutes. Its
  statement's snapshot held the primary's horizon all that time, 1,978 s or 420,766 transaction
  IDs, until 02:32:58.
- Meanwhile about 466,000 dead row versions (235.8 a second for 1,978 s) waited to be removed.
  That is about 12 times what the longest replica query of the hour would have kept on its own,
  and about 6 times the most the 5-minute cap allows the replica. It happened on every backup,
  with feedback or without, until the backups used `start-fast`.
- `pg_backup_start` took 1,978–1,983 s. pgBackRest's `db-timeout` in production was 2,700 s
  on 2026-11-27, as in the next day's backup log. The repo's `PGBACKREST_DB_TIMEOUT` said
  2,000 s, sized in `pgBackRest-Setup.md` for one 30-minute checkpoint, until `d08d219` brought
  it in line with production. So the backup had about 12 minutes to spare: it would have timed
  out only with more than about 18 minutes left on the checkpoint in progress at 02:00, and
  that one had about 6. A checkpoint in progress could have up to about 27 minutes left,
  depending on when checkpoints fell, so `pg_backup_start` could take up to about 54 minutes.
- pgBackRest's `start-fast` option makes `pg_backup_start` ask for an immediate checkpoint,
  which also hurries one in progress. That ends both the long hold and the risk of the timeout.
  The price is a burst of checkpoint writes at the start of each backup, instead of writes
  spread over half an hour. Raising `db-timeout` to about an hour would have removed the risk of
  the timeout alone.
- **pgBackRest has had `start-fast=y` since 2026-11-27 04:54 UTC**, recorded in
  `PGBACKREST_START_FAST` (commit `6f4ae68`).
- **The first backup with it, at 02:00 UTC on 2026-11-28, started in 2 s.** pgBackRest asked
  for the start at 02:00:00.812, to begin "after the requested immediate checkpoint completes",
  and the backup began at 02:00:02.796. So `pg_backup_start` took 2 s rather than 1,978 s, and
  neither the hold on the primary's horizon nor the burst of checkpoint writes lasted longer
  than that. The files were then copied from 02:00 to 02:34, half an hour earlier than the day
  before, and the backup completed successfully in 2,082 s.

### 9.4 Away from the backup

The collector ran a third time on both servers from 2026-11-27 18:14 to 19:15 UTC, about 16
hours after the change and far from the 02:00 backup.

**The replica** has had no conflicts of any kind since the change. Its counters read 349,931
snapshot, 18 lock and 177 buffer-pin conflicts at 01:50 UTC, and the same at 19:15. At the rate
before the change, about 430 would have come in those 17½ hours.

| | Before: 2026-11-26 21:40 UTC | After: 2026-11-27 01:50 UTC | After: 18:14 UTC |
|:-----|-----:|-----:|-----:|
| Conflicts in the hour | 20 | 0 | 0 |
| Samples with replay waiting on a conflict | 15% | 0 | 0 |
| Replay lag, p99 / max | 49.3 / 59.4 s | 0.4 / 0.4 s | 0.4 / 0.4 s |
| Oldest client snapshot, p99 / max | 47.8 / 58.5 s | 127.2 / 162.5 s | 109.1 / 144.4 s |
| Client transactions seen running 60 s or more | 0 | 5, all finished | 7, all finished |
| Statement execution time in the hour | 917 s | 1,899 s | 2,042 s |
| Diff query: calls, mean, share of execution time | 473, 1.2 s, 62% | 488, 2.7 s, 69% | 502, 2.5 s, 62% |

- The hourly burst came again. No client transaction ran for 10 s or more until 19:00, and then
  SolarQuery's datum queries came in bunches until 19:11: the diff query mostly in pairs from
  19:02 to 19:06, the longest for 144 s, and another query in seven copies at 19:10–19:11. All of
  them finished.
- The diff query's longest finished run is now 285 s, against 166 s at the end of the second
  run, so one run between 02:51 and 18:14 came within 15 s of the 5-minute cap. As these queries
  grow, some will reach the cap and fail with a statement timeout instead of a conflict. The
  collector counts those as `other_cancel`, and the part of the log this run read has none.
- That part of the log, from some time before 08:00 UTC, has only two waits, at 08:00 and 13:00,
  each of about 6 s on a buffer pin in `da_datm_meta`. Neither cancelled anything. Feedback does
  nothing for buffer-pin conflicts, so the 60 s delay still matters for them.

**The primary.** The walsender held a snapshot in all 720 samples. The primary's own horizon was
much as before the change: 37 transaction IDs at p50, and at most 21,200, about 94 s. How much
further back feedback held it:

| Beyond the primary's own horizon | p50 | p90 | p99 | max |
|:-----|-----:|-----:|-----:|-----:|
| Seconds | 3.3 | 27.0 | 109.6 | 145.1 |
| Extra dead row versions, at 259.2 a second | about 860 | about 7,000 | about 28,400 | about 37,600 |

- Feedback held the horizon further back than the primary's own in 664 of the 720 samples, most
  of the time by the 3–4 s that comes from the feedback interval, as in the second run.
- It held it back 60 s or more in 34 samples, about 3 minutes in all, between 19:04 and 19:11,
  while the burst's long queries ran. The most, 145 s or about 37,600 dead row versions, is in
  line with section 7.2. Averaged over the hour, the extra was about 2,700.
- The 285 s run would have held back about 74,000 by its end, close to the 5-minute bound in
  section 7.2.

The queue work, the hour before the change against this one:

| Per hour | Before the change | Third run |
|:-----|-----:|-----:|
| `process_one_agg_stale_datm`: calls, mean | 166,114, 22.9 ms | 191,604, 23.7 ms |
| `process_one_aud_stale_datm`: calls, mean | 113,442, 4.4 ms | 118,933, 4.3 ms |
| Dequeue from `agg_stale_datm`: calls, mean | 166,114, 0.55 ms | 191,611, 0.67 ms |
| Dequeue from `aud_stale_datm`: calls, mean | 113,442, 1.14 ms | 118,933, 1.20 ms |
| Execution time of all the primary's statements | 11,365 s | 11,955 s |
| Dead row versions a second | 244.8 | 259.2 |
| Autovacuums of `agg_stale_datm` and `aud_stale_datm` | 130 and 56 | 149 and 77 |

- The two hours are much alike, though at different times of day. `aud_acc_datm_daily` inserts
  were at the first hour's level (13,131, against 13,397), and the agg queue had 15% more work.
- The agg queue's items took 3% longer each, and the aud queue's 4% less.
- The agg dequeue took 22% longer a call, about 23 s more over the hour. That may be the extra
  load as much as feedback: in the second run, under the backup's 33-minute hold, it averaged
  only 0.59 ms.
- Both queue tables stayed small. Their vacuums found `agg_stale_datm` at up to 154 blocks, at
  18:20–18:35, before the burst, and `aud_stale_datm` at up to 140, during it: about 1 MB each.

So away from the backup, feedback costs the primary about what section 7.2 expected, and the
queue work shows no slowdown that can be put down to it.

**Two open points are settled.**

- Every SolarQuery connection seen in this run was opened between 17:27 and 19:03 UTC, long after
  the `ALTER ROLE`, so all of them have the 5-minute cap.
- `solarquest` now also has `transaction_timeout = 15min`, set between the second and third
  runs. That is section 7.1, step 2, and it bounds a read through a cursor as a whole.

### 9.5 Still to check

- Watch for statement timeouts in the replica's log, as the diff query's longest run is now
  285 s. The collector counts them as `other_cancel`.
- Optionally, find which client sends the hourly diff queries. They no longer cause cancels, but
  they take 62–69% of the replica's statement time, bunched into the first 10 minutes or so of
  each hour, and they set feedback's largest cost to the primary.
- Keep `log_recovery_conflict_waits = on`, so that any conflict that remains is logged with its
  WAL record and table.

## 10. Caveats

- Only one hour was sampled before the change, and its 20 cancels all came in one burst. The
  log's rate varies from 7 to 106 an hour, and its breakdown of waits comes from only 71 minutes.
- Two runs were made after the change. The backup covered half of the second run, and the third
  was at 18:14 UTC rather than the first run's 21:40, with 15% more work in the agg queue.
- In the second run, the SolarQuery connections seen were opened between 00:31 and 01:27 UTC,
  so some may have been opened before the `ALTER ROLE` and lacked the cap, though no query came
  near it. In the third run, all of them were opened after 17:27.
- The replica's logs do not show whether they cover all the time since the change. The second
  run's ends at its last conflict message, at 01:38:26 UTC, and the third run's starts some time
  before 08:00. The conflict counters cover all of it, and show none.
- There is no replication slot, so the primary forgets the replica's feedback whenever the
  connection drops. A few conflicts after a reconnect, before the first feedback arrives, are
  expected.
- In the repo, the `max_standby_streaming_delay` hunk of
  `dba/postgres/freebsd/postgresql-conf.pg17-solardb0.diff` is cut off at line 102. That is worth
  fixing when `hot_standby_feedback` is recorded there.

## 11. Files

The collector's outputs are kept outside this repo, in these folders and archives:

| Path | What |
|:-----|:-----|
| `replica-conflicts-primary-20261126T214044Z/summary.txt` | The primary's summary before the change |
| `replica-conflicts-replica-20261126T214014Z/summary.txt` | The replica's summary before the change, as produced on FreeBSD, without its samples and log sections |
| `replica-conflicts-replica-20261126T214014Z/summary-rebuilt.txt` | The replica's complete summary before the change, rebuilt with the fixed awk programs |
| `replica-conflicts-primary-20261127T015032Z/summary.txt` | The primary's summary of the second run, after the change, half of it during the backup |
| `replica-conflicts-replica-20261127T015019Z/summary.txt` | The replica's summary of the second run |
| `replica-conflicts-primary-20261127T181438Z/summary.txt` | The primary's summary of the third run, away from the backup |
| `replica-conflicts-replica-20261127T181434Z/summary.txt` | The replica's summary of the third run |
| `replica-conflicts-*-20261126T*.tgz`, `replica-conflicts-*-20261127T*.tar.gz` | The original archives of all the runs |
