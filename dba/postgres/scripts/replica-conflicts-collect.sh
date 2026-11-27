#!/bin/sh
#
# replica-conflicts-collect.sh - collect read-only diagnostics about the queries
# a streaming replica cancels because they conflict with recovery, to work out
# how to have fewer of them without costing the primary too much.
#
# Run it against the replica and, at the same time, against the primary, with
# the same -c and -i, so that the two can be lined up by time. It finds out
# which of the two it is connected to, and collects what is useful there:
#
#   replica   how many queries each kind of conflict cancels, and when; when
#             replay waits on a conflict, for how long, and on what; how far
#             replay falls behind; and the client sessions that hold a snapshot
#             or a lock for a long time, which are the ones a conflict cancels.
#             Their snapshots are also what hot_standby_feedback would ask the
#             primary to keep row versions for.
#   primary   how far back the primary's own work already holds the xmin
#             horizon (with hot_standby_feedback on, the replica's oldest
#             snapshot costs the primary something only when it is older than
#             that); how many dead row versions each table makes, which is what
#             a held back horizon keeps; and the ACCESS EXCLUSIVE locks taken,
#             each of which is replayed on the replica and conflicts there with
#             any query using the same table or index.
#
# The script changes nothing in the database: every session it opens is set to
# default_transaction_read_only, with a statement timeout. Each sample is one
# short psql session that reads only statistics views, the lock table and the
# catalogs, so it never holds a snapshot for long on the replica. It writes a
# directory of CSV and text files with a summary.txt, and a .tar.gz of that
# directory to hand back.
#
# Usage, run in two terminals at about the same time, or with one in the
# background as here:
#
#   export PGSSLCERT=superuser.crt PGSSLKEY=superuser.key
#   sh replica-conflicts-collect.sh -h REPLICA -U postgres -d solarnetwork \
#       -l /var/log/postgresql/replica.log &
#   sh replica-conflicts-collect.sh -h PRIMARY -U postgres -d solarnetwork
#   wait
#
# The defaults take a sample every 5 s for an hour. -l reads the log once the
# sampling ends, so the log must be readable where the script runs: if it is
# not, copy it over afterwards and run again with -c 0 -l FILE.
#
# Connection options are the same as psql's, and anything libpq reads from the
# environment (PGSSLCERT, PGSSLKEY, PGSSLROOTCERT, PGPASSWORD, ~/.pgpass, ...)
# applies. psql is run with -w, so it never stops to prompt for a password.
#
#   -h HOST  -p PORT  -U USER  -d DBNAME    connection, as for psql
#   -o DIR      where to create the output (default: current directory)
#   -c COUNT    number of samples (default 720); 0 takes none, and collects only
#               the context (and reads the -l logs)
#   -i SECONDS  seconds between samples (default 5)
#   -a SECONDS  record a session in a sample once its transaction has run this
#               long (default 5)
#   -t SECONDS  statement timeout for every query (default 60)
#   -l FILE     the replica's Postgres server log, in the stderr or syslog
#               format (not csvlog or jsonlog); may be given more than once, and
#               may be compressed (.gz, .bz2, .xz, .zst). Its recovery conflict
#               messages are extracted and summarised, and the relations they
#               name are looked up in the connected database. Give the whole
#               log, or a slice of it by time, not the output of grep: the
#               DETAIL, CONTEXT and STATEMENT lines after each message count.
#
# To stop early, press Ctrl-C or send TERM (kill %1 for the one in the
# background): sampling stops, and the second snapshot, the summary and the
# archive are still made.
#
# Connect as a superuser, or a role with pg_read_all_stats: without that, other
# roles' queries are hidden.
#
# The replica's log says the most when the replica has these set, all of which
# take effect on a reload:
#
#   log_recovery_conflict_waits = on    each conflict that holds replay up for
#                                       longer than deadlock_timeout is logged,
#                                       with the WAL record and the relation,
#                                       and the sessions in the way
#   log_min_error_statement = error     each cancelled statement (the default)
#   log_lock_waits = on                 queries kept waiting by a lock, such as
#                                       one replay holds
#
# Reading the results, in short:
#
#   - Mostly snapshot conflicts: hot_standby_feedback = on would end them. The
#     primary run shows what that costs: compare the replica's oldest snapshot
#     ages with the primary's own, and the dead row versions per second. A
#     statement_timeout or transaction_timeout for the query role on the
#     replica bounds the cost.
#   - Mostly lock conflicts: the log, the replica's lock waits and the
#     primary's ACCESS EXCLUSIVE locks name the relations. VACUUM truncating
#     the end of a table (vacuum_truncate = off stops that, per table),
#     TimescaleDB jobs and maintenance scripts are the usual sources.
#   - Statements cancelled having run much less than
#     max_standby_streaming_delay: replay was already behind, so the conflict
#     had little or none of the delay left. The log summary counts these as
#     cancels not tied to a wait (judging only those after the first logged
#     wait, as log_recovery_conflict_waits may have been off before it).
#   - A longer max_standby_streaming_delay lets longer queries finish, but each
#     conflict then holds up all of replay for up to that long, and every query
#     on the replica sees data that much older meanwhile.
#
# Needs psql 12 or later and PostgreSQL 14 or later. Written for POSIX sh; also
# runs under zsh and bash.

set -u
umask 077

# zsh gives a function's name as $0 inside it, so keep the script's name here
SCRIPT=$0
SCRIPT_VERSION=1
SAMPLES=720
INTERVAL=5
MIN_AGE=5
STMT_TIMEOUT=60
LOGS=
OUTBASE=.
PSQL=${PSQL:-psql}
NL='
'

usage() {
	sed -n '2,/^# Needs psql/p' "$SCRIPT" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

die() {
	printf 'replica-conflicts-collect: %s\n' "$*" >&2
	exit 1
}

is_number() {
	case $1 in
		'' | *[!0-9]*) return 1 ;;
	esac
	return 0
}

while getopts 'h:p:U:d:o:c:i:a:t:l:' opt; do
	case $opt in
		h) PGHOST=$OPTARG; export PGHOST ;;
		p) PGPORT=$OPTARG; export PGPORT ;;
		U) PGUSER=$OPTARG; export PGUSER ;;
		d) PGDATABASE=$OPTARG; export PGDATABASE ;;
		o) OUTBASE=$OPTARG ;;
		c) SAMPLES=$OPTARG ;;
		i) INTERVAL=$OPTARG ;;
		a) MIN_AGE=$OPTARG ;;
		t) STMT_TIMEOUT=$OPTARG ;;
		l) LOGS=$LOGS$OPTARG$NL ;;
		*) usage ;;
	esac
done
shift $((OPTIND - 1))
[ $# -eq 0 ] || usage

for v in "$SAMPLES" "$INTERVAL" "$MIN_AGE" "$STMT_TIMEOUT"; do
	is_number "$v" || die "options -c, -i, -a and -t take a whole number"
done
[ "$INTERVAL" -ge 1 ] || die "-i must be at least 1"
[ "$STMT_TIMEOUT" -ge 1 ] || die "-t must be at least 1"

# log_tool FILE - the program that reads FILE
log_tool() {
	case $1 in
		*.gz) echo gzip ;;
		*.bz2) echo bzip2 ;;
		*.xz) echo xz ;;
		*.zst) echo zstd ;;
		*) echo cat ;;
	esac
}

# read_log FILE - write FILE out, decompressed
read_log() {
	case $(log_tool "$1") in
		cat) cat "$1" ;;
		*) "$(log_tool "$1")" -dc "$1" ;;
	esac
}

# each log must be readable, and its decompressor present
if [ -n "$LOGS" ]; then
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		[ -r "$f" ] || die "cannot read the log file $f"
		command -v "$(log_tool "$f")" >/dev/null 2>&1 || die "$(log_tool "$f") is needed to read $f"
	done <<EOF
$LOGS
EOF
fi

command -v "$PSQL" >/dev/null 2>&1 || die "psql not found (set PSQL=/path/to/psql)"
PSQL_MAJOR=$("$PSQL" -V | sed -n 's/^[^0-9]*\([0-9][0-9]*\).*/\1/p')
is_number "${PSQL_MAJOR:-}" || die "cannot tell the version of $PSQL"
[ "$PSQL_MAJOR" -ge 12 ] || die "psql 12 or later is needed for --csv (found $PSQL_MAJOR)"

PGAPPNAME=replica-conflicts-collect
PGCONNECT_TIMEOUT=${PGCONNECT_TIMEOUT:-15}
export PGAPPNAME PGCONNECT_TIMEOUT

[ -d "$OUTBASE" ] || die "output directory $OUTBASE does not exist"

# -----------------------------------------------------------------------------
# Connect, and work out which server this is.
# -----------------------------------------------------------------------------

WHO=$("$PSQL" -X -q -w -A -t -F '|' -v ON_ERROR_STOP=1 -c "SET statement_timeout = '${STMT_TIMEOUT}s'" \
	-c "SELECT current_user
		, (SELECT rolsuper FROM pg_roles WHERE rolname = current_user)
		, pg_has_role(current_user, 'pg_read_all_stats', 'USAGE')
		, pg_is_in_recovery()
		, current_setting('server_version_num')
		, current_database()" 2>/dev/null </dev/null)
if [ -z "$WHO" ]; then
	# again, to show why
	"$PSQL" -X -q -w -c 'SELECT 1' >/dev/null </dev/null
	die "cannot connect; check the connection options and certificates"
fi
IFS='|' read -r DB_USER IS_SUPER CAN_STATS IN_RECOVERY SERVER_NUM DB_NAME <<EOF
$WHO
EOF
is_number "$SERVER_NUM" || die "cannot tell the server version ($SERVER_NUM)"
[ "$SERVER_NUM" -ge 140000 ] || die "PostgreSQL 14 or later is needed (found $SERVER_NUM)"
if [ "$IN_RECOVERY" = t ]; then
	ROLE=replica
	IS_REPLICA=true
else
	ROLE=primary
	IS_REPLICA=false
fi
if [ "$SERVER_NUM" -ge 160000 ]; then
	HAVE_IO=true
else
	HAVE_IO=false
fi

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
NAME=replica-conflicts-$ROLE-$STAMP
OUT=$OUTBASE/$NAME
mkdir "$OUT" "$OUT/sql" "$OUT/awk" "$OUT/samples" "$OUT/snap1" "$OUT/snap2" \
	|| die "cannot create $OUT"
LOG=$OUT/collect.log
FAILED=
: >"$LOG"

note() {
	printf '%s %s %s\n' "$(date -u +%H:%M:%SZ)" "$ROLE" "$*" | tee -a "$LOG" >&2
}

# ask SQL - run one statement and print its unaligned result
ask() {
	"$PSQL" -X -q -w -A -t -F '|' -v ON_ERROR_STOP=1 -c "SET statement_timeout = '${STMT_TIMEOUT}s'" \
		-c "SET default_transaction_read_only = on" -c "SET timezone = 'UTC'" -c "$1" \
		2>>"$LOG" </dev/null
}

# run FORMAT NAME OUTFILE [psql options] - run sql/NAME.sql into OUTFILE
#   csv    comma separated, with a header
#   text   psql's aligned tables
run() {
	_fmt=$1
	_name=$2
	_out=$3
	shift 3
	case $_fmt in
		csv) set -- --csv "$@" ;;
	esac
	"$PSQL" -X -q -w -v ON_ERROR_STOP=1 -v stmt_timeout="${STMT_TIMEOUT}s" "$@" \
		-f "$OUT/sql/session.sql" -f "$OUT/sql/$_name.sql" >"$_out" 2>>"$LOG" </dev/null
	_rc=$?
	if [ "$_rc" -ne 0 ]; then
		note "WARNING: $_name failed (psql exit $_rc), see collect.log"
		FAILED="$FAILED $_name"
	fi
	return "$_rc"
}

finish() {
	{
		printf 'finished=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		printf 'failed_steps=%s\n' "${FAILED# }"
	} >>"$OUT/run.txt"
	if tar -czf "$OUT.tar.gz" -C "$OUTBASE" "$NAME"; then
		note "Wrote $OUT.tar.gz"
	else
		note "WARNING: could not create $OUT.tar.gz; the files are in $OUT"
	fi
}

trap 'note "Interrupted; packaging what was collected"; finish; exit 130' INT TERM

