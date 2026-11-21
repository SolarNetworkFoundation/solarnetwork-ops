#!/bin/sh
#
# chunk-maintenance.sh - keep the chunks of the datum, aggregate and audit
# hypertables in index order, compact, and analyzed (OPS-51).
#
# Chunks drift out of the order of their unique index as backfill arrives, and
# their statistics go stale: the TimescaleDB reorder policies reorder a chunk
# only once, and the weekly vacuumdb --analyze-only was turned off (OPS-45).
# This script, run daily from cron, takes the chunks that need work from the
# _timescaledb_solarnetwork.chunk_maint_candidates view and works through a
# few each run. Install setup/timescaledb/tsdb-init-hypertables-maintenance.sql
# first; it explains how each chunk's needs are worked out. The tasks:
#
#   reorder   rewrite a chunk in index order with reorder_chunk(), then ANALYZE
#   move      the same with move_chunk(), into the tablespaces the chunk is
#             already in, for a chunk that a move_chunks job moved out of main
#             storage, to solarwarm or solarcold
#   reindex   REINDEX INDEX CONCURRENTLY, when only the index is bloated
#   analyze   ANALYZE a chunk whose statistics are out of date
#
# Without -y it only reports what it would do. It makes the same checks as a
# real run, prints each task with its SQL, and exits with the same status, but
# changes nothing and logs nothing. It still watches each chunk for writes
# before a rewrite, so give -w 0 for a quick report.
#
# Each run:
#
#  1. Takes a lock ($TMPDIR/chunk-maintenance.lock), or stops if another run
#     holds it.
#  2. Stops if the server is a replica, the TimescaleDB licence is not
#     timescale, a reorder policy or move_chunks job is running, WAL archiving
#     is failing or behind, or a replica or replication slot is too far behind:
#     the checks in the chunk_maint_preflight view.
#  3. Takes the candidates in order: rewrites and reindexes, the newest chunk
#     first and the chunks that move_chunks moved out of main storage last, then
#     ANALYZE for the chunks whose statistics are furthest behind. It rewrites or
#     reindexes at most one chunk in each tablespace chunks were moved to
#     (solarwarm, and solarcold where there is one) a run, as the replica's
#     storage for them is slow to write.
#  4. Before rewriting a chunk:
#     - if the chunk's statistics may be out of date, analyzes it and looks
#       again;
#     - watches its write counters for -w seconds, and leaves it for another
#       run if anything writes to it: a rewrite blocks writes to the chunk until
#       it finishes;
#     - checks the free space of each filesystem the task writes to: a new copy
#       of the heap and indexes in their tablespaces, the sort spill in the -t
#       tablespace, and WAL in pg_wal. Needs on one filesystem (or ZFS pool) are
#       added up, and must leave -r percent of it free. If they would not, the
#       run stops with "not enough space" (exit status 3).
#  5. Rewrites the chunk and analyzes it, in one session with a lock_timeout
#     (-l), so that it never waits long for a lock, nor holds up the queries
#     queued behind it on the chunk. A task that times out on a lock is rolled
#     back, and tried again another run.
#  6. Stops once its tasks reach the budget (-b). The first task always runs,
#     and each later one only if it fits in what is left. A rewrite counts its
#     heap and indexes, and an ANALYZE the pages it reads.
#
# Every task is logged in _timescaledb_solarnetwork.chunk_maint_log.
#
# Usage:
#
#   chunk-maintenance.sh [-y] [-h HOST] [-p PORT] [-U USER] [-d DBNAME] [options]
#
# Run it on the database server, as the postgres user, connecting as a
# superuser through the local socket, as it reads the free space of the
# server's filesystems. Connection options are the same as psql's, and anything
# libpq reads from the environment applies; psql is run with -w, so it never
# prompts for a password.
#
#   -y             act; without it, only report what would be done
#   -h -p -U -d    connection, as for psql
#   -b GB          the budget for one run, in GB (default 40)
#   -t TABLESPACE  temp_tablespaces for the script's sessions, where sorts
#                  spill (default: the database's default tablespace)
#   -r PERCENT     free space to keep on each filesystem, as a percentage of
#                  its size (default 20)
#   -w SECONDS     how long to watch a chunk for writes before rewriting it
#                  (default 60; 0 to not watch)
#   -l SECONDS     lock_timeout for every statement (default 60)
#   -m SIZE        maintenance_work_mem for the script's sessions, such as 1GB
#                  (default: the server's setting)
#   -s NAME=VALUE  set chunk_maint.NAME for the script's sessions: one of the
#                  thresholds listed in tsdb-init-hypertables-maintenance.sql.
#                  May be given more than once.
#   -C             use CLUSTER in place of reorder_chunk() and move_chunk(), to
#                  test on a server without the TimescaleDB licence. CLUSTER
#                  blocks reads of the chunk as well as writes: never use this
#                  on production.
#   -v             say more: every check, and each candidate left for later
#
# Exit status:
#
#   0    finished, whether or not there was anything to do
#   1    usage error, or an error running a query
#   2    stopped by a check: another run holds the lock, or a step 2 check
#   3    not enough space for the next task
#   4    a task failed; a task that timed out on a lock, or was cancelled,
#        does not count
#   130  interrupted by SIGINT, SIGTERM or SIGHUP: the run stops once the task
#        in hand ends, and logs it. A Ctrl-C at a terminal reaches psql too,
#        which cancels the statement running, so that task is rolled back.
#
# Written for POSIX sh (FreeBSD sh, dash).

