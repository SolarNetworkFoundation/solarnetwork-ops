#!/bin/sh
#
# net540-verify.sh - compare the NET-540 step 1 rollup, which returns an hour
# and its 15 minute rows, with the live hourly rollup, on real streams, before
# step 1 is deployed.
#
# Apply net540-candidate-copy.sql (next to this script) first, on the primary. It
# installs two functions under names ending in _net540: the step 1 rollup of one
# hour, which returns the hour and its 15 minute rows, and the hour rolled up
# from those 15 minute rows. This script then runs them beside the live hourly
# rollup for a sample of streams and hours, and reports where the results differ
# and what each costs. It stops if the live hourly rollup is not a version it
# knows, because the comparison would then mean nothing.
#
# The script changes nothing in the database: every session it opens is set to
# default_transaction_read_only, with a statement timeout. It never installs or
# removes the _net540 functions. It can be run against the replica once the
# functions have reached it.
#
# Every lookup it makes on a hypertable is for one stream at a time through the
# primary key, so it reads only the rows of the streams and hours it samples.
#
# Usage:
#
#   PGSSLCERT=superuser.crt PGSSLKEY=superuser.key sh net540-verify.sh \
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
#   -T FILE     compare the streams and hours listed in FILE, the targets.psv of
#               an earlier run, instead of choosing new ones; use it to repeat a
#               run after the candidate functions have changed
#
# The kinds of stream sampled, by what they posted in the latest complete hour:
#
#   dense       more than 4 datum in the hour
#   mid         2 to 4 datum in the hour
#   sparse      1 datum in the hour
#   status      has status properties
#   multi_a     has two or more accumulating properties
#   mixed_a     has two or more accumulating properties, and in one of the hours
#               compared one of them is carried by some datum and not by others.
#               These are the hours where a 15 minute row can have no value for
#               a property that the hour does have. Finding them reads the
#               datum of those hours for every such stream.
#   location    a location datum stream
#
# and by their history:
#
#   after_gap   posted in the last 7 days after at least a whole day without
#               datum (or for the first time in 30 days); compared for the hour
#               of the first datum after the gap, and the hour before
#   reset       has a reset record in the last 60 days; compared for the hour of
#               the reset, the hour before and the hour after
#   reset_pair  has two reset records at most an hour apart with no datum between
#               them, at any time; compared for the hours around the pair.
#               While the live rollup predates NET-543, whose fix the
#               candidate has, some of these hours differ as expected_fix.
#   partial_a   has two or more accumulating properties and at most 300 datum a
#               day, and in the 24 hours before the latest complete hour has an
#               hour where one 15 minute slot holds datum with a value for a
#               property and another holds datum with none; compared for the
#               latest two such hours. These hours nearly always have a
#               "partial" 15 minute row (see below), which mixed_a only makes
#               possible. The exception is when the slot without the property
#               is the first with datum and the datum before the hour had the
#               property: that datum's reading is counted in the first slot.
#               Finding them reads a day of datum for each stream with two or
#               more accumulating properties that is under the 300 a day limit;
#               denser streams are left out to keep that small.
#
# For each stream and hour it makes two comparisons.
#
# hour: the live hourly rollup, rollup_datm_for_time_span(), against the hour
# the candidate returns with its 15 minute rows. Stale processing will store
# that hour in place of the live rollup's, so it must be identical:
#
#   same             identical results, compared as text
#   expected_fix     only while the live rollup predates NET-543 (the script
#                    checks its md5): two reset records lie in the hour after
#                    the end of this hour, the clock accumulation (data_a)
#                    differs and nothing else does, which is the double count
#                    NET-543 removes
#   DIFFERENT        anything else: needs looking at
#
# slots: the hour rolled up from the candidate 15 minute rows, against the
# candidate's hour:
#
#   same                    identical results
#   same_rounding           identical but for averages (data_i) that differ by
#                           less than 1 part in 10^12
#   same_but_status         identical but for status values (data_s): the most
#                           frequent of the 15 minute values is not always the
#                           most frequent raw value. The hour will keep taking
#                           its status from the raw datum, so this is expected.
#   same_rounding_status    both of the above
#   DIFFERENT               anything else: needs looking at
#
# It also counts, for information, how many of the candidate 15 minute rows
# differ in clock accumulation from today's 15 minute query,
# rollup_datm_for_time_span_slots(). Differences there are expected for streams
# with gaps of more than 15 minutes between datum.
#
# And it counts the hours that have a "partial" 15 minute row: one with no value
# for an accumulating property that another 15 minute row of the same hour has
# a value for (rows_15m_partial_a in compare.psv, partial_a_hours in run.txt).
# In those hours the roll-up has to pass over a row to find the hour's first or
# last reading, so they are the ones that show that case is handled. A run with
# none of them says nothing about it either way.
#
# The exit status is 1 if any comparison is DIFFERENT or failed, else 0.
#
# Needs psql 12 or later. Written for POSIX sh; also runs under zsh and bash.