PSS_SCHEMA=$(ask "SELECT n.nspname FROM pg_extension e
	INNER JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = 'pg_stat_statements'")
if [ -n "$PSS_SCHEMA" ] && ! ask "SELECT 1 FROM \"$PSS_SCHEMA\".pg_stat_statements(false) LIMIT 1" >/dev/null; then
	note "WARNING: pg_stat_statements is installed but cannot be read (is it in shared_preload_libraries?)"
	PSS_SCHEMA=
fi
TSDB_VERSION=$(ask "SELECT extversion FROM pg_extension WHERE extname = 'timescaledb'")
if [ -n "$TSDB_VERSION" ]; then
	HAVE_TSDB=true
else
	HAVE_TSDB=false
fi
DELAY_MS=$(ask "SELECT setting FROM pg_settings WHERE name = 'max_standby_streaming_delay'")
FEEDBACK=$(ask "SELECT setting FROM pg_settings WHERE name = 'hot_standby_feedback'")

{
	printf 'script_version=%s\n' "$SCRIPT_VERSION"
	printf 'started=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf 'role=%s\n' "$ROLE"
	printf 'host=%s\nport=%s\ndatabase=%s\n' "${PGHOST:-}" "${PGPORT:-}" "$DB_NAME"
	printf 'user=%s\nsuperuser=%s\nread_all_stats=%s\nin_recovery=%s\n' \
		"$DB_USER" "$IS_SUPER" "$CAN_STATS" "$IN_RECOVERY"
	printf 'server_version_num=%s\npsql_major=%s\n' "$SERVER_NUM" "$PSQL_MAJOR"
	printf 'samples=%s\ninterval_s=%s\nmin_age_s=%s\nstatement_timeout_s=%s\n' \
		"$SAMPLES" "$INTERVAL" "$MIN_AGE" "$STMT_TIMEOUT"
	printf 'pg_stat_statements_schema=%s\ntimescaledb=%s\n' "$PSS_SCHEMA" "$TSDB_VERSION"
	printf 'max_standby_streaming_delay_ms=%s\nhot_standby_feedback=%s\n' "$DELAY_MS" "$FEEDBACK"
} >"$OUT/run.txt"

note "Connected to the $ROLE as $DB_USER (superuser=$IS_SUPER, read_all_stats=$CAN_STATS)"
if [ "$IS_SUPER" != t ] && [ "$CAN_STATS" != t ]; then
	note "WARNING: $DB_USER is neither a superuser nor in pg_read_all_stats; other roles'"
	note "         queries will be hidden."
fi
[ -n "$PSS_SCHEMA" ] || note "NOTE: no pg_stat_statements in this database; skipping it"

# -----------------------------------------------------------------------------
# The SQL. Each statement is kept in the output as sql/NAME.sql, so the results
# can be read next to exactly what produced them.
# -----------------------------------------------------------------------------

cat >"$OUT/sql/session.sql" <<'SQL'
SET application_name = 'replica-conflicts-collect';
SET timezone = 'UTC';
SET search_path = pg_catalog;
SET statement_timeout = :'stmt_timeout';
SET lock_timeout = '5s';
SET default_transaction_read_only = on;
SQL

cat >"$OUT/sql/context.sql" <<'SQL'
\echo == session
SELECT clock_timestamp() AS now_utc, current_user, current_database() AS db
	, pg_is_in_recovery() AS in_recovery
	, (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) AS superuser
	, pg_has_role(current_user, 'pg_read_all_stats', 'USAGE') AS read_all_stats
	, pg_postmaster_start_time() AS server_started
	, (SELECT stats_reset FROM pg_stat_database WHERE datname = current_database()) AS stats_reset;
SELECT version();

\echo == extensions
SELECT e.extname, e.extversion, n.nspname AS schema
FROM pg_extension e
INNER JOIN pg_namespace n ON n.oid = e.extnamespace
ORDER BY e.extname;

\echo == settings (reset_val is the value from before the SETs this script makes, which show as source session)
SELECT name, setting, unit, source, reset_val
FROM pg_settings
WHERE name IN ('hot_standby', 'hot_standby_feedback', 'max_standby_streaming_delay'
		, 'max_standby_archive_delay', 'wal_receiver_status_interval', 'wal_receiver_timeout'
		, 'wal_retrieve_retry_interval', 'recovery_min_apply_delay', 'recovery_prefetch'
		, 'primary_slot_name', 'wal_level', 'max_wal_senders', 'max_replication_slots'
		, 'wal_keep_size', 'max_slot_wal_keep_size', 'synchronous_commit'
		, 'synchronous_standby_names', 'wal_sender_timeout', 'track_commit_timestamp'
		, 'deadlock_timeout', 'log_recovery_conflict_waits', 'log_lock_waits'
		, 'log_min_error_statement', 'log_min_duration_statement', 'log_autovacuum_min_duration'
		, 'log_destination', 'logging_collector', 'log_line_prefix', 'log_error_verbosity'
		, 'lc_messages', 'syslog_ident', 'statement_timeout', 'lock_timeout'
		, 'idle_in_transaction_session_timeout', 'transaction_timeout', 'idle_session_timeout'
		, 'shared_buffers', 'max_connections', 'checkpoint_timeout', 'max_wal_size'
		, 'compute_query_id', 'track_activity_query_size', 'track_io_timing'
		, 'default_transaction_isolation', 'temp_tablespaces'
		, 'pg_stat_statements.max', 'pg_stat_statements.track')
	OR name ~ '^(autovacuum|vacuum)_'
	OR name = 'autovacuum'
	OR (name LIKE 'timescaledb.%' AND source <> 'default')
ORDER BY name;

\echo == settings made for a role or database
SELECT r.rolname, d.datname, s.setconfig
FROM pg_db_role_setting s
LEFT JOIN pg_roles r ON r.oid = s.setrole
LEFT JOIN pg_database d ON d.oid = s.setdatabase
ORDER BY 1, 2;

\echo == tables and indexes with storage parameters (vacuum_truncate, autovacuum_*, ...)
SELECT c.oid::regclass AS relation, c.relkind, c.reloptions
FROM pg_class c
INNER JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.reloptions IS NOT NULL
	AND n.nspname NOT IN ('pg_catalog', 'information_schema', '_timescaledb_internal')
ORDER BY 1
LIMIT 300;

\echo == chunks with storage parameters, by parameters
SELECT c.reloptions, c.relkind, count(*) AS relations, min(c.oid::regclass::text) AS example
FROM pg_class c
INNER JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.reloptions IS NOT NULL
	AND n.nspname = '_timescaledb_internal'
GROUP BY 1, 2
ORDER BY 3 DESC;

\if :is_replica
\echo == queries cancelled by recovery conflicts since the statistics were reset
SELECT c.datname
	, d.stats_reset
	, d.conflicts AS total
	, c.confl_snapshot AS snapshot
	, c.confl_lock AS lock
	, c.confl_bufferpin AS bufferpin
	, c.confl_deadlock AS deadlock
	, c.confl_tablespace AS tablespace
	, (to_jsonb(c) ->> 'confl_active_logicalslot')::bigint AS logicalslot
FROM pg_stat_database_conflicts c
INNER JOIN pg_stat_database d ON d.datid = c.datid
WHERE d.conflicts > 0 OR c.datname = current_database()
ORDER BY d.conflicts DESC, c.datname;

\echo == WAL receiver
SELECT pid, status, receive_start_lsn, receive_start_tli, written_lsn, flushed_lsn, received_tli
	, last_msg_send_time, last_msg_receipt_time, latest_end_lsn, latest_end_time, slot_name
	, sender_host, sender_port
FROM pg_stat_wal_receiver;

SELECT current_setting('server_version_num')::int >= 150000 AS have_prefetch \gset
\if :have_prefetch
\echo == recovery prefetch
SELECT * FROM pg_stat_recovery_prefetch;
\endif

\echo == replay
SELECT pg_get_wal_replay_pause_state() AS pause_state
	, pg_last_wal_receive_lsn() AS received
	, pg_last_wal_replay_lsn() AS replayed
	, pg_last_xact_replay_timestamp() AS last_replayed_commit;
\else
\echo == replication
SELECT pid, usename, application_name, client_addr, state, sync_state, sent_lsn, write_lsn
	, flush_lsn, replay_lsn, write_lag, flush_lag, replay_lag, backend_xmin, reply_time
FROM pg_stat_replication;

\echo == replication slots
SELECT slot_name, slot_type, active, active_pid, xmin, catalog_xmin, restart_lsn
	, confirmed_flush_lsn, wal_status, safe_wal_size
FROM pg_replication_slots;

\echo == prepared transactions
SELECT count(*) AS prepared, min(prepared) AS oldest FROM pg_prepared_xacts;
\endif

\if :have_tsdb
\echo == TimescaleDB jobs
SELECT j.job_id, j.application_name, j.proc_schema || '.' || j.proc_name AS proc
	, j.schedule_interval, j.max_runtime, j.scheduled
	, j.hypertable_schema || '.' || j.hypertable_name AS hypertable, j.config
FROM timescaledb_information.jobs j
ORDER BY j.job_id;
\endif
SQL

# every chunk, to count each one under its hypertable in the summary
cat >"$OUT/sql/chunks.sql" <<'SQL'
SELECT c.chunk_schema, c.chunk_name, c.hypertable_schema, c.hypertable_name
	, c.range_start, c.range_end, c.chunk_tablespace
FROM timescaledb_information.chunks c
ORDER BY c.hypertable_schema, c.hypertable_name, c.range_start;
SQL

cat >"$OUT/sql/snap-database.sql" <<'SQL'
SELECT statement_timestamp() AS snap_ts
	, round(EXTRACT(epoch FROM statement_timestamp()), 3) AS snap_epoch
	, d.*
FROM pg_stat_database d;
SQL

cat >"$OUT/sql/snap-tables.sql" <<'SQL'
SELECT statement_timestamp() AS snap_ts
	, round(EXTRACT(epoch FROM statement_timestamp()), 3) AS snap_epoch
	, t.*
FROM pg_stat_user_tables t;
SQL

# the first snapshot leaves out the statement text, which the second has
cat >"$OUT/sql/snap-pss-notext.sql" <<'SQL'
SELECT statement_timestamp() AS snap_ts, s.* FROM :"pss_schema".pg_stat_statements(false) s;
SQL

cat >"$OUT/sql/snap-pss-text.sql" <<'SQL'
SELECT statement_timestamp() AS snap_ts, s.* FROM :"pss_schema".pg_stat_statements s;
SQL

cat >"$OUT/sql/snap-pss-info.sql" <<'SQL'
SELECT statement_timestamp() AS snap_ts, i.* FROM :"pss_schema".pg_stat_statements_info i;
SQL

cat >"$OUT/sql/snap-jobs.sql" <<'SQL'
SELECT statement_timestamp() AS snap_ts
	, round(EXTRACT(epoch FROM statement_timestamp()), 3) AS snap_epoch
	, j.application_name, j.proc_name, s.*
FROM timescaledb_information.job_stats s
LEFT JOIN timescaledb_information.jobs j ON j.job_id = s.job_id
ORDER BY s.job_id;
SQL

cat >"$OUT/sql/snap-io.sql" <<'SQL'
SELECT statement_timestamp() AS snap_ts, i.* FROM pg_stat_io i;
SQL

cat >"$OUT/sql/snap-conflicts.sql" <<'SQL'
SELECT statement_timestamp() AS snap_ts, c.* FROM pg_stat_database_conflicts c;
SQL

cat >"$OUT/sql/snap-wal-receiver.sql" <<'SQL'
SELECT statement_timestamp() AS snap_ts
	, pid, status, receive_start_lsn, written_lsn, flushed_lsn, received_tli, last_msg_send_time
	, last_msg_receipt_time, latest_end_lsn, latest_end_time, slot_name, sender_host, sender_port
	, pg_last_wal_replay_lsn() AS replay_lsn
	, pg_last_xact_replay_timestamp() AS last_replayed_commit
FROM pg_stat_wal_receiver;
SQL

cat >"$OUT/sql/snap-wal.sql" <<'SQL'
SELECT statement_timestamp() AS snap_ts, pg_current_wal_lsn() AS wal_lsn, w.* FROM pg_stat_wal w;
SQL

cat >"$OUT/sql/snap-replication.sql" <<'SQL'
SELECT statement_timestamp() AS snap_ts, r.* FROM pg_stat_replication r;
SQL

cat >"$OUT/sql/snap-slots.sql" <<'SQL'
SELECT statement_timestamp() AS snap_ts, s.* FROM pg_replication_slots s;
SQL

# One sample on the replica. Each section starts with an ==NAME line, which
# splits it out into samples/NAME.csv.
#
#   startup   one row: replay's progress and what it waits on; the lock it
#             waits for (if any) and the sessions holding locks on that
#             relation; the conflict counts so far; the oldest snapshot held
#   sessions  each client session in a transaction that has run at least
#             :min_age seconds, which is what a conflict cancels
cat >"$OUT/sql/sample-replica.sql" <<'SQL'
\echo ==startup
WITH st AS (
	SELECT a.pid, a.wait_event_type, a.wait_event
	FROM pg_stat_activity a
	WHERE a.backend_type = 'startup'
)
, lk AS MATERIALIZED (
	SELECT l.pid, l.granted, l.mode, l.database, l.relation, l.waitstart
	FROM pg_locks l
	WHERE l.locktype = 'relation'
)
, w AS (
	SELECT lk.database, lk.relation, lk.waitstart
	FROM lk
	INNER JOIN st ON st.pid = lk.pid
	WHERE NOT lk.granted
	LIMIT 1
)
, h AS (
	SELECT string_agg(DISTINCT lk.pid::text, ' ') AS holders
	FROM lk
	INNER JOIN w ON w.relation = lk.relation AND w.database IS NOT DISTINCT FROM lk.database
	WHERE lk.granted
)
, ael AS (
	SELECT count(*) AS held
	FROM lk
	INNER JOIN st ON st.pid = lk.pid
	WHERE lk.granted AND lk.mode = 'AccessExclusiveLock'
)
, ael_rels AS (
	SELECT string_agg(r.rel, ' ') AS rels
	FROM (
		SELECT lk.relation::regclass::text AS rel
		FROM lk
		INNER JOIN st ON st.pid = lk.pid
		WHERE lk.granted AND lk.mode = 'AccessExclusiveLock'
			AND lk.database = (SELECT oid FROM pg_database WHERE datname = current_database())
		ORDER BY lk.relation
		LIMIT 5
	) r
)
, cs AS (
	SELECT count(*) FILTER (WHERE a.state = 'active') AS active
		, count(*) FILTER (WHERE a.state LIKE 'idle in transaction%') AS idle_in_xact
		, count(*) FILTER (WHERE a.wait_event_type = 'Lock') AS waiting_lock
		, max(statement_timestamp() - a.xact_start) FILTER (WHERE a.backend_xmin IS NOT NULL)
			AS oldest_snapshot
		, max(age(a.backend_xmin)) AS oldest_xmin_age
	FROM pg_stat_activity a
	WHERE a.backend_type = 'client backend'
		AND a.pid <> pg_backend_pid()
)
, c AS (
	SELECT c.confl_snapshot, c.confl_lock, c.confl_bufferpin, c.confl_deadlock, c.confl_tablespace
		, (to_jsonb(c) ->> 'confl_active_logicalslot')::bigint AS confl_active_logicalslot
	FROM pg_stat_database_conflicts c
	WHERE c.datname = current_database()
)
, r AS (
	SELECT r.status, r.last_msg_receipt_time
	FROM pg_stat_wal_receiver r
)
SELECT :round AS round
	, statement_timestamp() AS sample_ts
	, round(EXTRACT(epoch FROM statement_timestamp()), 3) AS sample_epoch
	, pg_last_wal_receive_lsn() AS receive_lsn
	, pg_last_wal_replay_lsn() AS replay_lsn
	, pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()) AS replay_behind_bytes
	, round(EXTRACT(epoch FROM statement_timestamp() - pg_last_xact_replay_timestamp()), 1)
		AS replay_age_s
	, pg_get_wal_replay_pause_state() AS pause_state
	, (SELECT r.status FROM r) AS receiver_status
	, round(EXTRACT(epoch FROM statement_timestamp() - (SELECT r.last_msg_receipt_time FROM r)), 1)
		AS receipt_age_s
	, pg_snapshot_xmax(pg_current_snapshot())::text::bigint AS next_xid
	, (SELECT st.pid FROM st) AS startup_pid
	, (SELECT st.wait_event_type FROM st) AS startup_wait_type
	, (SELECT st.wait_event FROM st) AS startup_wait
	, round(EXTRACT(epoch FROM statement_timestamp() - (SELECT w.waitstart FROM w)), 1) AS lock_wait_s
	, c.confl_snapshot
	, c.confl_lock
	, c.confl_bufferpin
	, c.confl_deadlock
	, c.confl_tablespace
	, c.confl_active_logicalslot
	, cs.active AS sessions_active
	, cs.idle_in_xact AS sessions_idle_in_xact
	, cs.waiting_lock AS sessions_waiting_lock
	, round(EXTRACT(epoch FROM cs.oldest_snapshot), 1) AS oldest_snapshot_s
	, cs.oldest_xmin_age
	, (SELECT ael.held FROM ael) AS startup_ael_held
	, (SELECT w.relation::regclass::text FROM w) AS lock_wait_rel
	, (SELECT h.holders FROM h) AS lock_wait_holders
	, (SELECT ael_rels.rels FROM ael_rels) AS startup_ael_rels