set -u
umask 077

# cron's PATH leaves out /usr/local/bin, where FreeBSD's packages install psql
PATH=${PATH:-/bin:/usr/bin}:/usr/local/bin
export PATH

# zsh gives a function's name as $0 inside it, so keep the script's name here
SCRIPT=$0
PSQL=${PSQL:-psql}
DO_IT=0
BUDGET_GB=40
TEMP_TS=
RESERVE_PCT=20
WATCH=60
LOCK_TIMEOUT=60
MWM=
USE_CLUSTER=0
VERBOSE=0
GUCS=
LOCK_DIR=${TMPDIR:-/tmp}/chunk-maintenance.lock
LOCKED=0
WORK=
INTERRUPTED=0

# pretty BYTES, as pg_size_pretty() would
AWK_PRETTY='function pretty(b,    u, i) {
	split("bytes kB MB GB TB PB", u, " ")
	for (i = 1; b >= 1024 && i < 6; i++) b /= 1024
	return (i == 1) ? sprintf("%d %s", b, u[i]) : sprintf("%.1f %s", b, u[i])
}'

usage() {
	sed -n '2,/^# Written for POSIX sh/p' "$SCRIPT" | sed 's/^# \{0,1\}//' >&2
	exit 1
}

note() {
	printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

die() {
	printf 'chunk-maintenance: %s\n' "$*" >&2
	exit 1
}

# stop REASON - a check failed: stop, with exit status 2
stop() {
	note "stopping: $*"
	exit 2
}

is_number() {
	case $1 in
		'' | *[!0-9]*) return 1 ;;
	esac
	return 0
}

pretty() {
	awk -v b="$1" "$AWK_PRETTY"' BEGIN { print pretty(b) }'
}

# in_list WORD LIST - true if WORD is one of the words of the space separated LIST
in_list() {
	case " $2 " in
		*" $1 "*) return 0 ;;
	esac
	return 1
}

# plural COUNT WORD - print "1 WORD" or "COUNT WORDs"
plural() {
	if [ "$1" -eq 1 ]; then
		printf '%s %s' "$1" "$2"
	else
		printf '%s %ss' "$1" "$2"
	fi
}

