#!/bin/sh
#
# net540-backfill.sh - fill solardatm.agg_datm_15m for the hours before step 1's
# boundary (NET-540 plan section 12), and list the hours whose stored hourly row
# really differs from today's rollup (D18).
#
# Run it on the primary, as a superuser. Every hour that has an hourly row, raw
# datum and no 15 minute row gets the 15 minute rows rollup_datm_15m_for_hour()
# computes for it, the same rows stale processing would store. They are inserted
# only (ON CONFLICT DO NOTHING); the stored hourly row is never changed, and no
# audit, stale or flux record is touched. Hours with a pending stale row are left
# to stale processing. See net540-backfill-design.md for what and why.
#
# Usage:
#
#   PGSSLCERT=superuser.crt PGSSLKEY=superuser.key sh net540-backfill.sh \
#       -h db.solarnetwork.net -U postgres -d solarnetwork COMMAND [OPTIONS]
#
# Connection options are as for psql, before the command; anything libpq reads
# from the environment applies. psql is run with -w, so it never prompts.
#
#   -h HOST  -p PORT  -U USER  -d DBNAME    connection, as for psql
#   -o DIR   where to write the log, run directories and reports (default:
#            the current directory). They hold stream ids, and the report datum
#            values: a directory inside a git work tree is refused, except by
#            stop, which writes none of them and logs only to a directory the
#            other commands would accept.
#   -X       run even if a function body, the table or the server is not what
#            this script was written against (otherwise it refuses)
#
# Commands, in the order of a run:
#
#   install [-b TIME] [-E] [-S TIME]
#       Create the net540_backfill schema, where the backfill keeps its
#       progress and lists. Nothing else changes. The hours to fill are from -S
#       (default 2002-07-12 00:00:00+00, the first seeded 15 minute chunk) to
#       step 1's boundary, which must still be set, unless -b gives it. -E
#       (clock errors) adds the hours before -S and from the boundary on that
#       have an hourly row and no 15 minute row, as two last chunks.
#
#   fill -n -c CHUNK [-t COUNT] [-D DAY] [-S SEED] [worker options]
#       Dry run: compute and compare the hours of one chunk (or of COUNT of its
#       streams) without inserting or rewriting anything. It needs no boundary
#       move, so it can run first. Another dry run of the same chunk replaces
#       its lists; other chunks' dry lists stay. -D DAY
#       (YYYY-MM-DD) does only that UTC day of the chunk, every stream one after
#       another as the full fill does them: what a day costs when its datum are
#       read once for all the streams, as in a chunk whose rows lie in arrival
#       order. A dry run, like a trial, reads no raw datum but what its hours'
#       rollups read (the full fill reads a year back for a stream's first unit).
#
#   boundary -b TIME
#       Move step 1's boundary from TIME, which must be its value now and the
#       range end, to -infinity, so that stale processing computes 15 minute
#       rows for every hour from then on; then wait, as
#       NET-540-production-stale.sql does, until no session that began before
#       the move holds a lock on agg_stale_datm. Run it again after a timeout
#       to wait again. It never sets any time but -infinity.
#
#   fill -t COUNT [-c CHUNK] [-S SEED] [worker options]
#       Trial: fill COUNT streams of the oldest chunk that has work (or of
#       CHUNK), then stop. Their rows are kept; the full fill does the rest.
#       Only before the full fill starts.
#
#   fill [worker options]
#       Fill every hour, chunk by chunk from the oldest. Each unit is one stream
#       for one UTC day, done in one transaction. When a chunk is filled, it is
#       vacuumed, checked (no hour left with an hourly row, raw datum and no
#       15 minute row, other than for a reason listed), and its index rebuilt
#       with REINDEX CONCURRENTLY to pack it.
#
#     Worker options:
#         -j  computing sessions, 1 (default) to 8. Each keeps a processor
#             busy: more than half of the server's processors is for a
#             server with nothing else to do
#         -s  what to do about raw datum stored as array slices: count (the
#             default) lists them and leaves out the hours whose rollup would
#             read one; rewrite stores them from position 1 first, logged
#         -B  most units for one call of the worker (default 50)
#         -T  most seconds for one call (default 30)
#         -P  seconds to pause after each call (default 0.5)
#         -Q  hold back while the hourly stale queue is longer (default
#             10000; 0 never)
#         -L  hold back while a replica replays more bytes behind, or a
#             replication slot holds more bytes of WAL (default 1073741824; 0
#             never)
#         -r  hold back while fewer replicas stream (default: as many as when
#             the fill starts)
#         -A  hold back while WAL archiving is failing, or more WAL segments
#             than this wait to be archived (default 64; 0 never)
#         -R  hold back while a filesystem the fill writes to has less than
#             this percentage of its size free, and refuse to start then
#             (default 20; 0 never). See FREE SPACE below.
#         -M  fill although a move_chunks job is scheduled or running
#             (otherwise refused: see MOVE JOBS below)
#         -H  seconds to wait before trying again when held back, or after a
#             unit met a lock wait, deadlock or serialization failure (default
#             60)
#         -F  stop when this many units in a row fail in every hour (default
#             3; 0 never)
#         -k  stop file (default net540-backfill.stop in -o)
#         -x  do not rebuild the indexes of filled chunks (see reindex)
#
#     Errors: a unit that meets a lock wait, a deadlock or a serialization
#     failure stays listed and is tried again after -H seconds. One that raises
#     an error its data can cause (a data exception, say, or XX000, which the
#     rollup's C functions raise for a datum whose array is longer than its
#     stream's names) is done again hour by hour: the hours that fail are left
#     unfilled and listed (status, report, failed.psv), the others are filled,
#     and the fill goes on; it then exits with status 1. Any other error (out of
#     disk or memory, I/O, corruption, a missing object or privilege) stops the
#     fill, the unit still listed, with status 3, as do -F units in a row that
#     fail in every hour. A failed hour is listed until it is done: retry -c
#     CHUNK plans it again.
#
#   check [-c CHUNK]
#       Check again every chunk the fill has been to (the final check), or the
#       one given; prints the hours left without 15 minute rows, by reason. The
#       hours of a chunk the fill has not finished, where it has not been yet,
#       are counted as pending and not tested. Exit status 1 if any hour is
#       missing or failed. It waits for a check of the same chunk the fill is
#       running.
#
#   retry -c CHUNK
#       Plan a chunk afresh, after a failed check or failed hours and whatever
#       caused them is put right; the next fill does it again, only the hours
#       still unfilled.
#
#   rewrite [-n] [-B COUNT] [-P -Q -L -r -A -R -H -k as for fill]
#       Store from position 1 every raw datum still listed as a slice (state
#       found in slices.psv), logged as fill -s rewrite logs them. That mode
#       rewrites only the slices its units read, so a pass of it leaves the
#       status slices of chunks already filled, whose hours need no unit, and
#       any slice no unit came to. This does them stream by stream in time
#       order, -B datum in a transaction (default 1000), with a fill's pause
#       and holds. It fills nothing: an hour left out as slice stays so until
#       its chunk is retried and filled again, which count mode then does. -n
#       only prints how many datum it would rewrite. Run it when no fill is
#       running. It makes its own function in net540_backfill, so a schema
#       installed by an earlier copy of this script needs no new install.
#
#   reindex [-c CHUNK]
#       Rebuild the index of the done chunks not rebuilt yet (after fill -x).
#
#   status
#       Print the chunks, the totals so far, the free space of the filesystems
#       the fill writes to, and the last hour's pace (ms an hour, hours an
#       hour, and the time the planned units left would take). Before install,
#       it only runs the guard rails.
#
#   report
#       Write a report directory: summary.txt (counts only), and the lists
#       diff.psv (the real differences, to reprocess), slices.psv,
#       unfilled.psv and failed.psv, which hold stream ids.
#
#   stop
#       Ask a running fill to stop after the units its sessions are on. It only
#       sets the stop flag in the database: no guard, no output directory.
#
#   drop [-f]
#       Drop the net540_backfill schema, with its progress and lists. Refuses
#       unless every chunk is done, or -f.
#
# STOPPING. A fill stops after the units its sessions are on when `stop` is
# run, when the stop file appears, or on SIGTERM. Ctrl-C (SIGINT) stops at
# once: the units in flight are rolled back. Nothing is lost either way: a unit
# is deleted from the list in the transaction that fills it, so running fill
# again carries on where it stopped, and does nothing twice.
# rewrite stops the same ways, after the transaction it is in (Ctrl-C rolls
# that one back), and carries on when run again.
#
# FREE SPACE. The fill adds about 250 GB over weeks, so it watches the
# filesystems it writes to, as chunk-maintenance.sh (OPS-51) does before a
# rewrite: those of the tablespaces holding the 15 minute chunks still to fill
# and their indexes, of the backfill's own lists, and of pg_wal. Filesystems in
# one ZFS pool share its space and count as one. A fill refuses to start while
# one has less than -R percent of its size free, and a running fill holds back
# (as for -Q and -L) before each call of a worker until the space is there
# again. It reads the space with df, so with -R the script must run on the
# database server, through the local socket, as a user who may read those
# directories (postgres, or root); elsewhere it refuses, and -R 0 runs without
# the check. A chunk's VACUUM and REINDEX are not held: the margin is for them.
# It cannot see a replica's filesystems, which take the same rows.
#
# MOVE JOBS. A solarcommon.move_chunks job that moves a chunk during the fill
# rewrites it, blocks writes to it, and leaves the replicas behind. Unschedule
# them before the first fill, and schedule them again after the last:
#
#   SELECT job_id, scheduled FROM timescaledb_information.jobs WHERE proc_name = 'move_chunks';
#   SELECT alter_job(job_id, scheduled => FALSE) FROM timescaledb_information.jobs WHERE proc_name = 'move_chunks';
#
# A fill refuses while one is scheduled or running, unless -M.
#
# Exit status: 0 done (every chunk, or the trial or dry run's units); 1 a
# chunk's check found an hour missing, or hours failed; 2 refused or bad
# options; 3 stopped before the end (run fill again to carry on), or stopped
# by an error the units' data cannot cause.
# rewrite: 0 every listed slice rewritten, or gone; 1 some are still listed
# (run it again); 2 refused; 3 stopped before the end, or by an error.
#
# Needs psql 12 or later, and a sleep that takes fractions of a second. Written
# for POSIX sh; also runs under zsh and bash.

set -u
umask 077

# zsh gives a function's name as $0 inside it, so keep the script's name here
SCRIPT=$0
# 2: the holds on WAL archiving and replication slots (hold_reason() and work() changed)
SCRIPT_VERSION=2
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SQL_FILE=$SCRIPT_DIR/net540-backfill.sql
PSQL=${PSQL:-psql}
OUTBASE=.
ALLOW_UNKNOWN=0