FROM cs
LEFT JOIN c ON TRUE;

\echo ==sessions
WITH lk AS (
	SELECT l.pid, count(*) AS rel_locks
	FROM pg_locks l
	WHERE l.locktype = 'relation' AND l.granted
	GROUP BY l.pid
)
SELECT :round AS round
	, statement_timestamp() AS sample_ts
	, round(EXTRACT(epoch FROM statement_timestamp()), 3) AS sample_epoch
	, a.pid
	, round(EXTRACT(epoch FROM a.xact_start), 3) AS xact_start_epoch
	, round(EXTRACT(epoch FROM statement_timestamp() - a.xact_start), 1) AS xact_age_s
	, round(EXTRACT(epoch FROM statement_timestamp() - a.query_start), 1) AS query_age_s
	, a.state
	, a.wait_event_type
	, a.wait_event
	, a.backend_xmin
	, age(a.backend_xmin) AS xmin_age
	, COALESCE(lk.rel_locks, 0) AS rel_locks
	, a.query_id
	, a.usename
	, a.client_addr
	, a.backend_start
	, a.xact_start
	, a.query_start
	, translate(a.application_name, ',', ' ') AS application_name
	, left(regexp_replace(a.query, '\s+', ' ', 'g'), 240) AS query
FROM pg_stat_activity a
LEFT JOIN lk ON lk.pid = a.pid
WHERE a.backend_type = 'client backend'
	AND a.pid <> pg_backend_pid()
	AND a.state <> 'idle'
	AND a.xact_start <= statement_timestamp() - make_interval(secs => :min_age)
ORDER BY a.xact_start;
SQL

# One sample on the primary.
#
#   horizon   one row: the oldest snapshot or transaction ID held, other than by
#             a VACUUM (whose own snapshot holds nothing back) or a walsender
#             (whose snapshot is a replica's feedback, counted apart); slots,
#             prepared transactions; replication lag
#   holders   the sessions holding a snapshot or transaction ID in a
#             transaction that has run at least :min_age seconds
#   ael       ACCESS EXCLUSIVE locks held or wanted on relations other than
#             temporary ones (at most 200): each is replayed on the replica
#   progress  VACUUM, ANALYZE, CLUSTER, VACUUM FULL, CREATE INDEX and REINDEX
#             in progress
cat >"$OUT/sql/sample-primary.sql" <<'SQL'
\echo ==horizon
WITH v AS (
	SELECT p.pid FROM pg_stat_progress_vacuum p
)
, b AS (
	SELECT a.pid, a.backend_type, a.usename, a.application_name, a.state, a.xact_start
		, a.query_start, a.backend_xmin, a.backend_xid, a.query
		, GREATEST(age(a.backend_xmin), age(a.backend_xid)) AS xid_age
		, a.pid IN (SELECT v.pid FROM v) AS in_vacuum
	FROM pg_stat_activity a
	WHERE (a.backend_xmin IS NOT NULL OR a.backend_xid IS NOT NULL)
		AND a.pid <> pg_backend_pid()
		AND a.backend_type <> 'walsender'
)
, o AS (
	SELECT b.*
	FROM b
	WHERE NOT b.in_vacuum
	ORDER BY b.xid_age DESC, b.xact_start
	LIMIT 1
)
, ws AS (
	SELECT max(age(r.backend_xmin)) AS xmin_age
		, max(EXTRACT(epoch FROM r.replay_lag)) AS replay_lag_s
		, max(pg_wal_lsn_diff(pg_current_wal_lsn(), r.replay_lsn)) AS replay_behind_bytes
		, count(*) AS replicas
	FROM pg_stat_replication r
)
, sl AS (
	SELECT max(GREATEST(age(s.xmin), age(s.catalog_xmin))) AS xmin_age
	FROM pg_replication_slots s
)
, px AS (
	SELECT count(*) AS n, min(p.prepared) AS oldest
	FROM pg_prepared_xacts p
)
SELECT :round AS round
	, statement_timestamp() AS sample_ts
	, round(EXTRACT(epoch FROM statement_timestamp()), 3) AS sample_epoch
	, pg_current_wal_lsn() AS wal_lsn
	, pg_snapshot_xmax(pg_current_snapshot())::text::bigint AS next_xid
	, (SELECT count(*) FROM b) AS holders
	, (SELECT count(*) FROM b WHERE b.in_vacuum) AS holders_in_vacuum
	, o.xid_age AS oldest_xid_age
	, round(EXTRACT(epoch FROM statement_timestamp() - o.xact_start), 1) AS oldest_xact_s
	, round(EXTRACT(epoch FROM statement_timestamp() - o.query_start), 1) AS oldest_query_s
	, ws.xmin_age AS walsender_xmin_age
	, sl.xmin_age AS slot_xmin_age
	, px.n AS prepared
	, round(EXTRACT(epoch FROM statement_timestamp() - px.oldest), 1) AS prepared_oldest_s
	, ws.replicas
	, round(ws.replay_lag_s, 1) AS replay_lag_s
	, ws.replay_behind_bytes
	, o.pid AS oldest_pid
	, o.backend_type AS oldest_backend_type
	, o.usename AS oldest_usename
	, o.state AS oldest_state
	, translate(o.application_name, ',', ' ') AS oldest_application_name
	, left(regexp_replace(o.query, '\s+', ' ', 'g'), 160) AS oldest_query
FROM ws
CROSS JOIN sl
CROSS JOIN px
LEFT JOIN o ON TRUE;

\echo ==holders
SELECT :round AS round
	, statement_timestamp() AS sample_ts
	, round(EXTRACT(epoch FROM statement_timestamp()), 3) AS sample_epoch
	, a.pid
	, round(EXTRACT(epoch FROM a.xact_start), 3) AS xact_start_epoch
	, round(EXTRACT(epoch FROM statement_timestamp() - a.xact_start), 1) AS xact_age_s
	, round(EXTRACT(epoch FROM statement_timestamp() - a.query_start), 1) AS query_age_s
	, GREATEST(age(a.backend_xmin), age(a.backend_xid)) AS xid_age
	, EXISTS (SELECT 1 FROM pg_stat_progress_vacuum p WHERE p.pid = a.pid) AS in_vacuum
	, a.state
	, a.backend_type
	, a.wait_event_type
	, a.wait_event
	, a.query_id
	, a.usename
	, translate(a.application_name, ',', ' ') AS application_name
	, left(regexp_replace(a.query, '\s+', ' ', 'g'), 240) AS query
FROM pg_stat_activity a
WHERE (a.backend_xmin IS NOT NULL OR a.backend_xid IS NOT NULL)
	AND a.pid <> pg_backend_pid()
	AND a.backend_type <> 'walsender'
	AND a.xact_start <= statement_timestamp() - make_interval(secs => :min_age)
ORDER BY a.xact_start
LIMIT 20;