# add_guc NAME=VALUE - add SET chunk_maint.NAME = 'VALUE' to the session settings
add_guc() {
	_name=${1%%=*}
	_value=${1#*=}
	[ "$_name" != "$1" ] || die "-s takes NAME=VALUE, not $1"
	case $_name in
		'' | *[!a-z_]*) die "-s $1: NAME may have only lower case letters and _" ;;
	esac
	case $_value in
		*"'"* | *\\*) die "-s $1: VALUE may not have quotes or backslashes" ;;
	esac
	GUCS="$GUCS SET chunk_maint.$_name = '$_value';"
}

while getopts 'yh:p:U:d:b:t:r:w:l:m:s:Cv' opt; do
	case $opt in
		y) DO_IT=1 ;;
		h) PGHOST=$OPTARG; export PGHOST ;;
		p) PGPORT=$OPTARG; export PGPORT ;;
		U) PGUSER=$OPTARG; export PGUSER ;;
		d) PGDATABASE=$OPTARG; export PGDATABASE ;;
		b) BUDGET_GB=$OPTARG ;;
		t) TEMP_TS=$OPTARG ;;
		r) RESERVE_PCT=$OPTARG ;;
		w) WATCH=$OPTARG ;;
		l) LOCK_TIMEOUT=$OPTARG ;;
		m) MWM=$OPTARG ;;
		s) add_guc "$OPTARG" ;;
		C) USE_CLUSTER=1 ;;
		v) VERBOSE=1 ;;
		*) usage ;;
	esac
done
shift $((OPTIND - 1))
[ $# -eq 0 ] || usage

for v in "$BUDGET_GB" "$RESERVE_PCT" "$WATCH" "$LOCK_TIMEOUT"; do
	is_number "$v" || die "options -b, -r, -w and -l take a whole number"
done
[ "$BUDGET_GB" -ge 1 ] || die "-b must be at least 1"
[ "$RESERVE_PCT" -le 90 ] || die "-r must be at most 90"
[ "$LOCK_TIMEOUT" -ge 1 ] || die "-l must be at least 1"
case $TEMP_TS in
	*[!A-Za-z0-9_]*) die "-t $TEMP_TS: not a tablespace name this script accepts" ;;
esac
if [ -n "$MWM" ]; then
	is_number "${MWM%[kMG]B}" || die "-m $MWM: give a size such as 512MB or 1GB"
fi

command -v "$PSQL" >/dev/null 2>&1 || die "psql not found (set PSQL=/path/to/psql)"

PGAPPNAME=chunk-maintenance
PGCONNECT_TIMEOUT=${PGCONNECT_TIMEOUT:-15}
export PGAPPNAME PGCONNECT_TIMEOUT

BUDGET=$((BUDGET_GB * 1073741824))

# the settings for every session; temp_tablespaces is added once it is known
if [ "$USE_CLUSTER" -eq 1 ]; then
	GUCS="SET chunk_maint.use_cluster = 'on';$GUCS"
fi
SESSION="SET statement_timeout = 0; SET lock_timeout = '${LOCK_TIMEOUT}s';${MWM:+ SET maintenance_work_mem = '$MWM';}$GUCS"

cleanup() {
	if [ -n "$WORK" ]; then
		rm -rf "$WORK"
	fi
	if [ "$LOCKED" -eq 1 ]; then
		rm -rf "$LOCK_DIR"
	fi
}

take_lock() {
	if ! mkdir "$LOCK_DIR" 2>/dev/null; then
		_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null)
		if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
			stop "another run (pid $_pid) holds $LOCK_DIR"
		fi
		# left by a run that died
		rm -rf "$LOCK_DIR"
		mkdir "$LOCK_DIR" 2>/dev/null || stop "cannot take the lock $LOCK_DIR"
	fi
	LOCKED=1
	echo $$ >"$LOCK_DIR/pid"
}

# a signal stops the run once the task in hand is finished, so that it is logged
interrupted() {
	if [ "$INTERRUPTED" -eq 1 ]; then
		note "interrupted: stopping"
		exit 130
	fi
}