# md5 of the function bodies this script was written against: step 1's rollup
# and boundary, the stale processing that writes 15 minute rows, and what the
# rollup reads through
FN_MD5='agg_datm_15m_complete_from=6b3efca26acd4a295d6b2d30fd380258
datm_has_accumulating_at=90dd4ae3500992294e952eb3f326986e
find_datm_aux_for_time_span=25736adf6674dd863ceb604fa738d860
find_datm_between=e4239f027acebb777c8826e73ce5ac41
find_datm_for_time_slot=8c6eb598f8920ddcb300b6327366e30d
find_metadata_for_stream=e263c4814155cce496f9d2a32ce44b9c
find_time_after_ts=b434ebbb0768284f7ba36c93c00076cf
find_time_before_ts=b46de5311cd411ea8130b92c6ce51633
process_one_agg_stale_datm=d3785efe9f95d9c8976b5d5d7cac4392
rollup_datm_15m_for_hour=d72a3b26891dec3956372b78bd253a85'
TABLE_COLS='stream_id:uuid,ts_start:timestamp with time zone,data_i:numeric[],data_a:numeric[],data_s:text[],data_t:text[],stat_i:numeric[],read_a:numeric[]'
PKEY_DEF='CREATE UNIQUE INDEX agg_datm_15m_pkey ON solardatm.agg_datm_15m USING btree (stream_id, ts_start DESC)'

usage() {
	sed -n '2,/^# for POSIX sh/p' "$SCRIPT" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

die() {
	printf 'net540-backfill: %s\n' "$*" >&2
	exit 2
}

is_number() {
	case $1 in
		'' | *[!0-9]*) return 1 ;;
	esac
	return 0
}

is_decimal() {
	case $1 in
		'' | . | *.*.* | *[!0-9.]*) return 1 ;;
	esac
	return 0
}

is_time() {
	case $1 in
		'' | *[!0-9:\ +.TZ-]*) return 1 ;;
	esac
	return 0
}

while getopts 'h:p:U:d:o:X' opt; do
	case $opt in
		h) PGHOST=$OPTARG; export PGHOST ;;
		p) PGPORT=$OPTARG; export PGPORT ;;
		U) PGUSER=$OPTARG; export PGUSER ;;
		d) PGDATABASE=$OPTARG; export PGDATABASE ;;
		o) OUTBASE=$OPTARG ;;
		X) ALLOW_UNKNOWN=1 ;;
		*) usage ;;
	esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || usage
CMD=$1
shift
OPTIND=1

command -v "$PSQL" >/dev/null 2>&1 || die "psql not found (set PSQL=/path/to/psql)"
PSQL_MAJOR=$("$PSQL" -V | sed -n 's/^[^0-9]*\([0-9][0-9]*\).*/\1/p')
is_number "${PSQL_MAJOR:-}" || die "cannot tell the version of $PSQL"
[ "$PSQL_MAJOR" -ge 12 ] || die "psql 12 or later is needed (found $PSQL_MAJOR)"

# in_work_tree DIR - DIR is inside a git work tree (without git: a .git in DIR or above it)
in_work_tree() {
	if command -v git >/dev/null 2>&1; then
		[ "$(git -C "$1" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]
		return
	fi
	iwt_d=$(cd "$1" && pwd -P) || return 1
	while :; do
		[ -e "$iwt_d/.git" ] && return 0
		[ "$iwt_d" != / ] || return 1
		iwt_d=$(dirname "$iwt_d")
	done
}

# the log, run directories and reports hold stream ids and datum values: keep them out of any
# repository. stop writes none of them, only the stop flag, so it works from anywhere, as it
# may be typed in a hurry: it logs only when -o is a directory the other commands accept
LOG=$OUTBASE/net540-backfill.log
if [ "$CMD" = stop ]; then
	if [ ! -d "$OUTBASE" ] || in_work_tree "$OUTBASE"; then
		LOG=
	fi
else
	[ -d "$OUTBASE" ] || die "output directory $OUTBASE does not exist"
	in_work_tree "$OUTBASE" && die "$OUTBASE is inside a git work tree: give -o a directory outside any repository"
	[ -r "$SQL_FILE" ] || die "cannot read $SQL_FILE"
fi

PGCONNECT_TIMEOUT=${PGCONNECT_TIMEOUT:-15}
export PGCONNECT_TIMEOUT

# new_dir PATH - make the directory PATH, or PATH-2, PATH-3 and so on while the one tried
# exists (two runs started in the same second), and print the one made
new_dir() {
	nd_p=$1
	nd_i=1
	while ! mkdir "$nd_p" 2>/dev/null; do
		if [ ! -e "$nd_p" ] || [ "$nd_i" -ge 99 ]; then
			mkdir "$nd_p"
			return 1
		fi
		nd_i=$((nd_i + 1))
		nd_p=$1-$nd_i
	done
	printf '%s\n' "$nd_p"
}

# note TEXT - a line on standard error, and in the log when there is one
note() {
	if [ -n "$LOG" ]; then
		printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG" >&2
	else
		printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
	fi
}

# psql_q ARGS - a short session: UTC, statement and lock timeouts, unaligned
# rows separated by |, no headers; never reads standard input
psql_q() {
	PGAPPNAME=net540-backfill "$PSQL" -X -q -w -v ON_ERROR_STOP=1 -At -F '|' \
		-c "SET timezone = 'UTC'" -c "SET statement_timeout = '60s'" -c "SET lock_timeout = '5s'" \
		"$@" </dev/null
}

# psql_long NAME LOCK_TIMEOUT ARGS - a session for long work: no statement timeout
psql_long() {
	psql_long_name=$1
	psql_long_lock=$2
	shift 2
	PGAPPNAME=$psql_long_name "$PSQL" -X -q -w -v ON_ERROR_STOP=1 -At -F '|' \
		-c "SET timezone = 'UTC'" -c "SET statement_timeout = 0" -c "SET lock_timeout = '$psql_long_lock'" \
		-c "SET jit = off" -c "SET max_parallel_workers_per_gather = 0" \
		"$@" </dev/null
}

# table ARGS - psql_q with a header and aligned columns, for people
table() {
	psql_q -P format=aligned -P tuples_only=off -P footer=off "$@"
}

# value KEY - the value of KEY=... in $FACTS
value() {
	printf '%s\n' "$FACTS" | sed -n "s/^$1=//p" | sed -n '1p'
}

# guard - what the database holds; refuses (exit 2) on anything unexpected
# unless -X. Sets FACTS.
guard() {
	FACTS=$(psql_q -c "
		SELECT 'server=' || current_setting('server_version_num');
		SELECT 'tsdb=' || COALESCE((SELECT extversion FROM pg_extension WHERE extname = 'timescaledb'), '');
		SELECT 'super=' || (SELECT rolsuper FROM pg_roles WHERE rolname = current_user);
		SELECT 'recovery=' || pg_is_in_recovery();
		SELECT 'fn:' || p.proname || '=' || string_agg(md5(p.prosrc), ',' ORDER BY md5(p.prosrc))
		FROM pg_proc p INNER JOIN pg_namespace n ON n.oid = p.pronamespace
		WHERE n.nspname = 'solardatm' AND p.proname IN ('agg_datm_15m_complete_from',
			'datm_has_accumulating_at', 'find_datm_aux_for_time_span', 'find_datm_between',
			'find_datm_for_time_slot', 'find_metadata_for_stream', 'find_time_after_ts',
			'find_time_before_ts', 'process_one_agg_stale_datm', 'rollup_datm_15m_for_hour')
		GROUP BY p.proname;
		SELECT 'table=' || COALESCE((SELECT string_agg(attname || ':' || format_type(atttypid, atttypmod), ',' ORDER BY attnum)
			FROM pg_attribute WHERE attrelid = to_regclass('solardatm.agg_datm_15m') AND attnum > 0 AND NOT attisdropped), '');
		SELECT 'hyper=' || EXISTS (SELECT 1 FROM timescaledb_information.hypertables
			WHERE hypertable_schema = 'solardatm' AND hypertable_name = 'agg_datm_15m');
		SELECT 'pkey=' || COALESCE((SELECT pg_get_indexdef(c.oid) FROM pg_class c INNER JOIN pg_namespace n ON n.oid = c.relnamespace
			WHERE n.nspname = 'solardatm' AND c.relname = 'agg_datm_15m_pkey'), '');
		SELECT 'compressed=' || COALESCE((SELECT string_agg(hypertable_name, ',') FROM timescaledb_information.hypertables
			WHERE hypertable_schema = 'solardatm' AND hypertable_name IN ('da_datm', 'agg_datm_15m') AND compression_enabled), '');
		SELECT 'triggers=' || count(*) FROM pg_trigger t
		WHERE NOT t.tgisinternal AND (
			(t.tgrelid = 'solardatm.da_datm'::regclass AND t.tgname <> 'ts_insert_blocker')
			OR t.tgrelid IN (SELECT format('%I.%I', chunk_schema, chunk_name)::regclass
				FROM timescaledb_information.chunks WHERE hypertable_schema = 'solardatm' AND hypertable_name = 'da_datm'));
		SELECT 'boundary=' || COALESCE(solardatm.agg_datm_15m_complete_from()::text, '');
		SELECT 'installed=' || EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'net540_backfill');
		SELECT 'local=' || (inet_server_addr() IS NULL OR inet_server_addr() <<= '127.0.0.0/8'::inet
			OR inet_server_addr() = '::1'::inet);
		SELECT 'movejobs=' || COALESCE(string_agg(x.job_id || CASE WHEN x.running THEN ' (running)' ELSE '' END
				, ', ' ORDER BY x.job_id), '')
		FROM (
			SELECT j.job_id, j.scheduled
				-- as timescaledb_information.job_stats finds a running job
				, EXISTS (SELECT 1 FROM pg_stat_activity a WHERE a.datname = current_database()
					AND a.application_name = j.application_name AND a.state = 'active') AS running
			FROM timescaledb_information.jobs j
			WHERE j.proc_name = 'move_chunks'
		) x
		WHERE x.scheduled OR x.running;
	") || die "cannot connect, or the checks failed"
	guard_bad=$(printf '%s\n' "$FN_MD5" | while IFS='=' read -r guard_fn guard_md5; do
		guard_have=$(value "fn:$guard_fn")
		[ "$guard_have" = "$guard_md5" ] || printf '%s\n' "solardatm.$guard_fn() is ${guard_have:-missing}, not $guard_md5"
	done)
	[ "$(value table)" = "$TABLE_COLS" ] || guard_bad="$guard_bad
solardatm.agg_datm_15m has columns $(value table)"
	[ "$(value hyper)" = true ] || guard_bad="$guard_bad
solardatm.agg_datm_15m is not a hypertable"
	[ "$(value pkey)" = "$PKEY_DEF" ] || guard_bad="$guard_bad
solardatm.agg_datm_15m_pkey is $(value pkey)"
	[ "$(value super)" = true ] || guard_bad="$guard_bad
not a superuser: VACUUM and REINDEX of the chunks, and replica lag, need one"
	[ "$(value server)" -ge 170000 ] 2>/dev/null || guard_bad="$guard_bad
PostgreSQL $(value server), not 17"
	case $(value tsdb) in
		2.19.*) ;;
		*) guard_bad="$guard_bad
