#!/bin/sh
#
# net539-verify.sh - compare the NET-539 version of
# solardatm.find_datm_for_time_slot() with the live one, on real streams, before
# NET-539 is deployed.
#
# Apply net539-candidate-copy.sql (next to this script) first. It installs the
# NET-539 function, and copies of the two rollup functions that call it, under
# names ending in _net539. This script then runs the live and the _net539
# functions side by side for a sample of streams and hours, and reports where
# their results differ and what each costs.
#
# The script changes nothing in the database: every session it opens is set to
# default_transaction_read_only, with a statement timeout. It never installs or
# removes the _net539 functions.
#
# Usage:
#
#   PGSSLCERT=superuser.crt PGSSLKEY=superuser.key sh net539-verify.sh \
#       -h db.solarnetwork.net -p 5432 -U postgres -d solarnetwork
#
# Connection options are the same as psql's, and anything libpq reads from the
# environment applies. psql is run with -w, so it never stops to prompt.
#
#   -h HOST  -p PORT  -U USER  -d DBNAME    connection, as for psql
#   -o DIR      where to create the output (default: current directory)
#   -H COUNT    most recent complete hours to compare for each stream (default 2)
#   -m COUNT    streams to sample of each kind (default 30)
#   -k COUNT    streams of each kind to run EXPLAIN ANALYZE for (default 2)
#   -t SECONDS  statement timeout for every query (default 300)
#   -x          skip the EXPLAIN ANALYZE step
#
# The kinds of stream sampled:
#
#   suspect       declares accumulating properties, none posted in 14 days:
#                 the streams NET-539 is for
#   mixed         declares accumulating properties, latest datum has none, but
#                 one within 14 days: where stored values are meant to change
#   control_a     posts accumulating properties
#   control_none  declares no accumulating properties
#   reset         has a reset record in the last 60 days; compared for the hour
#                 of the reset, the hour before and the hour after
#
# For each stream and hour it compares, live against _net539:
#
#   - the hourly rollup, rollup_datm_for_time_span()
#   - the datum lookup itself, find_datm_for_time_slot() with the rollup's one
#     year tolerance
#   - the sub-hour rollup, rollup_datm_for_time_span_slots(), in 10 minute slots
#
# and gives each rollup a verdict:
#
#   same             identical results
#   expected_null    the live result only carried a reading forward (a data_a of
#                    all zeros, read_a with zero difference) and the _net539
#                    result is NULL there: the change NET-539 intends
#   expected_no_row  the same, for an hour with no datum at all, where _net539
#                    returns no row
#   DIFFERENT        anything else: needs looking at
#
# The exit status is 1 if any comparison is DIFFERENT or failed, else 0.
#
# Needs psql 12 or later. Written for POSIX sh; also runs under zsh and bash.

set -u
umask 077

SCRIPT_VERSION=1
HOURS=2
SAMPLE=30
STREAMS=2
STMT_TIMEOUT=300
DO_EXPLAIN=1
OUTBASE=.
PSQL=${PSQL:-psql}

# md5 of the function bodies this script was written against
LIVE_MD5=e2a248d91c455b325708f5b2f538c486
CANDIDATE_MD5=8c6eb598f8920ddcb300b6327366e30d

usage() {
	sed -n '2,/^# Needs psql/p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

die() {
	printf 'net539-verify: %s\n' "$*" >&2
	exit 1
}

is_number() {
	case $1 in
		'' | *[!0-9]*) return 1 ;;
	esac
	return 0
}

while getopts 'h:p:U:d:o:H:m:k:t:x' opt; do
	case $opt in
		h) PGHOST=$OPTARG; export PGHOST ;;
		p) PGPORT=$OPTARG; export PGPORT ;;
		U) PGUSER=$OPTARG; export PGUSER ;;
		d) PGDATABASE=$OPTARG; export PGDATABASE ;;
		o) OUTBASE=$OPTARG ;;
		H) HOURS=$OPTARG ;;
		m) SAMPLE=$OPTARG ;;
		k) STREAMS=$OPTARG ;;
		t) STMT_TIMEOUT=$OPTARG ;;
		x) DO_EXPLAIN=0 ;;
		*) usage ;;
	esac