# ask SQL - run SQL after the session settings, and print its rows, unaligned and | separated.
# Exits the shell it runs in if the query fails, so call it as: x=$(ask "...") || exit 1
ask() {
	"$PSQL" -X -q -w -A -t -F '|' -v ON_ERROR_STOP=1 -c "$SESSION" -c "$1" 2>"$WORK/ask.err" </dev/null
	_rc=$?
	if [ "$_rc" -ne 0 ]; then
		cat "$WORK/ask.err" >&2
		die "query failed (psql exit $_rc): $1"
	fi
}

# run_sql STATEMENT... - run each statement on its own, in one session after the session settings,
# as reorder_chunk() and REINDEX CONCURRENTLY may not run in a transaction block
run_sql() {
	_n=$#
	for _s in "$@"; do
		set -- "$@" -c "$_s"
	done
	shift "$_n"
	"$PSQL" -X -q -w -A -t -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -c "$SESSION" "$@" </dev/null
}

# log_start CHUNK ACTION REASON STATEMENTS - print the ID of a new chunk_maint_log row
log_start() {
	"$PSQL" -X -q -w -A -t -v ON_ERROR_STOP=1 \
		-v chunk="$1" -v action="$2" -v reason="$3" -v stmt="$4" 2>>"$WORK/ask.err" <<'SQL'
SELECT _timescaledb_solarnetwork.chunk_maint_log_start(:'chunk', :'action', :'reason', :'stmt');
SQL
}

# log_finish ID [ERROR] - log the end of a task
log_finish() {
	"$PSQL" -X -q -w -A -t -v ON_ERROR_STOP=1 -v id="$1" -v err="${2:-}" >/dev/null 2>>"$WORK/ask.err" <<'SQL'
SELECT _timescaledb_solarnetwork.chunk_maint_log_finish(:id, NULLIF(:'err', ''));
SQL
}

# fs_info PATH - print "KEY SIZE_KB AVAIL_KB MOUNT" for the filesystem holding PATH. KEY is the
# ZFS pool for a ZFS dataset, as datasets in one pool share its space, and otherwise the device.
fs_info() {
	_fi=$(df -kP "$1" 2>/dev/null | awk 'NR == 2 { print $1, $2, $4, $NF }')
	[ -n "$_fi" ] || return 1
	if command -v zfs >/dev/null 2>&1; then
		_ds=$(zfs list -H -o name "$1" 2>/dev/null)
		if [ -n "$_ds" ]; then
			_fi="zfs:${_ds%%/*} ${_fi#* }"
		fi
	fi
	printf '%s\n' "$_fi"
}