\echo ==ael
SELECT :round AS round
	, statement_timestamp() AS sample_ts
	, round(EXTRACT(epoch FROM statement_timestamp()), 3) AS sample_epoch
	, l.pid
	, l.granted
	, l.relation
	, c.relkind
	, round(EXTRACT(epoch FROM statement_timestamp() - a.xact_start), 1) AS xact_age_s
	, a.backend_type
	, a.usename
	, CASE WHEN c.oid IS NULL THEN l.relation::text ELSE c.oid::regclass::text END AS relname
	, COALESCE((SELECT i.indrelid::regclass::text FROM pg_index i WHERE i.indexrelid = c.oid)
		, (SELECT t.oid::regclass::text FROM pg_class t WHERE c.relkind = 't' AND t.reltoastrelid = c.oid)
		, c.oid::regclass::text, l.relation::text) AS tbl
	, translate(a.application_name, ',', ' ') AS application_name
	, left(regexp_replace(a.query, '\s+', ' ', 'g'), 160) AS query
FROM pg_locks l
LEFT JOIN pg_class c ON c.oid = l.relation
LEFT JOIN pg_stat_activity a ON a.pid = l.pid
WHERE l.locktype = 'relation'
	AND l.mode = 'AccessExclusiveLock'
	AND l.database = (SELECT oid FROM pg_database WHERE datname = current_database())
	AND c.relpersistence IS DISTINCT FROM 't'
ORDER BY l.pid, l.relation
LIMIT 200;

\echo ==progress
SELECT :round AS round
	, statement_timestamp() AS sample_ts
	, round(EXTRACT(epoch FROM statement_timestamp()), 3) AS sample_epoch
	, p.kind
	, p.pid
	, a.backend_type
	, p.phase
	, p.blocks_total
	, p.blocks_done
	, round(EXTRACT(epoch FROM statement_timestamp() - a.xact_start), 1) AS xact_age_s
	, CASE WHEN c.oid IS NULL THEN p.relid::text ELSE c.oid::regclass::text END AS relname
FROM (
	SELECT 'vacuum' AS kind, v.pid, v.relid, v.phase, v.heap_blks_total AS blocks_total
		, v.heap_blks_scanned AS blocks_done
	FROM pg_stat_progress_vacuum v
	WHERE v.datname = current_database()
	UNION ALL
	SELECT 'analyze', n.pid, n.relid, n.phase, n.sample_blks_total, n.sample_blks_scanned
	FROM pg_stat_progress_analyze n
	WHERE n.datname = current_database()
	UNION ALL
	SELECT lower(k.command), k.pid, k.relid, k.phase, k.heap_blks_total, k.heap_blks_scanned
	FROM pg_stat_progress_cluster k
	WHERE k.datname = current_database()
	UNION ALL
	SELECT lower(i.command), i.pid, i.relid, i.phase, i.blocks_total, i.blocks_done
	FROM pg_stat_progress_create_index i
	WHERE i.datname = current_database()
) p
LEFT JOIN pg_class c ON c.oid = p.relid
LEFT JOIN pg_stat_activity a ON a.pid = p.pid
ORDER BY p.kind, p.pid;
SQL

# the statements with the longest finished run, from pg_stat_statements
cat >"$OUT/sql/pss-top.sql" <<'SQL'
\echo == statements by the longest run that finished (pg_stat_statements; cancelled runs are not counted)
SELECT s.queryid
	, r.rolname
	, s.calls
	, round((s.mean_exec_time / 1000)::numeric, 2) AS mean_s
	, round((s.stddev_exec_time / 1000)::numeric, 2) AS stddev_s
	, round((s.max_exec_time / 1000)::numeric, 1) AS max_s
	, round((s.total_exec_time / 1000)::numeric) AS total_s
	, round(s.rows::numeric / NULLIF(s.calls, 0)) AS rows_per_call
	, date_trunc('second', (to_jsonb(s) ->> 'minmax_stats_since')::timestamptz) AS max_since
	, left(regexp_replace(s.query, '\s+', ' ', 'g'), 140) AS query
FROM :"pss_schema".pg_stat_statements s
LEFT JOIN pg_roles r ON r.oid = s.userid
WHERE s.dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY s.max_exec_time DESC
LIMIT 25;
SQL

# -----------------------------------------------------------------------------
# The summaries, in awk. Like the SQL, each program is kept in the output.
# -----------------------------------------------------------------------------

cat >"$OUT/awk/lib.awk" <<'AWK'
# csvsplit(s, a) - split the CSV line s into a[1..n] and return n. A quoted
# field may hold commas and doubled quotes, but not a line break.
function csvsplit(s, a,    n, i, c, f, q, len) {
	if (index(s, "\"") == 0)
		return split(s, a, ",")
	split("", a)
	n = 0
	f = ""
	q = 0
	len = length(s)
	for (i = 1; i <= len; i++) {
		c = substr(s, i, 1)
		if (q) {
			if (c == "\"") {
				if (substr(s, i + 1, 1) == "\"") {
					f = f c
					i++
				} else
					q = 0
			} else
				f = f c
		} else if (c == "\"")
			q = 1
		else if (c == ",") {
			a[++n] = f
			f = ""
		} else
			f = f c
	}
	a[++n] = f
	return n
}

# header(s, h) - map each column name of the CSV header line s to its position
function header(s, h,    n, i, t) {
	n = csvsplit(s, t)
	for (i = 1; i <= n; i++)
		h[t[i]] = i
	return n
}

# hsort(a, n) - sort a[1..n] into ascending numeric order (a heap sort)
function hsort(a, n,    i, t) {
	for (i = int(n / 2); i >= 1; i--)
		hsift(a, i, n)
	for (i = n; i > 1; i--) {
		t = a[1]
		a[1] = a[i]
		a[i] = t
		hsift(a, 1, i - 1)
	}
}

function hsift(a, i, n,    c, t) {
	while ((c = 2 * i) <= n) {
		if (c < n && a[c + 1] > a[c])
			c++
		if (a[i] >= a[c])
			return
		t = a[i]
		a[i] = a[c]
		a[c] = t
		i = c
	}
}

# pct(a, n, p) - the p quantile (0 to 1) of the sorted a[1..n]
function pct(a, n, p) {
	if (n == 0)
		return "-"
	return a[int((n - 1) * p + 0.5) + 1]
}

# dist(a, n) - "p50 X  p90 X  p99 X  max X" of the unsorted a[1..n]
function dist(a, n) {
	if (n == 0)
		return "no values"
	hsort(a, n)
	return sprintf("p50 %s  p90 %s  p99 %s  max %s", pct(a, n, 0.5), pct(a, n, 0.9), pct(a, n, 0.99), a[n])
}

# over(a, n, t) - "N (P%)" of the values of a[1..n] at least t
function over(a, n, t,    i, c) {
	c = 0
	for (i = 1; i <= n; i++)
		if (a[i] >= t)
			c++
	return sprintf("%d (%.1f%%)", c, n ? 100 * c / n : 0)
}

function short(s, n) {
	return length(s) > n ? substr(s, 1, n - 3) "..." : s
}

# hyper(name) - the hypertable a chunk belongs to, from chunks.csv, or name
function hyper(name) {
	return (name in CHUNK) ? CHUNK[name] : name
}

# readchunks(f) - load chunks.csv into CHUNK
function readchunks(f,    line, h, a, first) {
	first = 1
	while ((getline line < f) > 0) {
		if (first) {
			header(line, h)
			first = 0
			continue
		}
		csvsplit(line, a)
		CHUNK[a[h["chunk_schema"]] "." a[h["chunk_name"]]] = a[h["hypertable_schema"]] "." a[h["hypertable_name"]]
	}
	close(f)
}

function bytes(b) {
	if (b == "")
		return "-"
	if (b >= 1073741824)
		return sprintf("%.1f GB", b / 1073741824)
	if (b >= 1048576)
		return sprintf("%.1f MB", b / 1048576)
	if (b >= 1024)
		return sprintf("%.1f kB", b / 1024)
	return sprintf("%d B", b)
}
AWK

# The replica's samples: startup.csv, then sessions.csv. -v interval=SECONDS
cat >"$OUT/awk/summary-replica.awk" <<'AWK'
function wait_class(p, t, e) {
	if (p == "")
		return "no startup process"
	if (e == "RecoveryWalStream")
		return "caught up, waiting for WAL"
	if (t == "" && e == "")
		return "busy replaying"
	if (e == "RecoveryConflictSnapshot")
		return "CONFLICT snapshot"
	if (t == "Lock")
		return "CONFLICT lock"
	if (e == "BufferPin")
		return "CONFLICT buffer pin"
	if (e == "RecoveryConflictTablespace")
		return "CONFLICT tablespace"
	return t "/" e
}

# conflicts(i, j) - the conflicts counted from sample i to sample j, as text
function conflicts(i, j,    k, s, d) {
	s = ""
	for (k = 1; k <= nk; k++) {
		d = cv[j, k] - cv[i, k]
		if (d > 0)
			s = s (s == "" ? "" : " ") cn[k] "=" d
	}
	return s == "" ? "none" : s
}

BEGIN {
	nk = split("confl_snapshot confl_lock confl_bufferpin confl_deadlock confl_tablespace confl_active_logicalslot", ck, " ")
	split("snapshot lock bufferpin deadlock tablespace logicalslot", cn, " ")
}

FILENAME == ARGV[1] && FNR == 1 {
	header($0, S)
	next
}

FILENAME == ARGV[1] {
	csvsplit($0, f)
	n++
	rd[n] = f[S["round"]] + 0
	at[rd[n]] = n
	ts[n] = f[S["sample_ts"]]
	ep[n] = f[S["sample_epoch"]] + 0
	for (k = 1; k <= nk; k++)
		cv[n, k] = f[S[ck[k]]] + 0
	cls[n] = wait_class(f[S["startup_pid"]], f[S["startup_wait_type"]], f[S["startup_wait"]])
	# how far behind replay is: none when it has replayed all it has received
	# and waits for more, as the time since the last replayed commit then
	# only says how long ago the primary last committed anything
	behind[++nbehind] = f[S["replay_behind_bytes"]] + 0
	if (cls[n] == "caught up, waiting for WAL" && behind[nbehind] == 0)
		ages[++nages] = 0
	else if (f[S["replay_age_s"]] != "")
		ages[++nages] = f[S["replay_age_s"]] + 0
	snap[n] = f[S["oldest_snapshot_s"]] == "" ? 0 : f[S["oldest_snapshot_s"]] + 0
	snaps[n] = snap[n]
	lw[n] = f[S["lock_wait_s"]]
	lrel[n] = f[S["lock_wait_rel"]]
	lhold[n] = f[S["lock_wait_holders"]]
	wl = f[S["sessions_waiting_lock"]] + 0
	if (wl > 0) {
		wlsamples++
		if (wl > wlmax)
			wlmax = wl
	}
	if (f[S["receiver_status"]] != "streaming")
		notstreaming++
	xid[n] = f[S["next_xid"]] + 0
	next
}

FILENAME == ARGV[2] && FNR == 1 {
	header($0, X)
	next
}

FILENAME == ARGV[2] {
	csvsplit($0, f)
	key = f[X["pid"]] "|" f[X["xact_start_epoch"]]
	r = f[X["round"]] + 0
	if (!(key in tfirst)) {
		tfirst[key] = r
		tts[key] = f[X["xact_start"]]
		nt++
		tk[nt] = key
		tpid[key] = f[X["pid"]]
		tuser[key] = f[X["usename"]]
	}
	tlast[key] = r
	a = f[X["xact_age_s"]] + 0
	if (a > tage[key])
		tage[key] = a
	s = f[X["state"]]
	if (index(" " tstate[key] ",", " " s ",") == 0)
		tstate[key] = tstate[key] (tstate[key] == "" ? "" : ", ") s
	w = f[X["wait_event_type"]] == "" ? "" : f[X["wait_event_type"]] "/" f[X["wait_event"]]
	if (w != "" && index(" " twait[key] ",", " " w ",") == 0)
		twait[key] = twait[key] (twait[key] == "" ? "" : ", ") w
	if (f[X["rel_locks"]] + 0 > tlocks[key])
		tlocks[key] = f[X["rel_locks"]] + 0
	tqid[key] = f[X["query_id"]]
	tq[key] = f[X["query"]]
	next
}