done
shift $((OPTIND - 1))
[ $# -eq 0 ] || usage

for v in "$HOURS" "$SAMPLE" "$STREAMS" "$STMT_TIMEOUT"; do
	is_number "$v" || die "options -H, -m, -k and -t take a whole number"
done
[ "$HOURS" -ge 1 ] || die "-H must be at least 1"
[ "$SAMPLE" -ge 1 ] || die "-m must be at least 1"

command -v "$PSQL" >/dev/null 2>&1 || die "psql not found (set PSQL=/path/to/psql)"
PSQL_MAJOR=$("$PSQL" -V | sed -n 's/^[^0-9]*\([0-9][0-9]*\).*/\1/p')
is_number "${PSQL_MAJOR:-}" || die "cannot tell the version of $PSQL"
[ "$PSQL_MAJOR" -ge 12 ] || die "psql 12 or later is needed (found $PSQL_MAJOR)"

PGAPPNAME=net539-verify
PGCONNECT_TIMEOUT=${PGCONNECT_TIMEOUT:-15}
export PGAPPNAME PGCONNECT_TIMEOUT

[ -d "$OUTBASE" ] || die "output directory $OUTBASE does not exist"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
NAME=net539-$STAMP
OUT=$OUTBASE/$NAME
mkdir "$OUT" "$OUT/sql" "$OUT/explain" || die "cannot create $OUT"
LOG=$OUT/verify.log
FAILED=
: >"$LOG"

note() {
	printf '%s %s\n' "$(date -u +%H:%M:%SZ)" "$*" | tee -a "$LOG" >&2
}

# ask SQL - run one statement and print its unaligned result
ask() {
	"$PSQL" -X -q -w -A -t -F '|' -v ON_ERROR_STOP=1 -c "SET timezone = 'UTC'" -c "$1" 2>>"$LOG"
}

# run FORMAT NAME OUTFILE [psql options] - run sql/NAME.sql into OUTFILE
#   psv    pipe separated, with a header
#   rows   pipe separated, no header
#   text   psql's aligned tables
run() {
	_fmt=$1
	_name=$2
	_out=$3
	shift 3
	case $_fmt in
		psv) set -- -A -F '|' -P footer=off "$@" ;;
		rows) set -- -A -t -F '|' "$@" ;;
	esac
	"$PSQL" -X -q -w -v ON_ERROR_STOP=1 -v stmt_timeout="${STMT_TIMEOUT}s" "$@" \
		-f "$OUT/sql/session.sql" -f "$OUT/sql/$_name.sql" >"$_out" 2>>"$LOG"
	_rc=$?
	if [ "$_rc" -ne 0 ]; then
		note "WARNING: $_name failed (psql exit $_rc), see verify.log"
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

# -----------------------------------------------------------------------------
# The SQL. Each statement is kept in the output as sql/NAME.sql.
# -----------------------------------------------------------------------------

# force_custom_plan makes each EXECUTE of the prepared comparison plan with its
# argument values as constants, as production's EXECUTE ... USING does, so the
# functions are inlined and planned over only the chunks that can match.
cat >"$OUT/sql/session.sql" <<'SQL'
SET application_name = 'net539-verify';
SET timezone = 'UTC';
SET statement_timeout = :'stmt_timeout';
SET lock_timeout = '5s';
SET default_transaction_read_only = on;
SET plan_cache_mode = force_custom_plan;
SQL

cat >"$OUT/sql/context.sql" <<'SQL'
\echo == session
SELECT statement_timestamp() AS now_utc, current_user, current_database() AS db
	, pg_is_in_recovery() AS in_recovery
	, (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) AS superuser;
SELECT version();

\echo == functions
SELECT p.oid::regprocedure AS func, l.lanname AS lang, p.proisstrict AS strict
	, p.provolatile AS vol, md5(p.prosrc) AS src_md5, length(p.prosrc) AS src_len