TimescaleDB $(value tsdb), not 2.19" ;;
	esac
	[ "$(value recovery)" = false ] || die "this is a standby; run it on the primary"
	guard_bad=$(printf '%s\n' "$guard_bad" | sed '/^$/d')
	if [ -n "$guard_bad" ]; then
		printf '%s\n' "$guard_bad" | sed 's/^/net540-backfill: unexpected: /' >&2
		[ "$ALLOW_UNKNOWN" -eq 1 ] || die "refusing; -X runs anyway"
		note "running despite: $(printf '%s' "$guard_bad" | tr '\n' ';')"
	fi
}

need_installed() {
	[ "$(value installed)" = true ] || die "the net540_backfill schema is not installed (run install)"
	SETTING=$(psql_q -c "SELECT script_version, range_start, range_end, clock_error,
		COALESCE(boundary_moved::text, ''), COALESCE(boundary_waited::text, '') FROM net540_backfill.setting") \
		|| die "cannot read net540_backfill.setting"
	[ "${SETTING%%"|"*}" = "$SCRIPT_VERSION" ] || die "installed by version ${SETTING%%"|"*} of this script, not $SCRIPT_VERSION"
}

# need_idle - refuse while another backfill session is connected
need_idle() {
	idle_n=$(psql_q -c "SELECT count(*) FROM pg_stat_activity
		WHERE application_name LIKE 'net540-backfill%' AND datname = current_database() AND pid <> pg_backend_pid()") \
		|| die "cannot read pg_stat_activity"
	[ "$idle_n" = 0 ] || die "another backfill session is running ($idle_n sessions)"
}

chunk_option() {
	is_number "$1" || die "-c takes a chunk number (see status)"
	[ "$(psql_q -c "SELECT count(*) FROM net540_backfill.chunk WHERE chunk_no = $1")" = 1 ] || die "no chunk $1 (see status)"
}

# -----------------------------------------------------------------------------
# Free space (see FREE SPACE in the header)

# fs_info PATH - print "KEY|POOL_KB" for the filesystem holding PATH. KEY names it as
# chunk-maintenance.sh (OPS-51) does: "zfs:POOL" for a ZFS dataset, as the datasets of one pool
# share its space, and otherwise the device df gives. POOL_KB is a ZFS pool's capacity: what its
# root dataset and everything under it uses (other datasets and snapshots too), and what is free.
# df gives a dataset's size as its own data and the free space only, which makes a pool look
# emptier than it is. POOL_KB is empty where it cannot be read, or not ZFS: df's size counts
# then. Fails if PATH cannot be read.
fs_info() {
	fi_key=$(df -kP "$1" 2>/dev/null | awk 'NR == 2 { print $1 }')
	[ -n "$fi_key" ] || return 1
	fi_pool=''
	if command -v zfs >/dev/null 2>&1; then
		fi_ds=$(zfs list -H -o name "$1" 2>/dev/null | sed -n '1p')
		if [ -n "$fi_ds" ]; then
			fi_key="zfs:${fi_ds%%/*}"
			fi_pool=$(zfs list -H -p -o used,avail "${fi_ds%%/*}" 2>/dev/null \
				| awk 'NR == 1 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ { printf "%.0f", ($1 + $2) / 1024 }')
		fi
	fi
	printf '%s|%s\n' "$fi_key" "$fi_pool"
}

# space_paths - set SPACE to a line "KEY|POOL_KB|WHAT|TABLESPACE|PATH" for each directory the fill
# writes to: the tablespaces of the 15 minute table (where a new chunk goes) and of its chunks
# still to fill, of their indexes and of the backfill's lists, then pg_wal. KEY and POOL_KB are
# fs_info's, looked up here once: the checks after it run only df. Returns 1, with SPACE_ERR
# set, if it cannot.
space_paths() {
	SPACE=''
	SPACE_ERR=''
	sp_list=$(psql_q -c "
		WITH rel AS (
			SELECT 'solardatm.agg_datm_15m'::regclass AS oid
			UNION
			SELECT to_regclass(c.chunk_table) FROM net540_backfill.chunk c
			WHERE c.chunk_table IS NOT NULL AND c.status <> 'done'
		)
		, obj AS (
			SELECT 1 AS seq, '15m rows' AS what, k.reltablespace
			FROM rel INNER JOIN pg_catalog.pg_class k ON k.oid = rel.oid
			UNION
			SELECT 2, '15m index', k.reltablespace
			FROM rel INNER JOIN pg_catalog.pg_index x ON x.indrelid = rel.oid
			INNER JOIN pg_catalog.pg_class k ON k.oid = x.indexrelid
			UNION
			SELECT 3, 'lists', k.reltablespace
			FROM pg_catalog.pg_class k WHERE k.oid = 'net540_backfill.unit_log'::regclass
		)
		, ts AS (
			-- reltablespace 0 is the default tablespace of the database
			SELECT min(o.seq) AS seq, string_agg(o.what, ', ' ORDER BY o.seq) AS what, t.oid, t.spcname
			FROM obj o
			INNER JOIN pg_catalog.pg_database d ON d.datname = current_database()
			INNER JOIN pg_catalog.pg_tablespace t
				ON t.oid = CASE WHEN o.reltablespace = 0 THEN d.dattablespace ELSE o.reltablespace END
			GROUP BY t.oid, t.spcname
		)
		SELECT x.what, x.name, x.path
		FROM (
			SELECT ts.seq, ts.what, ts.spcname::text AS name
				, CASE
					WHEN ts.spcname = 'pg_default' THEN current_setting('data_directory') || '/base'
					-- an in-place tablespace is given relative to the data directory
					WHEN pg_tablespace_location(ts.oid) NOT LIKE '/%'
						THEN current_setting('data_directory') || '/' || pg_tablespace_location(ts.oid)
					ELSE pg_tablespace_location(ts.oid)
					END AS path
			FROM ts
			UNION ALL
			SELECT 9, 'WAL', 'pg_wal', current_setting('data_directory') || '/pg_wal'
		) x
		ORDER BY x.seq, x.name") || { SPACE_ERR="cannot list the tablespaces the fill writes to"; return 1; }
	while IFS='|' read -r sp_what sp_name sp_path; do
		[ -n "$sp_path" ] || continue
		if ! sp_fs=$(fs_info "$sp_path"); then
			SPACE_ERR="cannot read the free space of $sp_path ($sp_name)"
			return 1
		fi
		SPACE="$SPACE$sp_fs|$sp_what|$sp_name|$sp_path
"
	done <<EOF
$sp_list
EOF
	[ -n "$SPACE" ] || { SPACE_ERR="no directory found for the tablespaces the fill writes to"; return 1; }
}

# space_lines RESERVE [reason] - read the free space of the filesystems in $SPACE, and print a
# line for each; with "reason", print only why to hold back, on one line, with no figure that
# changes, so that the fill logs it once. Paths with one KEY are one filesystem: its smallest free
# space counts, against the pool's capacity, or the largest size df gives where that is not
# known. Returns 1 if one has less than RESERVE percent of its size free (RESERVE 0: never), and
# 2 if one cannot be read.
space_lines() {
	sl_in=''
	while IFS='|' read -r sl_key sl_pool sl_what sl_name sl_path; do
		[ -n "$sl_path" ] || continue
		sl_df=$(df -kP "$sl_path" 2>/dev/null | awk 'NR == 2 { print $2 "|" $4 "|" $NF }')
		case $sl_df in
			[0-9]*'|'[0-9]*'|'*) ;;
			*)
				printf 'cannot read the free space of %s (%s)\n' "$sl_path" "$sl_name"
				return 2
				;;
		esac
		sl_in="$sl_in$sl_key|$sl_pool|$sl_df|$sl_what|$sl_name
"
	done <<EOF
$SPACE
EOF
	# each line: KEY|POOL_KB|SIZE_KB|AVAIL_KB|MOUNT|WHAT|TABLESPACE
	printf '%s' "$sl_in" | awk -F '|' -v reserve="$1" -v mode="${2:-lines}" '
		function pretty(kb) {
			if (kb >= 1073741824) return sprintf("%.2f TB", kb / 1073741824)
			if (kb >= 1048576) return sprintf("%.1f GB", kb / 1048576)
			return sprintf("%.0f MB", kb / 1024)
		}
		{
			k = $1
			s = ($2 != "") ? $2 + 0 : $3 + 0
			w = ($7 == "pg_wal") ? $6 : $6 " in " $7
			if (!(k in size)) {
				order[++n] = k; size[k] = s; avail[k] = $4 + 0; what[k] = w
				fs[k] = (k ~ /^zfs:/) ? "ZFS pool " substr(k, 5) : $5
			} else {
				if (s > size[k]) size[k] = s
				if ($4 + 0 < avail[k]) avail[k] = $4 + 0
				what[k] = what[k] "; " w
			}
		}
		END {
			bad = 0
			why = ""
			for (i = 1; i <= n; i++) {
				k = order[i]
				pct = (size[k] > 0) ? 100 * avail[k] / size[k] : 0
				low = (reserve > 0 && pct < reserve)
				if (low) {
					bad = 1
					why = why (why == "" ? "" : ", ") fs[k]
				}
				if (mode != "reason") {
					printf "%s %s (%s): %s free of %s, %.1f%%%s\n" \
						, (low ? "NOT ENOUGH FREE SPACE on" : "free space on"), fs[k], what[k] \
						, pretty(avail[k]), pretty(size[k]), pct \
						, (reserve > 0 ? (low ? ", under the " reserve "% to keep free" : "; the fill holds under " reserve "%") : "")
				}
			}
			if (mode == "reason" && bad) printf "free space under %s%% on %s\n", reserve, why
			exit bad
		}'
}

# -----------------------------------------------------------------------------

cmd_install() {
	i_end=''
	i_start='2002-07-12 00:00:00+00'
	i_clock=false
	while getopts 'b:ES:' opt; do
		case $opt in
			b) i_end=$OPTARG ;;
			E) i_clock=true ;;
			S) i_start=$OPTARG ;;
			*) usage ;;
		esac
	done
	shift $((OPTIND - 1))
	[ $# -eq 0 ] || usage
	is_time "$i_start" || die "-S takes a time such as '2002-07-12 00:00:00+00'"
	[ -z "$i_end" ] || is_time "$i_end" || die "-b takes a time such as '2026-11-20 02:00:00+00'"
	guard
	[ "$(value installed)" = false ] || die "net540_backfill is already installed (drop it first)"
	i_b=$(value boundary)
	case $i_b in
		'') die "step 1's boundary is not set: is step 1 deployed?" ;;
		-infinity)
			[ -n "$i_end" ] || die "the boundary is already -infinity: give the range end with -b"
			;;
		*)
			if [ -z "$i_end" ]; then
				i_end=$i_b
			else
				i_same=$(psql_q -c "SELECT '$i_end'::timestamptz = '$i_b'::timestamptz") || die "bad -b"
				[ "$i_same" = t ] || die "-b $i_end is not the boundary, $i_b"
			fi
			;;
	esac
	"$PSQL" -X -q -w -v ON_ERROR_STOP=1 -1 -v script_version="$SCRIPT_VERSION" \
		-v range_start="$i_start" -v range_end="$i_end" -v clock_error="$i_clock" \
		-f "$SQL_FILE" </dev/null || die "install failed (nothing was created)"
	note "installed: hours from $i_start to $i_end, clock errors $i_clock"
}