# check_space - check that each filesystem the current task writes to has room for it, printing a
# line for each; returns 1 if one has not
check_space() {
	: >"$WORK/space"
	for _item in "new_heap:$c_hts:$c_hneed" "new_indexes:$c_its:$c_ineed" "sort_spill:$c_tts:$c_tneed" \
		"WAL:pg_wal:$c_wneed"; do
		_role=${_item%%:*}
		_rest=${_item#*:}
		_name=${_rest%%:*}
		_need=${_rest#*:}
		[ "$_need" -gt 0 ] || continue
		_path=$(awk -F '|' -v n="$_name" '$1 == n { print $2; exit }' "$WORK/storage")
		[ -n "$_path" ] || die "no directory is known for tablespace $_name"
		_fs=$(fs_info "$_path") \
			|| die "cannot read the free space of $_path ($_name): run this on the database server, as the postgres user"
		printf '%s %s %s %s\n' "$_fs" "$_need" "$_role" "$_name" >>"$WORK/space"
	done
	awk -v reserve="$RESERVE_PCT" "$AWK_PRETTY"'
		{
			k = $1
			w = $6
			gsub(/_/, " ", w)
			if (w != "WAL") w = w " in " $7
			if (!(k in need)) {
				order[++n] = k; size[k] = $2; avail[k] = $3; need[k] = 0; what[k] = w
				fs[k] = (k ~ /^zfs:/) ? "ZFS pool " substr(k, 5) : $4
			} else {
				if ($2 > size[k]) size[k] = $2
				if ($3 < avail[k]) avail[k] = $3
				what[k] = what[k] ", " w
			}
			need[k] += $5
		}
		END {
			bad = 0
			for (i = 1; i <= n; i++) {
				k = order[i]
				a = avail[k] * 1024
				r = size[k] * 1024 * reserve / 100
				ok = (a - need[k] >= r)
				printf "%s %s (%s): needs %s, %s free, keeping %s free\n", (ok ? "space ok on" : "NOT ENOUGH SPACE on"), \
					fs[k], what[k], pretty(need[k]), pretty(a), pretty(r)
				if (!ok) bad = 1
			}
			exit bad
		}' "$WORK/space" >"$WORK/space.out"
	_rc=$?
	while read -r _line; do
		note "    $_line"
	done <"$WORK/space.out"
	return "$_rc"
}

# watch_writes - return 1 if anything writes to the current chunk within $WATCH seconds
watch_writes() {
	_sql="SELECT n_tup_ins + n_tup_upd + n_tup_del FROM pg_stat_user_tables WHERE relid = '$c_chunk'::regclass"
	_w1=$(ask "$_sql") || exit 1
	note "    watching for writes for $WATCH s"
	sleep "$WATCH"
	_w2=$(ask "$_sql") || exit 1
	if ! is_number "$_w1" || ! is_number "$_w2"; then
		note "    left for another run: cannot read its write counters"
		return 1
	fi
	if [ "$_w1" != "$_w2" ]; then
		note "    left for another run: $(plural $((_w2 - _w1)) row) written to it in $WATCH s, and a rewrite blocks writes until it finishes"
		return 1
	fi
	return 0
}

# task_summary ID - describe the outcome of a logged task
task_summary() {
	ask "SELECT round(extract(epoch FROM l.finished - l.started)) || ' s'
			|| CASE
				WHEN l.action IN ('reorder', 'move', 'cluster') THEN format(', heap %s to %s, index %s to %s, correlation %s to %s'
					, pg_size_pretty(l.heap_bytes_before), pg_size_pretty(l.heap_bytes_after)
					, pg_size_pretty(l.index_bytes_before), pg_size_pretty(l.index_bytes_after)
					, COALESCE(round(l.corr_before::NUMERIC, 3)::TEXT, 'unknown')
					, COALESCE(round(l.corr_after::NUMERIC, 3)::TEXT, 'unknown'))
				WHEN l.action = 'reindex' THEN format(', index %s to %s'
					, pg_size_pretty(l.index_bytes_before), pg_size_pretty(l.index_bytes_after))
				ELSE format(', correlation %s to %s'
					, COALESCE(round(l.corr_before::NUMERIC, 3)::TEXT, 'unknown')
					, COALESCE(round(l.corr_after::NUMERIC, 3)::TEXT, 'unknown'))
				END
		FROM _timescaledb_solarnetwork.chunk_maint_log l
		WHERE l.id = $1"
}

# drop_invalid_indexes - drop the invalid index a failed REINDEX CONCURRENTLY of the current
# chunk's index leaves behind (named like it, with _ccnew or _ccold added)
drop_invalid_indexes() {
	ask "SELECT format('DROP INDEX CONCURRENTLY IF EXISTS %I.%I', n.nspname, c.relname)
		FROM pg_index i
		INNER JOIN pg_class c ON c.oid = i.indexrelid
		INNER JOIN pg_namespace n ON n.oid = c.relnamespace
		WHERE i.indrelid = '$c_chunk'::regclass
			AND NOT i.indisvalid
			AND (c.relname LIKE '%\\_ccnew%' OR c.relname LIKE '%\\_ccold%')" >"$WORK/drop.sql" || exit 1
	while read -r _drop; do
		note "    dropping the invalid index left behind: $_drop"
		run_sql "$_drop" >/dev/null 2>>"$WORK/ask.err" || note "    WARNING: could not drop it; drop it by hand"
	done <"$WORK/drop.sql"
}

# run_task ACTION REASON STATEMENT... - perform a task on the current chunk: log its start, run
# its statements in one session, and log how it ended. Returns 1 if it failed or timed out on a
# lock. In a dry run, only print the statements.
run_task() {
	_t_action=$1
	_t_reason=$2
	shift 2
	_t_sql=
	for _s in "$@"; do
		_t_sql="$_t_sql$_s; "
	done
	_t_sql=${_t_sql%; }
	TASKS=$((TASKS + 1))
	if [ "$DO_IT" -eq 0 ]; then
		note "    would run: $_t_sql"
		return 0
	fi
	note "    running: $_t_sql"
	_t_id=$(log_start "$c_chunk" "$_t_action" "$_t_reason" "$_t_sql") || exit 1
	is_number "$_t_id" || die "could not log the start of a task on $c_chunk"
	if run_sql "$@" >"$WORK/task.out" 2>"$WORK/task.err"; then
		log_finish "$_t_id" || exit 1
		note "    done: $(task_summary "$_t_id")"
		return 0
	fi
	_t_err=$(grep -E -v '^((NOTICE|INFO|DETAIL|HINT|LOCATION|CONTEXT|WARNING):|Cancel request sent)' "$WORK/task.err" \
		| head -n 5 | tr '\n' ' ' | sed 's/ *$//')
	log_finish "$_t_id" "${_t_err:-psql failed}" || exit 1
	if grep -q '55P03' "$WORK/task.err"; then
		note "    timed out waiting for a lock, so left for another run: $_t_err"
	elif grep -q '57014' "$WORK/task.err"; then
		note "    cancelled, and rolled back: $_t_err"
	else
		note "    FAILED: $_t_err"
		FAILED=$((FAILED + 1))
	fi
	if [ "$_t_action" = reindex ]; then
		drop_invalid_indexes
	fi
	return 1
}

# recheck - after analyzing the current chunk, look at it again: return 1 if it no longer needs a
# rewrite or reindex, otherwise update the c_ variables
recheck() {
	ask "SELECT COALESCE(action, ''), reason, stmt, analyze_stmt, heap_tablespace, index_tablespace
			, temp_tablespace, heap_need, index_need, temp_need, wal_need, analyze_bytes, corr
		FROM _timescaledb_solarnetwork.chunk_maint_status
		WHERE chunk = '$c_chunk'::regclass" >"$WORK/recheck" || exit 1
	r_action= r_reason= r_stmt= r_astmt= r_hts= r_its= r_tts= r_hneed= r_ineed= r_tneed= r_wneed= r_abytes= r_corr=
	IFS='|' read -r r_action r_reason r_stmt r_astmt r_hts r_its r_tts r_hneed r_ineed r_tneed r_wneed \
		r_abytes r_corr <"$WORK/recheck"
	case $r_action in
		reorder | move | cluster | reindex) ;;
		*)
			note "    no longer needed, now that it is analyzed: correlation ${r_corr:-unknown}"
			return 1
			;;
	esac
	if [ "$r_action" != "$c_action" ] || [ "$r_reason" != "$c_reason" ]; then
		note "    now: $r_action, $r_reason"
	fi
	c_action=$r_action c_reason=$r_reason c_stmt=$r_stmt c_astmt=$r_astmt c_hts=$r_hts c_its=$r_its
	c_tts=$r_tts c_hneed=$r_hneed c_ineed=$r_ineed c_tneed=$r_tneed c_wneed=$r_wneed c_abytes=$r_abytes
	return 0
}