set -u
umask 077

# zsh gives a function's name as $0 inside it, so keep the script's name here
SCRIPT=$0
SCRIPT_VERSION=6
HOURS=2
SAMPLE=30
STREAMS=2
STMT_TIMEOUT=300
DO_EXPLAIN=1
OUTBASE=.
TARGETS_FILE=
PSQL=${PSQL:-psql}

# md5 of the function bodies this script was written against: the live hourly
# rollup with NET-543, which step 1 is built on, and the one before it; then the
# two _net540 functions, the first of which has the body of step 1's
# rollup_datm_15m_for_hour()
LIVE_MD5=6291c0c4841851ea80a61f6cc750c39f
LIVE_PRE_NET543_MD5=a183fe90ed6b25b4c804276f57681606
SLOTS_MD5=d72a3b26891dec3956372b78bd253a85
AGG_MD5=351afaa6e893ff4b3a1e02c0405835ff

usage() {
	sed -n '2,/^# Needs psql/p' "$SCRIPT" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

die() {
	printf 'net540-verify: %s\n' "$*" >&2
	exit 1
}

is_number() {
	case $1 in
		'' | *[!0-9]*) return 1 ;;
	esac
	return 0
}

while getopts 'h:p:U:d:o:H:m:k:t:xT:' opt; do
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
		T) TARGETS_FILE=$OPTARG ;;
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
[ -z "$TARGETS_FILE" ] || [ -r "$TARGETS_FILE" ] || die "cannot read $TARGETS_FILE"

command -v "$PSQL" >/dev/null 2>&1 || die "psql not found (set PSQL=/path/to/psql)"
PSQL_MAJOR=$("$PSQL" -V | sed -n 's/^[^0-9]*\([0-9][0-9]*\).*/\1/p')
is_number "${PSQL_MAJOR:-}" || die "cannot tell the version of $PSQL"
[ "$PSQL_MAJOR" -ge 12 ] || die "psql 12 or later is needed (found $PSQL_MAJOR)"

PGAPPNAME=net540-verify
PGCONNECT_TIMEOUT=${PGCONNECT_TIMEOUT:-15}
export PGAPPNAME PGCONNECT_TIMEOUT

[ -d "$OUTBASE" ] || die "output directory $OUTBASE does not exist"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
NAME=net540-$STAMP
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
SET application_name = 'net540-verify';
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

\echo == functions
SELECT p.oid::regprocedure AS func, l.lanname AS lang, p.proisstrict AS strict
	, p.provolatile AS vol, md5(p.prosrc) AS src_md5, length(p.prosrc) AS src_len