cmd_boundary() {
	b_expect=''
	while getopts 'b:' opt; do
		case $opt in
			b) b_expect=$OPTARG ;;
			*) usage ;;
		esac
	done
	shift $((OPTIND - 1))
	[ $# -eq 0 ] || usage
	[ -n "$b_expect" ] || die "boundary needs -b with the boundary as it is now"
	is_time "$b_expect" || die "-b takes a time such as '2026-11-20 02:00:00+00'"
	guard
	need_installed
	note "moving the boundary from $b_expect to -infinity, then waiting for older sessions"
	psql_long net540-backfill 5s -c "CALL net540_backfill.move_boundary('$b_expect')" \
		|| die "the boundary phase did not finish; see the message above"
	note "boundary phase done: $(psql_q -c "SELECT 'boundary ' || solardatm.agg_datm_15m_complete_from() || ', waited ' || boundary_waited FROM net540_backfill.setting")"
}

# reindex_chunk N - rebuild chunk N's index, packed; resumable
reindex_chunk() {
	ri_info=$(psql_q -c "SELECT COALESCE(chunk_table, ''), COALESCE(index_name, '')
		FROM net540_backfill.chunk WHERE chunk_no = $1") || return 1
	ri_table=${ri_info%%"|"*}
	ri_index=${ri_info#*"|"}
	[ -n "$ri_index" ] || return 0
	# an interrupted REINDEX CONCURRENTLY leaves an invalid index behind
	for ri_old in $(psql_q -c "SELECT indexrelid::regclass FROM pg_index
			WHERE indrelid = '$ri_table'::regclass AND NOT indisvalid"); do
		note "chunk $1: dropping invalid index $ri_old"
		psql_long net540-backfill-post 10min -c "DROP INDEX CONCURRENTLY $ri_old" || return 1
	done
	note "chunk $1: reindex $ri_index"
	psql_long net540-backfill-post 10min -c "REINDEX INDEX CONCURRENTLY $ri_index" || return 1
	psql_q -c "UPDATE net540_backfill.chunk SET reindexed = now()
		, index_bytes_packed = pg_relation_size('$ri_index') WHERE chunk_no = $1" >/dev/null || return 1
}

# post_chunk N - vacuum, check and reindex a filled chunk; resumable
post_chunk() {
	pc_info=$(psql_q -c "SELECT status, COALESCE(chunk_table, ''), COALESCE(index_name, ''),
		vacuumed IS NOT NULL, reindexed IS NOT NULL FROM net540_backfill.chunk WHERE chunk_no = $1") || return 1
	IFS='|' read -r pc_status pc_table pc_index pc_vac pc_rei <<EOF
$pc_info
EOF
	if [ "$pc_status" = filled ]; then
		if [ -n "$pc_table" ] && [ "$pc_vac" = f ]; then
			note "chunk $1: vacuum"
			psql_long net540-backfill-post 10min -c "VACUUM (ANALYZE) $pc_table" || return 1
			psql_q -c "UPDATE net540_backfill.chunk SET vacuumed = now()
				, index_bytes_filled = pg_relation_size('$pc_index')
				, rows_15m = (SELECT reltuples::bigint FROM pg_class WHERE oid = '$pc_table'::regclass)
				WHERE chunk_no = $1" >/dev/null || return 1
		fi
		note "chunk $1: check"
		psql_long net540-backfill-post 10min -c "CALL net540_backfill.check_chunk($1)" || return 1
		pc_status=$(psql_q -c "SELECT status FROM net540_backfill.chunk WHERE chunk_no = $1") || return 1
		note "chunk $1: $pc_status, unfilled $(psql_q -c "SELECT unfilled FROM net540_backfill.chunk WHERE chunk_no = $1")"
	fi
	if [ "$pc_status" = checked ]; then
		if [ "$pc_rei" = f ] && [ "$NO_REINDEX" -eq 0 ]; then
			reindex_chunk "$1" || return 1
		fi
		psql_q -c "UPDATE net540_backfill.chunk SET status = 'done' WHERE chunk_no = $1 AND status = 'checked'" \
			>/dev/null || return 1
		note "chunk $1: done"
	fi
	return 0
}

# worker N - call net540_backfill.work() until it is done, stopped or fails;
# writes its last status to $RUN/worker.N
worker() {
	# the fill's shell handles the signals; psql still cancels on a terminal's Ctrl-C
	trap '' INT TERM
	wk=$1
	wk_total=0
	wk_failed=0
	wk_held=''
	wk_status=error
	while :; do
		if [ -e "$STOPFILE" ]; then
			wk_status=stop
			break
		fi
		if ! kill -0 "$MAIN_PID" 2>/dev/null; then
			wk_status=orphan
			break
		fi
		# the free space, before each call: work() cannot see it. A fill held here calls no
		# work(), which is what sees the stop flag, so look at that too
		if [ "$RESERVE" -gt 0 ]; then
			if wk_low=$(space_lines "$RESERVE" reason); then
				case $wk_held in
					'hold: free space'* | 'hold: cannot read'*)
						note "worker $wk: going on"
						wk_held=''
						;;
				esac
			else
				if [ "$(psql_q -c "SELECT stop FROM net540_backfill.control" 2>/dev/null)" = t ]; then
					wk_status=stop
					break
				fi
				wk_status="hold: $wk_low"
				[ "$wk_held" = "$wk_status" ] || note "worker $wk: $wk_status; trying again every $HOLD s"
				wk_held=$wk_status
				sleep "$HOLD"
				continue
			fi
		fi
		wk_res=$(psql_long "net540-backfill-w$wk" 10s -v VERBOSITY=verbose -c "SET synchronous_commit = off" \
			-c "CALL net540_backfill.work($wk, $DRY, '$SLICE', $BATCH, $BATCH_SECONDS, $MAX_STALE, $MAX_LAG, $REPLICAS, $PLANNED_ONLY, $MAX_FAIL_RUN, $MAX_READY)" \
			2>"$RUN/worker$wk.last")
		wk_rc=$?
		cat "$RUN/worker$wk.last" >>"$RUN/worker$wk.err"
		if [ "$wk_rc" -ne 0 ]; then
			# a lock wait, deadlock or serialization failure outside a unit (planning, say)
			wk_state=$(sed -n 's/.*ERROR:  \([0-9A-Z]\{5\}\):.*/\1/p' "$RUN/worker$wk.last" | sed -n '$p')
			case $wk_state in
				40001 | 40P01 | 55P03)
					note "worker $wk: $wk_state outside a unit; trying again in $HOLD s"
					sleep "$HOLD"
					continue
					;;
			esac
			note "worker $wk: the call failed or was cancelled (${wk_state:-no SQLSTATE}); see $RUN/worker$wk.err"
			wk_status=error
			break
		fi
		IFS='|' read -r wk_n wk_f wk_failure wk_status <<EOF
$wk_res
EOF
		is_number "$wk_n" || wk_n=0
		is_number "$wk_f" || wk_f=0
		wk_total=$((wk_total + wk_n))
		if [ "$wk_f" -gt 0 ]; then
			wk_failed=$((wk_failed + wk_f))
			note "worker $wk: FAILED: $wk_f more hours left unfilled by errors ($wk_failed by this worker), listed; the fill goes on. Last: $wk_failure"
		fi
		case $wk_status in
			ok)
				[ -z "$wk_held" ] || note "worker $wk: going on"
				wk_held=''
				printf '%s %s units\n' "$(date -u +%H:%M:%SZ)" "$wk_total" >"$RUN/worker$wk.progress"
				sleep "$PAUSE"
				;;
			hold:*)
				[ "$wk_held" = "$wk_status" ] || note "worker $wk: $wk_status; trying again every $HOLD s"
				wk_held=$wk_status
				sleep "$HOLD"
				;;
			retry:*)
				note "worker $wk: a unit met ${wk_status#retry: }; it is still listed, trying again in $HOLD s"
				sleep "$HOLD"
				;;
			error:*)
				note "worker $wk: STOPPED by ${wk_status#error: }; the unit is still listed: put the cause right, then fill again"
				stop_flag true
				break
				;;
			wait)
				sleep 2
				;;
			filled:*)
				note "worker $wk: chunk ${wk_status#filled:} filled ($wk_total units by this worker)"
				if ! post_chunk "${wk_status#filled:}"; then
					note "worker $wk: post-processing chunk ${wk_status#filled:} failed; fill again to carry on"
					wk_status=error
					break
				fi
				;;
			*)
				break
				;;
		esac
	done
	note "worker $wk: $wk_status after $wk_total units"
	printf '%s\n' "$wk_status" >"$RUN/worker.$wk"
}

stop_flag() {
	psql_q -c "UPDATE net540_backfill.control SET stop = $1, changed = now()" >/dev/null
}

cancel_workers() {
	psql_q -c "SELECT pg_cancel_backend(pid) FROM pg_stat_activity
		WHERE application_name LIKE 'net540-backfill-w%' AND datname = current_database()" >/dev/null
}

on_int() {
	note "interrupted: stopping now; the units in flight are rolled back"
	stop_flag true
	cancel_workers
}

on_term() {
	SIGNALS=$((SIGNALS + 1))
	if [ "$SIGNALS" -eq 1 ]; then
		note "stopping after the units in flight (again, or Ctrl-C, to stop at once)"
		stop_flag true
	else
		on_int
	fi
}

