#!/bin/sh
#
# net538-collect.sh - collect read-only diagnostics about the change in IO on the
# SolarNet primary database after the NET-538 DDL was deployed.
#
# The script changes nothing in the database: every session it opens is set to
# default_transaction_read_only, with a statement timeout. It writes a directory
# of CSV and text files, and a .tar.gz of that directory to hand back.
#
# Usage:
#
#   PGSSLCERT=the.crt PGSSLKEY=the.key sh net538-collect.sh \
#       -h db.solarnetwork.net -p 5432 -U solarnet -d solarnetwork
#
# Connection options are the same as psql's, and anything libpq reads from the
# environment (PGSSLCERT, PGSSLKEY, PGSSLROOTCERT, PGPASSWORD, ~/.pgpass, ...)
# applies. psql is run with -w, so it never stops to prompt for a password.
#
#   -h HOST  -p PORT  -U USER  -d DBNAME    connection, as for psql
#   -o DIR      where to create the output (default: current directory)
#   -n COUNT    number of once-per-interval samples (default 5)
#   -i SECONDS  seconds between samples (default 60)
#   -k COUNT    streams of each kind to run EXPLAIN ANALYZE for (default 3)
#   -m COUNT    most active suspect streams to classify (default 100)
#   -t SECONDS  statement timeout for every query (default 300)
#   -x          skip the EXPLAIN ANALYZE step
#
# Connect as a superuser, or a role with pg_read_all_stats: without that,
# pg_stat_statements hides the query IDs of other roles and the statement
# snapshots are of no use.
#
# What it does, in order:
#
#   1. context    versions, settings, which function versions are live
#   2. snapshot 1 pg_stat_statements and the per-table statistics
#   3. samples    COUNT samples, SECONDS apart, of the stale aggregate queues,
#                 pg_stat_database, pg_stat_io and pg_stat_activity. Nothing
#                 else runs between snapshot 1 and snapshot 2, so the difference
#                 between them is production's own work over that time.
#   4. snapshot 2
#   5. streams    streams that declare accumulating properties but are not
#                 posting them (the suspected cause), and some control streams
#   6. explain    EXPLAIN (ANALYZE, BUFFERS) of the datum lookup of one hourly
#                 rollup, for a few streams of each kind. If the function
#                 solardatm.find_datm_for_time_slot_pre538 has been installed
#                 beforehand (net538-pre538-copy.sql, next to this script) it is
#                 run alongside the live function; the script never installs or
#                 removes it.
#
# Needs psql 12 or later. Written for POSIX sh; also runs under zsh and bash.

set -u
umask 077

SCRIPT_VERSION=1
SAMPLES=5
INTERVAL=60
STREAMS=3
MAX_CLASSIFY=100
STMT_TIMEOUT=300
DO_EXPLAIN=1
OUTBASE=.
PSQL=${PSQL:-psql}

usage() {
	sed -n '2,/^# Needs psql/p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

die() {
	printf 'net538-collect: %s\n' "$*" >&2
	exit 1
}

is_number() {
	case $1 in
		'' | *[!0-9]*) return 1 ;;
	esac
	return 0
}

while getopts 'h:p:U:d:o:n:i:k:m:t:x' opt; do
	case $opt in
		h) PGHOST=$OPTARG; export PGHOST ;;
		p) PGPORT=$OPTARG; export PGPORT ;;
		U) PGUSER=$OPTARG; export PGUSER ;;
		d) PGDATABASE=$OPTARG; export PGDATABASE ;;
		o) OUTBASE=$OPTARG ;;
		n) SAMPLES=$OPTARG ;;
		i) INTERVAL=$OPTARG ;;
		k) STREAMS=$OPTARG ;;
		m) MAX_CLASSIFY=$OPTARG ;;
		t) STMT_TIMEOUT=$OPTARG ;;
		x) DO_EXPLAIN=0 ;;
		*) usage ;;
	esac
