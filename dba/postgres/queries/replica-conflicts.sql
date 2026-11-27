/* ============================================================================
 * Recovery conflicts on a streaming replica: how many of each kind there have
 * been, whether replay is waiting on one now, and which sessions a conflict
 * would cancel first.
 *
 *   psql -X -d solarnetwork -f replica-conflicts.sql
 *
 * Run it on the replica, as a superuser or a member of pg_read_all_stats, so
 * that other roles' queries are shown. It reads only the statistics views and
 * the lock table. It needs PostgreSQL 14 or later.
 *
 * The kinds of conflict:
 *
 *   snapshot     VACUUM on the primary, or the pruning a page gets whenever it
 *                is read, removed row versions that a replica query's snapshot
 *                could still see. Every query in the database whose snapshot
 *                is older than the removed rows is cancelled, whatever table
 *                it reads, so a busy queue table on the primary can cancel a
 *                long datum query on the replica. hot_standby_feedback ends
 *                these conflicts, but the primary must then keep those row
 *                versions until the replica's queries finish (see
 *                primary-xmin-horizon.sql).
 *   lock         the primary took an ACCESS EXCLUSIVE lock, and a replica
 *                query held a lock on the same table or index. DROP, TRUNCATE,
 *                most ALTER TABLE, CLUSTER, VACUUM FULL, REINDEX, LOCK TABLE,
 *                VACUUM truncating empty pages off the end of a table, and
 *                TimescaleDB's drop_chunks, reorder_chunk and move_chunk all
 *                take one. hot_standby_feedback does not help with these.
 *   bufferpin    replay needed a page to itself, to prune or vacuum it, while a
 *                replica query had the page pinned (usually an open cursor).
 *   deadlock     a buffer pin wait in replay deadlocked with a replica query.
 *   tablespace   a dropped tablespace held a query's temporary files.
 *   logicalslot  a logical slot on the replica had to be invalidated.
 *
 * Replay waits for the conflicting queries to finish, for at most
 * max_standby_streaming_delay after the WAL arrived, and then cancels them.
 * That allowance is shared: once replay falls behind for any reason (a long
 * wait, or a burst of WAL from a large rewrite), the next conflict gets less
 * of it, and may cancel a query at once.
 *
 * The startup process (the one that replays WAL) shows what it is doing in
 * wait_event: RecoveryWalStream means it has replayed everything and is waiting
 * for more WAL; RecoveryConflictSnapshot, Lock/relation and BufferPin mean it
 * is waiting on a conflict; no wait event at all means it is busy replaying.
 * ============================================================================
 */

\echo == conflicts since the statistics were reset, by database
SELECT c.datname
	, date_trunc('second', d.stats_reset) AS stats_reset
	, d.conflicts AS total
	, c.confl_snapshot AS snapshot
	, c.confl_lock AS lock
	, c.confl_bufferpin AS bufferpin
	, c.confl_deadlock AS deadlock
	, c.confl_tablespace AS tablespace
	, (to_jsonb(c) ->> 'confl_active_logicalslot')::bigint AS logicalslot
	, round(d.conflicts / NULLIF(EXTRACT(epoch FROM now() - d.stats_reset)::numeric / 86400, 0), 1)
		AS per_day
FROM pg_stat_database_conflicts c
INNER JOIN pg_stat_database d ON d.datid = c.datid
WHERE d.conflicts > 0 OR c.datname = current_database()
ORDER BY d.conflicts DESC, c.datname;

\echo == replay now
SELECT pg_get_wal_replay_pause_state() AS pause_state
	, pg_last_wal_receive_lsn() AS received
	, pg_last_wal_replay_lsn() AS replayed
	, pg_size_pretty(pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()))
		AS replay_behind
	, date_trunc('second', now() - pg_last_xact_replay_timestamp()) AS since_last_replayed_commit
	, a.pid AS startup_pid
	, a.wait_event_type
	, a.wait_event
	, (SELECT count(*) FROM pg_locks l
		WHERE l.pid = a.pid AND l.granted AND l.mode = 'AccessExclusiveLock') AS ael_held
	, (SELECT r.status FROM pg_stat_wal_receiver r) AS receiver
	, date_trunc('second', pg_postmaster_start_time()) AS server_started
FROM pg_stat_activity a
WHERE a.backend_type = 'startup';

\echo == the lock replay is waiting for, and the sessions holding it (none unless it is waiting now)
SELECT w.relation::regclass AS relation
	, date_trunc('second', now() - w.waitstart) AS waiting
	, h.pid
	, h.mode
	, a.usename
	, a.state
	, date_trunc('second', now() - a.xact_start) AS xact_age
	, left(regexp_replace(a.query, '\s+', ' ', 'g'), 100) AS query
FROM pg_stat_activity s
INNER JOIN pg_locks w ON w.pid = s.pid AND NOT w.granted
INNER JOIN pg_locks h ON h.granted AND h.pid <> s.pid
	AND h.locktype = w.locktype
	AND h.database IS NOT DISTINCT FROM w.database
	AND h.relation IS NOT DISTINCT FROM w.relation
LEFT JOIN pg_stat_activity a ON a.pid = h.pid
WHERE s.backend_type = 'startup'
ORDER BY a.xact_start;

\echo == sessions holding a snapshot, oldest first: a snapshot conflict cancels these first
SELECT a.pid
	, a.usename
	, a.state
	, date_trunc('second', now() - a.xact_start) AS xact_age
	, date_trunc('second', now() - a.query_start) AS query_age
	, age(a.backend_xmin) AS xmin_age
	, a.wait_event_type
	, a.wait_event
	, a.query_id
	, left(regexp_replace(a.query, '\s+', ' ', 'g'), 100) AS query
FROM pg_stat_activity a
WHERE a.backend_xmin IS NOT NULL
	AND a.pid <> pg_backend_pid()
ORDER BY a.xact_start
LIMIT 20;

\echo == settings
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN ('hot_standby', 'hot_standby_feedback', 'max_standby_streaming_delay'
		, 'max_standby_archive_delay', 'wal_receiver_status_interval', 'recovery_min_apply_delay'
		, 'primary_slot_name', 'deadlock_timeout', 'log_recovery_conflict_waits', 'log_lock_waits'
		, 'log_min_error_statement', 'statement_timeout', 'idle_in_transaction_session_timeout'
		, 'transaction_timeout', 'lock_timeout')
ORDER BY name;

\echo == settings made for a role or database (statement_timeout and the like)
SELECT r.rolname, d.datname, s.setconfig
FROM pg_db_role_setting s
LEFT JOIN pg_roles r ON r.oid = s.setrole
LEFT JOIN pg_database d ON d.oid = s.setdatabase
ORDER BY 1, 2;