END {
	if (n == 0) {
		print "No replica samples were taken."
		exit
	}
	span = ep[n] - ep[1]
	printf "Samples: %d, from %s to %s (%.0f minutes)\n\n", n, ts[1], ts[n], span / 60

	print "Queries cancelled by conflicts in this database during the samples"
	print "(pg_stat_database_conflicts; the second number is in how many sample"
	print "intervals the count went up):"
	for (k = 1; k <= nk; k++) {
		d = cv[n, k] - cv[1, k]
		up = 0
		for (i = 2; i <= n; i++)
			if (cv[i, k] > cv[i - 1, k])
				up++
		printf "  %-12s %6d  %5d", cn[k], d, up
		if (span > 0)
			printf "   %.1f an hour", d * 3600 / span
		printf "\n"
		total += d
	}
	printf "  %-12s %6d\n\n", "total", total

	print "What replay was doing, by share of samples (the startup process's wait event):"
	for (i = 1; i <= n; i++)
		cc[cls[i]]++
	for (c in cc)
		printf "  %-34s %6d  %5.1f%%\n", c, cc[c], 100 * cc[c] / n | "LC_ALL=C sort"
	close("LC_ALL=C sort")
	print ""

	print "How far behind replay was, in seconds: the time since the last replayed commit,"
	print "or 0 when replay had caught up with the WAL received:"
	printf "  %s\n", dist(ages, nages)
	printf "  samples at least 5 s: %s, 30 s: %s, 60 s: %s\n", over(ages, nages, 5), over(ages, nages, 30), over(ages, nages, 60)
	printf "Received WAL not yet replayed: max %s\n", bytes(dist_max(behind, nbehind))
	if (notstreaming)
		printf "Samples with the WAL receiver not streaming: %d\n", notstreaming
	if (wlsamples)
		printf "Samples with sessions waiting on a lock: %d (at most %d at once)\n", wlsamples, wlmax
	print ""

	# runs of consecutive samples with replay waiting on the same kind of conflict
	ne = 0
	for (i = 1; i <= n; i++) {
		if (cls[i] !~ /^CONFLICT/)
			continue
		if (ne > 0 && eend[ne] == i - 1 && rd[i] == rd[i - 1] + 1 && ecls[ne] == cls[i]) {
			eend[ne] = i
		} else {
			ne++
			estart[ne] = i
			eend[ne] = i
			ecls[ne] = cls[i]
			elw[ne] = 0
		}
		if (lw[i] != "" && lw[i] + 0 >= elw[ne]) {
			elw[ne] = lw[i] + 0
			erel[ne] = lrel[i]
			ehold[ne] = lhold[i]
		}
	}
	print "Replay held up by a conflict: runs of samples in which replay waited on the"
	print "same kind of conflict, longest first. \"seen\" is from the first sample to the"
	print "last, so the wait began and ended up to one interval either side; for a lock,"
	print "\"waited\" is how long replay had waited for it by the last sample."
	if (ne == 0)
		print "  none seen"
	for (e = 1; e <= ne; e++) {
		elen[e] = ep[eend[e]] - ep[estart[e]]
		ord[e] = e
	}
	# longest first: a simple selection, as there are few
	for (i = 1; i <= ne; i++)
		for (j = i + 1; j <= ne; j++)
			if (elen[ord[j]] > elen[ord[i]]) {
				t = ord[i]
				ord[i] = ord[j]
				ord[j] = t
			}
	for (i = 1; i <= ne && i <= 25; i++) {
		e = ord[i]
		a = estart[e] > 1 ? estart[e] - 1 : estart[e]
		b = eend[e] < n ? eend[e] + 1 : eend[e]
		printf "  %s  %-20s seen %4.0fs", ts[estart[e]], ecls[e], elen[e]
		if (elw[e] > 0)
			printf "  waited %4.0fs on %s, held by %s", elw[e], erel[e], (ehold[e] == "" ? "-" : ehold[e])
		printf "  counted: %s\n", conflicts(a, b)
	}
	if (ne > 25)
		printf "  ... and %d more\n", ne - 25
	for (e = 1; e <= ne; e++) {
		ecount[ecls[e]]++
		esecs[ecls[e]] += elen[e] + interval
	}
	for (c in ecount)
		printf "  %s: %d runs, about %.0f s in all\n", c, ecount[c], esecs[c] | "LC_ALL=C sort"
	close("LC_ALL=C sort")
	print ""

	print "The oldest snapshot held by a client session on the replica, each sample, in"
	print "seconds. With hot_standby_feedback on, the primary would keep the row versions"
	print "this snapshot can see:"
	printf "  %s\n", dist(snaps, n)
	printf "  samples at least 60 s: %s, 300 s: %s, 600 s: %s\n", over(snaps, n, 60), over(snaps, n, 300), over(snaps, n, 600)
	if (span > 0 && xid[n] > xid[1])
		printf "  transaction IDs used on the primary: %.1f a second\n", (xid[n] - xid[1]) / span
	print ""

	printf "Client transactions seen running at least %s s (from samples/sessions.csv), by\n", min_age
	print "how long they were seen to run. \"ended\" says what was counted in the interval"
	print "in which each one ended: a conflict counted then is likely to have cancelled it."
	split("10 30 60 120 300 600 1800", lim, " ")
	for (l = 1; l <= 7; l++) {
		c = 0
		for (i = 1; i <= nt; i++)
			if (tage[tk[i]] >= lim[l])
				c++
		printf "  at least %5d s: %d\n", lim[l], c
	}
	for (i = 1; i <= nt; i++)
		tord[i] = tk[i]
	for (i = 1; i <= nt && i <= 30; i++)
		for (j = i + 1; j <= nt; j++)
			if (tage[tord[j]] > tage[tord[i]]) {
				t = tord[i]
				tord[i] = tord[j]
				tord[j] = t
			}
	if (nt > 0) {
		print ""
		print "  The longest 30:"
		printf "  %-19s %7s %7s %-10s %-28s %s\n", "xact_start", "seen_s", "pid", "user", "ended", "state, waits, locks, query_id, query"
	}
	for (i = 1; i <= nt && i <= 30; i++) {
		key = tord[i]
		r = tlast[key]
		if (r >= rd[n])
			ended = "still running at the end"
		else if ((r in at) && ((r + 1) in at))
			ended = conflicts(at[r], at[r + 1])
		else
			ended = "?"
		printf "  %-19s %7.0f %7s %-10s %-28s %s; %s; %d locks; %s; %s\n", substr(tts[key], 1, 19), tage[key], tpid[key], short(tuser[key], 10), short(ended, 28), tstate[key], (twait[key] == "" ? "no waits" : twait[key]), tlocks[key], tqid[key], short(tq[key], 100)
	}
}

function dist_max(a, m,    i, x) {
	x = ""
	for (i = 1; i <= m; i++)
		if (x == "" || a[i] > x)
			x = a[i]
	return x
}
AWK

# The primary's samples: horizon.csv, then holders.csv. -v min_age=SECONDS
cat >"$OUT/awk/summary-horizon.awk" <<'AWK'
FILENAME == ARGV[1] && FNR == 1 {
	header($0, H)
	next
}

FILENAME == ARGV[1] {
	csvsplit($0, f)
	n++
	ts[n] = f[H["sample_ts"]]
	ep[n] = f[H["sample_epoch"]] + 0
	xid[n] = f[H["next_xid"]] + 0
	hx[n] = f[H["oldest_xact_s"]] == "" ? 0 : f[H["oldest_xact_s"]] + 0
	ha[n] = f[H["oldest_xid_age"]] == "" ? 0 : f[H["oldest_xid_age"]] + 0
	if (f[H["walsender_xmin_age"]] != "")
		feedback++
	if (f[H["slot_xmin_age"]] != "")
		slotx++
	if (f[H["replay_lag_s"]] != "")
		lag[++nlag] = f[H["replay_lag_s"]] + 0
	if (f[H["replay_behind_bytes"]] != "")
		behind[++nbehind] = f[H["replay_behind_bytes"]] + 0
	if (f[H["prepared"]] + 0 > 0)
		prepared++
	next
}

FILENAME == ARGV[2] && FNR == 1 {
	header($0, X)
	next
}

FILENAME == ARGV[2] {
	csvsplit($0, f)
	key = f[X["pid"]] "|" f[X["xact_start_epoch"]]
	if (!(key in seen)) {
		seen[key] = 0
		nt++
		tk[nt] = key
		tpid[key] = f[X["pid"]]
		ttype[key] = f[X["backend_type"]]
		tuser[key] = f[X["usename"]]
		tapp[key] = f[X["application_name"]]
	}
	seen[key]++
	a = f[X["xact_age_s"]] + 0
	if (a > tage[key])
		tage[key] = a
	if (f[X["xid_age"]] + 0 > txid[key])
		txid[key] = f[X["xid_age"]] + 0
	if (f[X["in_vacuum"]] == "t")
		tvac[key] = 1
	tq[key] = f[X["query"]]
	next
}

END {
	if (n == 0) {
		print "No primary samples were taken."
		exit
	}
	span = ep[n] - ep[1]
	printf "Samples: %d, from %s to %s (%.0f minutes)\n\n", n, ts[1], ts[n], span / 60

	print "How far back the primary's own work held the xmin horizon, each sample: the"
	print "oldest snapshot or transaction ID held by a session other than a VACUUM or a"
	print "walsender. With hot_standby_feedback on, the replica's oldest snapshot costs"
	print "the primary something only when it is older than this."
	for (i = 1; i <= n; i++) {
		t1[i] = hx[i]
		t2[i] = ha[i]
	}
	printf "  age of that transaction, seconds:  %s\n", dist(t1, n)
	printf "  samples at least 60 s: %s, 300 s: %s, 600 s: %s\n", over(hx, n, 60), over(hx, n, 300), over(hx, n, 600)
	printf "  age in transaction IDs:           %s\n", dist(t2, n)
	if (span > 0 && xid[n] > xid[1])
		printf "  transaction IDs used: %.1f a second\n", (xid[n] - xid[1]) / span
	printf "  samples with a walsender holding a snapshot (hot_standby_feedback without a slot): %d\n", feedback
	printf "  samples with a replication slot holding an xmin (feedback through a slot): %d\n", slotx
	if (prepared)
		printf "  samples with prepared transactions: %d\n", prepared
	print ""
	printf "Replication lag reported by the replica, seconds: %s\n", dist(lag, nlag)
	printf "WAL not yet replayed by the replica, bytes: %s\n\n", dist(behind, nbehind)

	printf "Transactions holding a snapshot or transaction ID for at least %s s, longest\n", min_age
	print "first (from samples/holders.csv); a VACUUM's snapshot holds nothing back:"
	for (i = 1; i <= nt; i++)
		ord[i] = tk[i]
	for (i = 1; i <= nt && i <= 30; i++)
		for (j = i + 1; j <= nt; j++)
			if (tage[ord[j]] > tage[ord[i]]) {
				t = ord[i]
				ord[i] = ord[j]
				ord[j] = t
			}
	if (nt == 0)
		print "  none seen"
	else
		printf "  %7s %7s %8s %-24s %-12s %s\n", "seen_s", "pid", "xid_age", "backend_type", "user", "application: query"
	for (i = 1; i <= nt && i <= 30; i++) {
		key = ord[i]
		printf "  %7.0f %7s %8d %-24s %-12s %s%s: %s\n", tage[key], tpid[key], txid[key], short(ttype[key], 24), short(tuser[key], 12), tvac[key] ? "[VACUUM] " : "", tapp[key], short(tq[key], 110)
	}
}
AWK

# Table statistics from the two snapshots: chunks.csv, snap1 and snap2
# tables.csv. -v mode=write (the primary: rows changed) or mode=read (the
# replica: rows read)
cat >"$OUT/awk/summary-tables.awk" <<'AWK'
BEGIN {
	readchunks(ARGV[1])
	ARGV[1] = ""
}

FNR == 1 {
	file++
	split("", h)
	header($0, h)
	next
}