done
shift $((OPTIND - 1))
[ $# -eq 0 ] || usage

for v in "$SAMPLES" "$INTERVAL" "$STREAMS" "$MAX_CLASSIFY" "$STMT_TIMEOUT"; do
	is_number "$v" || die "options -n, -i, -k, -m and -t take a whole number"
done
[ "$SAMPLES" -ge 1 ] || die "-n must be at least 1"

command -v "$PSQL" >/dev/null 2>&1 || die "psql not found (set PSQL=/path/to/psql)"
PSQL_MAJOR=$("$PSQL" -V | sed -n 's/^[^0-9]*\([0-9][0-9]*\).*/\1/p')
is_number "${PSQL_MAJOR:-}" || die "cannot tell the version of $PSQL"
[ "$PSQL_MAJOR" -ge 12 ] || die "psql 12 or later is needed for --csv (found $PSQL_MAJOR)"

PGAPPNAME=net538-collect
PGCONNECT_TIMEOUT=${PGCONNECT_TIMEOUT:-15}
export PGAPPNAME PGCONNECT_TIMEOUT

[ -d "$OUTBASE" ] || die "output directory $OUTBASE does not exist"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
NAME=net538-$STAMP
OUT=$OUTBASE/$NAME
mkdir "$OUT" "$OUT/sql" "$OUT/samples" "$OUT/snap1" "$OUT/snap2" "$OUT/explain" \
	|| die "cannot create $OUT"
LOG=$OUT/collect.log
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
#   csv    comma separated, with a header
#   psv    pipe separated, with a header
#   text   psql's aligned tables
run() {
	_fmt=$1
	_name=$2
	_out=$3
	shift 3
	case $_fmt in
		csv) set -- --csv "$@" ;;
		psv) set -- -A -F '|' -P footer=off "$@" ;;
	esac
	"$PSQL" -X -q -w -v ON_ERROR_STOP=1 -v stmt_timeout="${STMT_TIMEOUT}s" "$@" \
		-f "$OUT/sql/session.sql" -f "$OUT/sql/$_name.sql" >"$_out" 2>>"$LOG"
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

# -----------------------------------------------------------------------------
# The SQL. Each statement is kept in the output as sql/NAME.sql, so the results
# can be read next to exactly what produced them.
# -----------------------------------------------------------------------------

cat >"$OUT/sql/session.sql" <<'SQL'
SET application_name = 'net538-collect';
SET timezone = 'UTC';
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
	, pg_postmaster_start_time() AS server_started;
SELECT version();

\echo == extensions
SELECT e.extname, e.extversion, n.nspname AS schema
FROM pg_extension e
INNER JOIN pg_namespace n ON n.oid = e.extnamespace
ORDER BY e.extname;

\echo == settings
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN ('shared_buffers', 'effective_cache_size', 'random_page_cost', 'seq_page_cost'
		, 'effective_io_concurrency', 'work_mem', 'maintenance_work_mem', 'max_connections'
		, 'plan_cache_mode', 'jit', 'track_io_timing', 'track_functions', 'track_counts'
		, 'max_parallel_workers_per_gather', 'default_statistics_target'
		, 'checkpoint_timeout', 'max_wal_size', 'bgwriter_lru_maxpages', 'bgwriter_delay'
		, 'autovacuum_vacuum_insert_scale_factor', 'autovacuum_vacuum_insert_threshold'
		, 'pg_stat_statements.track', 'pg_stat_statements.track_planning', 'pg_stat_statements.max')
	OR (name LIKE 'timescaledb.%' AND source <> 'default')
ORDER BY name;

\echo == functions (which versions are live)
SELECT p.oid::regprocedure AS func, l.lanname AS lang, p.proisstrict AS strict
	, p.provolatile AS vol, p.proparallel AS par, p.prorows AS est_rows
	, md5(p.prosrc) AS src_md5, length(p.prosrc) AS src_len
FROM pg_proc p
INNER JOIN pg_namespace n ON n.oid = p.pronamespace
INNER JOIN pg_language l ON l.oid = p.prolang
WHERE n.nspname = 'solardatm'
	AND p.proname IN ('find_datm_for_time_slot', 'find_datm_for_time_slot_pre538'
		, 'find_datm_around_ts', 'find_datm_around', 'find_time_before_ts', 'find_time_after_ts'
		, 'find_time_before', 'find_time_after', 'find_datm_between', 'datm_has_accumulating_at'
		, 'rollup_datm_for_time_span', 'rollup_datm_for_time_span_slots'
		, 'rollup_agg_data_for_time_span', 'process_one_agg_stale_datm', 'calc_stale_datm'
		, 'find_metadata_for_stream')
