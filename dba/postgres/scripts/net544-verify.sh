#!/bin/sh
#
# net544-verify.sh - compare the NET-544 candidate day and month rollup with the
# live one, on real streams, before NET-544 is deployed.
#
# Apply net544-candidate-copy.sql (next to this script) first, on the primary. It
# installs solardatm.rollup_agg_data_for_time_span_net544(): the rollup of hours to
# a day and of days to a month, with the NET-544 change, so that each accumulating
# property's start and end readings come from the first and last row that has
# them. This script runs it beside the live rollup_agg_data_for_time_span() for a
# sample of streams, days and months, and reports where the results differ and
# what each costs.
#
# The script changes nothing in the database: every session it opens is set to
# default_transaction_read_only, with a statement timeout. It never installs or
# removes the _net544 function. It can be run against the replica once the
# function has reached it.
#
# Every lookup it makes on a hypertable is for one stream at a time through the
# primary key, so it reads only the rows of the streams, days and months it
# samples, and for the partial kind (below) the daily rows of the last few days.
#
# Days and months are those of each stream's time zone. They are taken from the
# stored agg_datm_daily and agg_datm_monthly rows, or from the local day or month
# of a reset record, and each ends where the stale processing ends it:
# ((start AT TIME ZONE zone) + 1 day or 1 month) AT TIME ZONE zone.
#
# Usage:
#
#   PGSSLCERT=superuser.crt PGSSLKEY=superuser.key sh net544-verify.sh \
#       -h db.solarnetwork.net -p 5432 -U postgres -d solarnetwork
#
# Connection options are the same as psql's, and anything libpq reads from the
# environment applies. psql is run with -w, so it never stops to prompt.
#
#   -h HOST  -p PORT  -U USER  -d DBNAME    connection, as for psql
#   -o DIR      where to create the output (default: current directory)
#   -D COUNT    most recent complete days to compare for each sampled stream
#               (default 2)
#   -M COUNT    most recent complete months to compare for each sampled stream
#               (default 1)
#   -m COUNT    streams to sample of each kind (default 30)
#   -w DAYS     how many days back the partial kind looks (default 7)
#   -a COUNT    accumulating properties a stream needs for the partial kind to
#               look at it (default 2)
#   -k COUNT    streams of each kind to run EXPLAIN ANALYZE for (default 2)
#   -t SECONDS  statement timeout for every query (default 300)
#   -x          skip the EXPLAIN ANALYZE step
#   -T FILE     compare the streams, days and months listed in FILE, the
#               targets.psv of an earlier run, instead of choosing new ones
#
# The kinds of stream sampled:
#
#   partial     the kind where a difference is expected: streams with at least
#               -a accumulating properties that have, among the stored daily rows
#               of the last -w days, a day where a property has no start or no
#               end reading although it has a reading difference other than 0,
#               or only one of the two. That is what today's rollup stores when
#               the first or last hour of the day has no reading for the
#               property. Compared for the latest two such days of each stream,
#               and the month of each. Finding them reads those daily rows for
#               every stream with at least -a accumulating properties.
#   multi_a     two or more accumulating properties
#   single_a    one accumulating property
#   no_a        no accumulating properties: nothing may change for these
#   location    a location datum stream
#   reset       a reset record in the last 60 days; compared for the local day
#               and month holding the latest one
#
# Streams of the kinds multi_a to location are compared for their latest -D
# complete days and -M complete months that have stored rows.
#
# For each stream and day (rolled up from hours) or month (rolled up from days,
# as they are stored) it compares the live rollup with the _net544 one:
#
#   same            identical results, and no reading for the candidate to fill
#   expected_fill   identical but for start or end readings (read_a[n][2],
#                   read_a[n][3]) that the live rollup gives as NULL and the
#                   candidate gives as the first or last reading of the rows
#                   rolled up: the change NET-544 makes
#   DIFFERENT       anything else: needs looking at. That includes a reading the
#                   candidate should fill and does not, and one it fills with any
#                   other value.
#
# The first and last readings are worked out from the rows rolled up, apart from
# either function: for each property, the first (or last) row that has the
# reading, taking rows with an accumulation for the property first. In
# compare.psv, "shape" counts the readings the live rollup gives as NULL where
# such a row exists, "filled" the readings the candidate fills, and "wrong" the
# candidate's readings that differ from those worked out.
#
# The comparisons that exercise the change are those that are expected_fill
# (exercised in run.txt, and by kind in fill-summary.psv). A run with none of
# them says nothing about the change, only that it changes nothing else.
#
# A month is rolled up from the daily rows as they are stored, so where those
# days were stored by today's rollup with no start or end reading, the month
# has none to fill from: expect few months to be expected_fill.
#
# For information, each comparison also says whether the stored row is what
# the live rollup gives now (stored_same; a period still receiving data, or one
# awaiting reprocessing, may differ).
#
# The exit status is 1 if any comparison is DIFFERENT or failed, else 0.
#
# Needs psql 12 or later. Written for POSIX sh; also runs under zsh and bash.

set -u
umask 077