# do_task - perform the current candidate
do_task() {
	if [ "$c_action" = analyze ]; then
		USED=$((USED + c_abytes))
		run_task analyze "$c_reason" "$c_stmt"
		return
	fi
	if [ "$c_afirst" = t ]; then
		note "    its statistics may be out of date, so analyzing it first"
		USED=$((USED + c_abytes))
		run_task analyze "check before $c_action" "$c_astmt" || return
		interrupted
		if [ "$DO_IT" -eq 1 ]; then
			recheck || return
		else
			note "    (a real run looks again here; taking the $c_action as still needed)"
		fi
	fi
	if [ "$c_action" != reindex ] && [ "$WATCH" -gt 0 ]; then
		watch_writes || return
		interrupted
	fi
	if ! check_space; then
		note "stopping: not enough space to $c_action $c_chunk"
		exit 3
	fi
	if [ "$c_moved" = t ]; then
		MOVED_DONE="$MOVED_DONE $c_hts"
	fi
	if [ "$c_action" = reindex ]; then
		USED=$((USED + c_ineed))
		run_task reindex "$c_reason" "$c_stmt"
	else
		USED=$((USED + c_hneed + c_ineed + c_abytes))
		run_task "$c_action" "$c_reason" "$c_stmt" "$c_astmt"
	fi
}