ORDER BY 1;

\echo == hypertables
SELECT hypertable_schema, hypertable_name, num_chunks, compression_enabled
FROM timescaledb_information.hypertables
ORDER BY 1, 2;

\echo == newest da_datm chunks
SELECT c.chunk_schema || '.' || c.chunk_name AS chunk, c.range_start, c.range_end
	, pg_size_pretty(pg_table_size(format('%I.%I', c.chunk_schema, c.chunk_name)::regclass)) AS heap
	, pg_size_pretty(pg_indexes_size(format('%I.%I', c.chunk_schema, c.chunk_name)::regclass)) AS indexes
	, c.is_compressed
FROM timescaledb_information.chunks c
WHERE c.hypertable_schema = 'solardatm' AND c.hypertable_name = 'da_datm'
ORDER BY c.range_start DESC
LIMIT 4;

\echo == streams
SELECT count(*) AS node_streams
	, count(*) FILTER (WHERE cardinality(names_a) > 0) AS with_accumulating_names
FROM solardatm.da_datm_meta;
SQL

# GROUP BY ROLLUP gives a '*' total row even when the queue is empty, so every
# sample leaves a row.
cat >"$OUT/sql/sample-stale-agg.sql" <<'SQL'
SELECT clock_timestamp() AS sample_ts
	, COALESCE(agg_kind::text, '*') AS agg_kind
	, count(*) AS stale_rows
	, count(DISTINCT stream_id) AS streams
	, round(EXTRACT(epoch FROM clock_timestamp() - min(created))::numeric, 1) AS oldest_age_s
	, round(EXTRACT(epoch FROM clock_timestamp()
		- percentile_disc(0.5) WITHIN GROUP (ORDER BY created))::numeric, 1) AS median_age_s
	, min(ts_start) AS min_ts_start
	, max(ts_start) AS max_ts_start
FROM solardatm.agg_stale_datm
GROUP BY ROLLUP (agg_kind)
ORDER BY 2;
SQL

cat >"$OUT/sql/sample-stale-aud.sql" <<'SQL'
SELECT clock_timestamp() AS sample_ts
	, COALESCE(aud_kind::text, '*') AS aud_kind
	, count(*) AS stale_rows
	, min(created) AS oldest_created
	, min(ts_start) AS min_ts_start
	, max(ts_start) AS max_ts_start
FROM solardatm.aud_stale_datm
GROUP BY ROLLUP (aud_kind)
ORDER BY 2;
SQL

cat >"$OUT/sql/sample-database.sql" <<'SQL'
SELECT clock_timestamp() AS sample_ts, d.*
FROM pg_stat_database d
WHERE d.datname = current_database();
SQL

cat >"$OUT/sql/sample-io.sql" <<'SQL'
SELECT clock_timestamp() AS sample_ts, i.*
FROM pg_stat_io i
WHERE i.reads > 0 OR i.hits > 0 OR i.writes > 0 OR i.extends > 0;
SQL

cat >"$OUT/sql/sample-activity.sql" <<'SQL'
SELECT clock_timestamp() AS sample_ts, usename, state, wait_event_type, wait_event
	, count(*) AS sessions
	, round(max(EXTRACT(epoch FROM clock_timestamp() - query_start))::numeric, 1) AS max_query_age_s
FROM pg_stat_activity
WHERE backend_type = 'client backend' AND pid <> pg_backend_pid()
GROUP BY usename, state, wait_event_type, wait_event
ORDER BY usename, state, sessions DESC;
SQL

cat >"$OUT/sql/snap-tables.sql" <<'SQL'
SELECT clock_timestamp() AS snap_ts, t.* FROM pg_stat_user_tables t;
SQL

cat >"$OUT/sql/snap-statio.sql" <<'SQL'
SELECT clock_timestamp() AS snap_ts, t.* FROM pg_statio_user_tables t;
SQL