cmd_fill() {
	JOBS=1
	SLICE=count
	DRY=false
	TRIAL=0
	DAY=''
	CHUNK=''
	SEED=net540b
	BATCH=50
	BATCH_SECONDS=30
	PAUSE=0.5
	MAX_STALE=10000
	MAX_LAG=1073741824
	REPLICAS=''
	HOLD=60
	MAX_FAIL_RUN=3
	MAX_READY=64
	RESERVE=20
	MOVE_JOBS_OK=0
	STOPFILE=$OUTBASE/net540-backfill.stop
	NO_REINDEX=0
	while getopts 'j:s:nt:c:D:S:B:T:P:Q:L:r:H:F:k:xA:R:M' opt; do
		case $opt in
			j) JOBS=$OPTARG ;;
			s) SLICE=$OPTARG ;;
			n) DRY=true ;;
			t) TRIAL=$OPTARG ;;
			c) CHUNK=$OPTARG ;;
			D) DAY=$OPTARG ;;
			S) SEED=$OPTARG ;;
			B) BATCH=$OPTARG ;;
			T) BATCH_SECONDS=$OPTARG ;;
			P) PAUSE=$OPTARG ;;
			Q) MAX_STALE=$OPTARG ;;
			L) MAX_LAG=$OPTARG ;;
			r) REPLICAS=$OPTARG ;;
			H) HOLD=$OPTARG ;;
			F) MAX_FAIL_RUN=$OPTARG ;;
			k) STOPFILE=$OPTARG ;;
			x) NO_REINDEX=1 ;;
			A) MAX_READY=$OPTARG ;;
			R) RESERVE=$OPTARG ;;
			M) MOVE_JOBS_OK=1 ;;
			*) usage ;;
		esac
	done
	shift $((OPTIND - 1))
	[ $# -eq 0 ] || usage
	case $JOBS in [1-8]) ;; *) die "-j takes a number from 1 to 8" ;; esac
	case $SLICE in count | rewrite) ;; *) die "-s takes count or rewrite" ;; esac
	for v in "$TRIAL" "$BATCH" "$BATCH_SECONDS" "$MAX_STALE" "$MAX_LAG" "$HOLD" "$MAX_FAIL_RUN" "$MAX_READY" "$RESERVE" \
		${REPLICAS:+"$REPLICAS"}; do
		is_number "$v" || die "options -t -B -T -Q -L -r -H -F -A -R take a whole number"
	done
	[ "$RESERVE" -le 90 ] || die "-R takes a percentage, 90 at most"
	is_decimal "$PAUSE" || die "-P takes a number of seconds"
	[ "$BATCH" -ge 1 ] && [ "$BATCH_SECONDS" -ge 1 ] || die "-B and -T must be at least 1"
	case $SEED in
		'' | *[!A-Za-z0-9_.-]*) die "-S takes letters, digits and . _ -" ;;
	esac
	case $DAY in
		'' | [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
		*) die "-D takes a day as YYYY-MM-DD" ;;
	esac
	if [ "$DRY" = true ]; then
		[ -n "$CHUNK" ] || die "a dry run (-n) needs -c CHUNK"
	elif [ -n "$DAY" ]; then
		die "-D is for a dry run (-n)"
	elif [ "$TRIAL" -eq 0 ]; then
		[ -z "$CHUNK" ] || die "-c is for a dry run (-n) or a trial (-t)"
	fi
	[ ! -e "$STOPFILE" ] || die "the stop file $STOPFILE exists: remove it to start"

	guard
	need_installed
	[ -z "$CHUNK" ] || chunk_option "$CHUNK"
	if [ "$DRY" = false ]; then
		[ "$(value boundary)" = -infinity ] || die "step 1's boundary is $(value boundary): run the boundary phase first"
		case $SETTING in
			*'|') die "the boundary phase has not finished waiting: run boundary again" ;;
		esac
		if [ "$SLICE" = rewrite ]; then
			[ "$(value triggers)" = 0 ] || die "da_datm or its chunks have triggers other than ts_insert_blocker: will not rewrite slices"
			[ -z "$(value compressed)" ] || die "$(value compressed) has compression enabled: will not rewrite slices"
		fi
	fi
	need_idle
	if [ -n "$(value movejobs)" ]; then
		if [ "$MOVE_JOBS_OK" -eq 1 ]; then
			note "filling although move_chunks job(s) $(value movejobs) are scheduled or running (-M)"
		else
			die "move_chunks job(s) $(value movejobs) are scheduled or running: unschedule them first, with SELECT alter_job(job_id, scheduled => FALSE) FROM timescaledb_information.jobs WHERE proc_name = 'move_chunks', and wait for one that is running; -M fills anyway"
		fi
	fi
	if [ -z "$REPLICAS" ]; then
		REPLICAS=$(psql_q -c "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming'") \
			|| die "cannot read pg_stat_replication"
	fi
	# the free space, before anything is planned: see FREE SPACE in the header
	SPACE=''
	if [ "$RESERVE" -gt 0 ]; then
		[ "$(value local)" = true ] \
			|| die "the free space check reads the server's filesystems: run this on the database server, through the local socket, or give -R 0 to fill without it"
		space_paths || die "$SPACE_ERR: run this on the database server, as a user who may read that directory (postgres, or root), or give -R 0 to fill without the free space check"
		f_space=$(space_lines "$RESERVE")
		f_space_rc=$?
		while IFS= read -r f_line; do
			[ -z "$f_line" ] || note "$f_line"
		done <<EOF
$f_space
EOF
		[ "$f_space_rc" -eq 0 ] || die "not enough free space to start (-R $RESERVE; -R 0 fills without the check)"
	fi

	PLANNED_ONLY=false
	if [ "$DRY" = true ]; then
		PLANNED_ONLY=true
		f_have=$(psql_q -c "SELECT COALESCE(dry_plan, '') || '|' || (SELECT count(*) FROM net540_backfill.unit WHERE dry)
			FROM net540_backfill.control")
		if [ "${f_have%"|"*}" = "$CHUNK/$TRIAL/$SEED${DAY:+/$DAY}" ] && [ "${f_have##*"|"}" != 0 ]; then
			note "dry run: carrying on with the ${f_have##*"|"} dry units left"
		else
			note "dry run: planning chunk $CHUNK${DAY:+, day $DAY}, $([ "$TRIAL" -gt 0 ] && printf '%s streams' "$TRIAL" || printf 'every stream')"
			f_day_arg=''
			[ -z "$DAY" ] || f_day_arg=", p_day => '$DAY 00:00:00+00'"
			psql_long net540-backfill 10s -c "CALL net540_backfill.plan_chunk($CHUNK, true, $TRIAL, '$SEED'$f_day_arg)" \
				|| die "planning failed"
		fi
	elif [ "$TRIAL" -gt 0 ]; then
		PLANNED_ONLY=true
		f_started=$(psql_q -c "SELECT count(*) FROM net540_backfill.chunk WHERE status <> 'pending'")
		[ "$f_started" = 0 ] || die "the full fill has started: no trial now"
		f_left=$(psql_q -c "SELECT count(*) FROM net540_backfill.unit WHERE NOT dry")
		if [ "$f_left" = 0 ]; then
			if [ -n "$CHUNK" ]; then
				f_list=$CHUNK
			else
				f_list=$(psql_q -c "SELECT chunk_no FROM net540_backfill.chunk ORDER BY chunk_no")
			fi
			for f_c in $(printf '%s\n' "$f_list"); do
				psql_long net540-backfill 10s -c "CALL net540_backfill.plan_chunk($f_c, false, $TRIAL, '$SEED')" \
					|| die "planning failed"
				f_left=$(psql_q -c "SELECT count(*) FROM net540_backfill.unit WHERE NOT dry")
				if [ "$f_left" != 0 ]; then
					note "trial: $f_left units of $TRIAL streams in chunk $f_c"
					break
				fi
			done
			[ "$f_left" != 0 ] || die "no stream has hours to fill in the chunks tried"
		else
			note "trial: carrying on with the $f_left units left"
		fi
	else
		# chunks filled by an earlier run that stopped before vacuum, check or reindex
		for f_c in $(psql_q -c "SELECT chunk_no FROM net540_backfill.chunk WHERE status IN ('filled', 'checked') ORDER BY 1"); do
			post_chunk "$f_c" || die "post-processing chunk $f_c failed"
		done
	fi

	# made only now, so a fill refused or failing in its planning leaves no empty directory
	RUN=$(new_dir "$OUTBASE/net540-backfill-$(date -u +%Y%m%dT%H%M%SZ)") \
		|| die "cannot create a run directory in $OUTBASE"
	note "fill: $JOBS session(s), slices $SLICE, dry $DRY, trial $TRIAL; hold at $MAX_STALE stale, $MAX_LAG bytes lag, $REPLICAS replicas, $MAX_READY segments to archive, under $RESERVE% free; stop after $MAX_FAIL_RUN units failed in a row; log in $RUN"
	psql_q -c "UPDATE net540_backfill.control SET stop = false, fail_run = 0, changed = now()" >/dev/null \
		|| die "cannot clear the stop flag"
	SIGNALS=0
	MAIN_PID=$$
	trap on_int INT
	trap on_term TERM
	f_pids=''
	f_w=1
	while [ "$f_w" -le "$JOBS" ]; do
		worker "$f_w" &
		f_pids="$f_pids $!"
		f_w=$((f_w + 1))
	done
	# watch for the stop file, and wait for the workers
	f_stopped=0
	while :; do
		f_alive=0
		for f_p in $(printf '%s\n' "$f_pids"); do
			kill -0 "$f_p" 2>/dev/null && f_alive=$((f_alive + 1))
		done
		[ "$f_alive" -gt 0 ] || break
		if [ "$f_stopped" -eq 0 ] && [ -e "$STOPFILE" ]; then
			note "stop file found: stopping after the units in flight"
			stop_flag true
			f_stopped=1
		fi
		sleep 1
	done
	wait
	trap - INT TERM

	f_done=0
	f_error=0
	f_exit=3
	f_w=1
	while [ "$f_w" -le "$JOBS" ]; do
		f_s=$(cat "$RUN/worker.$f_w" 2>/dev/null || printf 'error')
		case $f_s in
			done) f_done=1 ;;
			failed:*) f_exit=1 ;;
			error*) f_error=1 ;;
		esac
		f_w=$((f_w + 1))
	done
	if [ "$f_exit" -ne 1 ] && [ "$f_done" -eq 1 ] && [ "$f_error" -eq 0 ]; then
		f_exit=0
		if [ "$PLANNED_ONLY" = false ]; then
			for f_c in $(psql_q -c "SELECT chunk_no FROM net540_backfill.chunk WHERE status IN ('filled', 'checked') ORDER BY 1"); do
				post_chunk "$f_c" || f_exit=3
			done
			f_open=$(psql_q -c "SELECT count(*) FROM net540_backfill.chunk WHERE status <> 'done'")
			[ "$f_open" = 0 ] || { note "$f_open chunks are not done"; [ "$f_exit" -eq 3 ] || f_exit=1; }
		fi
	fi
	f_failed=$(psql_q -c "SELECT count(*) FROM net540_backfill.failed WHERE dry = $DRY")
	if [ "${f_failed:-0}" != 0 ]; then
		note "FAILED: $f_failed hours are left unfilled by errors of their own (see status, and failed.psv in the report; retry -c CHUNK when put right)"
		[ "$f_exit" -eq 3 ] || f_exit=1
	fi
	status_text | tee -a "$LOG" >&2
	note "fill finished, exit status $f_exit"
	exit "$f_exit"
}