FROM pg_proc p
INNER JOIN pg_namespace n ON n.oid = p.pronamespace
INNER JOIN pg_language l ON l.oid = p.prolang
WHERE n.nspname = 'solardatm'
	AND p.proname IN ('rollup_datm_for_time_span', 'rollup_datm_15m_for_hour'
		, 'rollup_datm_15m_for_hour_net540', 'rollup_agg_data_15m_net540'
		, 'rollup_agg_data_for_time_span', 'rollup_datm_for_time_span_slots'
		, 'find_datm_for_time_slot', 'find_time_before_ts', 'find_time_after_ts'
		, 'find_datm_between', 'datm_has_accumulating_at', 'find_datm_aux_for_time_span')
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
#
# Every subquery on a hypertable is LATERAL with an aggregate, a window function
# or a LIMIT, so that it runs once for each stream through the primary key and
# cannot be turned into a join over a scan of a whole chunk.
cat >"$OUT/sql/targets.sql" <<'SQL'
WITH hrs AS (
	SELECT :'t0'::timestamptz - make_interval(hours => g.h) AS t0
	FROM generate_series(0, :hours - 1) AS g(h)
)
-- node streams with datum in the latest complete hour, and how many
, act AS MATERIALIZED (
	SELECT m.stream_id, n.cnt
		, COALESCE(cardinality(m.names_a), 0) AS n_a
		, COALESCE(cardinality(m.names_s), 0) AS n_s
	FROM solardatm.da_datm_meta m
	CROSS JOIN LATERAL (
		SELECT count(*) AS cnt
		FROM solardatm.da_datm d
		WHERE d.stream_id = m.stream_id
			AND d.ts >= :'t0'::timestamptz
			AND d.ts < :'t1'::timestamptz
	) n
	WHERE n.cnt > 0
)
, cadence AS MATERIALIZED (
	SELECT x.class, x.stream_id
	FROM (
		SELECT c.class, a.stream_id
			, row_number() OVER (PARTITION BY c.class ORDER BY md5(a.stream_id::text || :'t0')) AS rn
		FROM act a
		CROSS JOIN LATERAL (
			SELECT CASE WHEN a.cnt > 4 THEN 'dense' WHEN a.cnt > 1 THEN 'mid' ELSE 'sparse' END AS class
		) c
	) x
	WHERE x.rn <= :sample
)
, status AS MATERIALIZED (
	SELECT a.stream_id
	FROM act a
	WHERE a.n_s > 0
	ORDER BY md5(a.stream_id::text || 's' || :'t0')
	LIMIT :sample
)
, multi AS MATERIALIZED (
	SELECT a.stream_id
	FROM act a
	WHERE a.n_a > 1
	ORDER BY md5(a.stream_id::text || 'a' || :'t0')
	LIMIT :sample
)
, mixed AS MATERIALIZED (
	SELECT a.stream_id
	FROM (SELECT * FROM act WHERE n_a > 1) a
	CROSS JOIN LATERAL (
		SELECT bool_or(x.present > 0 AND x.missing > 0) AS mixed
		FROM (
			SELECT count(*) FILTER (WHERE d.data_a[i.idx] IS NOT NULL) AS present
				, count(*) FILTER (WHERE d.data_a[i.idx] IS NULL) AS missing
			FROM solardatm.da_datm d
			CROSS JOIN generate_series(1, a.n_a) AS i(idx)
			WHERE d.stream_id = a.stream_id
				AND d.ts >= :'t0'::timestamptz - make_interval(hours => :hours - 1)
				AND d.ts < :'t1'::timestamptz
				AND d.data_a IS NOT NULL
			GROUP BY date_trunc('hour', d.ts), i.idx
		) x
	) m
	WHERE m.mixed
	ORDER BY md5(a.stream_id::text || 'm' || :'t0')
	LIMIT :sample
)
, loc AS MATERIALIZED (
	SELECT m.stream_id
	FROM solardatm.da_loc_datm_meta m
	CROSS JOIN LATERAL (
		SELECT 1
		FROM solardatm.da_datm d
		WHERE d.stream_id = m.stream_id
			AND d.ts >= :'t0'::timestamptz
			AND d.ts < :'t1'::timestamptz
		LIMIT 1
	) l
	ORDER BY md5(m.stream_id::text || :'t0')
	LIMIT :sample
)
-- a day with datum in the last 7 days, where the day with datum before it (looking back 30
-- days) is more than 2 days earlier or there is none; then the first datum of that day
, gap_days AS MATERIALIZED (
	SELECT m.stream_id, a.ts_start
	FROM solardatm.da_datm_meta m
	CROSS JOIN LATERAL (
		SELECT a.ts_start, lag(a.ts_start) OVER (ORDER BY a.ts_start) AS prev_start
		FROM solardatm.aud_datm_daily a
		WHERE a.stream_id = m.stream_id
			AND a.ts_start >= :'t0'::timestamptz - INTERVAL 'P30D'
			AND a.ts_start < :'t0'::timestamptz
			AND a.datum_count > 0
	) a
	WHERE a.ts_start >= :'t0'::timestamptz - INTERVAL 'P7D'
		AND (a.prev_start IS NULL OR a.ts_start - a.prev_start > INTERVAL 'P2D')
	ORDER BY a.ts_start DESC, m.stream_id
	LIMIT :sample
)
, after_gap AS MATERIALIZED (
	SELECT g.stream_id, date_trunc('hour', f.ts) AS t0
	FROM gap_days g
	CROSS JOIN LATERAL (
		SELECT d.ts
		FROM solardatm.da_datm d
		WHERE d.stream_id = g.stream_id
			AND d.ts >= g.ts_start
			AND d.ts < g.ts_start + INTERVAL 'P2D'
		ORDER BY d.ts
		LIMIT 1
	) f
	WHERE f.ts < :'t0'::timestamptz
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
-- two reset records at most 1 hour apart; "bare" when no datum lies between them (the test is
-- in the select list so that it stays a probe for each pair)
, pair_all AS MATERIALIZED (
	SELECT r.stream_id, r.ts, r.nxt
		, NOT EXISTS (
			SELECT 1 FROM solardatm.da_datm d
			WHERE d.stream_id = r.stream_id AND d.ts > r.ts AND d.ts < r.nxt
		) AS bare
	FROM (
		SELECT aux.stream_id, aux.ts
			, lead(aux.ts) OVER (PARTITION BY aux.stream_id ORDER BY aux.ts) AS nxt
		FROM solardatm.da_datm_aux aux
		WHERE aux.atype = 'Reset'::solardatm.da_datm_aux_type
	) r
	WHERE r.nxt IS NOT NULL AND r.nxt - r.ts <= INTERVAL 'PT1H' AND r.nxt < :'t0'::timestamptz
)
, pairs AS MATERIALIZED (
	SELECT p.stream_id, p.ts, p.nxt
	FROM pair_all p
	WHERE p.bare
	ORDER BY p.ts DESC, p.stream_id
	LIMIT :sample
)
-- hours of the last day in which, for some accumulating property, one 15 minute slot has a
-- datum with a value and another slot has datum but none with a value; the latest two for
-- each stream. Only streams with at most 300 datum a day are read (the test is inside the
-- subquery so that the datum of denser streams are never touched).
, partial_hours AS MATERIALIZED (
	SELECT m.stream_id, p.hr
	FROM solardatm.da_datm_meta m
	CROSS JOIN LATERAL (
		SELECT max(a.datum_count) AS per_day
		FROM solardatm.aud_datm_daily a
		WHERE a.stream_id = m.stream_id
			AND a.ts_start >= :'t0'::timestamptz - INTERVAL 'P2D'
			AND a.ts_start < :'t0'::timestamptz
	) c
	CROSS JOIN LATERAL (
		SELECT y.hr
		FROM (
			SELECT x.hr, x.idx
				, count(*) FILTER (WHERE x.present > 0) AS slots_with
				, count(*) FILTER (WHERE x.present = 0) AS slots_without
			FROM (
				SELECT date_trunc('hour', d.ts) AS hr
					, time_bucket(INTERVAL 'PT15M', d.ts) AS slot
					, i.idx
					, count(d.data_a[i.idx]) AS present
				FROM solardatm.da_datm d
				CROSS JOIN generate_series(1, cardinality(m.names_a)) AS i(idx)
				WHERE c.per_day BETWEEN 1 AND 300
					AND d.stream_id = m.stream_id
					AND d.ts >= :'t0'::timestamptz - INTERVAL 'P1D'
					AND d.ts < :'t0'::timestamptz
					AND d.data_a IS NOT NULL
				GROUP BY 1, 2, 3
			) x
			GROUP BY x.hr, x.idx
		) y
		WHERE y.slots_with > 0 AND y.slots_without > 0
		GROUP BY y.hr
		ORDER BY y.hr DESC
		LIMIT 2
	) p
	WHERE cardinality(m.names_a) > 1
)
, partial AS MATERIALIZED (
	SELECT x.stream_id, x.hr
	FROM (
		SELECT p.stream_id, p.hr
			, dense_rank() OVER (ORDER BY md5(p.stream_id::text || 'p' || :'t0'), p.stream_id) AS rn
		FROM partial_hours p
	) x
	WHERE x.rn <= :sample
)
SELECT x.class, x.stream_id, x.t0, x.t0 + INTERVAL 'PT1H' AS t1
FROM (
	SELECT c.class, c.stream_id, h.t0 FROM cadence c CROSS JOIN hrs h
	UNION ALL
	SELECT 'status', s.stream_id, h.t0 FROM status s CROSS JOIN hrs h
	UNION ALL
	SELECT 'multi_a', s.stream_id, h.t0 FROM multi s CROSS JOIN hrs h
	UNION ALL
	SELECT 'mixed_a', s.stream_id, h.t0 FROM mixed s CROSS JOIN hrs h
	UNION ALL
	SELECT 'location', s.stream_id, h.t0 FROM loc s CROSS JOIN hrs h
	UNION ALL
	SELECT 'partial_a', s.stream_id, s.hr FROM partial s
	UNION ALL
	SELECT 'after_gap', g.stream_id, g.t0 + make_interval(hours => o.h)
	FROM after_gap g CROSS JOIN (VALUES (-1), (0)) AS o(h)
	UNION ALL
	SELECT 'reset', r.stream_id, r.t0 + make_interval(hours => o.h)
	FROM resets r CROSS JOIN (VALUES (-1), (0), (1)) AS o(h)
	UNION ALL
	SELECT DISTINCT 'reset_pair', p.stream_id, u.t0
	FROM pairs p
	CROSS JOIN LATERAL (
		VALUES (date_trunc('hour', p.ts) - INTERVAL 'PT1H')
			, (date_trunc('hour', p.ts))
			, (date_trunc('hour', p.nxt))
			, (date_trunc('hour', p.nxt) + INTERVAL 'PT1H')
	) AS u(t0)
) x
ORDER BY x.class, x.stream_id, x.t0;
SQL

# One row per stream and hour: $1 class, $2 stream, $3 slot start, $4 slot end.
#   l  the live hourly rollup
#   c  the candidate: the hour, and its 15 minute rows in an array
#   f  the candidate's hour
#   s  the candidate's 15 minute rows
#   r  the hour rolled up from the candidate's 15 minute rows
#   q  today's 15 minute query, for information
# :allow_fix is true only while the live hourly rollup predates NET-543.
cat >"$OUT/sql/compare-prepare.sql" <<'SQL'
PREPARE cmp(text, uuid, timestamptz, timestamptz) AS
WITH l AS MATERIALIZED (
	SELECT * FROM solardatm.rollup_datm_for_time_span($2, $3, $4)
)
, c AS MATERIALIZED (
	SELECT * FROM solardatm.rollup_datm_15m_for_hour_net540($2, $3, $4)
)
, f AS MATERIALIZED (
	SELECT c.stream_id, c.ts_start, c.data_i, c.data_a, c.data_s, c.data_t, c.stat_i, c.read_a
	FROM c
)
, s AS MATERIALIZED (
	SELECT u.* FROM c INNER JOIN LATERAL unnest(c.slots) AS u ON TRUE
)
, r AS MATERIALIZED (
	SELECT * FROM solardatm.rollup_agg_data_15m_net540($2, $3, $4)
)
, q AS MATERIALIZED (
	SELECT * FROM solardatm.rollup_datm_for_time_span_slots($2, $3, $4, 900)
)
, n AS (
	SELECT (SELECT count(*) FROM l) AS n_l
		, (SELECT count(*) FROM f) AS n_f
		, (SELECT count(*) FROM s) AS n_s
		, (SELECT count(*) FROM r) AS n_r
		, (SELECT count(*) FROM q) AS n_q
)
-- live against the candidate's hour, as text, so that a difference in scale counts
, lt AS (
	SELECT NOT EXISTS (SELECT l::text FROM l EXCEPT SELECT f::text FROM f)
		AND NOT EXISTS (SELECT f::text FROM f EXCEPT SELECT l::text FROM l) AS same
)
-- live against the candidate's hour: is data_a the only thing that differs?
, lf AS (
	SELECT bool_and(l.ts_start IS NOT DISTINCT FROM f.ts_start
			AND l.data_i IS NOT DISTINCT FROM f.data_i
			AND l.data_s IS NOT DISTINCT FROM f.data_s
			AND l.data_t IS NOT DISTINCT FROM f.data_t
			AND l.stat_i IS NOT DISTINCT FROM f.stat_i
			AND l.read_a IS NOT DISTINCT FROM f.read_a) AS rest_same
	FROM l, f
)
-- reset records at or after the end of the hour and within the hour after it: with two or
-- more, a live rollup that predates NET-543 counts the difference between them in this hour
-- as well as in theirs
, rp AS (
	SELECT count(*) AS n
	FROM solardatm.da_datm_aux aux
	WHERE aux.stream_id = $2
		AND aux.atype = 'Reset'::solardatm.da_datm_aux_type
		AND aux.ts >= $4
		AND aux.ts <= $4 + INTERVAL 'PT1H'
)
-- the candidate's hour against the hour rolled up from its 15 minute rows
, fr AS (
	SELECT bool_and(f.ts_start IS NOT DISTINCT FROM r.ts_start
			AND f.data_a IS NOT DISTINCT FROM r.data_a
			AND f.read_a IS NOT DISTINCT FROM r.read_a
			AND f.stat_i IS NOT DISTINCT FROM r.stat_i
			AND f.data_t IS NOT DISTINCT FROM r.data_t
			AND (f.data_i IS NULL) = (r.data_i IS NULL)
			AND COALESCE(cardinality(f.data_i), 0) = COALESCE(cardinality(r.data_i), 0)) AS exact_same
		, bool_and(f.data_i IS NOT DISTINCT FROM r.data_i) AS i_same
		, bool_and(f.data_s IS NOT DISTINCT FROM r.data_s) AS s_same
	FROM f, r
)
-- the largest relative difference between the averages
, di AS (
	SELECT max(abs(x.a - x.b) / NULLIF(GREATEST(abs(x.a), abs(x.b)), 0)) AS rel
		, COALESCE(bool_or((x.a IS NULL) <> (x.b IS NULL)), FALSE) AS null_mismatch
	FROM f, r, unnest(f.data_i, r.data_i) AS x(a, b)
)
-- candidate 15 minute rows against today's 15 minute query, on clock accumulation
, sq AS (
	SELECT count(*) FILTER (WHERE s.ts_start IS NULL OR q.ts_start IS NULL OR EXISTS (
			SELECT 1 FROM unnest(s.data_a, q.data_a) AS x(a, b)
			WHERE abs(COALESCE(x.a, 0) - COALESCE(x.b, 0)) > 1e-9
		)) AS differ
	FROM s
	FULL OUTER JOIN q ON q.ts_start = s.ts_start
)
-- candidate 15 minute rows with no value for an accumulating property that another row of the
-- hour has a value for
, sn AS (
	SELECT count(DISTINCT a.ts_start) AS n
	FROM s a
	CROSS JOIN generate_subscripts(a.data_a, 1) AS i(idx)
	WHERE a.data_a[i.idx] IS NULL
		AND EXISTS (SELECT 1 FROM s b WHERE b.data_a[i.idx] IS NOT NULL)
)
SELECT $1 AS class, $2 AS stream_id, $3 AS slot_start
	, CASE
		WHEN n.n_l = n.n_f AND lt.same THEN 'same'
		WHEN :allow_fix AND rp.n >= 2 AND n.n_l = 1 AND n.n_f = 1 AND lf.rest_same
			THEN 'expected_fix'
		ELSE 'DIFFERENT'
		END AS hour_verdict
	, CASE
		WHEN n.n_f = 0 AND n.n_r = 0 AND n.n_s = 0 THEN 'same'
		WHEN n.n_f <> 1 OR n.n_r <> 1 THEN 'DIFFERENT'
		WHEN NOT COALESCE(fr.exact_same, FALSE) THEN 'DIFFERENT'
		WHEN NOT fr.i_same AND (di.null_mismatch OR COALESCE(di.rel, 1) > 1e-12) THEN 'DIFFERENT'
		WHEN fr.i_same AND fr.s_same THEN 'same'
		WHEN fr.i_same THEN 'same_but_status'
		WHEN fr.s_same THEN 'same_rounding'
		ELSE 'same_rounding_status'
		END AS slots_verdict
	, n.n_l AS hour_rows_live, n.n_f AS hour_rows_candidate, n.n_r AS hour_rows_from_15m
	, n.n_s AS rows_15m, n.n_q AS rows_15m_query, sq.differ AS rows_15m_differ_from_query
	, di.rel::float8 AS data_i_rel_diff
	, (SELECT l.data_a::text FROM l LIMIT 1) AS data_a_live
	, (SELECT f.data_a::text FROM f LIMIT 1) AS data_a_candidate
	, (SELECT r.data_a::text FROM r LIMIT 1) AS data_a_from_15m
	, (SELECT f.read_a::text FROM f LIMIT 1) AS read_a_candidate
	, (SELECT r.read_a::text FROM r LIMIT 1) AS read_a_from_15m
	, (SELECT f.data_s::text FROM f LIMIT 1) AS data_s_candidate
	, (SELECT r.data_s::text FROM r LIMIT 1) AS data_s_from_15m
	, sn.n AS rows_15m_partial_a
FROM n, lt, lf, rp, fr, di, sq, sn;
SQL

COMPARE_HEADER='class|stream_id|slot_start|hour_verdict|slots_verdict|hour_rows_live|hour_rows_candidate|hour_rows_from_15m|rows_15m|rows_15m_query|rows_15m_differ_from_query|data_i_rel_diff|data_a_live|data_a_candidate|data_a_from_15m|read_a_candidate|read_a_from_15m|data_s_candidate|data_s_from_15m|rows_15m_partial_a'

# What each function costs, with literal arguments as production's
# EXECUTE ... USING gives them. The candidate runs first, so it gets no help from
# pages the live function has just read, and again at the end. The last plan
# includes a run of the candidate, whose rows it rolls up.
cat >"$OUT/sql/explain.sql" <<'SQL'
\echo ### stream :sid class :cls slot :t0 to :t1
\echo
\echo ### plan 1 candidate hour and 15m, first
EXPLAIN (ANALYZE, BUFFERS, SETTINGS)
SELECT count(*) FROM solardatm.rollup_datm_15m_for_hour_net540(
	:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz);
\echo
\echo ### plan 2 live hourly
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM solardatm.rollup_datm_for_time_span(
	:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz);
\echo
\echo ### plan 3 candidate hour and 15m, again
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM solardatm.rollup_datm_15m_for_hour_net540(
	:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz);
\echo
\echo ### plan 4 hour from candidate 15m
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM solardatm.rollup_agg_data_15m_net540(
	:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz);
SQL

# -----------------------------------------------------------------------------
# Connect, and check the _net540 functions are there.
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
	  (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('solardatm.rollup_datm_for_time_span(uuid,timestamptz,timestamptz,interval,interval)'))
	, (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('solardatm.rollup_datm_15m_for_hour_net540(uuid,timestamptz,timestamptz,interval,interval)'))
	, (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('solardatm.rollup_agg_data_15m_net540(uuid,timestamptz,timestamptz)'))
	, (SELECT 'slots' = ANY (proargnames) FROM pg_proc WHERE oid = to_regprocedure('solardatm.rollup_datm_15m_for_hour_net540(uuid,timestamptz,timestamptz,interval,interval)'))")
IFS='|' read -r HAVE_LIVE_MD5 HAVE_SLOTS_MD5 HAVE_AGG_MD5 HAVE_SLOTS_COL <<EOF
$FUNCS
EOF
if [ -z "$HAVE_SLOTS_MD5" ] || [ -z "$HAVE_AGG_MD5" ]; then
	rm -r "$OUT"
	die "the _net540 functions are not installed; apply net540-candidate-copy.sql first"
fi
if [ "$HAVE_SLOTS_COL" != t ]; then
	rm -r "$OUT"
	die "the _net540 functions are those of an older net540-candidate-copy.sql; apply the current one"
fi
# the hour must equal the live rollup's, which is meaningful only for a version known here
case $HAVE_LIVE_MD5 in
	"$LIVE_MD5") ALLOW_FIX=false ;;
	"$LIVE_PRE_NET543_MD5") ALLOW_FIX=true ;;
	*)
		rm -r "$OUT"
		die "the live hourly rollup has md5 '$HAVE_LIVE_MD5', which is neither the NET-543 version ($LIVE_MD5) nor the one before it ($LIVE_PRE_NET543_MD5); regenerate net540-candidate-copy.sql and this script"
		;;
