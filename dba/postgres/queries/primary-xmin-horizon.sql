/* ============================================================================
 * What turning on hot_standby_feedback would cost the primary.
 *
 *   psql -X -d solarnetwork -f primary-xmin-horizon.sql
 *
 * Run it on the primary, as a superuser or a member of pg_read_all_stats. It
 * needs TimescaleDB, to count chunks under their hypertable.
 *
 * With hot_standby_feedback on, the replica tells the primary how old the
 * oldest snapshot held by its queries is, and VACUUM and page pruning on the
 * primary then keep every row version that snapshot could still see. That
 * stops snapshot conflicts. It costs the primary something only while the
 * replica's oldest snapshot is older than the primary's own oldest one, as
 * the primary already keeps whatever its own oldest snapshot can see. The
 * replica can bound the cost: a statement_timeout or transaction_timeout for
 * its query role bounds how old a snapshot there can get.
 *
 * The first result is what holds the primary's horizon back now: sessions with
 * a snapshot or a transaction ID, replication slots, and prepared transactions.
 * A walsender with a snapshot, or a physical slot with an xmin, is a replica's
 * feedback. A session marked in_vacuum is a VACUUM, whose own snapshot holds
 * nothing back.
 *
 * The second is how fast each table makes dead row versions (n_tup_upd plus
 * n_tup_del), on average since the statistics were reset (or since the server
 * started, if they never were: then the rates are only rough). While the
 * horizon is held back by T seconds, about dead_per_s * T of them wait to be
 * removed: held_1m and held_10m give that for one and ten minutes. A table
 * grows by about what it has to hold, and the space is reused once the
 * horizon moves on.
 * ============================================================================
 */

\echo == what holds the xmin horizon back now, oldest first
SELECT 'session' AS holder
	, a.pid::text AS id
	, a.backend_type
	, a.usename
	, a.application_name
	, a.state
	, EXISTS (SELECT 1 FROM pg_stat_progress_vacuum v WHERE v.pid = a.pid) AS in_vacuum
	, date_trunc('second', now() - a.xact_start) AS xact_age
	, GREATEST(age(a.backend_xmin), age(a.backend_xid)) AS xid_age
	, left(regexp_replace(a.query, '\s+', ' ', 'g'), 80) AS query
FROM pg_stat_activity a
WHERE (a.backend_xmin IS NOT NULL OR a.backend_xid IS NOT NULL)
	AND a.pid <> pg_backend_pid()
UNION ALL
SELECT 'slot', s.slot_name, s.slot_type, NULL, NULL
	, CASE WHEN s.active THEN 'active' ELSE 'inactive' END, FALSE, NULL
	, GREATEST(age(s.xmin), age(s.catalog_xmin)), NULL
FROM pg_replication_slots s
WHERE s.xmin IS NOT NULL OR s.catalog_xmin IS NOT NULL
UNION ALL
SELECT 'prepared', p.gid, NULL, p.owner, NULL, NULL, FALSE
	, date_trunc('second', now() - p.prepared), age(p.transaction), NULL
FROM pg_prepared_xacts p
ORDER BY xid_age DESC NULLS LAST
LIMIT 25;

\echo == dead row versions made per table, chunks under their hypertable
WITH w AS (
	SELECT COALESCE(d.stats_reset, pg_postmaster_start_time()) AS since
		, NULLIF(EXTRACT(epoch FROM now() - COALESCE(d.stats_reset, pg_postmaster_start_time())), 0)
			AS secs
	FROM pg_stat_database d
	WHERE d.datname = current_database()
)
, t AS (
	SELECT COALESCE(ch.hypertable_schema || '.' || ch.hypertable_name
			, s.schemaname || '.' || s.relname) AS tbl
		, count(*) AS rels
		, sum(s.n_tup_ins) AS ins
		, sum(s.n_tup_upd) AS upd
		, sum(s.n_tup_hot_upd) AS hot_upd
		, sum(s.n_tup_del) AS del
		, sum(s.n_dead_tup) AS dead_now
		, sum(s.autovacuum_count) AS autovacuums
		, max(s.last_autovacuum) AS last_autovacuum
	FROM pg_stat_user_tables s
	LEFT JOIN timescaledb_information.chunks ch
		ON ch.chunk_schema = s.schemaname AND ch.chunk_name = s.relname
	GROUP BY 1
)
SELECT t.tbl
	, t.rels
	, round((t.upd + t.del) / w.secs, 1) AS dead_per_s
	, round((t.upd + t.del) / w.secs * 60) AS held_1m
	, round((t.upd + t.del) / w.secs * 600) AS held_10m
	, round(100.0 * t.hot_upd / NULLIF(t.upd, 0), 1) AS hot_pct
	, round(t.ins / w.secs, 1) AS ins_per_s
	, t.dead_now
	, round(t.autovacuums / (w.secs / 3600), 2) AS autovacuums_per_h
	, date_trunc('second', t.last_autovacuum) AS last_autovacuum
	, date_trunc('second', w.since) AS since
FROM t
CROSS JOIN w
WHERE t.upd + t.del > 0
ORDER BY t.upd + t.del DESC
LIMIT 30;