status_text() {
	table -c "
		SELECT chunk_no AS chunk, to_char(range_start, 'YYYY-MM-DD') AS from, to_char(range_end, 'YYYY-MM-DD') AS to
			, status, units
			, (SELECT count(*) FROM net540_backfill.unit u WHERE NOT u.dry AND u.chunk_no = c.chunk_no) AS left
			, rows_15m
			, round(index_bytes_filled / NULLIF(rows_15m, 0)::numeric, 1) AS idx_b_row
			, round(index_bytes_packed / NULLIF(rows_15m, 0)::numeric, 1) AS packed_b_row
			, unfilled
		FROM net540_backfill.chunk c
		ORDER BY chunk_no"
	table -c "
		SELECT status, count(*) AS chunks FROM net540_backfill.chunk GROUP BY 1 ORDER BY 1"
	table -c "
		SELECT dry, count(*) AS units, sum(hours) AS hours, sum(rows_15m) AS rows_15m
			, sum(n_same) AS same, sum(n_text_only + n_pad) AS writing, sum(n_round9) AS round9
			, sum(n_noise) AS noise, sum(n_no_raw) AS no_raw, sum(n_read_end) AS read_end, sum(n_compact) AS compact
			, sum(n_other) AS other, sum(n_stored_only) AS stored_only, sum(n_stale) AS stale, sum(n_slice) AS slice
			, sum(n_no_slots) AS no_slots, sum(n_error) AS error
			, sum(slices_found) AS slices, sum(slices_rewritten) AS rewritten
			, round((sum(ms_probe + ms_compute) / NULLIF(sum(hours), 0))::numeric, 2) AS ms_hour
		FROM net540_backfill.unit_log GROUP BY dry ORDER BY dry"
	# hours a fill left unfilled by errors: loud, by SQLSTATE (the messages are in failed.psv).
	# Hours only a dry run listed are not unfilled, so they are shown apart, not as failed
	for st_dry in false true; do
		st_failed=$(psql_q -c "SELECT count(*) FROM net540_backfill.failed WHERE dry = $st_dry")
		[ "${st_failed:-0}" != 0 ] || continue
		if [ "$st_dry" = false ]; then
			printf '\n*** FAILED: %s hours left unfilled by errors of their own (failed.psv in the report has them) ***\n' "$st_failed"
		else
			printf '\nA dry run listed %s hours that raised an error (failed.psv in the report has them, as dry):\n' "$st_failed"
		fi
		table -c "
			SELECT dry, sqlstate, count(*) AS hours, count(DISTINCT stream_id) AS streams
				, string_agg(DISTINCT chunk_no::text, ' ') AS chunks, min(ts_start) AS first, max(ts_start) AS last
			FROM net540_backfill.failed WHERE dry = $st_dry GROUP BY 1, 2 ORDER BY 1, 2"
	done
	# the free space of the filesystems the fill writes to (see FREE SPACE in the header); a fill
	# says what it holds under
	printf '\nFree space, where the fill writes:\n'
	if [ "$(value local)" != true ]; then
		printf '(not read: this is not run on the database server)\n'
	elif space_paths; then
		space_lines "${RESERVE:-0}" || :
	else
		printf '(%s)\n' "$SPACE_ERR"
	fi
	# the rate lately: ms_hour is one session's time for an hour, hours_an_hour what all the
	# sessions together fill an hour, and planned_left_in when the units planned so far are done
	printf '\nThe last hour:\n'
	table -c "
		WITH r AS (
			SELECT count(*) AS units, COALESCE(sum(hours), 0) AS hours, count(DISTINCT worker) AS sessions
				, round((sum(ms_probe + ms_compute) / NULLIF(sum(hours), 0))::numeric, 2) AS ms_hour
				, sum(hours) * 3600 / NULLIF(extract(epoch FROM max(done) - min(done)), 0) AS rate
			FROM net540_backfill.unit_log WHERE NOT dry AND done > now() - INTERVAL 'PT1H'
		), l AS (
			SELECT COALESCE(sum(hours), 0) AS left_hours FROM net540_backfill.unit WHERE NOT dry
		)
		SELECT r.units, r.hours, r.sessions, r.ms_hour, round(r.rate) AS hours_an_hour
			, l.left_hours AS planned_hours_left
			, date_trunc('minute', l.left_hours / NULLIF(r.rate, 0) * INTERVAL 'PT1H') AS planned_left_in
		FROM r, l"
}

cmd_status() {
	[ $# -eq 0 ] || usage
	guard
	[ -z "$(value movejobs)" ] \
		|| printf 'move_chunks job(s) %s are scheduled or running: a fill refuses until they are unscheduled (see MOVE JOBS in the header)\n' "$(value movejobs)"
	need_installed
	printf 'version|range start|range end|clock errors|boundary moved|waited\n%s\nboundary now %s\n' \
		"$SETTING" "$(value boundary)"
	status_text
}

cmd_check() {
	k_chunk=''
	while getopts 'c:' opt; do
		case $opt in
			c) k_chunk=$OPTARG ;;
			*) usage ;;
		esac
	done
	shift $((OPTIND - 1))
	[ $# -eq 0 ] || usage
	guard
	need_installed
	if [ -n "$k_chunk" ]; then
		chunk_option "$k_chunk"
		k_list=$k_chunk
	else
		# the chunks the fill has been to: a pending chunk has nothing to check, unless a trial
		# filled some of its streams
		k_list=$(psql_q -c "SELECT chunk_no FROM net540_backfill.chunk c WHERE status <> 'pending'
			OR EXISTS (SELECT 1 FROM net540_backfill.unit_log l WHERE NOT l.dry AND l.chunk_no = c.chunk_no)
			ORDER BY 1")
	fi
	for k_c in $(printf '%s\n' "$k_list"); do
		# the status of a chunk not yet filled, or done, is left alone
		k_set=$(psql_q -c "SELECT status IN ('filled', 'checked', 'failed') FROM net540_backfill.chunk WHERE chunk_no = $k_c")
		psql_long net540-backfill 10s -c "CALL net540_backfill.check_chunk($k_c, $([ "$k_set" = t ] && printf true || printf false))" \
			|| die "check of chunk $k_c failed"
		note "chunk $k_c: $(psql_q -c "SELECT status || ' ' || unfilled FROM net540_backfill.chunk WHERE chunk_no = $k_c")"
	done
	table -c "SELECT reason, count(*) AS hours, count(DISTINCT stream_id) AS streams
		FROM net540_backfill.unfilled GROUP BY 1 ORDER BY 1"
	k_pending=$(psql_q -c "SELECT COALESCE(sum((unfilled ->> 'pending')::bigint), 0) FROM net540_backfill.chunk")
	[ "$k_pending" = 0 ] || note "$k_pending hours pending: not filled yet"
	k_missing=$(psql_q -c "SELECT count(*) FROM net540_backfill.unfilled WHERE reason IN ('missing', 'error')")
	[ "$k_missing" = 0 ] || { note "$k_missing hours missing or failed"; exit 1; }
}

cmd_retry() {
	r_chunk=''
	while getopts 'c:' opt; do
		case $opt in
			c) r_chunk=$OPTARG ;;
			*) usage ;;
		esac
	done
	shift $((OPTIND - 1))
	[ $# -eq 0 ] && [ -n "$r_chunk" ] || usage
	guard
	need_installed
	chunk_option "$r_chunk"
	need_idle
	psql_q -c "CALL net540_backfill.retry_chunk($r_chunk)" || die "retry failed"
	note "chunk $r_chunk: planned afresh by the next fill"
}