# zsh gives a function's name as $0 inside it, so keep the script's name here
SCRIPT=$0
SCRIPT_VERSION=1
DAYS=2
MONTHS=1
SAMPLE=30
WINDOW=7
MIN_A=2
STREAMS=2
STMT_TIMEOUT=300
DO_EXPLAIN=1
OUTBASE=.
TARGETS_FILE=
PSQL=${PSQL:-psql}

# md5 of the function bodies this script was written against
LIVE_MD5=4865679d768aa12f3cbe905c56c64913
CANDIDATE_MD5=7ae308c50b55b4b7ac4dade8c995f610

usage() {
	sed -n '2,/^# Needs psql/p' "$SCRIPT" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

die() {
	printf 'net544-verify: %s\n' "$*" >&2
	exit 1
}

is_number() {
	case $1 in
		'' | *[!0-9]*) return 1 ;;
	esac
	return 0
}

while getopts 'h:p:U:d:o:D:M:m:w:a:k:t:xT:' opt; do
	case $opt in
		h) PGHOST=$OPTARG; export PGHOST ;;
		p) PGPORT=$OPTARG; export PGPORT ;;
		U) PGUSER=$OPTARG; export PGUSER ;;
		d) PGDATABASE=$OPTARG; export PGDATABASE ;;
		o) OUTBASE=$OPTARG ;;
		D) DAYS=$OPTARG ;;
		M) MONTHS=$OPTARG ;;
		m) SAMPLE=$OPTARG ;;
		w) WINDOW=$OPTARG ;;
		a) MIN_A=$OPTARG ;;
		k) STREAMS=$OPTARG ;;
		t) STMT_TIMEOUT=$OPTARG ;;
		x) DO_EXPLAIN=0 ;;
		T) TARGETS_FILE=$OPTARG ;;
		*) usage ;;
	esac