esac

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
	printf 'targets_file=%s\n' "$TARGETS_FILE"
	printf 'live_md5=%s\nlive_predates_net543=%s\nslots_net540_md5=%s\nagg_net540_md5=%s\n' \
		"$HAVE_LIVE_MD5" "$ALLOW_FIX" "$HAVE_SLOTS_MD5" "$HAVE_AGG_MD5"
} >"$OUT/run.txt"

note "Connected as $DB_USER; latest slot $T0 to $T1"
[ "$IN_RECOVERY" != t ] || note "NOTE: this server is a replica, not the primary"
if [ "$HAVE_SLOTS_MD5" != "$SLOTS_MD5" ] || [ "$HAVE_AGG_MD5" != "$AGG_MD5" ]; then
	note "NOTE: the _net540 functions are not the versions this script was written"
	note "      against (md5 $HAVE_SLOTS_MD5, $HAVE_AGG_MD5)"
fi
if [ "$ALLOW_FIX" = true ]; then
	note "NOTE: the live hourly rollup predates NET-543, so an hour followed by two"
	note "      reset records can differ from the candidate's, as expected_fix"
fi

# -----------------------------------------------------------------------------
# Compare.
# -----------------------------------------------------------------------------

note "Context"
run text context "$OUT/context.txt" -v t0="$T0"