FROM pg_proc p
INNER JOIN pg_namespace n ON n.oid = p.pronamespace
INNER JOIN pg_language l ON l.oid = p.prolang
WHERE n.nspname = 'solardatm'
	AND p.proname IN ('find_datm_for_time_slot', 'find_datm_for_time_slot_net539'
		, 'find_datm_for_time_slot_pre538'
		, 'rollup_datm_for_time_span', 'rollup_datm_for_time_span_net539'
		, 'rollup_datm_for_time_span_slots', 'rollup_datm_for_time_span_slots_net539'
		, 'find_time_before_ts', 'find_time_after_ts', 'find_datm_between'
		, 'datm_has_accumulating_at', 'find_datm_aux_for_time_span')
ORDER BY 1;

\echo == newest da_datm chunks
SELECT c.chunk_schema || '.' || c.chunk_name AS chunk, c.range_start, c.range_end
FROM timescaledb_information.chunks c
WHERE c.hypertable_schema = 'solardatm' AND c.hypertable_name = 'da_datm'
ORDER BY c.range_start DESC
LIMIT 3;

\echo == reset records
SELECT count(*) AS reset_records
	, count(*) FILTER (WHERE ts >= :'t0'::timestamptz - INTERVAL 'P60D') AS in_last_60_days
FROM solardatm.da_datm_aux
WHERE atype = 'Reset'::solardatm.da_datm_aux_type;
SQL

# The streams and hours to compare: class|stream_id|slot start|slot end.
cat >"$OUT/sql/targets.sql" <<'SQL'
WITH hrs AS (
	SELECT :'t0'::timestamptz - make_interval(hours => g.h) AS t0
	FROM generate_series(0, :hours - 1) AS g(h)
)
, cand AS (
	SELECT m.stream_id
	FROM solardatm.da_datm_meta m
	WHERE cardinality(m.names_a) > 0
	UNION ALL
	SELECT m.stream_id
	FROM solardatm.da_loc_datm_meta m
	WHERE cardinality(m.names_a) > 0
)
-- declares accumulating properties, and the latest datum has none
, flagged AS MATERIALIZED (
	SELECT c.stream_id
	FROM cand c
	CROSS JOIN LATERAL (
		SELECT d.ts, d.data_a
		FROM solardatm.da_datm d
		WHERE d.stream_id = c.stream_id
			AND d.ts >= :'t0'::timestamptz - INTERVAL 'PT2H'
		ORDER BY d.ts DESC
		LIMIT 1
	) l
	WHERE l.data_a IS NULL
)
, top AS MATERIALIZED (
	SELECT f.stream_id, n.rows_24h
	FROM flagged f
	CROSS JOIN LATERAL (
		SELECT count(*) AS rows_24h
		FROM solardatm.da_datm d
		WHERE d.stream_id = f.stream_id
			AND d.ts >= :'t1'::timestamptz - INTERVAL 'P1D'
			AND d.ts < :'t1'::timestamptz
	) n
	ORDER BY n.rows_24h DESC, f.stream_id
	LIMIT :sample * 3
)
-- any datum with accumulating properties in the 14 days before the slot?
, cls AS MATERIALIZED (
	SELECT t.stream_id, t.rows_24h
		, CASE WHEN a.last_a_ts IS NULL THEN 'suspect' ELSE 'mixed' END AS class
	FROM top t
	LEFT JOIN LATERAL (
		SELECT d.ts AS last_a_ts
		FROM solardatm.da_datm d
		WHERE d.stream_id = t.stream_id
			AND d.ts < :'t0'::timestamptz
			AND d.ts >= :'t0'::timestamptz - INTERVAL 'P14D'
			AND d.data_a IS NOT NULL
		ORDER BY d.ts DESC
		LIMIT 1
	) a ON TRUE
)
, picked AS MATERIALIZED (
	SELECT class, stream_id
	FROM (
		SELECT c.class, c.stream_id
			, row_number() OVER (PARTITION BY c.class ORDER BY c.rows_24h DESC, c.stream_id) AS rn
		FROM cls c
	) x
	WHERE x.rn <= :sample
)
, ctl_a AS MATERIALIZED (
	SELECT m.stream_id
	FROM solardatm.da_datm_meta m
	CROSS JOIN LATERAL (
		SELECT d.data_a
		FROM solardatm.da_datm d
		WHERE d.stream_id = m.stream_id
			AND d.ts >= :'t0'::timestamptz
			AND d.ts < :'t1'::timestamptz
		ORDER BY d.ts DESC
		LIMIT 1
	) l
	WHERE cardinality(m.names_a) > 0
		AND l.data_a IS NOT NULL
	ORDER BY md5(m.stream_id::text || :'t0')
	LIMIT :sample
)
, ctl_none AS MATERIALIZED (
	SELECT m.stream_id
	FROM solardatm.da_datm_meta m
	WHERE COALESCE(cardinality(m.names_a), 0) = 0
		AND EXISTS (
			SELECT 1
			FROM solardatm.da_datm d
			WHERE d.stream_id = m.stream_id
				AND d.ts >= :'t0'::timestamptz
				AND d.ts < :'t1'::timestamptz
		)
	ORDER BY md5(m.stream_id::text || :'t0')
	LIMIT :sample
)
-- the latest reset record of each stream in the last 60 days, newest first
, resets AS MATERIALIZED (
	SELECT r.stream_id, r.t0
	FROM (
		SELECT DISTINCT ON (aux.stream_id) aux.stream_id, date_trunc('hour', aux.ts) AS t0
		FROM solardatm.da_datm_aux aux
		WHERE aux.atype = 'Reset'::solardatm.da_datm_aux_type
			AND aux.ts >= :'t0'::timestamptz - INTERVAL 'P60D'
			AND aux.ts < :'t0'::timestamptz
		ORDER BY aux.stream_id, aux.ts DESC
	) r
	ORDER BY r.t0 DESC, r.stream_id
	LIMIT :sample
)
SELECT x.class, x.stream_id, x.t0, x.t0 + INTERVAL 'PT1H' AS t1
FROM (
	SELECT p.class, p.stream_id, h.t0 FROM picked p CROSS JOIN hrs h
	UNION ALL
	SELECT 'control_a', c.stream_id, h.t0 FROM ctl_a c CROSS JOIN hrs h
	UNION ALL
	SELECT 'control_none', c.stream_id, h.t0 FROM ctl_none c CROSS JOIN hrs h
	UNION ALL
	SELECT 'reset', r.stream_id, r.t0 + make_interval(hours => o.h)
	FROM resets r CROSS JOIN (VALUES (-1), (0), (1)) AS o(h)
) x
ORDER BY x.class, x.stream_id, x.t0;
SQL