done
shift $((OPTIND - 1))
[ $# -eq 0 ] || usage

for v in "$DAYS" "$MONTHS" "$SAMPLE" "$WINDOW" "$MIN_A" "$STREAMS" "$STMT_TIMEOUT"; do
	is_number "$v" || die "options -D, -M, -m, -w, -a, -k and -t take a whole number"
done
[ "$SAMPLE" -ge 1 ] || die "-m must be at least 1"
[ "$WINDOW" -ge 1 ] || die "-w must be at least 1"
[ "$MIN_A" -ge 1 ] || die "-a must be at least 1"
[ -z "$TARGETS_FILE" ] || [ -r "$TARGETS_FILE" ] || die "cannot read $TARGETS_FILE"

command -v "$PSQL" >/dev/null 2>&1 || die "psql not found (set PSQL=/path/to/psql)"
PSQL_MAJOR=$("$PSQL" -V | sed -n 's/^[^0-9]*\([0-9][0-9]*\).*/\1/p')
is_number "${PSQL_MAJOR:-}" || die "cannot tell the version of $PSQL"
[ "$PSQL_MAJOR" -ge 12 ] || die "psql 12 or later is needed (found $PSQL_MAJOR)"

PGAPPNAME=net544-verify
PGCONNECT_TIMEOUT=${PGCONNECT_TIMEOUT:-15}
export PGAPPNAME PGCONNECT_TIMEOUT

[ -d "$OUTBASE" ] || die "output directory $OUTBASE does not exist"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
NAME=net544-$STAMP
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
	"$PSQL" -X -q -w -A -t -F '|' -v ON_ERROR_STOP=1 \
		-c "SET timezone = 'UTC'; SET default_transaction_read_only = on; SET statement_timeout = '60s'" \
		-c "$1" 2>>"$LOG"
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
SET application_name = 'net544-verify';
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
SELECT extversion AS timescaledb FROM pg_extension WHERE extname = 'timescaledb';
SELECT name, setting FROM pg_settings
WHERE name IN ('jit', 'work_mem', 'shared_buffers', 'max_parallel_workers_per_gather', 'track_io_timing')
ORDER BY name;

\echo == functions
SELECT p.oid::regprocedure AS func, l.lanname AS lang, p.proisstrict AS strict
	, p.provolatile AS vol, md5(p.prosrc) AS src_md5, length(p.prosrc) AS src_len
FROM pg_proc p
INNER JOIN pg_namespace n ON n.oid = p.pronamespace
INNER JOIN pg_language l ON l.oid = p.prolang
WHERE n.nspname = 'solardatm'
	AND p.proname IN ('rollup_agg_data_for_time_span', 'rollup_agg_data_for_time_span_net544'
		, 'find_agg_datm_for_time_span', 'find_metadata_for_stream', 'process_one_agg_stale_datm')
ORDER BY 1;

\echo == newest aggregate chunks
SELECT c.hypertable_name, c.chunk_schema || '.' || c.chunk_name AS chunk, c.range_start, c.range_end
FROM timescaledb_information.chunks c
WHERE c.hypertable_schema = 'solardatm'
	AND c.hypertable_name IN ('agg_datm_hourly', 'agg_datm_daily', 'agg_datm_monthly')
	AND c.range_end > statement_timestamp() - INTERVAL 'P60D'
ORDER BY 1, c.range_start DESC;

\echo == streams by accumulating properties
SELECT CASE WHEN COALESCE(cardinality(names_a), 0) > 2 THEN '3+' ELSE COALESCE(cardinality(names_a), 0)::text END AS accumulating
	, count(*) AS node_streams
FROM solardatm.da_datm_meta
GROUP BY 1
ORDER BY 1;
SQL

# The streams, days and months to compare: class|stream_id|level|start|end|zone.
#
# Every subquery on a hypertable is LATERAL with an aggregate, a window function
# or a LIMIT, so that it runs once for each stream through the primary key and
# cannot be turned into a join over a scan of a whole chunk. Each also has a
# lower time bound, so that only the newest chunks are planned.
cat >"$OUT/sql/targets.sql" <<'SQL'
WITH nmeta AS MATERIALIZED (
	SELECT m.stream_id, COALESCE(cardinality(m.names_a), 0) AS n_a, FALSE AS loc
	FROM solardatm.da_datm_meta m
)
, lmeta AS MATERIALIZED (
	SELECT m.stream_id, COALESCE(cardinality(m.names_a), 0) AS n_a, TRUE AS loc
	FROM solardatm.da_loc_datm_meta m
)
-- stored days of the last :window days in which a property has no start or no end reading,
-- although it has a reading difference other than 0 or the other reading; the latest two for
-- each stream
, partial_days AS MATERIALIZED (
	SELECT m.stream_id, p.ts_start
	FROM nmeta m
	CROSS JOIN LATERAL (
		SELECT d.ts_start
		FROM solardatm.agg_datm_daily d
		WHERE d.stream_id = m.stream_id
			AND d.ts_start >= :'t_now'::timestamptz - make_interval(days => :window)
			AND d.ts_start < :'t_day'::timestamptz
			AND EXISTS (
				SELECT 1
				FROM generate_subscripts(d.read_a, 1) AS i
				WHERE (d.read_a[i][2] IS NULL OR d.read_a[i][3] IS NULL)
					AND (d.read_a[i][1] <> 0 OR (d.read_a[i][2] IS NULL) <> (d.read_a[i][3] IS NULL))
			)
		ORDER BY d.ts_start DESC
		LIMIT 2
	) p
	WHERE m.n_a >= :min_a
)
, partial AS MATERIALIZED (
	SELECT x.stream_id, x.ts_start
	FROM (
		SELECT p.stream_id, p.ts_start
			, dense_rank() OVER (ORDER BY md5(p.stream_id::text || 'p' || :'t_day'), p.stream_id) AS rn
		FROM partial_days p
	) x
	WHERE x.rn <= :sample
)
-- a sample of each kind of stream, five times as many as needed, since some have no rows
, picks AS MATERIALIZED (
	SELECT x.class, x.stream_id
	FROM (
		SELECT c.class, m.stream_id
			, row_number() OVER (PARTITION BY c.class ORDER BY md5(m.stream_id::text || c.class || :'t_day')) AS rn
		FROM (SELECT * FROM nmeta UNION ALL SELECT * FROM lmeta) m
		CROSS JOIN LATERAL (
			SELECT CASE
				WHEN m.loc THEN 'location'
				WHEN m.n_a > 1 THEN 'multi_a'
				WHEN m.n_a = 1 THEN 'single_a'
				ELSE 'no_a'
				END AS class
		) c
	) x
	WHERE x.rn <= :sample * 5
)
-- their latest complete stored days in the last 30 days
, pick_days AS MATERIALIZED (
	SELECT p.class, p.stream_id, d.ts_start
	FROM picks p
	CROSS JOIN LATERAL (
		SELECT d.ts_start
		FROM solardatm.agg_datm_daily d
		WHERE d.stream_id = p.stream_id
			AND d.ts_start >= :'t_day'::timestamptz - INTERVAL 'P30D'
			AND d.ts_start < :'t_day'::timestamptz
		ORDER BY d.ts_start DESC
		LIMIT :days
	) d
)
, sampled AS MATERIALIZED (
	SELECT x.class, x.stream_id
	FROM (
		SELECT y.class, y.stream_id
			, row_number() OVER (PARTITION BY y.class ORDER BY md5(y.stream_id::text || y.class || :'t_day')) AS rn
		FROM (SELECT DISTINCT class, stream_id FROM pick_days) y
	) x
	WHERE x.rn <= :sample
)
-- and their latest complete stored months in the last 400 days
, pick_months AS MATERIALIZED (
	SELECT s.class, s.stream_id, d.ts_start
	FROM sampled s
	CROSS JOIN LATERAL (
		SELECT d.ts_start
		FROM solardatm.agg_datm_monthly d
		WHERE d.stream_id = s.stream_id
			AND d.ts_start >= :'t_mon'::timestamptz - INTERVAL 'P400D'
			AND d.ts_start < :'t_mon'::timestamptz
		ORDER BY d.ts_start DESC
		LIMIT :months
	) d
)
-- the latest reset record of each stream in the last 60 days, newest first
, resets AS MATERIALIZED (
	SELECT r.stream_id, r.ts
	FROM (
		SELECT DISTINCT ON (aux.stream_id) aux.stream_id, aux.ts
		FROM solardatm.da_datm_aux aux
		WHERE aux.atype = 'Reset'::solardatm.da_datm_aux_type
			AND aux.ts >= :'t_now'::timestamptz - INTERVAL 'P60D'
			AND aux.ts < :'t_day'::timestamptz
		ORDER BY aux.stream_id, aux.ts DESC
	) r
	ORDER BY r.ts DESC, r.stream_id
	LIMIT :sample
)
, base AS (
	SELECT 'partial' AS class, p.stream_id, 'day' AS lvl, p.ts_start AS ts FROM partial p
	UNION ALL
	SELECT 'partial', p.stream_id, 'month_of', p.ts_start FROM partial p
	UNION ALL
	SELECT d.class, d.stream_id, 'day', d.ts_start
	FROM pick_days d
	INNER JOIN sampled s ON s.class = d.class AND s.stream_id = d.stream_id
	UNION ALL
	SELECT m.class, m.stream_id, 'month', m.ts_start FROM pick_months m
	UNION ALL
	SELECT 'reset', r.stream_id, 'day_of', r.ts FROM resets r
	UNION ALL
	SELECT 'reset', r.stream_id, 'month_of', r.ts FROM resets r
)
SELECT DISTINCT b.class, b.stream_id, s.level, s.t0
	, ((s.t0 AT TIME ZONE z.tz) + CASE s.level WHEN 'day' THEN INTERVAL 'P1D' ELSE INTERVAL 'P1M' END) AT TIME ZONE z.tz AS t1
	, z.tz
FROM base b
CROSS JOIN LATERAL (
	SELECT COALESCE(f.time_zone, 'UTC') AS tz
	FROM solardatm.find_metadata_for_stream(b.stream_id) f
	LIMIT 1
) z
CROSS JOIN LATERAL (
	SELECT CASE WHEN b.lvl IN ('day', 'day_of') THEN 'day' ELSE 'month' END AS level
		, CASE b.lvl
			WHEN 'day_of' THEN date_trunc('day', b.ts AT TIME ZONE z.tz) AT TIME ZONE z.tz
			WHEN 'month_of' THEN date_trunc('month', b.ts AT TIME ZONE z.tz) AT TIME ZONE z.tz
			ELSE b.ts
			END AS t0
) s
ORDER BY 1, 2, 3, 4;
SQL

# One row per stream and period: $1 class, $2 stream, $3 level, $4 start, $5 end.
#   i  the rows rolled up (hourly rows for a day, daily rows for a month)
#   l  the live rollup
#   c  the _net544 candidate
#   s  the stored row, for information
cat >"$OUT/sql/compare-prepare.sql" <<'SQL'
PREPARE cmp(text, uuid, text, timestamptz, timestamptz, text) AS
WITH i AS MATERIALIZED (
	SELECT * FROM solardatm.find_agg_datm_for_time_span($2, $4, $5
		, (CASE $3 WHEN 'month' THEN 'd' ELSE 'h' END)::character)
)
, l AS MATERIALIZED (
	SELECT * FROM solardatm.rollup_agg_data_for_time_span($2, $4, $5
		, (CASE $3 WHEN 'month' THEN 'd' ELSE 'h' END)::character)
)
, c AS MATERIALIZED (
	SELECT * FROM solardatm.rollup_agg_data_for_time_span_net544($2, $4, $5
		, (CASE $3 WHEN 'month' THEN 'd' ELSE 'h' END)::character)
)
, s AS MATERIALIZED (
	SELECT d.data_i, d.data_a, d.data_s, d.data_t, d.stat_i, d.read_a
	FROM solardatm.agg_datm_daily d
	WHERE $3 = 'day' AND d.stream_id = $2 AND d.ts_start = $4
	UNION ALL
	SELECT d.data_i, d.data_a, d.data_s, d.data_t, d.stat_i, d.read_a
	FROM solardatm.agg_datm_monthly d
	WHERE $3 = 'month' AND d.stream_id = $2 AND d.ts_start = $4
)
, n AS (
	SELECT (SELECT count(*) FROM i) AS n_i
		, (SELECT count(*) FROM l) AS n_l
		, (SELECT count(*) FROM c) AS n_c
		, (SELECT count(*) FROM s) AS n_s
		, GREATEST(
			  COALESCE((SELECT max(array_upper(x.data_a, 1)) FROM i x), 0)
			, COALESCE((SELECT max(array_upper(x.read_a, 1)) FROM l x), 0)
			, COALESCE((SELECT max(array_upper(x.read_a, 1)) FROM c x), 0)
		) AS n_p
)
-- each property: the live and candidate readings, and the first and last readings of the rows
-- rolled up, worked out here: rows that have the property (data_a reaches it) and the reading,
-- those with an accumulation for it first, then by time
, p AS (
	SELECT g.idx
		, (SELECT x.read_a[g.idx][1] FROM l x) AS l1
		, (SELECT x.read_a[g.idx][2] FROM l x) AS l2
		, (SELECT x.read_a[g.idx][3] FROM l x) AS l3
		, (SELECT x.read_a[g.idx][1] FROM c x) AS c1
		, (SELECT x.read_a[g.idx][2] FROM c x) AS c2
		, (SELECT x.read_a[g.idx][3] FROM c x) AS c3
		, (SELECT x.read_a[g.idx][2] FROM i x
			WHERE array_upper(x.data_a, 1) >= g.idx AND x.read_a[g.idx][2] IS NOT NULL
			ORDER BY x.data_a[g.idx] IS NULL, x.ts_start
			LIMIT 1) AS e2
		, (SELECT x.read_a[g.idx][3] FROM i x
			WHERE array_upper(x.data_a, 1) >= g.idx AND x.read_a[g.idx][3] IS NOT NULL
			ORDER BY x.data_a[g.idx] IS NULL, x.ts_start DESC
			LIMIT 1) AS e3
	FROM n
	CROSS JOIN generate_series(1, n.n_p) AS g(idx)
)
, pa AS (
	SELECT count(*) AS props
		, count(*) FILTER (WHERE l2 IS NULL AND e2 IS NOT NULL)
			+ count(*) FILTER (WHERE l3 IS NULL AND e3 IS NOT NULL) AS shape
		, count(*) FILTER (WHERE l2 IS NULL AND c2 IS NOT NULL)
			+ count(*) FILTER (WHERE l3 IS NULL AND c3 IS NOT NULL) AS filled
		, count(*) FILTER (WHERE c2 IS DISTINCT FROM e2)
			+ count(*) FILTER (WHERE c3 IS DISTINCT FROM e3) AS wrong
		, count(*) FILTER (WHERE l1 IS DISTINCT FROM c1
			OR (l2 IS NOT NULL AND l2 IS DISTINCT FROM c2)
			OR (l3 IS NOT NULL AND l3 IS DISTINCT FROM c3)) AS changed
	FROM p
)
-- live against candidate, apart from read_a
, lc AS (
	SELECT bool_and((l.stream_id, l.ts_start, l.data_i, l.data_a, l.data_s, l.data_t, l.stat_i)
			IS NOT DISTINCT FROM (c.stream_id, c.ts_start, c.data_i, c.data_a, c.data_s, c.data_t, c.stat_i)
			AND array_dims(l.read_a) IS NOT DISTINCT FROM array_dims(c.read_a)) AS rest_same
		, bool_and(l.read_a IS NOT DISTINCT FROM c.read_a) AS read_same
	FROM l, c
)
SELECT $1 AS class, $2 AS stream_id, $3 AS level, $4 AS period_start, $6 AS time_zone
	, CASE
		WHEN n.n_l = 0 AND n.n_c = 0 AND pa.shape = 0 THEN 'same'
		WHEN n.n_l <> 1 OR n.n_c <> 1 THEN 'DIFFERENT'
		WHEN NOT lc.rest_same OR pa.changed > 0 OR pa.wrong > 0 THEN 'DIFFERENT'
		WHEN lc.read_same THEN 'same'
		ELSE 'expected_fill'
		END AS verdict
	, n.n_i AS input_rows, n.n_l AS rows_live, n.n_c AS rows_candidate, pa.props AS properties
	, pa.shape, pa.filled, pa.wrong
	, n.n_s AS stored_rows
	, CASE WHEN n.n_s = 1 AND n.n_l = 1 THEN (
		SELECT (s.data_i, s.data_a, s.data_s, s.data_t, s.stat_i, s.read_a)
			IS NOT DISTINCT FROM (l.data_i, l.data_a, l.data_s, l.data_t, l.stat_i, l.read_a)
		FROM s, l) END AS stored_same
	, (SELECT x.read_a::text FROM l x) AS read_a_live
	, (SELECT x.read_a::text FROM c x) AS read_a_candidate
FROM n, pa, lc;
SQL

COMPARE_HEADER='class|stream_id|level|period_start|time_zone|verdict|input_rows|rows_live|rows_candidate|properties|shape|filled|wrong|stored_rows|stored_same|read_a_live|read_a_candidate'

# What each function costs, with literal arguments as production's
# EXECUTE ... USING gives them. Both run once unmeasured, then twice each,
# alternating, for the day and for the month.
cat >"$OUT/sql/explain.sql" <<'SQL'
\echo ### stream :sid class :cls day :d0 month :m0
\echo
\if :has_day
SELECT count(*) FROM solardatm.rollup_agg_data_for_time_span(:'sid'::uuid, :'d0'::timestamptz, :'d1'::timestamptz, 'h') \g /dev/null
SELECT count(*) FROM solardatm.rollup_agg_data_for_time_span_net544(:'sid'::uuid, :'d0'::timestamptz, :'d1'::timestamptz, 'h') \g /dev/null
\echo ### plan 1 day live
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT * FROM solardatm.rollup_agg_data_for_time_span(:'sid'::uuid, :'d0'::timestamptz, :'d1'::timestamptz, 'h');
\echo
\echo ### plan 2 day candidate
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM solardatm.rollup_agg_data_for_time_span_net544(:'sid'::uuid, :'d0'::timestamptz, :'d1'::timestamptz, 'h');
\echo
\echo ### plan 3 day live
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM solardatm.rollup_agg_data_for_time_span(:'sid'::uuid, :'d0'::timestamptz, :'d1'::timestamptz, 'h');
\echo
\echo ### plan 4 day candidate
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM solardatm.rollup_agg_data_for_time_span_net544(:'sid'::uuid, :'d0'::timestamptz, :'d1'::timestamptz, 'h');
\echo
\endif
\if :has_month
SELECT count(*) FROM solardatm.rollup_agg_data_for_time_span(:'sid'::uuid, :'m0'::timestamptz, :'m1'::timestamptz, 'd') \g /dev/null
SELECT count(*) FROM solardatm.rollup_agg_data_for_time_span_net544(:'sid'::uuid, :'m0'::timestamptz, :'m1'::timestamptz, 'd') \g /dev/null
\echo ### plan 5 month live
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM solardatm.rollup_agg_data_for_time_span(:'sid'::uuid, :'m0'::timestamptz, :'m1'::timestamptz, 'd');
\echo
\echo ### plan 6 month candidate
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM solardatm.rollup_agg_data_for_time_span_net544(:'sid'::uuid, :'m0'::timestamptz, :'m1'::timestamptz, 'd');
\echo
\echo ### plan 7 month live
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM solardatm.rollup_agg_data_for_time_span(:'sid'::uuid, :'m0'::timestamptz, :'m1'::timestamptz, 'd');
\echo
\echo ### plan 8 month candidate
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM solardatm.rollup_agg_data_for_time_span_net544(:'sid'::uuid, :'m0'::timestamptz, :'m1'::timestamptz, 'd');
\endif
SQL

# -----------------------------------------------------------------------------
# Connect, and check the _net544 function is there.
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
	  (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('solardatm.rollup_agg_data_for_time_span(uuid,timestamptz,timestamptz,character)'))
	, (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('solardatm.rollup_agg_data_for_time_span_net544(uuid,timestamptz,timestamptz,character)'))")
if [ -z "$FUNCS" ]; then
	cat "$LOG" >&2
	rm -r "$OUT"
	die "cannot look up the functions"
fi
IFS='|' read -r HAVE_LIVE_MD5 HAVE_CANDIDATE_MD5 <<EOF
$FUNCS
EOF
if [ -z "$HAVE_CANDIDATE_MD5" ]; then
	rm -r "$OUT"
	die "the _net544 function is not installed; apply net544-candidate-copy.sql first"
fi

# days whose start is before T_DAY, and months whose start is before T_MON, have ended in
# every time zone
TIMES=$(ask "SELECT n, n - INTERVAL 'PT25H', n - INTERVAL 'P31DT1H' FROM date_trunc('second', CURRENT_TIMESTAMP) AS n")
[ -n "$TIMES" ] || die "cannot read the time, see $LOG"
IFS='|' read -r T_NOW T_DAY T_MON <<EOF
$TIMES
EOF

{
	printf 'script_version=%s\n' "$SCRIPT_VERSION"
	printf 'started=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf 'host=%s\nport=%s\ndatabase=%s\n' "${PGHOST:-}" "${PGPORT:-}" "${PGDATABASE:-}"
	printf 'user=%s\nsuperuser=%s\nin_recovery=%s\n' "$DB_USER" "$IS_SUPER" "$IN_RECOVERY"
	printf 'psql_major=%s\n' "$PSQL_MAJOR"
	printf 'days=%s\nmonths=%s\nsample=%s\nwindow_days=%s\nmin_accumulating=%s\n' \
		"$DAYS" "$MONTHS" "$SAMPLE" "$WINDOW" "$MIN_A"
	printf 'explain_streams=%s\nstatement_timeout_s=%s\n' "$STREAMS" "$STMT_TIMEOUT"
	printf 'now=%s\ndays_before=%s\nmonths_before=%s\n' "$T_NOW" "$T_DAY" "$T_MON"
	printf 'targets_file=%s\n' "$TARGETS_FILE"
	printf 'live_md5=%s\ncandidate_net544_md5=%s\n' "$HAVE_LIVE_MD5" "$HAVE_CANDIDATE_MD5"
} >"$OUT/run.txt"

note "Connected as $DB_USER; days before $T_DAY, months before $T_MON"
[ "$IN_RECOVERY" != t ] || note "NOTE: this server is a replica, not the primary"
if [ "$HAVE_CANDIDATE_MD5" != "$CANDIDATE_MD5" ]; then
	note "NOTE: the _net544 function is not the version this script was written"
	note "      against (md5 $HAVE_CANDIDATE_MD5, expected $CANDIDATE_MD5)"
fi
if [ "$HAVE_LIVE_MD5" != "$LIVE_MD5" ]; then
	note "NOTE: the live rollup_agg_data_for_time_span() is not the version the _net544"
	note "      copy was made from (md5 $HAVE_LIVE_MD5, expected $LIVE_MD5)"
fi

# -----------------------------------------------------------------------------
# Compare.
# -----------------------------------------------------------------------------

note "Context"
run text context "$OUT/context.txt"

if [ -n "$TARGETS_FILE" ]; then
	note "Using the streams, days and months in $TARGETS_FILE"
	awk -F'|' 'NF == 6 && length($2) == 36' "$TARGETS_FILE" >"$OUT/targets.psv"
else
	note "Choosing streams"
	run rows targets "$OUT/targets.psv" -v t_now="$T_NOW" -v t_day="$T_DAY" -v t_mon="$T_MON" \
		-v days="$DAYS" -v months="$MONTHS" -v sample="$SAMPLE" -v window="$WINDOW" -v min_a="$MIN_A"
fi
TARGET_COUNT=$(($(wc -l <"$OUT/targets.psv")))
[ "$TARGET_COUNT" -gt 0 ] || { finish; die "no streams found to compare, see $OUT/verify.log"; }
awk -F'|' '{ n[$1 "|" $3]++; if (!(($1, $2) in s)) { s[$1, $2] = 1; st[$1]++ } }
	END { for (k in n) { split(k, a, "|"); printf "%s %s: %d comparisons (%d streams of the kind)\n", a[1], a[2], n[k], st[a[1]] } }' \
	"$OUT/targets.psv" | sort | while IFS= read -r line; do note "  $line"; done

printf '%s\n' "$COMPARE_HEADER" >"$OUT/compare.psv"
: >"$OUT/compare-errors.txt"
# the kinds are listed here, not in a variable, as zsh would not split one into words
for cls in partial multi_a single_a no_a location reset; do
	# one EXECUTE per stream and period; the values come from the database, and
	# are checked here before being written into SQL
	awk -F'|' -v cls="$cls" '
		$1 == cls && length($2) == 36 && $2 ~ /^[0-9a-f-]+$/ && ($3 == "day" || $3 == "month") \
				&& $4 ~ /^[0-9: +-]+$/ && $5 ~ /^[0-9: +-]+$/ && $6 ~ /^[A-Za-z0-9\/_+-]+$/ {
			printf "EXECUTE cmp(\047%s\047, \047%s\047, \047%s\047, \047%s\047, \047%s\047, \047%s\047);\n", $1, $2, $3, $4, $5, $6
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
DIFFERENT=$(awk -F'|' 'NR > 1 && $6 == "DIFFERENT" { n++ } END { print n + 0 }' "$OUT/compare.psv")
EXERCISED=$(awk -F'|' 'NR > 1 && $6 == "expected_fill" { n++ } END { print n + 0 }' "$OUT/compare.psv")
FILLED=$(awk -F'|' 'NR > 1 { n += $12 } END { print n + 0 }' "$OUT/compare.psv")

# class and level by verdict
{
	printf 'class|level|verdict|comparisons|streams\n'
	awk -F'|' '
		NR > 1 {
			k = $1 "|" $3 "|" $6
			n[k]++
			if (!((k, $2) in seen)) {
				seen[k, $2] = 1
				s[k]++
			}
		}
		END { for (k in n) print k "|" n[k] "|" s[k] }
	' "$OUT/compare.psv" | sort
} >"$OUT/compare-summary.psv"

# how often the change was exercised: comparisons with a reading to fill, and readings filled
{
	printf 'class|level|comparisons|with_shape|expected_fill|readings_shape|readings_filled|readings_wrong|stored_differ\n'
	awk -F'|' '
		NR > 1 {
			k = $1 "|" $3
			c[k]++
			if ($11 + 0 > 0) w[k]++
			if ($6 == "expected_fill") e[k]++
			sh[k] += $11; f[k] += $12; wr[k] += $13
			if ($15 == "f") sd[k]++
		}
		END { for (k in c) print k "|" c[k] "|" w[k] + 0 "|" e[k] + 0 "|" sh[k] + 0 "|" f[k] + 0 "|" wr[k] + 0 "|" sd[k] + 0 }
	' "$OUT/compare.psv" | sort
} >"$OUT/fill-summary.psv"

if [ "$DO_EXPLAIN" -eq 1 ] && [ "$STREAMS" -ge 1 ]; then
	# the first STREAMS streams of each kind, at their first day and first month compared
	awk -F'|' -v k="$STREAMS" '
		!(($1, $2) in seen) && n[$1] < k { seen[$1, $2] = 1; n[$1]++; order[++m] = $1 "|" $2 }
		$3 == "day" && !(($1, $2) in day) { day[$1, $2] = $4 "|" $5 }
		$3 == "month" && !(($1, $2) in mon) { mon[$1, $2] = $4 "|" $5 }
		END {
			for (j = 1; j <= m; j++) {
				split(order[j], a, "|")
				d = ((a[1], a[2]) in day) ? day[a[1], a[2]] : "|"
				mo = ((a[1], a[2]) in mon) ? mon[a[1], a[2]] : "|"
				print a[1] "|" a[2] "|" d "|" mo
			}
		}
	' "$OUT/targets.psv" >"$OUT/explain/targets.psv"
	seq_no=0
	: >"$OUT/explain/files.txt"
	while IFS='|' read -r cls sid d0 d1 m0 m1; do
		[ -n "$sid" ] || continue
		seq_no=$((seq_no + 1))
		has_day=false
		has_month=false
		[ -z "$d0" ] || has_day=true
		[ -z "$m0" ] || has_month=true
		note "Explain $seq_no: $cls $sid"
		_f=$(printf '%s/explain/%02d-%s-%s.txt' "$OUT" "$seq_no" "$cls" "$sid")
		printf '%s\n' "$_f" >>"$OUT/explain/files.txt"
		"$PSQL" -X -q -w -A -t -v ON_ERROR_STOP=0 -v stmt_timeout="${STMT_TIMEOUT}s" \
			-v sid="$sid" -v cls="$cls" -v d0="$d0" -v d1="$d1" -v m0="$m0" -v m1="$m1" \
			-v has_day="$has_day" -v has_month="$has_month" \
			-f "$OUT/sql/session.sql" -f "$OUT/sql/explain.sql" \
			>"$_f" 2>&1 </dev/null
	done <"$OUT/explain/targets.psv"

	# the top line of each plan: buffers touched, and the times
	{
		printf 'file|plan|buffers_hit|buffers_read|planning_ms|execution_ms\n'
		while IFS= read -r f; do
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
				/^### plan/ {
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
		done <"$OUT/explain/files.txt"
	} >"$OUT/explain-summary.psv"

	# the average of each plan over the streams explained
	{
		printf 'plan|runs|avg_buffers_hit|avg_buffers_read|avg_planning_ms|avg_execution_ms\n'
		awk -F'|' '
			NR > 1 && $6 != "" { n[$2]++; h[$2] += $3; r[$2] += $4; p[$2] += $5; e[$2] += $6 }
			END { for (k in n) printf "%s|%d|%.0f|%.0f|%.3f|%.3f\n", k, n[k], h[k] / n[k], r[k] / n[k], p[k] / n[k], e[k] / n[k] }
		' "$OUT/explain-summary.psv" | sort
	} >"$OUT/explain-averages.psv"

	# candidate against live, for the day and the month: total time and buffers
	{
		printf 'level|runs|live_buffers|candidate_buffers|live_total_ms|candidate_total_ms|ratio\n'
		awk -F'|' '
			NR > 1 && $6 != "" {
				split($2, w, " ")
				lv = w[3]; fn = w[4]
				t = $5 + $6; b = $3 + $4
				if (fn == "live") { lt[lv] += t; lb[lv] += b; ln[lv]++ }
				else { ct[lv] += t; cb[lv] += b; cn[lv]++ }
			}
			END {
				for (k in ln) if (cn[k] > 0)
					printf "%s|%d|%.1f|%.1f|%.3f|%.3f|%.3f\n", k, ln[k], lb[k] / ln[k], cb[k] / cn[k], lt[k] / ln[k], ct[k] / cn[k], (ct[k] / cn[k]) / (lt[k] / ln[k])
			}
		' "$OUT/explain-summary.psv" | sort
	} >"$OUT/explain-ratio.psv"
else
	note "Skipping EXPLAIN"
fi

trap - INT TERM
{
	printf 'targets=%s\ncompared=%s\nmissing=%s\ndifferent=%s\nexercised=%s\nreadings_filled=%s\n' \
		"$TARGET_COUNT" "$COMPARED" "$MISSING" "$DIFFERENT" "$EXERCISED" "$FILLED"
} >>"$OUT/run.txt"

note "Results by kind of stream and level (comparisons, streams):"
awk -F'|' 'NR > 1 { printf "  %-9s %-6s %-14s %5d %5d\n", $1, $2, $3, $4, $5 }' "$OUT/compare-summary.psv" \
	| while IFS= read -r line; do note "$line"; done

note "Readings to fill, by kind and level (comparisons with any; expected_fill; readings filled):"
awk -F'|' 'NR > 1 { printf "  %-9s %-6s %5d %5d %6d\n", $1, $2, $4, $5, $7 }' "$OUT/fill-summary.psv" \
	| while IFS= read -r line; do note "$line"; done

if [ -f "$OUT/explain-ratio.psv" ]; then
	note "Cost, candidate against live (runs; buffers live, candidate; ms live, candidate; ratio):"
	awk -F'|' 'NR > 1 { printf "  %-6s %4d %8.1f %8.1f %9.3f %9.3f %7.3f\n", $1, $2, $3, $4, $5, $6, $7 }' "$OUT/explain-ratio.psv" \
		| while IFS= read -r line; do note "$line"; done
fi

note "Comparisons that exercised the change (expected_fill): $EXERCISED of $COMPARED, $FILLED readings filled"
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
finish
if [ "$DIFFERENT" -gt 0 ] || [ "$MISSING" -gt 0 ] || [ -n "$FAILED" ]; then
	exit 1
fi
exit 0
