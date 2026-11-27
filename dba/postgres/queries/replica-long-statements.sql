/* ============================================================================
 * The statements that have run longest on the replica, from
 * pg_stat_statements: the ones a recovery conflict is most likely to cancel.
 *
 *   psql -X -d solarnetwork -v min_s=10 -f replica-long-statements.sql
 *
 * min_s (default 10) leaves out statements that have never run that long.
 * Run it on the replica, as a superuser or a member of pg_read_all_stats to see
 * other roles' statements. If pg_stat_statements is not on the search_path,
 * SET search_path first.
 *
 * pg_stat_statements counts only statements that finished: a cancelled one is
 * never counted. So max_s is the longest run that finished, and the runs that
 * were cancelled for taking too long are missing. A statement whose max_s is
 * near max_standby_streaming_delay is likely to be among the cancelled ones.
 * The minimum and maximum are kept since max_since; pg_stat_statements_reset()
 * with minmax_only => true starts them again without losing the totals.
 *
 * pct_time is the statement's share of all the time the replica spent running
 * statements in this database.
 * ============================================================================
 */

\if :{?min_s}
\else
	\set min_s 10
\endif

\echo == statements by the longest run that finished
WITH s AS (
	SELECT s.*
		, (to_jsonb(s) ->> 'minmax_stats_since')::timestamptz AS minmax_since
		, sum(s.total_exec_time) OVER () AS all_exec_time
	FROM pg_stat_statements s
	WHERE s.dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
)
SELECT s.queryid
	, r.rolname
	, s.calls
	, round((s.mean_exec_time / 1000)::numeric, 2) AS mean_s
	, round((s.stddev_exec_time / 1000)::numeric, 2) AS stddev_s
	, round((s.max_exec_time / 1000)::numeric, 1) AS max_s
	, round((s.total_exec_time / 1000)::numeric) AS total_s
	, round((100 * s.total_exec_time / NULLIF(s.all_exec_time, 0))::numeric, 1) AS pct_time
	, round(s.rows::numeric / NULLIF(s.calls, 0)) AS rows_per_call
	, date_trunc('second', s.minmax_since) AS max_since
	, left(regexp_replace(s.query, '\s+', ' ', 'g'), 160) AS query
FROM s
LEFT JOIN pg_roles r ON r.oid = s.userid
WHERE s.max_exec_time >= :min_s * 1000
ORDER BY s.max_exec_time DESC
LIMIT 30;

\echo == statement run time by role
SELECT r.rolname
	, count(*) AS statements
	, sum(s.calls) AS calls
	, round((sum(s.total_exec_time) / 1000)::numeric) AS total_s
	, round((max(s.max_exec_time) / 1000)::numeric, 1) AS max_s
	, count(*) FILTER (WHERE s.max_exec_time >= :min_s * 1000) AS statements_over_min_s
FROM pg_stat_statements s
LEFT JOIN pg_roles r ON r.oid = s.userid
WHERE s.dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
GROUP BY r.rolname
ORDER BY sum(s.total_exec_time) DESC;