# -----------------------------------------------------------------------------
# Start
# -----------------------------------------------------------------------------

trap cleanup EXIT
trap 'INTERRUPTED=1' INT TERM HUP

take_lock
WORK=$(mktemp -d "${TMPDIR:-/tmp}/chunk-maintenance.XXXXXX") || die "cannot create a work directory"

CTX=$(ask "SELECT r.rolsuper
		, inet_server_addr() IS NULL OR inet_server_addr() <<= '127.0.0.0/8'::INET OR inet_server_addr() = '::1'::INET
		, to_regclass('_timescaledb_solarnetwork.chunk_maint_candidates') IS NOT NULL
		, current_database()
		, (SELECT t.spcname FROM pg_database d INNER JOIN pg_tablespace t ON t.oid = d.dattablespace
			WHERE d.datname = current_database())
		, (SELECT count(*) FROM pg_tablespace WHERE spcname = '$TEMP_TS')
		, COALESCE((SELECT extversion FROM pg_extension WHERE extname = 'timescaledb'), 'not installed')
		, COALESCE((SELECT extversion FROM pg_extension WHERE extname = 'pgstattuple'), 'not installed')
	FROM pg_roles r
	WHERE r.rolname = current_user") || exit 1
IFS='|' read -r IS_SUPER IS_LOCAL HAS_DDL DB_NAME DB_TS TEMP_TS_FOUND TSDB_VERSION PGST_VERSION <<EOF
$CTX
EOF
[ "$IS_SUPER" = t ] || die "connect as a superuser"
[ "$HAS_DDL" = t ] || die "install tsdb-init-hypertables-maintenance.sql in $DB_NAME first"
[ "$IS_LOCAL" = t ] || die "run this on the database server, through the local socket: it reads the server's free space"
if [ -z "$TEMP_TS" ]; then
	TEMP_TS=$DB_TS
elif [ "$TEMP_TS_FOUND" != 1 ]; then
	die "-t $TEMP_TS: no such tablespace"
fi
SESSION="$SESSION SET temp_tablespaces = '$TEMP_TS'; SET chunk_maint.temp_tablespace = '$TEMP_TS';"

if [ "$DO_IT" -eq 1 ]; then
	note "chunk maintenance of $DB_NAME"
else
	note "chunk maintenance of $DB_NAME: DRY RUN, reporting only (-y to act)"
fi
note "budget $(pretty "$BUDGET"), sorts spill to $TEMP_TS, keeping $RESERVE_PCT% of each filesystem free; timescaledb $TSDB_VERSION, pgstattuple $PGST_VERSION"
if [ "$USE_CLUSTER" -eq 1 ]; then
	note "WARNING: rewriting with CLUSTER (-C), which blocks reads of each chunk too: for testing only"
fi

# step 2: the server checks
ask "SELECT check_name, ok, detail FROM _timescaledb_solarnetwork.chunk_maint_preflight ORDER BY seq" \
	>"$WORK/preflight" || exit 1
PRE_FAILED=0
while IFS='|' read -r p_check p_ok p_detail; do
	if [ "$p_ok" != t ]; then
		note "check $p_check FAILED: $p_detail"
		PRE_FAILED=1
	elif [ "$VERBOSE" -eq 1 ]; then
		note "check $p_check: $p_detail"
	fi
done <"$WORK/preflight"
[ "$PRE_FAILED" -eq 0 ] || stop "a check failed"

ask "SELECT name, path FROM _timescaledb_solarnetwork.chunk_maint_storage" >"$WORK/storage" || exit 1

ask "SELECT priority, chunk, hypertable_name, range_end::DATE, moved, action, reason, analyze_first
		, stmt, analyze_stmt, heap_tablespace, index_tablespace, temp_tablespace
		, heap_need, index_need, temp_need, wal_need, analyze_bytes, cost
		, pg_size_pretty(heap_bytes), pg_size_pretty(index_bytes)
	FROM _timescaledb_solarnetwork.chunk_maint_candidates
	ORDER BY priority" >"$WORK/candidates" || exit 1

if [ ! -s "$WORK/candidates" ]; then
	note "finished: no chunk needs anything"
	exit 0
fi
note "$(awk -F '|' '{ n[$6]++; t++ } END {
	s = "work to do on " t (t == 1 ? " chunk:" : " chunks:")
	split("reorder move cluster reindex analyze", a, " ")
	for (i = 1; i <= 5; i++) if (a[i] in n) { s = s sep " " n[a[i]] " " a[i]; sep = "," }
	print s
}' "$WORK/candidates")"