{
	csvsplit($0, f)
	rel = f[h["relid"]]
	g = hyper(f[h["schemaname"]] "." f[h["relname"]])
	# TimescaleDB's own tables, read on the replica in planning queries
	if (mode == "read" && g ~ /^_timescaledb_/)
		next
	if (file == 1) {
		e1 = f[h["snap_epoch"]] + 0
		b_ins[rel] = f[h["n_tup_ins"]] + 0
		b_upd[rel] = f[h["n_tup_upd"]] + 0
		b_hot[rel] = f[h["n_tup_hot_upd"]] + 0
		b_del[rel] = f[h["n_tup_del"]] + 0
		b_av[rel] = f[h["autovacuum_count"]] + 0
		b_v[rel] = f[h["vacuum_count"]] + 0
		b_seq[rel] = f[h["seq_scan"]] + 0
		b_seqr[rel] = f[h["seq_tup_read"]] + 0
		b_idx[rel] = f[h["idx_scan"]] + 0
		b_idxf[rel] = f[h["idx_tup_fetch"]] + 0
		next
	}
	e2 = f[h["snap_epoch"]] + 0
	if (!(g in gi)) {
		gi[g] = 1
		ng++
		gk[ng] = g
	}
	grels[g]++
	gins[g] += f[h["n_tup_ins"]] - b_ins[rel]
	gupd[g] += f[h["n_tup_upd"]] - b_upd[rel]
	ghot[g] += f[h["n_tup_hot_upd"]] - b_hot[rel]
	gdel[g] += f[h["n_tup_del"]] - b_del[rel]
	gav[g] += f[h["autovacuum_count"]] - b_av[rel]
	gv[g] += f[h["vacuum_count"]] - b_v[rel]
	gdead[g] += f[h["n_dead_tup"]]
	gseq[g] += f[h["seq_scan"]] - b_seq[rel]
	gseqr[g] += f[h["seq_tup_read"]] - b_seqr[rel]
	gidx[g] += f[h["idx_scan"]] - b_idx[rel]
	gidxf[g] += f[h["idx_tup_fetch"]] - b_idxf[rel]
}

END {
	secs = e2 - e1
	if (file < 2 || secs <= 0) {
		print "The table statistics need both snapshots."
		exit
	}
	for (i = 1; i <= ng; i++) {
		g = gk[i]
		key[i] = mode == "read" ? gseqr[g] + gidxf[g] : gupd[g] + gdel[g]
		ord[i] = i
		all += key[i]
	}
	for (i = 1; i <= ng && i <= 25; i++)
		for (j = i + 1; j <= ng; j++)
			if (key[ord[j]] > key[ord[i]]) {
				t = ord[i]
				ord[i] = ord[j]
				ord[j] = t
			}
	if (mode == "read") {
		printf "Rows read on the replica in the %.0f s between the snapshots, by table (chunks\n", secs
		print "under their hypertable): the tables its queries hold locks on, which a lock"
		print "replayed from the primary conflicts with."
		printf "  %-46s %6s %10s %12s %10s %12s\n", "table", "rels", "seq_scans", "seq_rows", "idx_scans", "idx_rows"
		for (i = 1; i <= ng && i <= 25; i++) {
			g = gk[ord[i]]
			if (key[ord[i]] <= 0 && gseq[g] + gidx[g] <= 0)
				break
			printf "  %-46s %6d %10d %12d %10d %12d\n", short(g, 46), grels[g], gseq[g], gseqr[g], gidx[g], gidxf[g]
		}
		exit
	}
	printf "Dead row versions made in the %.0f s between the snapshots (n_tup_upd plus\n", secs
	print "n_tup_del), by table, chunks under their hypertable. While the horizon is held"
	print "back an extra T seconds, about dead_per_s * T more of them wait to be removed."
	printf "  %-46s %6s %10s %10s %6s %8s %6s %10s\n", "table", "rels", "dead", "dead_per_s", "hot%", "ins_per_s", "vacs", "dead_now"
	for (i = 1; i <= ng && i <= 25; i++) {
		g = gk[ord[i]]
		if (key[ord[i]] <= 0)
			break
		printf "  %-46s %6d %10d %10.1f %6s %8.1f %6d %10d\n", short(g, 46), grels[g], key[ord[i]], key[ord[i]] / secs, (gupd[g] > 0 ? sprintf("%.0f", 100 * ghot[g] / gupd[g]) : "-"), gins[g] / secs, gav[g] + gv[g], gdead[g]
	}
	printf "  all tables: %.1f dead row versions a second; held back an extra minute, about\n", all / secs
	printf "  %.0f more wait to be removed; ten minutes, %.0f; an hour, %.0f.\n", all / secs * 60, all / secs * 600, all / secs * 3600
}
AWK

# The primary's ACCESS EXCLUSIVE locks and maintenance: chunks.csv, ael.csv,
# progress.csv
cat >"$OUT/awk/summary-locks.awk" <<'AWK'
BEGIN {
	readchunks(ARGV[1])
	ARGV[1] = ""
}

FILENAME == ARGV[2] && FNR == 1 {
	header($0, A)
	next
}

FILENAME == ARGV[2] {
	csvsplit($0, f)
	rel = f[A["relname"]]
	g = hyper(f[A["tbl"]])
	k = g
	if (!(k in ai)) {
		ai[k] = 1
		na++
		ak[na] = k
	}
	r = f[A["round"]]
	if (!((k, r) in ar)) {
		ar[k, r] = 1
		asamples[k]++
	}
	if (index(" " arel[k] " ", " " rel " ") == 0 && length(arel[k]) < 200)
		arel[k] = arel[k] (arel[k] == "" ? "" : " ") rel
	if (f[A["granted"]] == "f")
		await[k]++
	x = f[A["xact_age_s"]] + 0
	if (x >= amax[k]) {
		amax[k] = x
		awho[k] = f[A["backend_type"]] " " f[A["application_name"]]
		aq[k] = f[A["query"]]
	}
	next
}

FILENAME == ARGV[3] && FNR == 1 {
	header($0, P)
	next
}

FILENAME == ARGV[3] {
	csvsplit($0, f)
	k = f[P["kind"]] "|" hyper(f[P["relname"]])
	if (!(k in pi)) {
		pi[k] = 1
		np++
		pk[np] = k
	}
	psamples[k]++
	ph = f[P["phase"]]
	if (index("," pphase[k] ",", "," ph ",") == 0)
		pphase[k] = pphase[k] (pphase[k] == "" ? "" : ",") ph
	if (f[P["xact_age_s"]] + 0 > pmax[k])
		pmax[k] = f[P["xact_age_s"]] + 0
	next
}

END {
	print "ACCESS EXCLUSIVE locks seen on the primary, by table (chunks under their"
	print "hypertable). Each one is replayed on the replica, and there it conflicts with"
	print "every query holding any lock on the same relation."
	if (na == 0)
		print "  none seen"
	else
		printf "  %-40s %8s %6s %8s  %s\n", "table", "samples", "waits", "max_age", "holder: query"
	for (i = 1; i <= na; i++)
		ord[i] = ak[i]
	for (i = 1; i <= na; i++)
		for (j = i + 1; j <= na; j++)
			if (asamples[ord[j]] > asamples[ord[i]]) {
				t = ord[i]
				ord[i] = ord[j]
				ord[j] = t
			}
	for (i = 1; i <= na && i <= 30; i++) {
		k = ord[i]
		printf "  %-40s %8d %6d %8.0f  %s: %s\n", short(k, 40), asamples[k], await[k], amax[k], awho[k], short(aq[k], 90)
		printf "  %-40s relations: %s\n", "", short(arel[k], 120)
	}
	print ""
	print "Maintenance seen running on the primary (pg_stat_progress_*), by table:"
	if (np == 0)
		print "  none seen"
	else
		printf "  %-22s %-40s %8s %8s  %s\n", "kind", "table", "samples", "max_age", "phases"
	for (i = 1; i <= np; i++)
		pord[i] = pk[i]
	for (i = 1; i <= np; i++)
		for (j = i + 1; j <= np; j++)
			if (psamples[pord[j]] > psamples[pord[i]]) {
				t = pord[i]
				pord[i] = pord[j]
				pord[j] = t
			}
	for (i = 1; i <= np && i <= 30; i++) {
		k = pord[i]
		split(k, kp, "|")
		printf "  %-22s %-40s %8d %8.0f  %s\n", kp[1], short(kp[2], 40), psamples[k], pmax[k], pphase[k]
	}
}
AWK

# TimescaleDB jobs that ran between the snapshots: snap1 and snap2
# job_stats.csv
cat >"$OUT/awk/summary-jobs.awk" <<'AWK'
FNR == 1 {
	file++
	split("", h)
	header($0, h)
	next
}

{
	csvsplit($0, f)
	j = f[h["job_id"]]
	if (file == 1) {
		runs[j] = f[h["total_runs"]] + 0
		fails[j] = f[h["total_failures"]] + 0
		next
	}
	d = f[h["total_runs"]] - runs[j]
	if (!(j in runs) || d > 0) {
		nj++
		printf "  %6s %-30s %-30s %-34s %4d %4d  %-16s %s\n", j, short(f[h["application_name"]], 30), short(f[h["proc_name"]], 30), short(f[h["hypertable_schema"]] "." f[h["hypertable_name"]], 34), d, f[h["total_failures"]] - fails[j], f[h["last_run_duration"]], f[h["last_run_status"]]
	}
}

END {
	if (nj == 0)
		print "  none ran"
}
AWK

# The replica's log: pull out the recovery conflict messages, one line each,
# | separated, numbered in log order. Works on the stderr and syslog formats
# whatever log_line_prefix is, as long as it holds the process ID in [] (as %p
# in [%p], or syslog's postgres[PID]) to tie a message's DETAIL, CONTEXT and
# STATEMENT lines to it.
cat >"$OUT/awk/log-extract.awk" <<'AWK'
function clean(s) {
	gsub(/#011/, " ", s)
	gsub(/[|\t\r]/, " ", s)
	gsub(/  +/, " ", s)
	sub(/^ /, "", s)
	sub(/ $/, "", s)
	return s
}

function cancel_reason(s) {
	if (s ~ /row versions that must be removed/)
		return "snapshot"
	if (s ~ /relation lock/)
		return "lock"
	if (s ~ /buffer pin/)
		return "bufferpin"
	if (s ~ /buffer deadlock/)
		return "deadlock"
	if (s ~ /tablespace/)
		return "tablespace"
	if (s ~ /replication slot/)
		return "logicalslot"
	if (s ~ /database that must be dropped/)
		return "database"
	return "unknown"
}

function wait_reason(s) {
	if (s ~ /conflict on snapshot/)
		return "snapshot"
	if (s ~ /conflict on lock/)
		return "lock"
	if (s ~ /conflict on buffer pin/)
		return "bufferpin"
	if (s ~ /conflict on buffer deadlock/)
		return "deadlock"
	if (s ~ /conflict on tablespace/)
		return "tablespace"
	if (s ~ /conflict on replication slot/)
		return "logicalslot"
	if (s ~ /conflict on database/)
		return "database"
	return "unknown"
}

function emit(p) {
	if (!(p in ev))
		return
	print seq[p], ts[p], p, ev[p], rs[p], ms[p], op[p], lsn[p], rec[p], ldb[p], lrel[p], bspc[p], bdb[p], brel[p], substr(clean(st[p]), 1, 500)
	delete ev[p]
}

function begin_event(p, t, e, r) {
	emit(p)
	seq[p] = NR
	ts[p] = t
	ev[p] = e
	rs[p] = r
	ms[p] = ""
	op[p] = ""
	lsn[p] = ""
	rec[p] = ""
	ldb[p] = ""
	lrel[p] = ""
	bspc[p] = ""
	bdb[p] = ""
	brel[p] = ""
	st[p] = ""
}

BEGIN {
	OFS = "|"
	print "seq", "log_ts", "pid", "event", "reason", "wait_ms", "other_pids", "wal_lsn", "wal_record", "lock_db", "lock_rel", "blk_spc", "blk_db", "blk_rel", "statement"
	tagre = "(LOG|ERROR|FATAL|PANIC|WARNING|NOTICE|INFO|DEBUG[1-5]?|DETAIL|HINT|CONTEXT|STATEMENT|QUERY|LOCATION):  "
	last = ""
}

{
	if (!match($0, tagre)) {
		# a line with no level continues the last one: a statement written
		# over several lines (syslog numbers each such line [N-M])
		if (last != "" && lasttag == "STATEMENT" && (last in ev) && length(st[last]) < 600) {
			t = $0
			sub(/^.*\[[0-9]+-[0-9]+\] /, "", t)
			st[last] = st[last] " " t
		}
		next
	}
	pre = substr($0, 1, RSTART - 1)
	tag = substr($0, RSTART, RLENGTH - 3)
	msg = substr($0, RSTART + RLENGTH)
	pid = "?"
	if (match(pre, /\[[0-9]+\]/))
		pid = substr(pre, RSTART + 1, RLENGTH - 2)
	# the time, with its fraction of a second and time zone if given
	t = ""
	if (match(pre, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][ T][0-9][0-9]:[0-9][0-9]:[0-9][0-9](\.[0-9]+)?( ?[A-Z][A-Za-z]*| ?[+-][0-9][0-9]:?[0-9]*)?/))
		t = substr(pre, RSTART, RLENGTH)
	else if (match(pre, /[A-Z][a-z][a-z] +[0-9]+ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]/))
		t = substr(pre, RSTART, RLENGTH)
	last = pid
	lasttag = tag

	if (tag !~ /^(DETAIL|HINT|CONTEXT|STATEMENT|QUERY|LOCATION)$/) {
		# a new message ends the last one from the same process
		emit(pid)
		if (msg ~ /due to conflict with recovery/) {
			begin_event(pid, t, tag == "FATAL" ? "terminate" : "cancel", "unknown")
		} else if (msg ~ /^recovery (still|finished) waiting after [0-9.]+ ms: recovery conflict on /) {
			begin_event(pid, t, msg ~ /^recovery still/ ? "wait" : "wait_end", wait_reason(msg))
			x = msg
			sub(/^recovery [a-z]+ waiting after /, "", x)
			sub(/ ms:.*$/, "", x)
			ms[pid] = x
		} else if (msg ~ /^canceling statement due to (statement timeout|user request|lock timeout)/) {
			x = msg
			sub(/^canceling statement due to /, "", x)
			gsub(/ /, "_", x)
			begin_event(pid, t, "other_cancel", x)
		} else if (msg ~ /still waiting for [A-Za-z]+ on relation [0-9]+ of database [0-9]+ after /) {
			begin_event(pid, t, "lock_wait", "")
			x = msg
			sub(/^.*still waiting for /, "", x)
			m = x
			sub(/ .*$/, "", m)
			rs[pid] = m
			sub(/^[A-Za-z]+ on relation /, "", x)
			lrel[pid] = x
			sub(/ .*$/, "", lrel[pid])
			sub(/^[0-9]+ of database /, "", x)
			ldb[pid] = x
			sub(/ .*$/, "", ldb[pid])
			x = msg
			sub(/^.* after /, "", x)
			sub(/ ms.*$/, "", x)
			ms[pid] = x
		}
		next
	}
	if (!(pid in ev))
		next
	if (tag == "DETAIL") {
		if (ev[pid] == "cancel" || ev[pid] == "terminate")
			rs[pid] = cancel_reason(msg)
		else if (ev[pid] == "wait" || ev[pid] == "lock_wait") {
			# "Conflicting processes: 1, 2." or "Process holding the lock: 1. Wait queue: 2."
			x = msg
			sub(/^[^:]*: /, "", x)
			sub(/\..*$/, "", x)
			gsub(/[^0-9,]/, "", x)
			op[pid] = x
		}
	} else if (tag == "CONTEXT" && msg ~ /^WAL redo at /) {
		x = msg
		sub(/^WAL redo at /, "", x)
		lsn[pid] = x
		sub(/ .*$/, "", lsn[pid])
		sub(/^[^ ]+ for /, "", x)
		rec[pid] = x
		sub(/[: ].*$/, "", rec[pid])
		if (rec[pid] == "Standby/LOCK" && match(msg, /db [0-9]+ rel [0-9]+/)) {
			split(substr(msg, RSTART, RLENGTH), a, " ")
			ldb[pid] = a[2]
			lrel[pid] = a[4]
		}
		if (match(msg, /blkref #[0-9]+: rel [0-9]+\/[0-9]+\/[0-9]+/)) {
			x = substr(msg, RSTART, RLENGTH)
			sub(/^.* rel /, "", x)
			split(x, a, "/")
			bspc[pid] = a[1]
			bdb[pid] = a[2]
			brel[pid] = a[3]
		}
	} else if (tag == "STATEMENT") {
		st[pid] = msg
	}
}