if [ -n "$TARGETS_FILE" ]; then
	note "Using the streams and hours in $TARGETS_FILE"
	awk -F'|' 'NF == 4 && length($2) == 36' "$TARGETS_FILE" >"$OUT/targets.psv"
else
	note "Choosing streams"
	run rows targets "$OUT/targets.psv" -v t0="$T0" -v t1="$T1" -v hours="$HOURS" -v sample="$SAMPLE"
fi
TARGET_COUNT=$(($(wc -l <"$OUT/targets.psv")))
[ "$TARGET_COUNT" -gt 0 ] || { finish; die "no streams found to compare, see $OUT/verify.log"; }
awk -F'|' '{ n[$1]++; if (!(($1, $2) in s)) { s[$1, $2] = 1; st[$1]++ } }
	END { for (k in n) printf "%s: %d streams, %d comparisons\n", k, st[k], n[k] }' \
	"$OUT/targets.psv" | sort | while IFS= read -r line; do note "  $line"; done

printf '%s\n' "$COMPARE_HEADER" >"$OUT/compare.psv"
: >"$OUT/compare-errors.txt"
# the kinds are listed here, not in a variable, because zsh would not split one
for cls in dense mid sparse status multi_a mixed_a partial_a location after_gap reset reset_pair; do
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
		-v allow_fix="$ALLOW_FIX" \
		-f "$OUT/sql/session.sql" -f "$OUT/sql/compare-prepare.sql" -f "$OUT/sql/compare-$cls.sql" \
		>>"$OUT/compare.psv" 2>>"$OUT/compare-errors.txt" </dev/null