# One row per stream and hour: $1 class, $2 stream, $3 slot start, $4 slot end.
# "carried" is the live hourly row when all it says about accumulating
# properties is that nothing changed: data_a all zeros (or NULL), and each
# read_a row a zero difference with equal start and end.
cat >"$OUT/sql/compare-prepare.sql" <<'SQL'
PREPARE cmp(text, uuid, timestamptz, timestamptz) AS
WITH l AS MATERIALIZED (
	SELECT * FROM solardatm.rollup_datm_for_time_span($2, $3, $4)
)
, c AS MATERIALIZED (
	SELECT * FROM solardatm.rollup_datm_for_time_span_net539($2, $3, $4)
)
, ll AS MATERIALIZED (
	SELECT count(*) AS n
		, count(*) FILTER (WHERE rtype = 0 AND data_a IS NOT NULL) AS n_a
		, count(*) FILTER (WHERE rtype <> 0) AS n_reset
		, min(ts) AS min_ts
	FROM solardatm.find_datm_for_time_slot($2, $3, $4, INTERVAL 'P1Y')
)
, lc AS MATERIALIZED (
	SELECT count(*) AS n
		, count(*) FILTER (WHERE rtype = 0 AND data_a IS NOT NULL) AS n_a
		, count(*) FILTER (WHERE rtype <> 0) AS n_reset
		, min(ts) AS min_ts
	FROM solardatm.find_datm_for_time_slot_net539($2, $3, $4, INTERVAL 'P1Y')
)
, sl AS MATERIALIZED (
	SELECT * FROM solardatm.rollup_datm_for_time_span_slots($2, $3, $4, 600)
)
, sc AS MATERIALIZED (
	SELECT * FROM solardatm.rollup_datm_for_time_span_slots_net539($2, $3, $4, 600)
)
, carried AS (
	SELECT l.*
	FROM l
	WHERE NOT EXISTS (SELECT 1 FROM unnest(l.data_a) AS x(v) WHERE x.v <> 0)
		AND NOT EXISTS (
			SELECT 1
			FROM generate_subscripts(l.read_a, 1) AS g(i)
			WHERE l.read_a[g.i][1] <> 0
				OR l.read_a[g.i][2] IS DISTINCT FROM l.read_a[g.i][3]
		)
)
SELECT $1 AS class, $2 AS stream_id, $3 AS slot_start
	, CASE
		WHEN (SELECT count(*) FROM l) = (SELECT count(*) FROM c)
			AND NOT EXISTS (SELECT * FROM l EXCEPT SELECT * FROM c)
			AND NOT EXISTS (SELECT * FROM c EXCEPT SELECT * FROM l)
			THEN 'same'
		WHEN (SELECT count(*) FROM l) = 1 AND (SELECT count(*) FROM c) = 1
			AND EXISTS (
				SELECT 1
				FROM carried z
				INNER JOIN c ON c.ts_start = z.ts_start
				WHERE c.data_a IS NULL AND c.read_a IS NULL
					AND z.data_i IS NOT DISTINCT FROM c.data_i
					AND z.data_s IS NOT DISTINCT FROM c.data_s
					AND z.data_t IS NOT DISTINCT FROM c.data_t
					AND z.stat_i IS NOT DISTINCT FROM c.stat_i
			)
			THEN 'expected_null'
		WHEN (SELECT count(*) FROM l) = 1 AND (SELECT count(*) FROM c) = 0
			AND EXISTS (
				SELECT 1
				FROM carried z
				WHERE z.data_i IS NULL AND z.data_s IS NULL AND z.data_t IS NULL
			)
			THEN 'expected_no_row'
		ELSE 'DIFFERENT'
		END AS rollup_verdict
	, CASE
		WHEN (SELECT count(*) FROM sl) = (SELECT count(*) FROM sc)
			AND NOT EXISTS (SELECT * FROM sl EXCEPT SELECT * FROM sc)
			AND NOT EXISTS (SELECT * FROM sc EXCEPT SELECT * FROM sl)
			THEN 'same'
		WHEN NOT EXISTS (
				SELECT 1
				FROM sl
				FULL OUTER JOIN sc ON sc.ts_start = sl.ts_start
				WHERE sl.ts_start IS NULL OR sc.ts_start IS NULL
					OR sl.data_i IS DISTINCT FROM sc.data_i
					OR sl.data_s IS DISTINCT FROM sc.data_s
					OR sl.data_t IS DISTINCT FROM sc.data_t
					OR sl.stat_i IS DISTINCT FROM sc.stat_i
					OR NOT (
						sl.data_a IS NOT DISTINCT FROM sc.data_a
						OR (sc.data_a IS NULL
							AND NOT EXISTS (SELECT 1 FROM unnest(sl.data_a) AS x(v) WHERE x.v <> 0))
					)
			)
			THEN 'expected_null'
		ELSE 'DIFFERENT'
		END AS slots_verdict
	, ll.n AS lookup_rows_live, lc.n AS lookup_rows_net539
	, ll.n_a AS lookup_acc_live, lc.n_a AS lookup_acc_net539
	, ll.n_reset AS lookup_reset_live, lc.n_reset AS lookup_reset_net539
	, ll.min_ts AS lookup_first_live, lc.min_ts AS lookup_first_net539
	, (SELECT count(*) FROM l) AS rollup_rows_live, (SELECT count(*) FROM c) AS rollup_rows_net539
	, (SELECT count(*) FROM sl) AS slots_rows_live, (SELECT count(*) FROM sc) AS slots_rows_net539
	, (SELECT l.data_a::text FROM l LIMIT 1) AS data_a_live
	, (SELECT c.data_a::text FROM c LIMIT 1) AS data_a_net539
	, (SELECT l.read_a::text FROM l LIMIT 1) AS read_a_live
	, (SELECT c.read_a::text FROM c LIMIT 1) AS read_a_net539