END {
	for (p in ev)
		emit(p)
}
AWK

# The relations named in the log, to look up: one VALUES row each
cat >"$OUT/awk/log-rels.awk" <<'AWK'
BEGIN {
	FS = "|"
}

NR == 1 {
	for (i = 1; i <= NF; i++)
		h[$i] = i
	next
}

{
	if ($h["lock_rel"] != "")
		k["oid:" $h["lock_db"] ":" $h["lock_rel"]] = "('oid:" $h["lock_db"] ":" $h["lock_rel"] "', 'oid', 0, " $h["lock_db"] ", " $h["lock_rel"] ")"
	if ($h["blk_rel"] != "")
		k["file:" $h["blk_spc"] ":" $h["blk_db"] ":" $h["blk_rel"]] = "('file:" $h["blk_spc"] ":" $h["blk_db"] ":" $h["blk_rel"] "', 'file', " $h["blk_spc"] ", " $h["blk_db"] ", " $h["blk_rel"] ")"
}

END {
	n = 0
	for (x in k)
		print (n++ ? "\t, " : "\t  ") k[x]
}
AWK

# The summary of the log: chunks.csv, rels.psv, then events.psv. -v delay_ms=MS
cat >"$OUT/awk/log-summary.awk" <<'AWK'
# relname(key) - the table a relation named in the log belongs to, a chunk
# given as its hypertable
function relname(key) {
	if (key == "")
		return ""
	return (key in RN) ? RN[key] : key " (not found)"
}