# rewrite_sql - the SQL of the rewrite command: one batch. It is here and not in
# net540-backfill.sql, and the command creates it, so that a schema an earlier copy of this
# script installed can run it without a new install (SCRIPT_VERSION is unchanged); drop takes
# it with the schema. Its statements on the datum are fill_unit()'s for -s rewrite.
rewrite_sql() {
	cat <<'EOF'
/*
 * Rewrite the next slices still listed as found: at most p_rows datum of one stream, the first
 * after (p_after_sid, p_after_ts) in stream then time order. As fill_unit() does in rewrite
 * mode: lock the datum, log the arrays they hold now, store them from position 1 with NULL in
 * the leading places, and mark them rewritten; a datum that is gone, or no longer a slice, is
 * marked gone. One call is one transaction. p_status: ok (call again, from p_sid and p_ts),
 * done (no slice is listed as found after that place), stop (control.stop is set), or
 * hold: .. (hold_reason()).
 */
CREATE OR REPLACE FUNCTION net540_backfill.rewrite_found(
		p_after_sid		UUID,
		p_after_ts		TIMESTAMP WITH TIME ZONE,
		p_rows			INTEGER,
		p_max_stale		INTEGER,
		p_max_lag		BIGINT,
		p_replicas		INTEGER,
		p_max_ready		INTEGER,
		OUT p_status	TEXT,
		OUT p_sid		UUID,
		OUT p_ts		TIMESTAMP WITH TIME ZONE,
		OUT p_rewritten	INTEGER,
		OUT p_gone		INTEGER
	) LANGUAGE plpgsql VOLATILE AS $fn$
DECLARE
	reason		TEXT;
	sid			UUID;
	lo			TIMESTAMP WITH TIME ZONE;
	rw_ts		TIMESTAMP WITH TIME ZONE[];
	rw_done		TIMESTAMP WITH TIME ZONE[];
BEGIN
	p_sid := p_after_sid;
	p_ts := p_after_ts;
	p_rewritten := 0;
	p_gone := 0;
	IF (SELECT stop FROM net540_backfill.control) THEN
		p_status := 'stop';
		RETURN;
	END IF;
	reason := net540_backfill.hold_reason(p_max_stale, p_max_lag, p_replicas, p_max_ready);
	IF reason IS NOT NULL THEN
		p_status := 'hold: ' || reason;
		RETURN;
	END IF;
	SELECT s.stream_id INTO sid
	FROM net540_backfill.slice s
	WHERE (s.stream_id, s.ts) > (p_after_sid, p_after_ts) AND s.state = 'found'
	ORDER BY s.stream_id, s.ts
	LIMIT 1;
	IF sid IS NULL THEN
		p_status := 'done';
		RETURN;
	END IF;
	p_status := 'ok';
	-- the stream's probe row keeps this and a unit of a fill apart, as it does two units
	INSERT INTO net540_backfill.probe (stream_id) VALUES (sid) ON CONFLICT DO NOTHING;
	PERFORM 1 FROM net540_backfill.probe WHERE stream_id = sid FOR UPDATE;
	lo := CASE WHEN sid = p_after_sid THEN p_after_ts ELSE '-infinity' END;
	SELECT array_agg(x.ts ORDER BY x.ts) INTO rw_ts
	FROM (
		SELECT s.ts FROM net540_backfill.slice s
		WHERE s.stream_id = sid AND s.ts > lo AND s.state = 'found'
		ORDER BY s.ts
		LIMIT p_rows
	) x;
	IF rw_ts IS NULL THEN
		-- a unit of a fill rewrote them meanwhile: the next call looks again from the same place
		RETURN;
	END IF;
	-- lock the datum and log the arrays they hold now, then rewrite them
	EXECUTE format($q$
		UPDATE net540_backfill.slice s
		SET old_i = d.data_i, old_a = d.data_a, old_s = d.data_s
		FROM (
			SELECT d.ts, d.data_i, d.data_a, d.data_s
			FROM solardatm.da_datm d
			WHERE d.stream_id = %1$L::uuid
				AND d.ts >= %2$L::timestamptz AND d.ts <= %3$L::timestamptz
				AND d.ts = ANY (%4$L::timestamptz[])
			FOR UPDATE
		) d
		WHERE s.stream_id = %1$L::uuid AND s.ts = d.ts
		$q$, sid, rw_ts[1], rw_ts[cardinality(rw_ts)], rw_ts);
	EXECUTE format($q$
		WITH u AS (
			UPDATE solardatm.da_datm d SET
				  data_i = CASE WHEN array_lower(d.data_i, 1) > 1
					THEN array_fill(NULL::NUMERIC, ARRAY[array_lower(d.data_i, 1) - 1]) || d.data_i
					ELSE d.data_i END
				, data_a = CASE WHEN array_lower(d.data_a, 1) > 1
					THEN array_fill(NULL::NUMERIC, ARRAY[array_lower(d.data_a, 1) - 1]) || d.data_a
					ELSE d.data_a END
				, data_s = CASE WHEN array_lower(d.data_s, 1) > 1
					THEN array_fill(NULL::TEXT, ARRAY[array_lower(d.data_s, 1) - 1]) || d.data_s
					ELSE d.data_s END
			WHERE d.stream_id = %1$L::uuid
				AND d.ts >= %2$L::timestamptz AND d.ts <= %3$L::timestamptz
				AND d.ts = ANY (%4$L::timestamptz[])
				AND (array_lower(d.data_i, 1) > 1 OR array_lower(d.data_a, 1) > 1
					OR array_lower(d.data_s, 1) > 1)
			RETURNING d.ts
		)
		SELECT COALESCE(array_agg(u.ts), '{}') FROM u
		$q$, sid, rw_ts[1], rw_ts[cardinality(rw_ts)], rw_ts) INTO rw_done;
	UPDATE net540_backfill.slice s
	SET state = CASE WHEN s.ts = ANY (rw_done) THEN 'rewritten' ELSE 'gone' END
		, rewritten = now()
	WHERE s.stream_id = sid AND s.ts = ANY (rw_ts);
	p_sid := sid;
	p_ts := rw_ts[cardinality(rw_ts)];
	p_rewritten := cardinality(rw_done);
	p_gone := cardinality(rw_ts) - p_rewritten;
END
$fn$;
EOF
}

# rw_wait SECONDS - wait, a second at a time, until a signal or the stop file
rw_wait() {
	rw_w=$1
	while [ "$rw_w" -gt 0 ] && [ "$RW_SIGNAL" -eq 0 ] && [ ! -e "$STOPFILE" ]; do
		sleep 1
		rw_w=$((rw_w - 1))
	done
}

cmd_rewrite() {
	DRY=false
	BATCH=1000
	PAUSE=0.5
	MAX_STALE=10000
	MAX_LAG=1073741824
	REPLICAS=''
	HOLD=60
	MAX_READY=64
	RESERVE=20
	STOPFILE=$OUTBASE/net540-backfill.stop
	while getopts 'nB:P:Q:L:r:H:k:A:R:' opt; do
		case $opt in
			n) DRY=true ;;
			B) BATCH=$OPTARG ;;
			P) PAUSE=$OPTARG ;;
			Q) MAX_STALE=$OPTARG ;;
			L) MAX_LAG=$OPTARG ;;
			r) REPLICAS=$OPTARG ;;
			H) HOLD=$OPTARG ;;
			k) STOPFILE=$OPTARG ;;
			A) MAX_READY=$OPTARG ;;
			R) RESERVE=$OPTARG ;;
			*) usage ;;
		esac
	done
	shift $((OPTIND - 1))
	[ $# -eq 0 ] || usage
	for v in "$BATCH" "$MAX_STALE" "$MAX_LAG" "$HOLD" "$MAX_READY" "$RESERVE" ${REPLICAS:+"$REPLICAS"}; do
		is_number "$v" || die "options -B -Q -L -r -H -A -R take a whole number"
	done
	[ "$RESERVE" -le 90 ] || die "-R takes a percentage, 90 at most"
	is_decimal "$PAUSE" || die "-P takes a number of seconds"
	[ "$BATCH" -ge 1 ] || die "-B must be at least 1"

	guard
	need_installed
	rw_have=$(psql_q -c "SELECT count(*), count(DISTINCT stream_id)
			, count(*) FILTER (WHERE lower_i IS NULL AND lower_a IS NULL)
		FROM net540_backfill.slice WHERE state = 'found'") || die "cannot read net540_backfill.slice"
	IFS='|' read -r rw_left rw_streams rw_s_only <<EOF
$rw_have
EOF
	note "rewrite: $rw_left datum are listed as slices still stored so, on $rw_streams streams; $rw_s_only of them in data_s only"
	if [ "$DRY" = true ]; then
		note "rewrite: nothing changed (-n)"
		exit 0
	fi
	if [ "$rw_left" = 0 ]; then
		note "rewrite: nothing to rewrite"
		exit 0
	fi
	[ ! -e "$STOPFILE" ] || die "the stop file $STOPFILE exists: remove it to start"
	[ "$(value triggers)" = 0 ] || die "da_datm or its chunks have triggers other than ts_insert_blocker: will not rewrite slices"
	[ -z "$(value compressed)" ] || die "$(value compressed) has compression enabled: will not rewrite slices"
	need_idle
	if [ -z "$REPLICAS" ]; then
		REPLICAS=$(psql_q -c "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming'") \
			|| die "cannot read pg_stat_replication"
	fi
	# the free space, as a fill checks it. A rewritten datum takes a new row version in its own
	# da_datm chunk, whose filesystem is not among those watched: a few hundred bytes a datum
	SPACE=''
	if [ "$RESERVE" -gt 0 ]; then
		[ "$(value local)" = true ] \
			|| die "the free space check reads the server's filesystems: run this on the database server, through the local socket, or give -R 0 to rewrite without it"
		space_paths || die "$SPACE_ERR: run this on the database server, as a user who may read that directory (postgres, or root), or give -R 0 to rewrite without the free space check"
		rw_space=$(space_lines "$RESERVE")
		rw_space_rc=$?
		while IFS= read -r rw_line; do
			[ -z "$rw_line" ] || note "$rw_line"
		done <<EOF
$rw_space
EOF
		[ "$rw_space_rc" -eq 0 ] || die "not enough free space to start (-R $RESERVE; -R 0 rewrites without the check)"
	fi
	rewrite_sql | PGAPPNAME=net540-backfill "$PSQL" -X -q -w -v ON_ERROR_STOP=1 -1 -f - >/dev/null \
		|| die "cannot create net540_backfill.rewrite_found()"

	RUN=$(new_dir "$OUTBASE/net540-backfill-$(date -u +%Y%m%dT%H%M%SZ)") \
		|| die "cannot create a run directory in $OUTBASE"
	note "rewrite: $BATCH datum a transaction; hold at $MAX_STALE stale, $MAX_LAG bytes lag, $REPLICAS replicas, $MAX_READY segments to archive, under $RESERVE% free; log in $RUN"
	psql_q -c "UPDATE net540_backfill.control SET stop = false, changed = now()" >/dev/null \
		|| die "cannot clear the stop flag"
	RW_SIGNAL=0
	trap 'RW_SIGNAL=1' INT TERM
	rw_sid=00000000-0000-0000-0000-000000000000
	rw_ts=-infinity
	rw_total=0
	rw_total_gone=0
	rw_calls=0
	rw_held=''
	rw_end=error
	while :; do
		if [ "$RW_SIGNAL" -ne 0 ]; then
			note "rewrite: interrupted"
			rw_end=stop
			break
		fi
		if [ -e "$STOPFILE" ]; then
			note "rewrite: stop file found"
			rw_end=stop
			break
		fi
		# the free space, before each call: the function cannot see it
		if [ "$RESERVE" -gt 0 ]; then
			if rw_low=$(space_lines "$RESERVE" reason); then
				case $rw_held in
					'hold: free space'* | 'hold: cannot read'*)
						note "rewrite: going on"
						rw_held=''
						;;
				esac
			else
				if [ "$(psql_q -c "SELECT stop FROM net540_backfill.control" 2>/dev/null)" = t ]; then
					rw_end=stop
					break
				fi
				[ "$rw_held" = "hold: $rw_low" ] || note "rewrite: hold: $rw_low; trying again every $HOLD s"
				rw_held="hold: $rw_low"
				rw_wait "$HOLD"
				continue
			fi
		fi
		rw_res=$(psql_long net540-backfill-rw 10s -v VERBOSITY=verbose -c "SET synchronous_commit = off" \
			-c "SELECT p_status, p_sid, p_ts, p_rewritten, p_gone FROM net540_backfill.rewrite_found('$rw_sid', '$rw_ts', $BATCH, $MAX_STALE, $MAX_LAG, $REPLICAS, $MAX_READY)" \
			2>"$RUN/rewrite.last")
		rw_rc=$?
		cat "$RUN/rewrite.last" >>"$RUN/rewrite.err"
		if [ "$rw_rc" -ne 0 ]; then
			# cancelled by Ctrl-C: the top of the loop says so
			[ "$RW_SIGNAL" -eq 0 ] || continue
			rw_state=$(sed -n 's/.*ERROR:  \([0-9A-Z]\{5\}\):.*/\1/p' "$RUN/rewrite.last" | sed -n '$p')
			case $rw_state in
				40001 | 40P01 | 55P03)
					note "rewrite: $rw_state; trying again in $HOLD s"
					rw_wait "$HOLD"
					continue
					;;
			esac
			note "rewrite: STOPPED: the call failed (${rw_state:-no SQLSTATE}); see $RUN/rewrite.err"
			break
		fi
		IFS='|' read -r rw_status rw_sid_new rw_ts_new rw_n rw_g <<EOF