# steps 3 to 6: the candidates, in order
USED=0
TASKS=0
LATER=0
FAILED=0
MOVED_DONE=
while IFS='|' read -r c_prio c_chunk c_ht c_end c_moved c_action c_reason c_afirst c_stmt c_astmt \
	c_hts c_its c_tts c_hneed c_ineed c_tneed c_wneed c_abytes c_cost c_hsize c_isize <&3; do
	interrupted
	if [ "$USED" -ge "$BUDGET" ]; then
		LATER=$((LATER + 1))
		continue
	fi
	c_where=
	if [ "$c_moved" = t ]; then
		c_where=" in $c_hts,"
	fi
	c_label="$c_action $c_chunk ($c_ht to $c_end,$c_where heap $c_hsize, index $c_isize)"
	if [ "$c_moved" = t ] && [ "$c_action" != analyze ] && in_list "$c_hts" "$MOVED_DONE"; then
		if [ "$VERBOSE" -eq 1 ]; then
			note "[$c_prio] later: $c_label: one rewrite or reindex in $c_hts a run"
		fi
		LATER=$((LATER + 1))
		continue
	fi
	if [ "$USED" -gt 0 ] && [ $((USED + c_cost)) -gt "$BUDGET" ]; then
		if [ "$VERBOSE" -eq 1 ]; then
			note "[$c_prio] later: $c_label: needs $(pretty "$c_cost") of the budget, $(pretty $((BUDGET - USED))) left"
		fi
		LATER=$((LATER + 1))
		continue
	fi
	note "[$c_prio] $c_label: $c_reason"
	do_task
done 3<"$WORK/candidates"
interrupted

_done=$(plural "$TASKS" task)
if [ "$DO_IT" -eq 0 ]; then
	_done="$_done would run"
fi
note "finished: $_done, $(pretty "$USED") of the $(pretty "$BUDGET") budget, $(plural "$LATER" candidate) left for later runs"
if [ "$FAILED" -gt 0 ]; then
	note "$(plural "$FAILED" task) failed: see _timescaledb_solarnetwork.chunk_maint_log"
	exit 4
fi
exit 0