# hour_of(t) - the hour of the log time t, with its time zone
function hour_of(t,    h, z) {
	if (!match(t, /[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/))
		return "?"
	h = substr(t, 1, RSTART + 1)
	z = substr(t, RSTART + RLENGTH)
	sub(/^\.[0-9]+/, "", z)
	sub(/^ /, "", z)
	return h ":00" (z == "" ? "" : " " z)
}

# the table (or hypertable) a wait's relation belongs to, for grouping
function wait_rel(i) {
	if (lrel[i] != "")
		return relname("oid:" ldb[i] ":" lrel[i])
	if (brel[i] != "")
		return relname("file:" bspc[i] ":" bdb[i] ":" brel[i])
	return "-"
}

function norm(s) {
	gsub(/'[^']*'/, "'?'", s)
	gsub(/  +/, " ", s)
	return substr(s, 1, 150)
}

BEGIN {
	readchunks(ARGV[1])
	ARGV[1] = ""
	FS = "|"
}

# key|relation|table|relkind
FILENAME == ARGV[2] {
	if (FNR > 1)
		RN[$1] = $2 == "" ? $1 " (dropped, or in another database)" : hyper($3) ($4 == "i" ? " (index)" : $4 == "t" ? " (TOAST)" : "")
	next
}

FNR == 1 {
	for (i = 1; i <= NF; i++)
		h[$i] = i
	next
}

{
	n++
	ts[n] = $h["log_ts"]
	pid[n] = $h["pid"]
	ev[n] = $h["event"]
	rs[n] = $h["reason"]
	ms[n] = $h["wait_ms"]
	op[n] = $h["other_pids"]
	rec[n] = $h["wal_record"]
	ldb[n] = $h["lock_db"]
	lrel[n] = $h["lock_rel"]
	bspc[n] = $h["blk_spc"]
	bdb[n] = $h["blk_db"]
	brel[n] = $h["blk_rel"]
	st[n] = $h["statement"]
	if (first == "" && ts[n] != "")
		first = ts[n]
	if (ts[n] != "")
		lastts = ts[n]
}

END {
	if (n == 0) {
		print "No recovery conflict messages found in the log."
		exit
	}
	printf "Messages: %d, from %s to %s\n\n", n, first, lastts

	print "By kind of message and reason:"
	for (i = 1; i <= n; i++)
		c[ev[i] "|" rs[i]]++
	for (k in c) {
		split(k, a, "|")
		printf "  %-14s %-20s %7d\n", a[1], (a[2] == "" ? "-" : a[2]), c[k] | "LC_ALL=C sort"
	}
	close("LC_ALL=C sort")
	print "  (cancel: a statement cancelled; terminate: a session ended, as it was idle in a"
	print "  transaction; wait/wait_end: replay waited longer than deadlock_timeout on a"
	print "  conflict, logged with log_recovery_conflict_waits; other_cancel: cancelled for"
	print "  another reason; lock_wait: a session waited on a lock, with log_lock_waits)"
	print ""

	# A cancel is tied to the wait going on when it came, if that wait was on
	# the same kind of conflict or listed the cancelled process. Replay waits
	# on one conflict at a time, and a buffer pin wait lists no processes.
	openw = 0
	for (i = 1; i <= n; i++) {
		if (ev[i] == "wait") {
			np = split(op[i], ps, ",")
			for (j = 1; j <= np; j++)
				pw[ps[j]] = i
			openw = i
			if (waits++ == 0)
				wfirst = ts[i]
			wr = rs[i] "|" rec[i] "|" wait_rel(i)
			wcount[wr]++
		} else if (ev[i] == "wait_end") {
			x = ms[i] + 0
			wend[rs[i]]++
			wsum[rs[i]] += x
			if (x > wmax[rs[i]])
				wmax[rs[i]] = x
			if (delay_ms != "" && x >= delay_ms - 500)
				wfull[rs[i]]++
			openw = 0
		} else if (ev[i] == "cancel" || ev[i] == "terminate") {
			cancels++
			hr = hour_of(ts[i])
			if (!(hr in hours)) {
				hours[hr] = 1
				nh++
				hk[nh] = hr
			}
			byhour[hr, rs[i]]++
			w = 0
			if (openw && (rs[openw] == rs[i] || ((pid[i] in pw) && pw[pid[i]] == openw)))
				w = openw
			if (w) {
				cw[rs[w] "|" rec[w] "|" wait_rel(w)]++
				tied[rs[i]]++
			} else if (waits == 0)
				early[rs[i]]++
			else
				untied[rs[i]]++
			sk = rs[i] "|" norm(st[i])
			if (!(sk in sc))
				nsk++
			sc[sk]++
		}
	}

	print "Cancelled and terminated, by hour (in the log's time zone):"
	printf "  %-22s %8s %8s %9s %8s %8s\n", "hour", "snapshot", "lock", "bufferpin", "deadlock", "other"
	for (i = 1; i <= nh; i++) {
		hr = hk[i]
		o = 0
		for (k in byhour) {
			split(k, a, SUBSEP)
			if (a[1] == hr && a[2] !~ /^(snapshot|lock|bufferpin|deadlock)$/)
				o += byhour[k]
		}
		printf "  %-22s %8d %8d %9d %8d %8d\n", hr, byhour[hr, "snapshot"], byhour[hr, "lock"], byhour[hr, "bufferpin"], byhour[hr, "deadlock"], o | "LC_ALL=C sort"
	}
	close("LC_ALL=C sort")
	print ""

	nr = split("snapshot lock bufferpin deadlock tablespace logicalslot database unknown", RL, " ")
	print "Replay's logged waits, by reason (from \"recovery finished waiting\"):"
	if (waits == 0 && cancels > 0)
		print "  none: log_recovery_conflict_waits is probably off"
	else if (waits == 0)
		print "  none"
	for (j = 1; j <= nr; j++) {
		r = RL[j]
		if (r in wend)
			printf "  %-12s %6d waits, %8.0f s in all, longest %6.1f s; %d of them about max_standby_streaming_delay (%s ms) long\n", r, wend[r], wsum[r] / 1000, wmax[r] / 1000, wfull[r], delay_ms
	}
	print ""

	print "Cancellations tied to a logged wait, and not: a cancel with no wait going on"
	print "when it came was made at once (or after a wait shorter than deadlock_timeout),"
	print "as replay was already about max_standby_streaming_delay behind. Only cancels"
	print "after the first logged wait are judged: log_recovery_conflict_waits may have"
	print "been off before it."
	if (waits > 0)
		printf "  (the first wait was logged at %s)\n", wfirst
	for (j = 1; j <= nr; j++) {
		r = RL[j]
		if ((r in tied) || (r in untied) || (r in early))
			printf "  %-12s %6d tied, %6d not, %6d before the first logged wait\n", r, tied[r], untied[r], early[r]
	}
	print ""

	print "What replay waited on (from the CONTEXT of each wait): the number of waits and"
	print "of the cancellations tied to them, by reason, WAL record and table (a chunk"
	print "given as its hypertable):"
	if (waits > 0)
		printf "  %6s %8s  %-10s %-28s %s\n", "waits", "cancels", "reason", "WAL record", "table"
	for (k in wcount) {
		split(k, a, "|")
		printf "  %6d %8d  %-10s %-28s %s\n", wcount[k], cw[k], a[1], (a[2] == "" ? "-" : a[2]), a[3] | "LC_ALL=C sort -k1,1nr -k2,2nr | head -n 40"
	}
	close("LC_ALL=C sort -k1,1nr -k2,2nr | head -n 40")
	print ""

	printf "Cancelled statements, by reason and the start of the statement (%d kinds):\n", nsk
	for (k in sc) {
		split(k, a, "|")
		printf "  %6d  %-10s %s\n", sc[k], a[1], (a[2] == "" ? "(no statement logged)" : a[2]) | "LC_ALL=C sort -k1,1nr | head -n 40"
	}
	close("LC_ALL=C sort -k1,1nr | head -n 40")
}
AWK

# -----------------------------------------------------------------------------
# Collect.
# -----------------------------------------------------------------------------

# split_round FILE - add each ==NAME section of a sample's output to
# samples/NAME.csv, keeping the header only the first time
split_round() {
	awk -v dir="$OUT/samples" '
		/^==[a-z_]+$/ {
			if (f != "")
				close(f)
			f = dir "/" substr($0, 3) ".csv"
			hdr = 1
			next
		}
		f == "" {
			next
		}
		hdr {
			hdr = 0
			if ((getline t < f) > 0) {
				close(f)
				next
			}
			close(f)
		}
		{
			print >>f
		}
	' "$1"
}

snapshot() {
	_d=$OUT/$1
	run csv snap-database "$_d/database.csv"
	run csv snap-tables "$_d/tables.csv"
	if [ -n "$PSS_SCHEMA" ]; then
		if [ "$1" = snap1 ]; then
			run csv snap-pss-notext "$_d/pg_stat_statements.csv" -v pss_schema="$PSS_SCHEMA"
		else
			run csv snap-pss-text "$_d/pg_stat_statements.csv" -v pss_schema="$PSS_SCHEMA"
		fi
		run csv snap-pss-info "$_d/pg_stat_statements_info.csv" -v pss_schema="$PSS_SCHEMA"
	fi
	[ "$HAVE_TSDB" = false ] || run csv snap-jobs "$_d/job_stats.csv"
	[ "$HAVE_IO" = false ] || run csv snap-io "$_d/io.csv"
	if [ "$ROLE" = replica ]; then
		run csv snap-conflicts "$_d/database_conflicts.csv"
		run csv snap-wal-receiver "$_d/wal_receiver.csv"
	else
		run csv snap-wal "$_d/wal.csv"
		run csv snap-replication "$_d/replication.csv"
		run csv snap-slots "$_d/slots.csv"
	fi
}

note "Context"
run text context "$OUT/context.txt" -v is_replica="$IS_REPLICA" -v have_tsdb="$HAVE_TSDB"
if [ "$HAVE_TSDB" = true ]; then
	run csv chunks "$OUT/chunks.csv"
else
	printf 'chunk_schema,chunk_name,hypertable_schema,hypertable_name\n' >"$OUT/chunks.csv"
fi

ROUNDS_DONE=0
ROUNDS_FAILED=0
if [ "$SAMPLES" -gt 0 ]; then
	note "Snapshot 1"
	snapshot snap1

	note "Taking $SAMPLES samples, $INTERVAL s apart (Ctrl-C to stop early)"
	STOP=0
	trap 'STOP=1' INT TERM
	NOTE_EVERY=$((300 / INTERVAL))
	[ "$NOTE_EVERY" -ge 1 ] || NOTE_EVERY=1
	ROUND_OUT=$OUT/samples/round.out
	ROUND_ERR=$OUT/samples/round.err
	sample_no=1
	while [ "$sample_no" -le "$SAMPLES" ] && [ "$STOP" -eq 0 ]; do
		# psql goes on after an error, and exits 0, so look for what it wrote
		"$PSQL" -X -q -w --csv -v ON_ERROR_STOP=0 -v stmt_timeout="${STMT_TIMEOUT}s" \
			-v round="$sample_no" -v min_age="$MIN_AGE" \
			-f "$OUT/sql/session.sql" -f "$OUT/sql/sample-$ROLE.sql" \
			>"$ROUND_OUT" 2>"$ROUND_ERR" </dev/null
		if [ -s "$ROUND_ERR" ]; then
			ROUNDS_FAILED=$((ROUNDS_FAILED + 1))
			{
				printf 'sample %s at %s:\n' "$sample_no" "$(date -u +%H:%M:%SZ)"
				cat "$ROUND_ERR"
			} >>"$OUT/samples/errors.log"
		fi
		split_round "$ROUND_OUT"
		ROUNDS_DONE=$sample_no
		if [ $((sample_no % NOTE_EVERY)) -eq 0 ]; then
			note "Sample $sample_no of $SAMPLES"
		fi
		sample_no=$((sample_no + 1))
		if [ "$sample_no" -le "$SAMPLES" ] && [ "$STOP" -eq 0 ]; then
			sleep "$INTERVAL"
		fi
	done
	rm -f "$ROUND_OUT" "$ROUND_ERR"
	trap 'note "Interrupted; packaging what was collected"; finish; exit 130' INT TERM
	[ "$STOP" -eq 0 ] || note "Stopped after $ROUNDS_DONE samples"
	[ "$ROUNDS_FAILED" -eq 0 ] \
		|| note "WARNING: $ROUNDS_FAILED samples had errors, see samples/errors.log"
	printf 'samples_taken=%s\nsamples_with_errors=%s\n' "$ROUNDS_DONE" "$ROUNDS_FAILED" >>"$OUT/run.txt"

	note "Snapshot 2"
	snapshot snap2
fi

if [ -n "$PSS_SCHEMA" ]; then
	note "Longest statements"
	run text pss-top "$OUT/pss-top.txt" -v pss_schema="$PSS_SCHEMA"
fi

if [ -n "$LOGS" ]; then
	note "Reading the log"
	mkdir -p "$OUT/log"
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		read_log "$f" 2>>"$LOG" || note "WARNING: could not read all of $f, see collect.log"
	done <<EOF | awk -f "$OUT/awk/log-extract.awk" >"$OUT/log/events.raw"
$LOGS
EOF
	{
		head -n 1 "$OUT/log/events.raw"
		tail -n +2 "$OUT/log/events.raw" | sort -t '|' -k1,1n
	} >"$OUT/log/events.psv"
	rm -f "$OUT/log/events.raw"
	EVENTS=$(($(wc -l <"$OUT/log/events.psv") - 1))
	note "Found $EVENTS recovery conflict messages"
	printf 'log_events=%s\n' "$EVENTS" >>"$OUT/run.txt"

	# look up the relations the messages name: an OID for a lock, a
	# tablespace/database/relfilenode for a page; an index or TOAST table is
	# given with the table it belongs to
	printf 'key|relation|table|relkind\n' >"$OUT/log/rels.psv"
	awk -f "$OUT/awk/log-rels.awk" "$OUT/log/events.psv" >"$OUT/log/rels.values"
	if [ -s "$OUT/log/rels.values" ]; then
		{
			printf 'WITH r(k, kind, spc, db, rel) AS (VALUES\n'
			cat "$OUT/log/rels.values"
			cat <<'SQL'
)
, me AS (
	SELECT d.oid AS db, d.dattablespace AS spc
	FROM pg_database d
	WHERE d.datname = current_database()
)
, x AS (
	SELECT r.k
		, CASE
			WHEN r.db::oid <> me.db THEN NULL
			WHEN r.kind = 'oid' THEN (SELECT c.oid FROM pg_class c WHERE c.oid = r.rel::oid)
			ELSE pg_filenode_relation(CASE WHEN r.spc::oid = me.spc THEN 0 ELSE r.spc END::oid
				, r.rel::oid)::oid
			END AS relid
	FROM r
	CROSS JOIN me
)
SELECT x.k
	, x.relid::regclass::text AS relation
	, COALESCE((SELECT i.indrelid FROM pg_index i WHERE i.indexrelid = x.relid)
		, (SELECT o.oid FROM pg_class o WHERE o.reltoastrelid = x.relid AND o.reltoastrelid <> 0)
		, x.relid)::regclass::text AS tbl
	, (SELECT c.relkind FROM pg_class c WHERE c.oid = x.relid) AS relkind
FROM x;
SQL
		} >"$OUT/sql/log-rels.sql"
		"$PSQL" -X -q -w -A -t -F '|' -v ON_ERROR_STOP=1 -v stmt_timeout="${STMT_TIMEOUT}s" \
			-f "$OUT/sql/session.sql" -f "$OUT/sql/log-rels.sql" >>"$OUT/log/rels.psv" 2>>"$LOG" </dev/null \
			|| { note "WARNING: could not look up the log's relations, see collect.log"; FAILED="$FAILED log-rels"; }
	fi
	rm -f "$OUT/log/rels.values"
fi

# -----------------------------------------------------------------------------
# Summarise.
# -----------------------------------------------------------------------------

note "Summary"
# each of this server's sample files, so that a summary of none still runs
if [ "$ROLE" = replica ]; then
	set -- startup sessions
else
	set -- horizon holders ael progress
fi
for f in "$@"; do
	[ "$SAMPLES" -eq 0 ] || : >>"$OUT/samples/$f.csv"
done
{
	printf 'replica-conflicts-collect summary: the %s, database %s\n' "$ROLE" "$DB_NAME"
	printf 'host %s, started %s\n' "${PGHOST:-local}" "$(sed -n 's/^started=//p' "$OUT/run.txt")"
	printf 'max_standby_streaming_delay %s ms, hot_standby_feedback %s\n' "$DELAY_MS" "$FEEDBACK"
	printf '%s\n\n' '==============================================================================='
	if [ "$SAMPLES" -gt 0 ]; then
		if [ "$ROLE" = replica ]; then
			awk -f "$OUT/awk/lib.awk" -f "$OUT/awk/summary-replica.awk" -v interval="$INTERVAL" \
				-v min_age="$MIN_AGE" "$OUT/samples/startup.csv" "$OUT/samples/sessions.csv"
			printf '\n'
			awk -f "$OUT/awk/lib.awk" -f "$OUT/awk/summary-tables.awk" -v mode=read \
				"$OUT/chunks.csv" "$OUT/snap1/tables.csv" "$OUT/snap2/tables.csv"
		else
			awk -f "$OUT/awk/lib.awk" -f "$OUT/awk/summary-horizon.awk" -v min_age="$MIN_AGE" \
				"$OUT/samples/horizon.csv" "$OUT/samples/holders.csv"
			printf '\n'
			awk -f "$OUT/awk/lib.awk" -f "$OUT/awk/summary-tables.awk" -v mode=write \
				"$OUT/chunks.csv" "$OUT/snap1/tables.csv" "$OUT/snap2/tables.csv"
			printf '\n'
			awk -f "$OUT/awk/lib.awk" -f "$OUT/awk/summary-locks.awk" \
				"$OUT/chunks.csv" "$OUT/samples/ael.csv" "$OUT/samples/progress.csv"
		fi
		if [ -s "$OUT/snap1/job_stats.csv" ] && [ -s "$OUT/snap2/job_stats.csv" ]; then
			printf '\nTimescaleDB jobs that ran between the snapshots:\n'
			printf '  %6s %-30s %-30s %-34s %4s %4s  %-16s %s\n' job application proc hypertable runs fail \
				last_duration last_status
			awk -f "$OUT/awk/lib.awk" -f "$OUT/awk/summary-jobs.awk" \
				"$OUT/snap1/job_stats.csv" "$OUT/snap2/job_stats.csv"
		fi
	fi
	if [ -s "$OUT/pss-top.txt" ]; then
		printf '\n'
		cat "$OUT/pss-top.txt"
	fi
	if [ -n "$LOGS" ]; then
		printf '\nThe log\n'
		printf '%s\n\n' '-------'
		awk -f "$OUT/awk/lib.awk" -f "$OUT/awk/log-summary.awk" -v delay_ms="$DELAY_MS" \
			"$OUT/chunks.csv" "$OUT/log/rels.psv" "$OUT/log/events.psv"
	fi
} >"$OUT/summary.txt" 2>"$OUT/summary.err"
if [ -s "$OUT/summary.err" ]; then
	note "WARNING: parts of the summary failed, see collect.log"
	cat "$OUT/summary.err" >>"$LOG"
	FAILED="$FAILED summary"
fi
rm -f "$OUT/summary.err"

trap - INT TERM
finish

if [ -n "$FAILED" ]; then
	note "Finished, but these steps failed:$FAILED"
else
	note "Finished"
fi
note "Summary in $OUT/summary.txt"
exit 0