FROM ll, lc;
SQL

COMPARE_HEADER='class|stream_id|slot_start|rollup_verdict|slots_verdict|lookup_rows_live|lookup_rows_net539|lookup_acc_live|lookup_acc_net539|lookup_reset_live|lookup_reset_net539|lookup_first_live|lookup_first_net539|rollup_rows_live|rollup_rows_net539|slots_rows_live|slots_rows_net539|data_a_live|data_a_net539|read_a_live|read_a_net539'

# What each function costs, with literal arguments as production's
# EXECUTE ... USING gives them. In pass 1 the _net539 function runs first, so
# it gets no help from pages the live function has just read.
cat >"$OUT/sql/explain.sql" <<'SQL'
\echo ### stream :sid class :cls slot :t0 to :t1
\echo
\echo ### pass 1 net539 find_datm_for_time_slot_net539
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT count(*) FROM solardatm.find_datm_for_time_slot_net539(
	:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz, INTERVAL 'P1Y');
\echo
\echo ### pass 1 live find_datm_for_time_slot
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM solardatm.find_datm_for_time_slot(
	:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz, INTERVAL 'P1Y');
\echo
\echo ### pass 2 live find_datm_for_time_slot
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM solardatm.find_datm_for_time_slot(
	:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz, INTERVAL 'P1Y');