cat >"$OUT/sql/snap-functions.sql" <<'SQL'
SELECT clock_timestamp() AS snap_ts, f.* FROM pg_stat_user_functions f;
SQL

cat >"$OUT/sql/snap-pss.sql" <<'SQL'
SELECT clock_timestamp() AS snap_ts, s.* FROM :"pss_schema".pg_stat_statements s;
SQL

cat >"$OUT/sql/snap-pss-info.sql" <<'SQL'
SELECT clock_timestamp() AS snap_ts, i.* FROM :"pss_schema".pg_stat_statements_info i;
SQL

# Streams that declare accumulating property names, are posting now, and whose
# latest datum has no accumulating values. One index probe per stream that
# declares accumulating names, then an index-only count for the flagged ones.
cat >"$OUT/sql/streams-flagged.sql" <<'SQL'
WITH cand AS (
	SELECT m.stream_id, 'n' AS kind, m.node_id AS obj_id, m.source_id::text AS source_id, m.names_a
	FROM solardatm.da_datm_meta m
	WHERE cardinality(m.names_a) > 0
	UNION ALL
	SELECT m.stream_id, 'l' AS kind, m.loc_id AS obj_id, m.source_id::text AS source_id, m.names_a
	FROM solardatm.da_loc_datm_meta m
	WHERE cardinality(m.names_a) > 0
)
, flagged AS MATERIALIZED (
	SELECT c.stream_id, c.kind, c.obj_id, c.source_id, c.names_a, l.ts AS latest_ts
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
SELECT f.stream_id, n.rows_24h
	, count(*) OVER () AS flagged_streams
	, sum(n.rows_24h) OVER () AS flagged_rows_24h
	, f.kind, f.obj_id, f.latest_ts, f.source_id, f.names_a
FROM flagged f
CROSS JOIN LATERAL (
	SELECT count(*) AS rows_24h
	FROM solardatm.da_datm d
	WHERE d.stream_id = f.stream_id
		AND d.ts >= :'t1'::timestamptz - INTERVAL 'P1D'
		AND d.ts < :'t1'::timestamptz
) n
ORDER BY n.rows_24h DESC, f.stream_id
LIMIT 500;
SQL

# For the most active flagged streams: is there any datum with accumulating
# values in the 14 days before the slot? This is the first search the rollup
# does, so for each stream it costs what one of that stream's rollups already
# costs. "none_in_14d" streams are the ones whose rollups now run the second
# search; "mixed" streams post accumulating values on only some datum.
cat >"$OUT/sql/streams-classified.sql" <<'SQL'
WITH cand AS (
	SELECT m.stream_id, 'n' AS kind, m.node_id AS obj_id
	FROM solardatm.da_datm_meta m
	WHERE cardinality(m.names_a) > 0
	UNION ALL
	SELECT m.stream_id, 'l' AS kind, m.loc_id AS obj_id
	FROM solardatm.da_loc_datm_meta m
	WHERE cardinality(m.names_a) > 0
)
, flagged AS MATERIALIZED (
	SELECT c.stream_id, c.kind, c.obj_id
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
	SELECT f.stream_id, f.kind, f.obj_id, n.rows_24h
	FROM flagged f
	CROSS JOIN LATERAL (
		SELECT count(*) AS rows_24h
		FROM solardatm.da_datm d
		WHERE d.stream_id = f.stream_id
			AND d.ts >= :'t1'::timestamptz - INTERVAL 'P1D'
			AND d.ts < :'t1'::timestamptz
	) n
	ORDER BY n.rows_24h DESC, f.stream_id
	LIMIT :max_classify
)
SELECT t.stream_id, t.kind, t.obj_id, t.rows_24h, s.rows_slot, a.last_a_ts
	, CASE WHEN a.last_a_ts IS NULL THEN 'none_in_14d' ELSE 'mixed' END AS a_0_14d
FROM top t
CROSS JOIN LATERAL (
	SELECT count(*) AS rows_slot
	FROM solardatm.da_datm d
	WHERE d.stream_id = t.stream_id
		AND d.ts >= :'t0'::timestamptz
		AND d.ts < :'t1'::timestamptz
) s
LEFT JOIN LATERAL (
	SELECT d.ts AS last_a_ts
	FROM solardatm.da_datm d
	WHERE d.stream_id = t.stream_id
		AND d.ts < :'t0'::timestamptz
		AND d.ts >= :'t14'::timestamptz
		AND d.data_a IS NOT NULL
	ORDER BY d.ts DESC
	LIMIT 1
) a ON TRUE
ORDER BY t.rows_24h DESC, t.stream_id;
SQL

# Control streams, posting at least every two minutes in the slot: some that
# post accumulating values, and some with no accumulating property names.
cat >"$OUT/sql/streams-controls.sql" <<'SQL'
(
	SELECT 'control_a' AS class, m.stream_id, m.node_id AS obj_id, n.rows_slot
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
	CROSS JOIN LATERAL (
		SELECT count(*) AS rows_slot
		FROM solardatm.da_datm d
		WHERE d.stream_id = m.stream_id
			AND d.ts >= :'t0'::timestamptz
			AND d.ts < :'t1'::timestamptz
	) n
	WHERE cardinality(m.names_a) > 0
		AND l.data_a IS NOT NULL
		AND n.rows_slot >= 30
	LIMIT :streams
)
UNION ALL
(
	SELECT 'control_none' AS class, m.stream_id, m.node_id AS obj_id, n.rows_slot
	FROM solardatm.da_datm_meta m
	CROSS JOIN LATERAL (
		SELECT count(*) AS rows_slot
		FROM solardatm.da_datm d
		WHERE d.stream_id = m.stream_id
			AND d.ts >= :'t0'::timestamptz
			AND d.ts < :'t1'::timestamptz
	) n
	WHERE COALESCE(cardinality(m.names_a), 0) = 0
		AND n.rows_slot >= 30
	LIMIT :streams
);
SQL

# The datum lookup of one hourly rollup, with literal arguments as production's
# EXECUTE ... USING gives it. Pass 1 shows what is read from disk; pass 2 the
# buffers touched once cached. The row counts come last so they do not warm the
# cache for the plans above them.
cat >"$OUT/sql/explain.sql" <<'SQL'
\echo ### stream :sid class :cls slot :t0 to :t1
\if :have_pre538
\echo
\echo ### pass 1 pre538 find_datm_for_time_slot_pre538
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT count(*) FROM solardatm.find_datm_for_time_slot_pre538(
	:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz, INTERVAL 'P1Y');
\endif
\echo
\echo ### pass 1 live find_datm_for_time_slot
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT count(*) FROM solardatm.find_datm_for_time_slot(
	:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz, INTERVAL 'P1Y');
\if :have_pre538
\echo
\echo ### pass 2 pre538 find_datm_for_time_slot_pre538
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM solardatm.find_datm_for_time_slot_pre538(
	:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz, INTERVAL 'P1Y');
\endif
\echo
\echo ### pass 2 live find_datm_for_time_slot
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM solardatm.find_datm_for_time_slot(
	:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz, INTERVAL 'P1Y');
\echo
\echo ### rollup live rollup_datm_for_time_span
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM solardatm.rollup_datm_for_time_span(
	:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz);
\echo
\echo ### row counts
SELECT 'rows_slot=' || count(*) FILTER (WHERE ts >= :'t0'::timestamptz)
	|| ' rows_0_14d=' || count(*) FILTER (WHERE ts >= :'t14'::timestamptz AND ts < :'t0'::timestamptz)
	|| ' rows_14_28d=' || count(*) FILTER (WHERE ts < :'t14'::timestamptz)
FROM solardatm.da_datm
WHERE stream_id = :'sid'::uuid
	AND ts >= :'t28'::timestamptz
	AND ts < :'t1'::timestamptz;
SQL

# -----------------------------------------------------------------------------
# Connect, and work out what this run can do.
# -----------------------------------------------------------------------------

note "Connecting"
WHO=$(ask "SELECT current_user
	, (SELECT rolsuper FROM pg_roles WHERE rolname = current_user)
	, pg_has_role(current_user, 'pg_read_all_stats', 'USAGE')
	, pg_is_in_recovery()")
if [ $? -ne 0 ] || [ -z "$WHO" ]; then
	cat "$LOG" >&2
	rm -r "$OUT"
	die "cannot connect; check the connection options and certificates"
fi
IFS='|' read -r DB_USER IS_SUPER CAN_STATS IN_RECOVERY <<EOF
$WHO
EOF

# the last complete hour, as the slot every stream is examined for
SLOT=$(ask "SELECT h - INTERVAL 'PT1H', h, h - INTERVAL 'PT1H' - INTERVAL 'P14D'
		, h - INTERVAL 'PT1H' - INTERVAL 'P28D'
	FROM date_trunc('hour', CURRENT_TIMESTAMP) AS h")
[ -n "$SLOT" ] || die "cannot work out the time slot, see $LOG"
IFS='|' read -r T0 T1 T14 T28 <<EOF
$SLOT
EOF

PSS_SCHEMA=${NET538_PSS_SCHEMA:-$(ask "SELECT n.nspname FROM pg_extension e
	INNER JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = 'pg_stat_statements'")}

case $(ask "SELECT to_regprocedure('solardatm.find_datm_for_time_slot_pre538(uuid,timestamptz,timestamptz,interval,interval)') IS NOT NULL") in
	t) HAVE_PRE538=true ;;
	*) HAVE_PRE538=false ;;
esac

{
	printf 'script_version=%s\n' "$SCRIPT_VERSION"
	printf 'started=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf 'host=%s\nport=%s\ndatabase=%s\n' "${PGHOST:-}" "${PGPORT:-}" "${PGDATABASE:-}"
	printf 'user=%s\nsuperuser=%s\nread_all_stats=%s\nin_recovery=%s\n' \
		"$DB_USER" "$IS_SUPER" "$CAN_STATS" "$IN_RECOVERY"
	printf 'psql_major=%s\n' "$PSQL_MAJOR"
	printf 'samples=%s\ninterval_s=%s\nstatement_timeout_s=%s\n' "$SAMPLES" "$INTERVAL" "$STMT_TIMEOUT"
	printf 'slot_start=%s\nslot_end=%s\nslot_minus_14d=%s\nslot_minus_28d=%s\n' "$T0" "$T1" "$T14" "$T28"
	printf 'pg_stat_statements_schema=%s\n' "$PSS_SCHEMA"
	printf 'have_pre538=%s\n' "$HAVE_PRE538"
} >"$OUT/run.txt"

note "Connected as $DB_USER (superuser=$IS_SUPER, read_all_stats=$CAN_STATS)"
if [ "$IS_SUPER" != t ] && [ "$CAN_STATS" != t ]; then
	note "WARNING: $DB_USER is neither a superuser nor in pg_read_all_stats; the"
	note "         pg_stat_statements snapshots will lack other roles' query IDs."
fi
[ "$IN_RECOVERY" != t ] || note "NOTE: this server is a replica, not the primary"
[ -n "$PSS_SCHEMA" ] || note "WARNING: pg_stat_statements is not installed in this database"
note "Slot $T0 to $T1; pre-538 copy installed: $HAVE_PRE538"

# -----------------------------------------------------------------------------
# Collect.
# -----------------------------------------------------------------------------

snapshot() {
	run csv snap-tables "$OUT/$1/tables.csv"
	run csv snap-statio "$OUT/$1/statio.csv"
	run csv snap-functions "$OUT/$1/functions.csv"
	if [ -n "$PSS_SCHEMA" ]; then
		run csv snap-pss "$OUT/$1/pg_stat_statements.csv" -v pss_schema="$PSS_SCHEMA"
		run csv snap-pss-info "$OUT/$1/pg_stat_statements_info.csv" -v pss_schema="$PSS_SCHEMA"
	fi
}

sample() {
	run csv sample-stale-agg "$OUT/samples/stale-agg.$1.csv"
	run csv sample-stale-aud "$OUT/samples/stale-aud.$1.csv"
	run csv sample-database "$OUT/samples/database.$1.csv"
	run csv sample-io "$OUT/samples/io.$1.csv"
	run csv sample-activity "$OUT/samples/activity.$1.csv"
}

# merge NAME - join samples/NAME.N.csv into NAME.csv under one header
merge() {
	_first=1
	_n=1
	: >"$OUT/$1.csv"
	while [ "$_n" -le "$SAMPLES" ]; do
		_f=$OUT/samples/$1.$_n.csv
		if [ -s "$_f" ]; then
			if [ "$_first" -eq 1 ]; then
				cat "$_f" >>"$OUT/$1.csv"
				_first=0
			else
				tail -n +2 "$_f" >>"$OUT/$1.csv"
			fi
		fi
		_n=$((_n + 1))
	done
}

note "Context"
run text context "$OUT/context.txt"

note "Snapshot 1"
snapshot snap1

sample_no=1
while [ "$sample_no" -le "$SAMPLES" ]; do
	note "Sample $sample_no of $SAMPLES"
	sample "$sample_no"
	if [ "$sample_no" -lt "$SAMPLES" ]; then
		sleep "$INTERVAL"
	fi
	sample_no=$((sample_no + 1))
done

note "Snapshot 2"
snapshot snap2

for f in stale-agg stale-aud database io activity; do
	merge "$f"
done

note "Suspect streams"
run csv streams-flagged "$OUT/streams-flagged.csv" -v t0="$T0" -v t1="$T1"

note "Classifying the $MAX_CLASSIFY most active suspect streams"
run psv streams-classified "$OUT/streams-classified.psv" \
	-v t0="$T0" -v t1="$T1" -v t14="$T14" -v max_classify="$MAX_CLASSIFY"

note "Control streams"
run psv streams-controls "$OUT/streams-controls.psv" -v t0="$T0" -v t1="$T1" -v streams="$STREAMS"

if [ "$DO_EXPLAIN" -eq 1 ] && [ "$STREAMS" -ge 1 ]; then
	TARGETS=$OUT/explain/targets.psv
	: >"$TARGETS"
	if [ -s "$OUT/streams-classified.psv" ]; then
		awk -F'|' -v k="$STREAMS" \
			'NR > 1 && $NF == "none_in_14d" && n < k { print "suspect|" $1; n++ }' \
			"$OUT/streams-classified.psv" >>"$TARGETS"
		awk -F'|' 'NR > 1 && $NF == "mixed" && n < 1 { print "suspect_mixed|" $1; n++ }' \
			"$OUT/streams-classified.psv" >>"$TARGETS"
	fi
	if [ ! -s "$TARGETS" ] && [ -s "$OUT/streams-flagged.csv" ]; then
		# classification failed: fall back to the most active flagged streams
		awk -F',' -v k="$STREAMS" 'NR > 1 && n < k { print "suspect_unclassified|" $1; n++ }' \
			"$OUT/streams-flagged.csv" >>"$TARGETS"
	fi
	if [ -s "$OUT/streams-controls.psv" ]; then
		awk -F'|' 'NR > 1 { print $1 "|" $2 }' "$OUT/streams-controls.psv" >>"$TARGETS"
	fi

	seq_no=0
	while IFS='|' read -r cls sid; do
		[ -n "$sid" ] || continue
		seq_no=$((seq_no + 1))
		note "Explain $seq_no: $cls $sid"
		"$PSQL" -X -q -w -A -t -v ON_ERROR_STOP=0 -v stmt_timeout="${STMT_TIMEOUT}s" \
			-v sid="$sid" -v cls="$cls" -v have_pre538="$HAVE_PRE538" \
			-v t0="$T0" -v t1="$T1" -v t14="$T14" -v t28="$T28" \
			-f "$OUT/sql/session.sql" -f "$OUT/sql/explain.sql" \
			>"$(printf '%s/explain/%02d-%s-%s.txt' "$OUT" "$seq_no" "$cls" "$sid")" 2>&1 </dev/null
	done <"$TARGETS"
	[ "$seq_no" -gt 0 ] || note "No streams to explain"
else
	note "Skipping EXPLAIN"
fi

trap - INT TERM
finish

if [ -n "$FAILED" ]; then
	note "Finished, but these steps failed:$FAILED"
else
	note "Finished"
fi
[ "$HAVE_PRE538" = true ] || [ "$DO_EXPLAIN" -eq 0 ] || \
	note "NOTE: solardatm.find_datm_for_time_slot_pre538 was not installed, so only the live function was explained"
exit 0