$rw_res
EOF
		case $rw_status in
			ok)
				[ -z "$rw_held" ] || note "rewrite: going on"
				rw_held=''
				rw_sid=$rw_sid_new
				rw_ts=$rw_ts_new
				rw_total=$((rw_total + rw_n))
				rw_total_gone=$((rw_total_gone + rw_g))
				rw_calls=$((rw_calls + 1))
				printf '%s %s rewritten, %s gone\n' "$(date -u +%H:%M:%SZ)" "$rw_total" "$rw_total_gone" >"$RUN/rewrite.progress"
				[ $((rw_calls % 100)) -ne 0 ] || note "rewrite: $rw_total datum rewritten so far, $rw_total_gone no longer slices"
				sleep "$PAUSE"
				;;
			hold:*)
				[ "$rw_held" = "$rw_status" ] || note "rewrite: $rw_status; trying again every $HOLD s"
				rw_held=$rw_status
				rw_wait "$HOLD"
				;;
			done)
				rw_end=done
				break
				;;
			stop)
				rw_end=stop
				break
				;;
			*)
				note "rewrite: STOPPED: an answer that is none of ok, hold, done or stop; see $RUN/rewrite.err"
				break
				;;
		esac
	done
	trap - INT TERM
	rw_now=$(psql_q -c "SELECT count(*) FROM net540_backfill.slice WHERE state = 'found'") || rw_now='?'
	note "rewrite: $rw_total datum rewritten, $rw_total_gone no longer slices (marked gone); $rw_now still listed as found"
	rw_out=$(psql_q -c "SELECT COALESCE(sum(x.n), 0), COALESCE(string_agg(x.chunk_no::text, ', ' ORDER BY x.chunk_no), '')
		FROM (SELECT chunk_no, count(*) AS n FROM net540_backfill.skipped WHERE NOT dry AND reason = 'slice' GROUP BY 1) x") \
		|| rw_out='0|'
	[ "${rw_out%%"|"*}" = 0 ] \
		|| note "rewrite: hours still left out as slice: ${rw_out%%"|"*}, in chunk(s) ${rw_out#*"|"}; when a chunk's fill is finished, retry -c it and fill again"
	case $rw_end in
		done)
			if [ "$rw_now" = 0 ]; then
				note "rewrite finished, exit status 0"
				exit 0
			fi
			note "rewrite finished with slices still listed as found: run it again; exit status 1"
			exit 1
			;;
		stop)
			note "rewrite stopped: run it again to carry on; exit status 3"
			exit 3
			;;
	esac
	note "rewrite stopped by an error, exit status 3"
	exit 3
}

cmd_reindex() {
	x_chunk=''
	while getopts 'c:' opt; do
		case $opt in
			c) x_chunk=$OPTARG ;;
			*) usage ;;
		esac
	done
	shift $((OPTIND - 1))
	[ $# -eq 0 ] || usage
	guard
	need_installed
	[ -z "$x_chunk" ] || chunk_option "$x_chunk"
	need_idle
	for x_c in $(psql_q -c "SELECT chunk_no FROM net540_backfill.chunk WHERE status = 'done' AND reindexed IS NULL
			AND index_name IS NOT NULL $([ -n "$x_chunk" ] && printf 'AND chunk_no = %s' "$x_chunk") ORDER BY 1"); do
		reindex_chunk "$x_c" || die "reindex of chunk $x_c failed; run reindex again"
	done
	note "reindex done"
}

cmd_report() {
	[ $# -eq 0 ] || usage
	guard
	need_installed
	R=$(new_dir "$OUTBASE/net540-backfill-report-$(date -u +%Y%m%dT%H%M%SZ)") \
		|| die "cannot create a report directory in $OUTBASE"
	{
		printf 'net540-backfill report %s\nrange %s\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SETTING"
		status_text
		printf '\nBy year of the hour (units log):\n'
		table -c "
			SELECT dry, extract(year FROM day)::integer AS year, count(*) AS units, sum(hours) AS hours
				, sum(rows_15m) AS rows_15m, sum(n_same) AS same, sum(n_text_only + n_pad) AS writing
				, sum(n_round9) AS round9, sum(n_noise) AS noise, sum(n_no_raw) AS no_raw
				, sum(n_read_end) AS read_end, sum(n_compact) AS compact, sum(n_other) AS other
				, sum(n_stored_only) AS stored_only, sum(n_stale) AS stale, sum(n_slice) AS slice
				, sum(n_no_slots) AS no_slots, sum(n_error) AS error
				, round((sum(ms_compute) / NULLIF(sum(hours), 0))::numeric, 2) AS ms_hour
				, round((sum(ms_probe) / count(*))::numeric, 2) AS ms_probe_unit
				, round((sum(ms_probe + ms_compute) / NULLIF(sum(hours), 0))::numeric, 2) AS ms_hour_all
			FROM net540_backfill.unit_log GROUP BY 1, 2 ORDER BY 1, 2"
		# a unit's probe reads its day's raw datum before the rollups do, so cold reads show in
		# ms_probe, the rollups' own work in ms_hour, and what an hour costs in ms_hour_all
		printf '\nProbe by kind of unit (exact: a dry run or a trial):\n'
		table -c "
			SELECT dry, exact, count(*) AS units, sum(hours) AS hours, sum(n_prefix) AS prefix_hours
				, round((sum(ms_probe) / count(*))::numeric, 2) AS ms_probe_unit
				, round((sum(ms_compute) / NULLIF(sum(hours), 0))::numeric, 2) AS ms_hour
				, round((sum(ms_probe + ms_compute) / NULLIF(sum(hours), 0))::numeric, 2) AS ms_hour_all
			FROM net540_backfill.unit_log GROUP BY 1, 2 ORDER BY 1, 2"
		printf '\nReal differences by verdict, kind and year:\n'
		table -c "
			SELECT dry, verdict, kind, extract(year FROM ts_start)::integer AS year, count(*) AS hours
				, count(DISTINCT stream_id) AS streams
			FROM net540_backfill.diff GROUP BY 1, 2, 3, 4 ORDER BY 1, 2, 3, 4"
		printf '\nReal differences by column codes (most common 40):\n'
		table -c "
			SELECT dry, verdict, cols, count(*) AS hours FROM net540_backfill.diff
			GROUP BY 1, 2, 3 ORDER BY 4 DESC LIMIT 40"
		printf '\nSlices by state:\n'
		table -c "
			SELECT state, count(*) FILTER (WHERE lower_i IS NOT NULL) AS data_i
				, count(*) FILTER (WHERE lower_a IS NOT NULL) AS data_a
				, count(*) FILTER (WHERE lower_s IS NOT NULL) AS data_s
				, count(DISTINCT stream_id) AS streams, min(ts)::date AS first, max(ts)::date AS last
			FROM net540_backfill.slice GROUP BY 1 ORDER BY 1"
		printf '\nHours left out:\n'
		table -c "SELECT dry, reason, count(*) AS hours, count(DISTINCT stream_id) AS streams
			FROM net540_backfill.skipped GROUP BY 1, 2 ORDER BY 1, 2"
		printf '\nUnfilled hours by reason (from the last check of each chunk):\n'
		table -c "SELECT reason, count(*) AS hours, count(DISTINCT stream_id) AS streams
			FROM net540_backfill.unfilled GROUP BY 1 ORDER BY 1"
		printf '\nFailed hours (left unfilled by errors of their own; see failed.psv):\n'
		table -c "SELECT dry, sqlstate, count(*) AS hours, count(DISTINCT stream_id) AS streams
			FROM net540_backfill.failed WHERE NOT dry GROUP BY 1, 2 ORDER BY 1, 2"
		printf '\nHours a dry run listed that raised an error (see failed.psv, as dry):\n'
		table -c "SELECT dry, sqlstate, count(*) AS hours, count(DISTINCT stream_id) AS streams
			FROM net540_backfill.failed WHERE dry GROUP BY 1, 2 ORDER BY 1, 2"
	} >"$R/summary.txt" 2>&1
	psql_q -P tuples_only=off -P footer=off -c "SELECT dry, stream_id, ts_start, verdict, cols, kind, stored_md5, chunk_no
		FROM net540_backfill.diff ORDER BY dry, stream_id, ts_start" >"$R/diff.psv"
	psql_q -P tuples_only=off -P footer=off -c "SELECT stream_id, ts, state, lower_i, lower_a, lower_s, found, rewritten
		, old_i, old_a, old_s FROM net540_backfill.slice ORDER BY stream_id, ts" >"$R/slices.psv"
	psql_q -P tuples_only=off -P footer=off -c "SELECT chunk_no, stream_id, ts_start, reason FROM net540_backfill.unfilled
		ORDER BY chunk_no, stream_id, ts_start" >"$R/unfilled.psv"
	psql_q -P tuples_only=off -P footer=off -c "SELECT dry, chunk_no, stream_id, ts_start, day, at, sqlstate, message
		FROM net540_backfill.failed ORDER BY dry, stream_id, ts_start" >"$R/failed.psv"
	note "wrote $R"
}

cmd_stop() {
	[ $# -eq 0 ] || usage
	stop_flag true || die "cannot set the stop flag (is net540_backfill installed?)"
	note "asked the fill to stop"
}

cmd_drop() {
	d_force=0
	while getopts 'f' opt; do
		case $opt in
			f) d_force=1 ;;
			*) usage ;;
		esac
	done
	shift $((OPTIND - 1))
	[ $# -eq 0 ] || usage
	guard
	need_installed
	need_idle
	d_open=$(psql_q -c "SELECT count(*) FROM net540_backfill.chunk WHERE status <> 'done'")
	[ "$d_open" = 0 ] || [ "$d_force" -eq 1 ] || die "$d_open chunks are not done: -f to drop anyway"
	psql_q -c "DROP SCHEMA net540_backfill CASCADE" || die "drop failed"
	note "dropped net540_backfill"
}

case $CMD in
	install) cmd_install "$@" ;;
	boundary) cmd_boundary "$@" ;;
	fill) cmd_fill "$@" ;;
	check) cmd_check "$@" ;;
	retry) cmd_retry "$@" ;;
	rewrite) cmd_rewrite "$@" ;;
	reindex) cmd_reindex "$@" ;;
	status) cmd_status "$@" ;;
	report) cmd_report "$@" ;;
	stop) cmd_stop "$@" ;;
	drop) cmd_drop "$@" ;;
	*) usage ;;
esac