\echo
\echo ### pass 2 net539 find_datm_for_time_slot_net539
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM solardatm.find_datm_for_time_slot_net539(
	:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz, INTERVAL 'P1Y');
\echo
\echo ### rollup live rollup_datm_for_time_span
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM solardatm.rollup_datm_for_time_span(
	:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz);
\echo
\echo ### rollup net539 rollup_datm_for_time_span_net539
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM solardatm.rollup_datm_for_time_span_net539(
	:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz);
SQL

# -----------------------------------------------------------------------------
# Connect, and check the _net539 functions are there.
# -----------------------------------------------------------------------------

note "Connecting"
WHO=$(ask "SELECT current_user
	, (SELECT rolsuper FROM pg_roles WHERE rolname = current_user)
	, pg_is_in_recovery()")
if [ $? -ne 0 ] || [ -z "$WHO" ]; then
	cat "$LOG" >&2
	rm -r "$OUT"
	die "cannot connect; check the connection options and certificates"
fi
IFS='|' read -r DB_USER IS_SUPER IN_RECOVERY <<EOF
$WHO
EOF

FUNCS=$(ask "SELECT
	  (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('solardatm.find_datm_for_time_slot(uuid,timestamptz,timestamptz,interval,interval)'))
	, (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('solardatm.find_datm_for_time_slot_net539(uuid,timestamptz,timestamptz,interval,interval)'))
	, to_regprocedure('solardatm.rollup_datm_for_time_span_net539(uuid,timestamptz,timestamptz,interval,interval)') IS NOT NULL
	, to_regprocedure('solardatm.rollup_datm_for_time_span_slots_net539(uuid,timestamptz,timestamptz,integer,interval)') IS NOT NULL")
IFS='|' read -r HAVE_LIVE_MD5 HAVE_CAND_MD5 HAVE_ROLLUP HAVE_SLOTS <<EOF
$FUNCS
EOF
if [ -z "$HAVE_CAND_MD5" ] || [ "$HAVE_ROLLUP" != t ] || [ "$HAVE_SLOTS" != t ]; then
	rm -r "$OUT"
	die "the _net539 functions are not installed; apply net539-candidate-copy.sql first"
fi

# the most recent complete hour is the first slot
SLOT=$(ask "SELECT h - INTERVAL 'PT1H', h FROM date_trunc('hour', CURRENT_TIMESTAMP) AS h")
[ -n "$SLOT" ] || die "cannot work out the time slot, see $LOG"
IFS='|' read -r T0 T1 <<EOF
$SLOT
EOF

{
	printf 'script_version=%s\n' "$SCRIPT_VERSION"
	printf 'started=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf 'host=%s\nport=%s\ndatabase=%s\n' "${PGHOST:-}" "${PGPORT:-}" "${PGDATABASE:-}"
	printf 'user=%s\nsuperuser=%s\nin_recovery=%s\n' "$DB_USER" "$IS_SUPER" "$IN_RECOVERY"
	printf 'psql_major=%s\n' "$PSQL_MAJOR"
	printf 'hours=%s\nsample=%s\nexplain_streams=%s\nstatement_timeout_s=%s\n' \
		"$HOURS" "$SAMPLE" "$STREAMS" "$STMT_TIMEOUT"
	printf 'slot_start=%s\nslot_end=%s\n' "$T0" "$T1"
	printf 'live_md5=%s\nnet539_md5=%s\n' "$HAVE_LIVE_MD5" "$HAVE_CAND_MD5"
} >"$OUT/run.txt"

note "Connected as $DB_USER; latest slot $T0 to $T1"
[ "$IN_RECOVERY" != t ] || note "NOTE: this server is a replica, not the primary"
if [ "$HAVE_CAND_MD5" != "$CANDIDATE_MD5" ]; then
	note "NOTE: the _net539 function is not the version this script was written"
	note "      against (md5 $HAVE_CAND_MD5, expected $CANDIDATE_MD5)"
fi
if [ "$HAVE_LIVE_MD5" = "$HAVE_CAND_MD5" ]; then
	note "NOTE: the live function is already the same as the _net539 one, so every"
	note "      comparison will be 'same'"
elif [ "$HAVE_LIVE_MD5" != "$LIVE_MD5" ]; then
	note "NOTE: the live function is not the NET-538 version (md5 $HAVE_LIVE_MD5)"
fi

# -----------------------------------------------------------------------------
# Compare.
# -----------------------------------------------------------------------------

note "Context"
run text context "$OUT/context.txt" -v t0="$T0"

note "Choosing streams"
run rows targets "$OUT/targets.psv" -v t0="$T0" -v t1="$T1" -v hours="$HOURS" -v sample="$SAMPLE"
TARGET_COUNT=$(($(wc -l <"$OUT/targets.psv")))
[ "$TARGET_COUNT" -gt 0 ] || { finish; die "no streams found to compare, see $OUT/verify.log"; }
awk -F'|' '{ n[$1]++; if (!(($1, $2) in s)) { s[$1, $2] = 1; st[$1]++ } }
	END { for (k in n) printf "%s: %d streams, %d comparisons\n", k, st[k], n[k] }' \
	"$OUT/targets.psv" | sort | while IFS= read -r line; do note "  $line"; done

printf '%s\n' "$COMPARE_HEADER" >"$OUT/compare.psv"
: >"$OUT/compare-errors.txt"
for cls in suspect mixed control_a control_none reset; do
	# one EXECUTE per stream and hour; the values come from the database, and
	# are checked here before being written into SQL
	awk -F'|' -v cls="$cls" '
		$1 == cls && length($2) == 36 && $2 ~ /^[0-9a-f-]+$/ \
				&& $3 ~ /^[0-9: +-]+$/ && $4 ~ /^[0-9: +-]+$/ {
			printf "EXECUTE cmp(\047%s\047, \047%s\047, \047%s\047, \047%s\047);\n", $1, $2, $3, $4
		}
	' "$OUT/targets.psv" >"$OUT/sql/compare-$cls.sql"
	_n=$(($(wc -l <"$OUT/sql/compare-$cls.sql")))
	[ "$_n" -gt 0 ] || continue
	note "Comparing $cls: $_n"
	"$PSQL" -X -q -w -A -t -F '|' -v ON_ERROR_STOP=0 -v stmt_timeout="${STMT_TIMEOUT}s" \
		-f "$OUT/sql/session.sql" -f "$OUT/sql/compare-prepare.sql" -f "$OUT/sql/compare-$cls.sql" \
		>>"$OUT/compare.psv" 2>>"$OUT/compare-errors.txt" </dev/null
done

COMPARED=$(($(wc -l <"$OUT/compare.psv") - 1))
MISSING=$((TARGET_COUNT - COMPARED))
DIFFERENT=$(awk -F'|' 'NR > 1 && ($4 == "DIFFERENT" || $5 == "DIFFERENT") { n++ } END { print n + 0 }' "$OUT/compare.psv")

# class by verdict, for the hourly rollup and for the sub-hour rollup
{
	printf 'class|rollup|verdict|comparisons|streams\n'
	awk -F'|' '
		NR > 1 {
			for (i = 4; i <= 5; i++) {
				k = $1 "|" (i == 4 ? "hourly" : "slots") "|" $i
				n[k]++
				if (!((k, $2) in seen)) {
					seen[k, $2] = 1
					s[k]++
				}
			}
		}
		END { for (k in n) print k "|" n[k] "|" s[k] }
	' "$OUT/compare.psv" | sort
} >"$OUT/compare-summary.psv"

if [ "$DO_EXPLAIN" -eq 1 ] && [ "$STREAMS" -ge 1 ]; then
	# the first STREAMS streams of each kind, at their first hour compared
	awk -F'|' -v k="$STREAMS" '!(($1, $2) in seen) && n[$1] < k { seen[$1, $2] = 1; n[$1]++; print }' \
		"$OUT/targets.psv" >"$OUT/explain/targets.psv"
	seq_no=0
	while IFS='|' read -r cls sid t0 t1; do
		[ -n "$sid" ] || continue
		seq_no=$((seq_no + 1))
		note "Explain $seq_no: $cls $sid"
		"$PSQL" -X -q -w -A -t -v ON_ERROR_STOP=0 -v stmt_timeout="${STMT_TIMEOUT}s" \
			-v sid="$sid" -v cls="$cls" -v t0="$t0" -v t1="$t1" \
			-f "$OUT/sql/session.sql" -f "$OUT/sql/explain.sql" \
			>"$(printf '%s/explain/%02d-%s-%s.txt' "$OUT" "$seq_no" "$cls" "$sid")" 2>&1 </dev/null
	done <"$OUT/explain/targets.psv"

	# the top line of each plan: buffers touched, and the times
	{
		printf 'file|plan|buffers_hit|buffers_read|planning_ms|execution_ms\n'
		for f in "$OUT"/explain/[0-9]*.txt; do
			[ -f "$f" ] || continue
			awk -v file="${f##*/}" '
				function flush() {
					if (plan != "") print file "|" plan "|" hit + 0 "|" rd + 0 "|" pl "|" ex
				}
				function num(s, key,    i, r) {
					i = index(s, key "=")
					if (i == 0) return 0
					r = substr(s, i + length(key) + 1)
					sub(/[^0-9].*/, "", r)
					return r
				}
				/^### (pass|rollup)/ {
					flush()
					plan = substr($0, 5)
					hit = rd = 0
					pl = ex = ""
					got = planning = 0
					next
				}
				/^Planning:/ { planning = 1 }
				/Buffers: shared/ && !got && !planning && plan != "" {
					hit = num($0, "hit")
					rd = num($0, "read")
					got = 1
				}
				/^Planning Time:/ { pl = $3 }
				/^Execution Time:/ { ex = $3 }
				END { flush() }
			' "$f"
		done
	} >"$OUT/explain-summary.psv"
else
	note "Skipping EXPLAIN"
fi

trap - INT TERM
{
	printf 'targets=%s\ncompared=%s\nmissing=%s\ndifferent=%s\n' \
		"$TARGET_COUNT" "$COMPARED" "$MISSING" "$DIFFERENT"
} >>"$OUT/run.txt"
finish

note "Results by kind of stream (comparisons, streams):"
awk -F'|' 'NR > 1 { printf "  %-13s %-7s %-16s %5d %5d\n", $1, $2, $3, $4, $5 }' "$OUT/compare-summary.psv" \
	| while IFS= read -r line; do note "$line"; done

if [ "$MISSING" -gt 0 ]; then
	note "WARNING: $MISSING of $TARGET_COUNT comparisons failed, see compare-errors.txt"
fi
if [ "$DIFFERENT" -gt 0 ]; then
	note "RESULT: $DIFFERENT comparisons are DIFFERENT, see compare.psv"
elif [ "$MISSING" -gt 0 ] || [ -n "$FAILED" ]; then
	note "RESULT: no unexpected difference in $COMPARED comparisons, but some steps failed"
else
	note "RESULT: no unexpected difference in $COMPARED comparisons"
fi
if [ "$DIFFERENT" -gt 0 ] || [ "$MISSING" -gt 0 ] || [ -n "$FAILED" ]; then
	exit 1
fi
exit 0