done

COMPARED=$(($(wc -l <"$OUT/compare.psv") - 1))
MISSING=$((TARGET_COUNT - COMPARED))
DIFFERENT=$(awk -F'|' 'NR > 1 && ($4 == "DIFFERENT" || $5 == "DIFFERENT") { n++ } END { print n + 0 }' "$OUT/compare.psv")

# class by verdict, for the hour and for the 15 minute rows
{
	printf 'class|comparison|verdict|comparisons|streams\n'
	awk -F'|' '
		NR > 1 {
			for (i = 4; i <= 5; i++) {
				k = $1 "|" (i == 4 ? "hour" : "slots") "|" $i
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

# how the candidate 15 minute rows compare with today's 15 minute query
{
	printf 'class|comparisons|rows_15m|rows_15m_query|rows_15m_differ_from_query|partial_a_hours\n'
	awk -F'|' '
		NR > 1 { c[$1]++; a[$1] += $9; b[$1] += $10; d[$1] += $11; if ($20 + 0 > 0) e[$1]++ }
		END { for (k in c) print k "|" c[k] "|" a[k] + 0 "|" b[k] + 0 "|" d[k] + 0 "|" e[k] + 0 }
	' "$OUT/compare.psv" | sort
} >"$OUT/query-summary.psv"
PARTIAL=$(awk -F'|' 'NR > 1 && $20 + 0 > 0 { n++ } END { print n + 0 }' "$OUT/compare.psv")

if [ "$DO_EXPLAIN" -eq 1 ] && [ "$STREAMS" -ge 1 ]; then
	# the first STREAMS streams of each kind, at their first hour compared
	awk -F'|' -v k="$STREAMS" '!(($1, $2) in seen) && n[$1] < k { seen[$1, $2] = 1; n[$1]++; print }' \
		"$OUT/targets.psv" >"$OUT/explain/targets.psv"
	seq_no=0
	# a list of the files written, because a glob that matches nothing stops zsh
	: >"$OUT/explain/files.txt"
	while IFS='|' read -r cls sid t0 t1; do
		[ -n "$sid" ] || continue
		seq_no=$((seq_no + 1))
		note "Explain $seq_no: $cls $sid"
		_f=$(printf '%s/explain/%02d-%s-%s.txt' "$OUT" "$seq_no" "$cls" "$sid")
		printf '%s\n' "$_f" >>"$OUT/explain/files.txt"
		"$PSQL" -X -q -w -A -t -v ON_ERROR_STOP=0 -v stmt_timeout="${STMT_TIMEOUT}s" \
			-v sid="$sid" -v cls="$cls" -v t0="$t0" -v t1="$t1" \
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
		printf 'plan|streams|avg_buffers_hit|avg_buffers_read|avg_planning_ms|avg_execution_ms\n'
		awk -F'|' '
			NR > 1 { n[$2]++; h[$2] += $3; r[$2] += $4; p[$2] += $5; e[$2] += $6 }
			END { for (k in n) printf "%s|%d|%.0f|%.0f|%.3f|%.3f\n", k, n[k], h[k] / n[k], r[k] / n[k], p[k] / n[k], e[k] / n[k] }
		' "$OUT/explain-summary.psv" | sort
	} >"$OUT/explain-averages.psv"
else
	note "Skipping EXPLAIN"
fi

trap - INT TERM
{
	printf 'targets=%s\ncompared=%s\nmissing=%s\ndifferent=%s\npartial_a_hours=%s\n' \
		"$TARGET_COUNT" "$COMPARED" "$MISSING" "$DIFFERENT" "$PARTIAL"
} >>"$OUT/run.txt"
finish

note "Results by kind of stream (comparisons, streams):"
awk -F'|' 'NR > 1 { printf "  %-11s %-6s %-21s %5d %5d\n", $1, $2, $3, $4, $5 }' "$OUT/compare-summary.psv" \
	| while IFS= read -r line; do note "$line"; done

if [ -f "$OUT/explain-averages.psv" ]; then
	note "Average cost of each function (buffers hit, read; planning ms, execution ms):"
	awk -F'|' 'NR > 1 { printf "  %-32s %7d %6d %9.3f %9.3f\n", $1, $3, $4, $5, $6 }' "$OUT/explain-averages.psv" \
		| while IFS= read -r line; do note "$line"; done
fi

note "Hours with a 15 minute row lacking a property the hour has: $PARTIAL of $COMPARED"
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
