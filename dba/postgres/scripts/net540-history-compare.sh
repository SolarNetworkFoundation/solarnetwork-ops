#!/bin/sh
#
# net540-history-compare.sh - measure how far the hourly rows stored for past
# hours differ from what today's rollup computes from the raw datum still
# stored (NET-540 plan section 12.4, decision D18).
#
# It answers three questions, from a sample of streams and days in every year:
#
#  1. Of the stored hours that still have raw datum, what share is identical to
#     today's rollup, and how do the others differ: which columns, in what way,
#     and by how much?
#  2. Do step 1's rollup_datm_15m_for_hour() and the hourly rollup,
#     rollup_datm_for_time_span(), agree on old datum? The hour each returns is
#     compared as text for every hour compared. Any disagreement is reported at
#     the top of summary.txt and makes the exit status 1.
#  3. What does one rollup_datm_15m_for_hour() call cost on old datum that are
#     not in memory: elapsed time, blocks read and hit, read time (when
#     track_io_timing can be set) and 15 minute rows returned, by year.
#
# Run it on the primary. The replica keeps the solarwarm tablespace, where the
# old chunks live, on slow storage, so the cold reads this script makes would
# compete there with production queries; the primary's storage is fast. The
# script changes nothing in the database and installs nothing. Every session it
# opens is set to default_transaction_read_only, with a statement timeout and a
# lock timeout, and each statement is its own short transaction, so no session
# holds back vacuum. It uses no temporary tables, so it would also run on a hot
# standby. Every lookup it makes on a hypertable is for one stream at a time
# through the primary key, and each statement covers one hour, one day, or the
# audit rows of one stream. One session runs at a time, and it pauses after each
# stream-day (-P) to limit its load.
#
# Usage:
#
#   PGSSLCERT=superuser.crt PGSSLKEY=superuser.key sh net540-history-compare.sh \
#       -h db.solarnetwork.net -p 5432 -U postgres -d solarnetwork
#
# Connection options are the same as psql's, and anything libpq reads from the
# environment applies. psql is run with -w, so it never stops to prompt.
#
#   -h HOST  -p PORT  -U USER  -d DBNAME    connection, as for psql
#   -o DIR      where to create the output directory (default: current directory)
#   -n COUNT    node stream-days to sample in each year (default 40)
#   -l COUNT    location stream-days to sample in each year (default 10)
#   -D COUNT    most days to take from one stream in one year (default 5)
#   -k COUNT    sampled node stream-days in each year that are also timed, for
#               question 3 (default 6)
#   -c COUNT    control streams (default 20)
#   -C HOURS    control hours for each control stream (default 12)
#   -B COUNT    stream-days for each psql session (default 20)
#   -P SECONDS  pause after each stream-day (default 0.5)
#   -t SECONDS  statement timeout (default 60)
#   -R HOURS    leave out hours that end less than this many hours ago (default 3)
#   -S SEED     seed for the sample (default net540h); another seed gives other
#               streams and days
#   -b TIME     step 1's boundary, for the control group, when
#               agg_datm_15m_complete_from() no longer returns it
#   -x          do not time the calls (question 3)
#   -X          run even if a rollup function's body is not one the script knows
#   -T FILE     compare the stream-days and control windows in FILE, the
#               targets.psv of an earlier run, instead of sampling new ones
#
# SAMPLING. Node streams come from da_datm_meta, with the time zone of the
# node's location (UTC when there is none), and location streams from
# da_loc_datm_meta. For each stream the script reads aud_datm_monthly through
# its primary key, for the local years with a month whose datum_count and
# datum_hourly_count are both above zero. In each year it takes -n node and -l
# location streams, in md5 order of stream, seed and year, and for each reads
# that year of aud_datm_daily, again through the primary key, for days with both
# counts above zero. It takes one such day of each stream when the year has at
# least -n (or -l) streams, and more of each, up to -D, when it has fewer. Expire
# sets datum_count to zero for the days whose raw datum it deletes, so these are
# the days whose raw datum should still be there; the script checks every hour
# for raw datum all the same.
#
# COMPARING. Every UTC hour that overlaps a sampled local day is compared: 24 in
# most zones, 23 or 25 on a daylight saving change, and one more in a half or
# quarter hour zone. For each hour, one statement reads the stored hourly row,
# calls rollup_datm_15m_for_hour() and rollup_datm_for_time_span(), and counts
# the hour's raw datum, the gaps to the datum either side (looking up to a year
# away), the reset records within an hour of it, any agg_stale_datm row for it,
# stored hourly rows that start inside it, and its stored 15 minute rows. Hours
# with a stale row are left out, and so are hours ending less than -R hours ago;
# both are counted. The raw datum of each sampled day are also counted, to set
# against its audit datum_count.
#
# Question 1 compares the stored row with the hour rollup_datm_15m_for_hour()
# returns, as that is the hour the backfill's 15 minute rows will sum to. The
# two functions' hours are compared separately (question 2). Each hour gets one
# class, the first that applies:
#
#   same                identical as text
#   value               averages, statistics, accumulation or readings differ
#                       in value, or are present on one side only
#   zero_or_nothing     accumulation or readings are zero on one side and absent
#                       on the other (the NET-539 shape), including a stored row
#                       of nothing but zero accumulation, for an hour with raw
#                       datum, where today's rollup returns none
#   read_layout         readings stored as [start, end, diff], the order NET-266
#                       converted them in, or as NULLs, as it converted location
#                       datum
#   status              status or tags differ
#   rounding            averages, accumulation or readings within 1 part in 10^9
#   format              the same values written differently: trailing zeros,
#                       tags in another order, or arrays that today's rollup pads
#                       for properties added to the stream later
#   stored_only         a stored row and no row today, with raw datum in the hour
#   stored_only_no_raw  a stored row for an hour with no raw datum
#   today_only          a row today and none stored, with raw datum in the hour
#   today_only_no_raw   a row today for an hour with no raw datum, none stored
#   neither             no row on either side
#
# The signature records how each column differs, so that hours can be counted
# by the shape of their difference. When both rows exist it lists the columns
# that are not identical (i averages, a accumulation, r readings, si statistics,
# s status, t tags), each with its code:
#
#   fmt    the same values, written differently
#   rnd    within 1 part in 10^9
#   pad    one array is longer, and its extra elements are what today's rollup
#          gives a property absent from the hour (added to any other code: +pad)
#   z0     zero on one side, NULL on the other (a, r)
#   perm   readings stored as [start, end, diff] (r)
#   nul3   readings stored as NULLs (r)
#   nul    a value on one side only
#   dif    values differ; for readings dif: and d, s, e for the difference,
#          start and end, and for statistics dif: and c, m for count, min or max
#
# for example "a:dif r:dif:d" or "i:rnd s:dif". When only one row exists it is S:
# (stored) or T: (today) and what that row holds: i, a, a0 (zero accumulation),
# r, r0 (zero reading differences), s, t.
#
# compare.psv also gives each hour the largest absolute and relative difference
# of its accumulation and of its reading differences, and the largest relative
# difference of its averages, with a missing value taken as zero; relative is
# |stored - today| / max(|stored|, |today|). Units differ from property to
# property, so there are no totals. And it has the evidence for raw datum gone
# rather than a change of rule: no raw datum in the hour; more than an hour (or
# no datum within a year) to the datum before or after; a day whose audit
# datum_count is above its raw datum count; a day after a day whose audit
# datum_count is zero, as expire leaves it.
#
# CONTROL. Hours at or after step 1's boundary, agg_datm_15m_complete_from(),
# were stored by today's functions with their 15 minute rows, so they must come
# out same, with stored 15 minute rows identical to the slots the function
# returns; anything else means the script is wrong. The control group is -c
# streams with an hourly row in the last -C complete hours at or after the
# boundary, all those hours compared, plus any sampled hour at or after it.
# Control hours are kept out of the yearly figures. When the boundary is NULL or
# -infinity (after the backfill) there is no control group unless -b gives it.
#
# COST (question 3). For -k sampled node stream-days in each year, before the
# day is compared, each of its hours is run once, in time order, under
# EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, SUMMARY ON): SELECT * FROM
# rollup_datm_15m_for_hour(stream, start, end). The statement has the hour as
# literals, so it is planned with them, as processing's EXECUTE ... USING is,
# over only the chunks that can match: no prepared statement can turn generic.
# plan_cache_mode is left at auto, so the PL/pgSQL helpers the rollup calls keep
# their cached plans from call to call, as in a long-lived processing session
# (force_custom_plan replans them on every call, which made them cost 8.7 ms
# instead of 0.05 ms in plan section 12.3). Each session first runs a warm-up
# hour, on a stream it does not time, so no timed call carries the session's
# catalog loading. The first timed hour of a day is the first touch of that
# stream's datum there, and is reported apart from the later hours. The time is
# planning plus execution as the server measures it: no network and no result
# rows sent. It does not include writing the 15 minute rows, WAL, or the
# backfill's own bookkeeping. The blocks read are reads from outside shared
# buffers, some of which the operating system's cache may serve; read time,
# where it is measured, tells the two apart.
#
# DURATION AND READS. On a copy of production's aud_datm_daily (16,112 streams,
# with monthly rows and time zones made up from it; 24 years with datum) the
# defaults chose 934 stream-days of 704 streams in about a second, reading about
# 75 MB, mostly aud_datm_monthly's index: 22,416 hours, 3,072 of them timed, in
# 48 sessions.
# Each hour compared runs both rollups, about 45 ms on production going by plan
# section 12.3, so comparing takes about 17 minutes, timing about 2, the 0.5 s
# pauses about 8, and starting the sessions about 2 (each plans its first
# statement for about 2 s, then runs a warm-up): about half an hour. The reads
# are the sampled days' datum and hourly rows and their index pages. Those days
# held about 380,000 datum (median 253 a day; a tenth of them a datum a minute)
# and 15,000 hourly rows, so the reads are at most about 3.5 GB, if every row
# is on a page of its own (as rows are that arrived interleaved with other
# streams'), and far less where a stream's rows share pages: on average at most
# about 250 random reads a second. Before it starts comparing, the script prints
# both estimates again for the sample it has chosen.
#
# OUTPUT, in a new directory net540-history-STAMP under -o, also packed beside
# it as a .tar.gz:
#
#   summary.txt              read this first
#   run.txt                  settings, function checksums, boundary, counts
#   targets.psv              the stream-days and control windows; give to -T
#   hours.psv                every hour, and why any was left out
#   compare.psv              one row for each hour compared
#   details.psv              both rows as text for every hour that is not same
#   timing.psv               one row for each timed call
#   days.psv                 raw datum counted in each sampled day
#   by-year.psv              question 1 by year
#   by-year-class.psv        hours and streams by year, group and class
#   by-year-signature.psv    the same by signature, with evidence counts
#   value-size.psv           value hours by size of difference
#   q2.psv                   question 2 by year
#   q2-different.psv         every hour where the two rollups disagree (only if any)
#   control.psv              the control group
#   control-not-same.psv     every control hour that is not same (only if any)
#   cost-by-year.psv         question 3 by year
#   examples.psv             up to 3 hours for each year, class and signature
#   failed.psv               hours that could not be compared
#   sql/                     every statement run, including classify.sql
#   out/                     what each psql session printed
#
# A statement that fails or times out is recorded and the run carries on; the
# hours it lost are tried once more at the end, without timing. The exit status
# is 1 if the two rollups disagree on any hour, or a control hour is not same or
# its 15 minute rows differ; 3 if there is no such finding but the run is not
# complete (hours or timed calls that failed, or an interruption); 2 if the
# script did not run (bad options, no connection, or a function body it does
# not know, without -X); else 0.
#
# To stop it early, press Ctrl-C: the session running stops at once, and the
# script writes the summary of what it has compared, marked not complete, and
# exits 3. kill (SIGTERM) does the same once the session running has finished.
#
# Needs psql 12 or later. Written for POSIX sh; also runs under zsh and bash.

set -u
umask 077

# zsh gives a function's name as $0 inside it, so keep the script's name here
SCRIPT=$0
SCRIPT_VERSION=1
NODE_PER_YEAR=40
LOC_PER_YEAR=10
MAX_DAYS=5
TIMED_PER_YEAR=6
CTL_STREAMS=20
CTL_HOURS=12
BATCH=20
PAUSE=
STMT_TIMEOUT=60
RECENT=3
SEED=net540h
BOUNDARY_OPT=
DO_TIMING=1
ALLOW_UNKNOWN=0
TARGETS_FILE=
OUTBASE=.
PSQL=${PSQL:-psql}

# md5 of the function bodies this script was written against: the hourly rollup
# with NET-543 and the one before it, and step 1's rollup of an hour and its 15
# minute rows
LIVE_MD5=6291c0c4841851ea80a61f6cc750c39f
LIVE_PRE_NET543_MD5=a183fe90ed6b25b4c804276f57681606
STEP1_MD5=d72a3b26891dec3956372b78bd253a85

# hourly rows by year on production in November 2026 (plan section 3.2), in
# millions, 2017 standing for every year before it too; for scaling question 3
PROD_HOURS='2017=7.7 2018=11.8 2019=15.7 2020=18.1 2021=21.0 2022=21.3 2023=25.6 2024=31.0 2025=34.6 2026=35.7'
PROD_RAW_SHARE=0.96

usage() {
	sed -n '2,/^# Needs psql/p' "$SCRIPT" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

die() {
	printf 'net540-history-compare: %s\n' "$*" >&2
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

while getopts 'h:p:U:d:o:n:l:D:k:c:C:B:P:t:R:S:b:xXT:' opt; do
	case $opt in
		h) PGHOST=$OPTARG; export PGHOST ;;
		p) PGPORT=$OPTARG; export PGPORT ;;
		U) PGUSER=$OPTARG; export PGUSER ;;
		d) PGDATABASE=$OPTARG; export PGDATABASE ;;
		o) OUTBASE=$OPTARG ;;
		n) NODE_PER_YEAR=$OPTARG ;;
		l) LOC_PER_YEAR=$OPTARG ;;
		D) MAX_DAYS=$OPTARG ;;
		k) TIMED_PER_YEAR=$OPTARG ;;
		c) CTL_STREAMS=$OPTARG ;;
		C) CTL_HOURS=$OPTARG ;;
		B) BATCH=$OPTARG ;;
		P) PAUSE=$OPTARG ;;
		t) STMT_TIMEOUT=$OPTARG ;;
		R) RECENT=$OPTARG ;;
		S) SEED=$OPTARG ;;
		b) BOUNDARY_OPT=$OPTARG ;;
		x) DO_TIMING=0 ;;
		X) ALLOW_UNKNOWN=1 ;;
		T) TARGETS_FILE=$OPTARG ;;
		*) usage ;;
	esac
done
shift $((OPTIND - 1))
[ $# -eq 0 ] || usage

for v in "$NODE_PER_YEAR" "$LOC_PER_YEAR" "$MAX_DAYS" "$TIMED_PER_YEAR" "$CTL_STREAMS" \
		"$CTL_HOURS" "$BATCH" "$STMT_TIMEOUT" "$RECENT"; do
	is_number "$v" || die "options -n -l -D -k -c -C -B -t -R take a whole number"
done
[ "$MAX_DAYS" -ge 1 ] || die "-D must be at least 1"
[ "$BATCH" -ge 1 ] || die "-B must be at least 1"
[ "$STMT_TIMEOUT" -ge 1 ] || die "-t must be at least 1"
[ -z "$PAUSE" ] || is_decimal "$PAUSE" || die "-P takes a number of seconds"
case $SEED in
	'' | *[!A-Za-z0-9_.-]*) die "-S takes letters, digits and . _ -" ;;
esac
case $BOUNDARY_OPT in
	*[!0-9:\ +.TZ-]*) die "-b takes a time such as '2026-11-20 03:00:00+00'" ;;
esac
[ -z "$TARGETS_FILE" ] || [ -r "$TARGETS_FILE" ] || die "cannot read $TARGETS_FILE"

command -v "$PSQL" >/dev/null 2>&1 || die "psql not found (set PSQL=/path/to/psql)"
PSQL_MAJOR=$("$PSQL" -V | sed -n 's/^[^0-9]*\([0-9][0-9]*\).*/\1/p')
is_number "${PSQL_MAJOR:-}" || die "cannot tell the version of $PSQL"
[ "$PSQL_MAJOR" -ge 12 ] || die "psql 12 or later is needed (found $PSQL_MAJOR)"

PGAPPNAME=net540-history-compare
PGCONNECT_TIMEOUT=${PGCONNECT_TIMEOUT:-15}
export PGAPPNAME PGCONNECT_TIMEOUT

[ -d "$OUTBASE" ] || die "output directory $OUTBASE does not exist"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
NAME=net540-history-$STAMP
OUT=$OUTBASE/$NAME
mkdir "$OUT" "$OUT/sql" "$OUT/out" || die "cannot create $OUT"
LOG=$OUT/run.log
: >"$LOG"
EXIT_STATUS=0

note() {
	printf '%s %s\n' "$(date -u +%H:%M:%SZ)" "$*" | tee -a "$LOG" >&2
}

# psql_ro ARGS - psql in a session set up by sql/session.sql (read-only, UTC,
# timeouts, pipe-separated rows), then ARGS; never reads standard input
psql_ro() {
	"$PSQL" -X -q -w -v stmt_timeout="${STMT_TIMEOUT}s" -f "$OUT/sql/session.sql" "$@" </dev/null
}

# setting NAME - a value from run.txt
setting() {
	sed -n "s/^$1=//p" "$OUT/run.txt" | sed -n '1p'
}

finish() {
	{
		printf 'finished=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
		printf 'exit_status=%s\n' "$1"
	} >>"$OUT/run.txt"
	if tar -czf "$OUT.tar.gz" -C "$OUTBASE" "$NAME"; then
		note "Wrote $OUT.tar.gz"
	else
		note "WARNING: could not create $OUT.tar.gz; the files are in $OUT"
	fi
}

# -----------------------------------------------------------------------------
# The SQL. Every statement run is kept in the output under sql/.
# -----------------------------------------------------------------------------

# The session: read-only, UTC, short timeouts, plan_cache_mode at its default
# so that the rollup's PL/pgSQL helpers keep their plans as in processing, jit
# off as production has it (the rollups' estimated costs are far above
# jit_above_cost, and with jit on a single rollup_datm_15m_for_hour() call
# compiled 355 functions and took a second in testing), and track_io_timing on
# where this user may set it. psql stops if the session is not read-only.
cat >"$OUT/sql/session.sql" <<'SQL'
SET application_name = 'net540-history-compare';
SET timezone = 'UTC';
SET statement_timeout = :'stmt_timeout';
SET lock_timeout = '5s';
SET default_transaction_read_only = on;
SET plan_cache_mode = auto;
SET jit = off;
\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'
\pset footer off
\pset null ''
SELECT current_setting('default_transaction_read_only') = 'on' AS net540h_ro \gset
\if :net540h_ro
\else
\echo net540-history-compare: the session is not read-only, stopping
\quit
\endif
SELECT current_setting('server_version_num')::integer >= 150000 AS net540h_pg15 \gset
\if :net540h_pg15
SELECT current_setting('is_superuser') = 'on'
	OR has_parameter_privilege('track_io_timing', 'SET') AS net540h_iot \gset
\else
SELECT current_setting('is_superuser') = 'on' AS net540h_iot \gset
\endif
\if :net540h_iot
SET track_io_timing = on;
\endif
SQL

cat >"$OUT/sql/context.sql" <<'SQL'
SELECT 'server_now=' || statement_timestamp();
SELECT 'server_version=' || current_setting('server_version');
SELECT 'timescaledb=' || COALESCE((SELECT extversion FROM pg_extension WHERE extname = 'timescaledb'), 'none');
SELECT 'database=' || current_database();
SELECT 'current_user=' || current_user;
SELECT 'is_superuser=' || current_setting('is_superuser');
SELECT 'in_recovery=' || pg_is_in_recovery();
SELECT 'read_only=' || current_setting('default_transaction_read_only');
SELECT 'track_io_timing=' || current_setting('track_io_timing');
SELECT 'plan_cache_mode=' || current_setting('plan_cache_mode');
SELECT 'plan_cache_mode_default=' || COALESCE((SELECT reset_val FROM pg_settings WHERE name = 'plan_cache_mode'), '');
SELECT 'jit=' || current_setting('jit');
SELECT 'jit_default=' || COALESCE((SELECT reset_val FROM pg_settings WHERE name = 'jit'), '');
SELECT 'work_mem=' || current_setting('work_mem');
SELECT 'shared_buffers=' || current_setting('shared_buffers');
SELECT 'effective_cache_size=' || current_setting('effective_cache_size');
SELECT 'max_parallel_workers_per_gather=' || current_setting('max_parallel_workers_per_gather');
SELECT 'max_standby_streaming_delay=' || current_setting('max_standby_streaming_delay');
SELECT 'statement_timeout=' || current_setting('statement_timeout');
SELECT 'md5_' || p.proname || '=' || string_agg(md5(p.prosrc), ',' ORDER BY p.oid)
FROM pg_proc p
INNER JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'solardatm'
	AND p.proname IN ('rollup_datm_for_time_span', 'rollup_datm_15m_for_hour'
		, 'agg_datm_15m_complete_from', 'process_one_agg_stale_datm'
		, 'find_datm_for_time_slot', 'find_metadata_for_stream')
GROUP BY p.proname
ORDER BY p.proname;
SELECT 'boundary=' || COALESCE(solardatm.agg_datm_15m_complete_from()::text, 'NULL');
SELECT 'streams_unknown_time_zone=' || count(*)
FROM (
	SELECT COALESCE(l.time_zone, 'UTC') AS tz
	FROM solardatm.da_datm_meta m
	LEFT OUTER JOIN solarnet.sn_node n ON n.node_id = m.node_id
	LEFT OUTER JOIN solarnet.sn_loc l ON l.id = n.loc_id
	UNION ALL
	SELECT COALESCE(l.time_zone, 'UTC') AS tz
	FROM solardatm.da_loc_datm_meta m
	LEFT OUTER JOIN solarnet.sn_loc l ON l.id = m.loc_id
) x
WHERE x.tz NOT IN (SELECT z.name FROM pg_timezone_names z);
SQL

# The stream-days to sample: T|tid|S|year|stream|n or l|time zone|day start|
# day end|datum_count|datum_hourly_count|datum_count of the day before|timed.
#
# Each read of an audit hypertable is a LATERAL subquery for one stream, with an
# aggregate or a LIMIT, so it runs once for each stream through the primary key
# and cannot be turned into a join over whole chunks, whatever the planner's
# estimates (a plain LATERAL lookup can be, and was in testing). The monthly rows give
# each stream's years and months; the days are then read only for the months
# chosen, at most 31 rows each.
cat >"$OUT/sql/targets.sql" <<'SQL'
WITH st AS MATERIALIZED (
	SELECT m.stream_id, 'n'::text AS ok, COALESCE(l.time_zone, 'UTC') AS tz
	FROM solardatm.da_datm_meta m
	LEFT OUTER JOIN solarnet.sn_node n ON n.node_id = m.node_id
	LEFT OUTER JOIN solarnet.sn_loc l ON l.id = n.loc_id
	UNION ALL
	SELECT m.stream_id, 'l'::text AS ok, COALESCE(l.time_zone, 'UTC') AS tz
	FROM solardatm.da_loc_datm_meta m
	LEFT OUTER JOIN solarnet.sn_loc l ON l.id = m.loc_id
)
-- each stream's local years with a month that has both raw datum and hourly rows,
-- and those months in md5 order (a stream whose zone the server does not know is
-- left out, and counted in run.txt)
, sy AS MATERIALIZED (
	SELECT st.stream_id, st.ok, st.tz, y.yr, y.months
	FROM st
	CROSS JOIN LATERAL (
		SELECT extract(year FROM a.ts_start AT TIME ZONE st.tz)::integer AS yr
			, array_agg(a.ts_start ORDER BY md5(st.stream_id::text || :'seed' || a.ts_start::text)) AS months
		FROM solardatm.aud_datm_monthly a
		WHERE a.stream_id = st.stream_id
			AND a.datum_count > 0
			AND a.datum_hourly_count > 0
		GROUP BY 1
	) y
	WHERE st.tz IN (SELECT z.name FROM pg_timezone_names z)
)
, ch AS (
	SELECT sy.stream_id, sy.ok, sy.tz, sy.yr, sy.months
		, row_number() OVER (PARTITION BY sy.ok, sy.yr
			ORDER BY md5(sy.stream_id::text || :'seed' || sy.yr::text)) AS rn
		, count(*) OVER (PARTITION BY sy.ok, sy.yr) AS ny
		, CASE sy.ok WHEN 'n' THEN :nper ELSE :lper END AS q
	FROM sy
)
-- -n (or -l) streams of each year, with one day each, or more when the year has
-- fewer streams, up to -D
, pick AS MATERIALIZED (
	SELECT ch.stream_id, ch.ok, ch.tz, ch.yr, ch.months
		, LEAST(:dmax, ceil(ch.q::numeric / GREATEST(LEAST(ch.q, ch.ny), 1)))::integer AS ndays
	FROM ch
	WHERE ch.rn <= ch.q
)
-- the days: from each of the stream's first ndays months, or, when it has fewer,
-- as many from each month as make up ndays
, dd AS MATERIALIZED (
	SELECT pick.stream_id, pick.ok, pick.tz, pick.yr, pick.ndays, d.ts_start AS d0
		, d.datum_count, d.datum_hourly_count
	FROM pick
	CROSS JOIN LATERAL unnest(pick.months[1:pick.ndays]) AS m(m0)
	CROSS JOIN LATERAL (
		SELECT a.ts_start, a.datum_count, a.datum_hourly_count
		FROM solardatm.aud_datm_daily a
		WHERE a.stream_id = pick.stream_id
			AND a.ts_start >= m.m0
			AND a.ts_start < (m.m0 AT TIME ZONE pick.tz + INTERVAL 'P1M') AT TIME ZONE pick.tz
			AND a.ts_start < now() - make_interval(hours => :recent + 1)
			AND a.datum_count > 0
			AND a.datum_hourly_count > 0
		ORDER BY md5(pick.stream_id::text || :'seed' || a.ts_start::text)
		LIMIT ceil(pick.ndays::numeric / LEAST(pick.ndays, cardinality(pick.months)))::integer
	) d
)
, dp AS (
	SELECT dd.*
		, (dd.d0 AT TIME ZONE dd.tz + INTERVAL 'P1D') AT TIME ZONE dd.tz AS d1
		, pv.datum_count AS prev_count
		, row_number() OVER (PARTITION BY dd.stream_id, dd.yr
			ORDER BY md5(dd.stream_id::text || :'seed' || dd.d0::text)) AS srn
	FROM dd
	-- LIMIT 1 keeps this a lookup for each day: without it the planner may make it a
	-- join over the whole table
	LEFT OUTER JOIN LATERAL (
		SELECT a.datum_count
		FROM solardatm.aud_datm_daily a
		WHERE a.stream_id = dd.stream_id
			AND a.ts_start = (dd.d0 AT TIME ZONE dd.tz - INTERVAL 'P1D') AT TIME ZONE dd.tz
		LIMIT 1
	) pv ON TRUE
)
-- the first -k node stream-days of each year are timed
, dk AS (
	SELECT dp.*
		, row_number() OVER (PARTITION BY dp.ok, dp.yr
			ORDER BY md5(dp.stream_id::text || :'seed' || dp.d0::text)) AS trn
	FROM dp
	WHERE dp.srn <= dp.ndays
)
SELECT 'T'
	, 'S' || lpad(row_number() OVER (ORDER BY md5(dk.stream_id::text || :'seed' || dk.d0::text))::text, 5, '0')
	, 'S', dk.yr, dk.stream_id, dk.ok, dk.tz, dk.d0, dk.d1
	, dk.datum_count, dk.datum_hourly_count, dk.prev_count
	, (dk.ok = 'n' AND dk.trn <= :kper)::integer
FROM dk
ORDER BY 2;
SQL

# The control streams: the first -c streams, in md5 order, with an hourly row in
# the window, which is the last -C complete hours at or after the boundary.
cat >"$OUT/sql/control.sql" <<'SQL'
WITH w AS (
	SELECT GREATEST(:'bnd'::timestamptz
			, date_trunc('hour', now() - make_interval(hours => :recent)) - make_interval(hours => :chours)) AS w0
		, date_trunc('hour', now() - make_interval(hours => :recent)) AS w1
)
, so AS MATERIALIZED (
	SELECT x.stream_id, x.ok, md5(x.stream_id::text || :'seed') AS o
	FROM (
		SELECT m.stream_id, 'n'::text AS ok FROM solardatm.da_datm_meta m
		UNION ALL
		SELECT m.stream_id, 'l'::text AS ok FROM solardatm.da_loc_datm_meta m
	) x
	ORDER BY 3
)
-- streams in md5 order, each probed for one hourly row in the window, until -c are found
, s AS MATERIALIZED (
	SELECT so.stream_id, so.ok, so.o, w.w0, w.w1
	FROM w
	CROSS JOIN so
	CROSS JOIN LATERAL (
		SELECT 1
		FROM solardatm.agg_datm_hourly h
		WHERE h.stream_id = so.stream_id
			AND h.ts_start >= w.w0
			AND h.ts_start < w.w1
		LIMIT 1
	) x
	WHERE w.w0 < w.w1
	LIMIT :cn
)
SELECT 'T'
	, 'C' || lpad(row_number() OVER (ORDER BY s.o)::text, 5, '0')
	, 'C', extract(year FROM s.w0)::integer, s.stream_id, s.ok, 'UTC', s.w0, s.w1
	, '', '', '', 0
FROM s
ORDER BY 2;
SQL

# One hour of one stream; psql variables tg, hi, sid, t0, t1 and bnd. The output
# row is C|tid|hour|start|... as described in compare.psv's header.
cat >"$OUT/sql/compare-head.sql" <<'SQL'
WITH s AS MATERIALIZED (
	SELECT h.stream_id, h.ts_start, h.data_i, h.data_a, h.data_s, h.data_t, h.stat_i, h.read_a
	FROM solardatm.agg_datm_hourly h
	WHERE h.stream_id = :'sid'::uuid AND h.ts_start = :'t0'::timestamptz
)
, c AS MATERIALIZED (
	SELECT r.stream_id, r.ts_start, r.data_i, r.data_a, r.data_s, r.data_t, r.stat_i, r.read_a, r.slots
	FROM solardatm.rollup_datm_15m_for_hour(:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz) r
)
, l AS MATERIALIZED (
	SELECT r::text AS txt
	FROM solardatm.rollup_datm_for_time_span(:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz) r
)
, p AS (
	SELECT
		  (SELECT ROW(s.stream_id, s.ts_start, s.data_i, s.data_a, s.data_s, s.data_t, s.stat_i, s.read_a)::solardatm.agg_datm FROM s) AS s
		, (SELECT ROW(c.stream_id, c.ts_start, c.data_i, c.data_a, c.data_s, c.data_t, c.stat_i, c.read_a)::solardatm.agg_datm FROM c) AS t
)
, k AS (
SQL

# The classification, as a fragment to reuse: it reads p(s, t), the stored row
# and today's row as solardatm.agg_datm (NULL when there is none), and gives one
# row of class, signature, zero-carry flags and sizes for each row of p. The
# class here knows nothing of raw datum; compare.sql refines stored_only and
# today_only with the hour's raw datum count.
cat >"$OUT/sql/classify.sql" <<'SQL'
	SELECT
		  CASE
			WHEN NOT e.hs AND NOT e.ht THEN 'neither'
			WHEN NOT e.ht THEN 'stored_only'
			WHEN NOT e.hs THEN 'today_only'
			WHEN (p.s)::text = (p.t)::text THEN 'same'
			WHEN ci.c ~ '^(dif|nul)(\+|:|$)' OR ca.c ~ '^(dif|nul)(\+|:|$)'
				OR cr.c ~ '^(dif|nul)(\+|:|$)' OR csi.c ~ '^(dif|nul)(\+|:|$)' THEN 'value'
			WHEN ca.c LIKE 'z0%' OR cr.c LIKE 'z0%' THEN 'zero_or_nothing'
			WHEN cr.c LIKE 'perm%' OR cr.c LIKE 'nul3%' THEN 'read_layout'
			WHEN cs.c ~ '^(dif|nul)' OR ct.c ~ '^(dif|nul)' THEN 'status'
			WHEN ci.c LIKE 'rnd%' OR ca.c LIKE 'rnd%' OR cr.c LIKE 'rnd%' THEN 'rounding'
			ELSE 'format'
		  END AS cls
		, CASE
			WHEN NOT e.hs AND NOT e.ht THEN '-'
			WHEN NOT (e.hs AND e.ht) THEN CASE WHEN e.hs THEN 'S:' ELSE 'T:' END || COALESCE(NULLIF(concat_ws(','
				, CASE WHEN o.has_i THEN 'i' END
				, CASE WHEN o.a_all0 THEN 'a0' WHEN o.has_a THEN 'a' END
				, CASE WHEN o.r_all0 THEN 'r0' WHEN o.has_r THEN 'r' END
				, CASE WHEN o.has_s THEN 's' END
				, CASE WHEN o.has_t THEN 't' END), ''), 'empty')
			ELSE COALESCE(NULLIF(concat_ws(' '
				, CASE WHEN ci.c <> '=' THEN 'i:' || ci.c END
				, CASE WHEN ca.c <> '=' THEN 'a:' || ca.c END
				, CASE WHEN cr.c <> '=' THEN 'r:' || cr.c END
				, CASE WHEN csi.c <> '=' THEN 'si:' || csi.c END
				, CASE WHEN cs.c <> '=' THEN 's:' || cs.c END
				, CASE WHEN ct.c <> '=' THEN 't:' || ct.c END), ''), '=')
		  END AS sig
		, zs.z AS zs
		, zt.z AS zt
		, ca.a_abs, ca.a_rel, ca.a_n, ca.a_dir
		, cr.r_abs, cr.r_rel
		, ci.i_rel
	FROM p
	CROSS JOIN LATERAL (
		SELECT (p.s).ts_start IS NOT NULL AS hs, (p.t).ts_start IS NOT NULL AS ht
	) e
	-- zero carry: a row with accumulation or readings but no averages, status or tags,
	-- whose accumulation and reading differences are all zero (or NULL)
	CROSS JOIN LATERAL (
		SELECT (p.s).ts_start IS NOT NULL
			AND ((p.s).data_a IS NOT NULL OR (p.s).read_a IS NOT NULL)
			AND NOT EXISTS (SELECT FROM unnest((p.s).data_i) x WHERE x IS NOT NULL)
			AND NOT EXISTS (SELECT FROM unnest((p.s).data_s) x WHERE x IS NOT NULL)
			AND (p.s).data_t IS NULL
			AND NOT EXISTS (SELECT FROM unnest((p.s).data_a) x WHERE x <> 0)
			AND NOT EXISTS (SELECT FROM generate_subscripts((p.s).read_a, 1) g(i) WHERE ((p.s).read_a)[g.i][1] <> 0)
			AS z
	) zs
	CROSS JOIN LATERAL (
		SELECT (p.t).ts_start IS NOT NULL
			AND ((p.t).data_a IS NOT NULL OR (p.t).read_a IS NOT NULL)
			AND NOT EXISTS (SELECT FROM unnest((p.t).data_i) x WHERE x IS NOT NULL)
			AND NOT EXISTS (SELECT FROM unnest((p.t).data_s) x WHERE x IS NOT NULL)
			AND (p.t).data_t IS NULL
			AND NOT EXISTS (SELECT FROM unnest((p.t).data_a) x WHERE x <> 0)
			AND NOT EXISTS (SELECT FROM generate_subscripts((p.t).read_a, 1) g(i) WHERE ((p.t).read_a)[g.i][1] <> 0)
			AS z
	) zt
	-- what the row on one side only holds
	CROSS JOIN LATERAL (
		SELECT
			  EXISTS (SELECT FROM unnest((w.r).data_i) x WHERE x IS NOT NULL) AS has_i
			, (w.r).data_a IS NOT NULL AS has_a
			, (w.r).data_a IS NOT NULL AND NOT EXISTS (SELECT FROM unnest((w.r).data_a) x WHERE x <> 0) AS a_all0
			, (w.r).read_a IS NOT NULL AS has_r
			, (w.r).read_a IS NOT NULL AND NOT EXISTS (
				SELECT FROM generate_subscripts((w.r).read_a, 1) g(i) WHERE ((w.r).read_a)[g.i][1] <> 0) AS r_all0
			, EXISTS (SELECT FROM unnest((w.r).data_s) x WHERE x IS NOT NULL) AS has_s
			, (w.r).data_t IS NOT NULL AS has_t
		FROM (SELECT CASE WHEN e.hs THEN p.s ELSE p.t END AS r) w
	) o
	-- data_i, averages: = fmt rnd nul dif, +pad when the longer array adds only NULLs
	CROSS JOIN LATERAL (
		SELECT
			  CASE
				WHEN NOT (e.hs AND e.ht) THEN NULL
				WHEN (p.s).data_i::text IS NOT DISTINCT FROM (p.t).data_i::text THEN '='
				WHEN (p.s).data_i IS NULL OR (p.t).data_i IS NULL THEN
					CASE WHEN bool_or(COALESCE(g.x, g.y) IS NOT NULL) THEN 'nul' ELSE 'fmt' END
				ELSE COALESCE(NULLIF(concat_ws('+'
					, CASE max(CASE
						WHEN g.ext THEN CASE WHEN COALESCE(g.x, g.y) IS NOT NULL THEN 3 END
						WHEN g.x IS NULL AND g.y IS NULL THEN NULL
						WHEN g.x IS NULL OR g.y IS NULL THEN 3
						WHEN g.x = g.y THEN NULL
						WHEN abs(g.x - g.y) <= 0.000000001 * GREATEST(abs(g.x), abs(g.y)) THEN 1
						ELSE 4 END)
						WHEN 4 THEN 'dif' WHEN 3 THEN 'nul' WHEN 1 THEN 'rnd' END
					, CASE WHEN bool_or(g.ext AND COALESCE(g.x, g.y) IS NULL) THEN 'pad' END), ''), 'fmt')
			  END AS c
			, max(abs(g.x - g.y) / NULLIF(GREATEST(abs(g.x), abs(g.y)), 0)) AS i_rel
		FROM generate_series(1, GREATEST(COALESCE(array_upper((p.s).data_i, 1), 0), COALESCE(array_upper((p.t).data_i, 1), 0))) AS n(i)
		CROSS JOIN LATERAL (
			SELECT ((p.s).data_i)[n.i] AS x, ((p.t).data_i)[n.i] AS y
				, n.i > COALESCE(array_upper((p.s).data_i, 1), 0) OR n.i > COALESCE(array_upper((p.t).data_i, 1), 0) AS ext
		) g
	) ci
	-- data_a, accumulation: = fmt rnd z0 nul dif, +pad when the longer array adds only
	-- zeros; sizes take a missing value as zero
	CROSS JOIN LATERAL (
		SELECT
			  CASE
				WHEN NOT (e.hs AND e.ht) THEN NULL
				WHEN (p.s).data_a::text IS NOT DISTINCT FROM (p.t).data_a::text THEN '='
				WHEN (p.s).data_a IS NULL OR (p.t).data_a IS NULL THEN
					CASE WHEN bool_or(COALESCE(g.x, g.y) <> 0) THEN 'nul' ELSE 'z0' END
				ELSE COALESCE(NULLIF(concat_ws('+'
					, CASE max(CASE
						WHEN g.ext THEN CASE WHEN COALESCE(g.x, g.y) <> 0 THEN 4 END
						WHEN g.x IS NULL AND g.y IS NULL THEN NULL
						WHEN g.x IS NULL OR g.y IS NULL THEN CASE WHEN COALESCE(g.x, g.y) = 0 THEN 3 ELSE 4 END
						WHEN g.x = g.y THEN NULL
						WHEN abs(g.x - g.y) <= 0.000000001 * GREATEST(abs(g.x), abs(g.y)) THEN 2
						ELSE 5 END)
						WHEN 5 THEN 'dif' WHEN 4 THEN 'nul' WHEN 3 THEN 'z0' WHEN 2 THEN 'rnd' END
					, CASE WHEN bool_or(g.ext AND COALESCE(g.x, g.y, 0) = 0) THEN 'pad' END), ''), 'fmt')
			  END AS c
			, max(abs(g.x0 - g.y0)) AS a_abs
			, COALESCE(max(abs(g.x0 - g.y0) / NULLIF(GREATEST(abs(g.x0), abs(g.y0)), 0)), 0) AS a_rel
			, count(*) FILTER (WHERE g.x0 <> g.y0) AS a_n
			, CASE
				WHEN NOT COALESCE(bool_or(g.x0 <> g.y0), FALSE) THEN NULL
				WHEN bool_and(g.y0 >= g.x0) THEN '+'
				WHEN bool_and(g.y0 <= g.x0) THEN '-'
				ELSE '~'
			  END AS a_dir
		FROM generate_series(1, GREATEST(COALESCE(array_upper((p.s).data_a, 1), 0), COALESCE(array_upper((p.t).data_a, 1), 0))) AS n(i)
		CROSS JOIN LATERAL (
			SELECT ((p.s).data_a)[n.i] AS x, ((p.t).data_a)[n.i] AS y
				, COALESCE(((p.s).data_a)[n.i], 0) AS x0, COALESCE(((p.t).data_a)[n.i], 0) AS y0
				, n.i > COALESCE(array_upper((p.s).data_a, 1), 0) OR n.i > COALESCE(array_upper((p.t).data_a, 1), 0) AS ext
		) g
	) ca
	-- read_a, readings [diff, start, end]: = fmt rnd perm nul3 z0 nul dif:[d][s][e], +pad
	-- when the longer array adds only [0, NULL, NULL]
	CROSS JOIN LATERAL (
		SELECT
			  CASE
				WHEN NOT (e.hs AND e.ht) THEN NULL
				WHEN (p.s).read_a::text IS NOT DISTINCT FROM (p.t).read_a::text THEN '='
				WHEN (p.s).read_a IS NULL OR (p.t).read_a IS NULL THEN
					CASE WHEN bool_or(COALESCE(g.x1, g.y1) <> 0) THEN 'nul' ELSE 'z0' END
				ELSE COALESCE(NULLIF(concat_ws('+'
					, CASE max(g.rk)
						WHEN 6 THEN 'dif:' || concat(
							  CASE WHEN bool_or(g.rk = 6 AND g.dd) THEN 'd' END
							, CASE WHEN bool_or(g.rk = 6 AND g.ds) THEN 's' END
							, CASE WHEN bool_or(g.rk = 6 AND g.de) THEN 'e' END)
						WHEN 5 THEN 'nul' WHEN 4 THEN 'nul3' WHEN 3 THEN 'perm' WHEN 2 THEN 'rnd' END
					, CASE WHEN bool_or(g.ext AND g.rk IS NULL) THEN 'pad' END), ''), 'fmt')
			  END AS c
			, max(abs(g.xd - g.yd)) AS r_abs
			, COALESCE(max(abs(g.xd - g.yd) / NULLIF(GREATEST(abs(g.xd), abs(g.yd)), 0)), 0) AS r_rel
		FROM generate_series(1, GREATEST(COALESCE(array_upper((p.s).read_a, 1), 0), COALESCE(array_upper((p.t).read_a, 1), 0))) AS n(i)
		CROSS JOIN LATERAL (
			SELECT ((p.s).read_a)[n.i][1] AS x1, ((p.s).read_a)[n.i][2] AS x2, ((p.s).read_a)[n.i][3] AS x3
				, ((p.t).read_a)[n.i][1] AS y1, ((p.t).read_a)[n.i][2] AS y2, ((p.t).read_a)[n.i][3] AS y3
				, n.i > COALESCE(array_upper((p.s).read_a, 1), 0) OR n.i > COALESCE(array_upper((p.t).read_a, 1), 0) AS ext
		) v
		CROSS JOIN LATERAL (
			SELECT v.ext, v.x1, v.y1
				, v.x1 IS DISTINCT FROM v.y1 AS dd, v.x2 IS DISTINCT FROM v.y2 AS ds, v.x3 IS DISTINCT FROM v.y3 AS de
				, COALESCE(CASE WHEN (v.x1, v.x2, v.x3) IS NOT DISTINCT FROM (v.y2, v.y3, v.y1) THEN v.x3 ELSE v.x1 END, 0) AS xd
				, COALESCE(v.y1, 0) AS yd
				, CASE
					WHEN v.ext THEN CASE
						WHEN COALESCE(v.x1, v.y1, 0) = 0 AND COALESCE(v.x2, v.y2) IS NULL AND COALESCE(v.x3, v.y3) IS NULL THEN NULL
						ELSE 5 END
					WHEN (v.x1, v.x2, v.x3) IS NOT DISTINCT FROM (v.y1, v.y2, v.y3) THEN NULL
					WHEN v.x1 IS NULL AND v.x2 IS NULL AND v.x3 IS NULL THEN 4
					WHEN v.y1 IS NULL AND v.y2 IS NULL AND v.y3 IS NULL THEN 5
					WHEN (v.x1, v.x2, v.x3) IS NOT DISTINCT FROM (v.y2, v.y3, v.y1) THEN 3
					WHEN (v.x1 IS NOT DISTINCT FROM v.y1 OR abs(v.x1 - v.y1) <= 0.000000001 * GREATEST(abs(v.x1), abs(v.y1)))
						AND (v.x2 IS NOT DISTINCT FROM v.y2 OR abs(v.x2 - v.y2) <= 0.000000001 * GREATEST(abs(v.x2), abs(v.y2)))
						AND (v.x3 IS NOT DISTINCT FROM v.y3 OR abs(v.x3 - v.y3) <= 0.000000001 * GREATEST(abs(v.x3), abs(v.y3))) THEN 2
					ELSE 6
				  END AS rk
		) g
	) cr
	-- stat_i, [count, min, max]: = fmt nul dif:[c][m], +pad
	CROSS JOIN LATERAL (
		SELECT
			CASE
				WHEN NOT (e.hs AND e.ht) THEN NULL
				WHEN (p.s).stat_i::text IS NOT DISTINCT FROM (p.t).stat_i::text THEN '='
				WHEN (p.s).stat_i IS NULL OR (p.t).stat_i IS NULL THEN
					CASE WHEN bool_or(COALESCE(v.x1, v.y1, 0) <> 0) THEN 'nul' ELSE 'fmt' END
				ELSE COALESCE(NULLIF(concat_ws('+'
					, CASE
						WHEN bool_or(v.ext AND NOT (COALESCE(v.x1, v.y1, 0) = 0 AND COALESCE(v.x2, v.y2) IS NULL AND COALESCE(v.x3, v.y3) IS NULL))
							OR bool_or(NOT v.ext AND (v.x1, v.x2, v.x3) IS DISTINCT FROM (v.y1, v.y2, v.y3)
								AND ((v.x1 IS NULL AND v.x2 IS NULL AND v.x3 IS NULL) OR (v.y1 IS NULL AND v.y2 IS NULL AND v.y3 IS NULL)))
							THEN 'nul'
						WHEN bool_or(NOT v.ext AND (v.x1, v.x2, v.x3) IS DISTINCT FROM (v.y1, v.y2, v.y3)) THEN 'dif:' || concat(
							  CASE WHEN bool_or(NOT v.ext AND v.x1 IS DISTINCT FROM v.y1) THEN 'c' END
							, CASE WHEN bool_or(NOT v.ext AND (v.x2 IS DISTINCT FROM v.y2 OR v.x3 IS DISTINCT FROM v.y3)) THEN 'm' END)
						END
					, CASE WHEN bool_or(v.ext AND COALESCE(v.x1, v.y1, 0) = 0 AND COALESCE(v.x2, v.y2) IS NULL AND COALESCE(v.x3, v.y3) IS NULL) THEN 'pad' END), ''), 'fmt')
			END AS c
		FROM generate_series(1, GREATEST(COALESCE(array_upper((p.s).stat_i, 1), 0), COALESCE(array_upper((p.t).stat_i, 1), 0))) AS n(i)
		CROSS JOIN LATERAL (
			SELECT ((p.s).stat_i)[n.i][1] AS x1, ((p.s).stat_i)[n.i][2] AS x2, ((p.s).stat_i)[n.i][3] AS x3
				, ((p.t).stat_i)[n.i][1] AS y1, ((p.t).stat_i)[n.i][2] AS y2, ((p.t).stat_i)[n.i][3] AS y3
				, n.i > COALESCE(array_upper((p.s).stat_i, 1), 0) OR n.i > COALESCE(array_upper((p.t).stat_i, 1), 0) AS ext
		) v
	) csi
	-- data_s, status: = fmt nul dif, +pad
	CROSS JOIN LATERAL (
		SELECT
			CASE
				WHEN NOT (e.hs AND e.ht) THEN NULL
				WHEN (p.s).data_s::text IS NOT DISTINCT FROM (p.t).data_s::text THEN '='
				WHEN (p.s).data_s IS NULL OR (p.t).data_s IS NULL THEN
					CASE WHEN bool_or(COALESCE(v.x, v.y) IS NOT NULL) THEN 'nul' ELSE 'fmt' END
				ELSE COALESCE(NULLIF(concat_ws('+'
					, CASE WHEN bool_or(v.x IS DISTINCT FROM v.y AND NOT (v.ext AND COALESCE(v.x, v.y) IS NULL)) THEN 'dif' END
					, CASE WHEN bool_or(v.ext AND COALESCE(v.x, v.y) IS NULL) THEN 'pad' END), ''), 'fmt')
			END AS c
		FROM generate_series(1, GREATEST(COALESCE(array_upper((p.s).data_s, 1), 0), COALESCE(array_upper((p.t).data_s, 1), 0))) AS n(i)
		CROSS JOIN LATERAL (
			SELECT ((p.s).data_s)[n.i] AS x, ((p.t).data_s)[n.i] AS y
				, n.i > COALESCE(array_upper((p.s).data_s, 1), 0) OR n.i > COALESCE(array_upper((p.t).data_s, 1), 0) AS ext
		) v
	) cs
	-- data_t, tags: = fmt (the same set in another order) nul dif
	CROSS JOIN LATERAL (
		SELECT
			CASE
				WHEN NOT (e.hs AND e.ht) THEN NULL
				WHEN (p.s).data_t::text IS NOT DISTINCT FROM (p.t).data_t::text THEN '='
				WHEN (p.s).data_t IS NULL OR (p.t).data_t IS NULL THEN 'nul'
				WHEN ARRAY(SELECT DISTINCT x FROM unnest((p.s).data_t) x ORDER BY 1)
					= ARRAY(SELECT DISTINCT x FROM unnest((p.t).data_t) x ORDER BY 1) THEN 'fmt'
				ELSE 'dif'
			END AS c
	) ct
SQL

cat >"$OUT/sql/compare-tail.sql" <<'SQL'
)
, raw AS (
	SELECT count(*) AS n, count(*) FILTER (WHERE d.data_a IS NOT NULL) AS na
		, min(d.ts) AS ts_first, max(d.ts) AS ts_last
	FROM solardatm.da_datm d
	WHERE d.stream_id = :'sid'::uuid AND d.ts >= :'t0'::timestamptz AND d.ts < :'t1'::timestamptz
)
, prv AS (
	SELECT max(x.ts) AS ts FROM (
		SELECT d.ts FROM solardatm.da_datm d
		WHERE d.stream_id = :'sid'::uuid
			AND d.ts < :'t0'::timestamptz AND d.ts >= :'t0'::timestamptz - INTERVAL 'P1Y'
		ORDER BY d.ts DESC
		LIMIT 1
	) x
)
, nxt AS (
	SELECT min(x.ts) AS ts FROM (
		SELECT d.ts FROM solardatm.da_datm d
		WHERE d.stream_id = :'sid'::uuid
			AND d.ts >= :'t1'::timestamptz AND d.ts < :'t1'::timestamptz + INTERVAL 'P1Y'
		ORDER BY d.ts
		LIMIT 1
	) x
)
, aux AS (
	SELECT count(*) AS n FROM solardatm.da_datm_aux a
	WHERE a.stream_id = :'sid'::uuid
		AND a.ts >= :'t0'::timestamptz - INTERVAL 'PT1H' AND a.ts <= :'t1'::timestamptz + INTERVAL 'PT1H'
)
, st AS (
	SELECT count(*) AS n FROM solardatm.agg_stale_datm a
	WHERE a.agg_kind = 'h' AND a.ts_start = :'t0'::timestamptz AND a.stream_id = :'sid'::uuid
)
, off AS (
	SELECT count(*) AS n FROM solardatm.agg_datm_hourly h
	WHERE h.stream_id = :'sid'::uuid AND h.ts_start > :'t0'::timestamptz AND h.ts_start < :'t1'::timestamptz
)
, q AS (
	SELECT count(*) AS n
		, array_agg(ROW(f.stream_id, f.ts_start, f.data_i, f.data_a, f.data_s, f.data_t, f.stat_i, f.read_a)::solardatm.agg_datm
			ORDER BY f.ts_start)::text AS txt
	FROM solardatm.agg_datm_15m f
	WHERE f.stream_id = :'sid'::uuid AND f.ts_start >= :'t0'::timestamptz AND f.ts_start < :'t1'::timestamptz
)
, v AS (
	SELECT
		  CASE
			WHEN k.cls = 'stored_only' AND raw.n = 0 THEN 'stored_only_no_raw'
			WHEN k.cls = 'stored_only' AND k.zs THEN 'zero_or_nothing'
			WHEN k.cls = 'today_only' AND raw.n = 0 THEN 'today_only_no_raw'
			ELSE k.cls
		  END AS cls
		, CASE WHEN (p.t)::text IS NOT DISTINCT FROM (SELECT l.txt FROM l) THEN 'same' ELSE 'DIFFERENT' END AS q2
		, CASE
			WHEN q.n = 0 AND x.slots IS NULL THEN 'none'
			WHEN q.n = 0 THEN CASE WHEN :'t0'::timestamptz >= :'bnd'::timestamptz THEN 'missing' ELSE 'n/a' END
			WHEN x.slots IS NULL THEN 'extra'
			WHEN q.txt = x.slots::text THEN 'same'
			ELSE 'DIFFERENT'
		  END AS f15
		, x.slots
	FROM k, raw, q, p
	LEFT OUTER JOIN LATERAL (SELECT c.slots FROM c) x ON TRUE
)
SELECT 'C', :'tg', :'hi', :'t0'
	, ((p.s).ts_start IS NOT NULL)::integer, ((p.t).ts_start IS NOT NULL)::integer, (EXISTS (SELECT FROM l))::integer
	, v.cls, k.sig, k.zs::integer, k.zt::integer, v.q2, v.f15, q.n, cardinality(v.slots)
	, raw.n, raw.na, aux.n
	, COALESCE(extract(epoch FROM COALESCE(raw.ts_first, :'t0'::timestamptz) - prv.ts)::bigint, -1)
	, COALESCE(extract(epoch FROM nxt.ts - COALESCE(raw.ts_last, :'t1'::timestamptz))::bigint, -1)
	, st.n, off.n
	, trim(to_char(k.a_abs, '9.999EEEE')), trim(to_char(k.a_rel, '9.999EEEE')), k.a_n, k.a_dir
	, trim(to_char(k.r_abs, '9.999EEEE')), trim(to_char(k.r_rel, '9.999EEEE'))
	, trim(to_char(k.i_rel, '9.999EEEE'))
	, CASE WHEN v.cls <> 'same' OR v.q2 <> 'same' OR v.f15 IN ('DIFFERENT', 'extra', 'missing') THEN
		replace(replace(replace(replace((p.s)::text, '%', '%25'), '|', '%7C'), E'\n', '%0A'), E'\r', '%0D') END
	, CASE WHEN v.cls <> 'same' OR v.q2 <> 'same' OR v.f15 IN ('DIFFERENT', 'extra', 'missing') THEN
		replace(replace(replace(replace((p.t)::text, '%', '%25'), '|', '%7C'), E'\n', '%0A'), E'\r', '%0D') END
	, CASE WHEN v.q2 <> 'same' THEN
		replace(replace(replace(replace((SELECT l.txt FROM l), '%', '%25'), '|', '%7C'), E'\n', '%0A'), E'\r', '%0D') END
	, CASE WHEN v.f15 IN ('DIFFERENT', 'extra') THEN
		replace(replace(replace(replace(q.txt, '%', '%25'), '|', '%7C'), E'\n', '%0A'), E'\r', '%0D') END
	, CASE WHEN v.f15 IN ('DIFFERENT', 'missing') THEN
		replace(replace(replace(replace(v.slots::text, '%', '%25'), '|', '%7C'), E'\n', '%0A'), E'\r', '%0D') END
FROM p, k, v, raw, prv, nxt, aux, st, off, q;
SQL

cat "$OUT/sql/compare-head.sql" "$OUT/sql/classify.sql" "$OUT/sql/compare-tail.sql" >"$OUT/sql/compare.sql" \
	|| die "cannot write $OUT/sql/compare.sql"

# One timed call: a marker row, then the plan with its buffers and timings
cat >"$OUT/sql/time.sql" <<'SQL'
SELECT 'X', :'tg', :'hi';
EXPLAIN (ANALYZE, BUFFERS, TIMING OFF, SUMMARY ON)
SELECT * FROM solardatm.rollup_datm_15m_for_hour(:'sid'::uuid, :'t0'::timestamptz, :'t1'::timestamptz);
SQL

# The raw datum of one sampled local day
cat >"$OUT/sql/day.sql" <<'SQL'
SELECT 'D', :'tg', count(*)
FROM solardatm.da_datm d
WHERE d.stream_id = :'sid'::uuid AND d.ts >= :'d0'::timestamptz AND d.ts < :'d1'::timestamptz;
SQL

# -----------------------------------------------------------------------------
# Context: the server, the functions, the boundary
# -----------------------------------------------------------------------------

{
	printf 'script=net540-history-compare.sh\n'
	printf 'script_version=%s\n' "$SCRIPT_VERSION"
	printf 'started=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	printf 'host=%s\n' "${PGHOST:-}"
	printf 'port=%s\n' "${PGPORT:-}"
	printf 'dbname=%s\n' "${PGDATABASE:-}"
	printf 'user=%s\n' "${PGUSER:-}"
	printf 'psql=%s\n' "$("$PSQL" -V)"
	printf 'options=-n %s -l %s -D %s -k %s -c %s -C %s -B %s -P %s -t %s -R %s -S %s -b %s -x %s -X %s -T %s\n' \
		"$NODE_PER_YEAR" "$LOC_PER_YEAR" "$MAX_DAYS" "$TIMED_PER_YEAR" "$CTL_STREAMS" "$CTL_HOURS" \
		"$BATCH" "${PAUSE:-default}" "$STMT_TIMEOUT" "$RECENT" "$SEED" "${BOUNDARY_OPT:-none}" \
		"$((1 - DO_TIMING))" "$ALLOW_UNKNOWN" "${TARGETS_FILE:-none}"
} >"$OUT/run.txt"

note "Output in $OUT"
if ! psql_ro -v ON_ERROR_STOP=1 -f "$OUT/sql/context.sql" >>"$OUT/run.txt" 2>>"$LOG"; then
	note "Could not read the server's context; see run.log"
	finish 2
	exit 2
fi
[ "$(setting read_only)" = on ] || { note "The session is not read-only; stopping"; finish 2; exit 2; }

IN_RECOVERY=$(setting in_recovery)
LIVE_HAS=$(setting md5_rollup_datm_for_time_span)
STEP1_HAS=$(setting md5_rollup_datm_15m_for_hour)
case $LIVE_HAS in
	"$LIVE_MD5") LIVE_KNOWN=current ;;
	"$LIVE_PRE_NET543_MD5") LIVE_KNOWN=pre_net543 ;;
	*) LIVE_KNOWN=UNKNOWN ;;
esac
case $STEP1_HAS in
	"$STEP1_MD5") STEP1_KNOWN=step1 ;;
	*) STEP1_KNOWN=UNKNOWN ;;
esac
{
	printf 'rollup_datm_for_time_span_known=%s\n' "$LIVE_KNOWN"
	printf 'rollup_datm_15m_for_hour_known=%s\n' "$STEP1_KNOWN"
} >>"$OUT/run.txt"
[ -n "$STEP1_HAS" ] || { note "rollup_datm_15m_for_hour() is not there: is step 1 deployed?"; finish 2; exit 2; }
if [ "$LIVE_KNOWN" = UNKNOWN ] || [ "$STEP1_KNOWN" = UNKNOWN ]; then
	note "A rollup function's body is not one this script knows (live $LIVE_KNOWN, step 1 $STEP1_KNOWN)"
	if [ "$ALLOW_UNKNOWN" -eq 0 ]; then
		note "Stopping: the comparison would mean something else. Run with -X to compare anyway."
		finish 2
		exit 2
	fi
	note "Comparing anyway (-X)"
fi
[ "$LIVE_KNOWN" != pre_net543 ] \
	|| note "NOTE: the hourly rollup predates NET-543; question 2 will differ at reset pairs after an hour"
if [ "$IN_RECOVERY" = true ]; then
	note "The server is a standby (in recovery); the script is meant for the primary"
else
	note "The server is a primary"
fi

[ -n "$PAUSE" ] || PAUSE=0.5
printf 'pause=%s\n' "$PAUSE" >>"$OUT/run.txt"

# the boundary for the control group
BND=$(setting boundary)
if [ -n "$BOUNDARY_OPT" ]; then
	BND=$(psql_ro -v ON_ERROR_STOP=1 -v b="$BOUNDARY_OPT" -c "SELECT :'b'::timestamptz" 2>>"$LOG") \
		|| { note "-b $BOUNDARY_OPT is not a time"; finish 2; exit 2; }
fi
case $BND in
	'' | NULL | -infinity | infinity)
		note "No finite boundary ($BND): no control group (give one with -b)"
		CTL_BND=
		;;
	*)
		CTL_BND=$BND
		;;
esac
printf 'control_boundary=%s\n' "${CTL_BND:-none}" >>"$OUT/run.txt"

# -----------------------------------------------------------------------------
# The targets: stream-days, control windows, and their hours
# -----------------------------------------------------------------------------

TARGETS_HEADER='tid|kind|year|stream_id|obj|time_zone|start|end|datum_count|hourly_count|prev_datum_count|timed'
if [ -n "$TARGETS_FILE" ]; then
	note "Reading targets from $TARGETS_FILE"
	{
		printf '%s\n' "$TARGETS_HEADER"
		awk -F'|' 'NF == 12 && $1 ~ /^[SC][0-9]+$/ && length($4) == 36 && $4 ~ /^[0-9a-f-]+$/ \
			&& $7 ~ /^[0-9: +.-]+$/ && $8 ~ /^[0-9: +.-]+$/ && $12 ~ /^[01]$/' "$TARGETS_FILE"
	} >"$OUT/targets.psv"
	if [ "$DO_TIMING" -eq 0 ]; then
		awk -F'|' 'BEGIN { OFS = "|" } NR > 1 { $12 = 0 } { print }' "$OUT/targets.psv" >"$OUT/targets.tmp" \
			&& mv "$OUT/targets.tmp" "$OUT/targets.psv"
	fi
else
	note "Choosing stream-days: $NODE_PER_YEAR node and $LOC_PER_YEAR location a year"
	TK=$TIMED_PER_YEAR
	[ "$DO_TIMING" -eq 1 ] || TK=0
	if ! psql_ro -v ON_ERROR_STOP=1 -v seed="$SEED" -v nper="$NODE_PER_YEAR" -v lper="$LOC_PER_YEAR" \
			-v dmax="$MAX_DAYS" -v kper="$TK" -v recent="$RECENT" \
			-f "$OUT/sql/targets.sql" >"$OUT/out/targets.out" 2>>"$LOG"; then
		note "Choosing the stream-days failed; see run.log"
		finish 2
		exit 2
	fi
	if [ -n "$CTL_BND" ] && [ "$CTL_STREAMS" -gt 0 ]; then
		note "Choosing $CTL_STREAMS control streams at or after $CTL_BND"
		psql_ro -v ON_ERROR_STOP=1 -v seed="$SEED" -v bnd="$CTL_BND" -v cn="$CTL_STREAMS" \
			-v chours="$CTL_HOURS" -v recent="$RECENT" \
			-f "$OUT/sql/control.sql" >>"$OUT/out/targets.out" 2>>"$LOG" \
			|| note "WARNING: choosing control streams failed; see run.log"
	fi
	{
		printf '%s\n' "$TARGETS_HEADER"
		sed -n 's/^T|//p' "$OUT/out/targets.out" | awk -F'|' 'NF == 12 && length($4) == 36 \
			&& $4 ~ /^[0-9a-f-]+$/ && $7 ~ /^[0-9: +.-]+$/ && $8 ~ /^[0-9: +.-]+$/'
	} >"$OUT/targets.psv"
fi
N_TARGETS=$(awk 'NR > 1' "$OUT/targets.psv" | awk 'END { print NR }')
[ "$N_TARGETS" -gt 0 ] || { note "No stream-days to compare"; finish 2; exit 2; }

# the hours of each target, from SQL so that time zones and dates are the
# server's: H|tid|hour|start|end|left out
awk -F'|' -v q="'" -v recent="$RECENT" '
	BEGIN {
		print "SELECT " q "H" q ", v.tid, row_number() OVER (PARTITION BY v.tid ORDER BY g.h) - 1, g.h, g.h + INTERVAL " q "PT1H" q
		print "\t, CASE WHEN g.h + INTERVAL " q "PT1H" q " > now() - make_interval(hours => " recent ") THEN " q "recent" q " ELSE " q q " END"
		print "FROM (VALUES"
	}
	NR > 1 { printf "\t%s(%s%s%s, %s%s%s::timestamptz, %s%s%s::timestamptz)\n", (n++ ? ", " : ""), q, $1, q, q, $7, q, q, $8, q }
	END {
		print ") AS v(tid, d0, d1)"
		print "CROSS JOIN LATERAL generate_series(date_trunc(" q "hour" q ", v.d0), v.d1 - INTERVAL " q "PT0.000001S" q ", INTERVAL " q "PT1H" q ") AS g(h)"
		print "ORDER BY 2, 3;"
	}' "$OUT/targets.psv" >"$OUT/sql/hours.sql"
if ! psql_ro -v ON_ERROR_STOP=1 -f "$OUT/sql/hours.sql" >"$OUT/out/hours.out" 2>>"$LOG"; then
	note "Listing the hours failed; see run.log"
	finish 2
	exit 2
fi
{
	printf 'tid|hi|start|end|left_out\n'
	sed -n 's/^H|//p' "$OUT/out/hours.out"
} >"$OUT/hours.psv"

awk -F'|' -v out="$OUT/counts.tmp" '
	FNR == 1 { f++; next }
	f == 1 { k[$1] = $2; tm[$1] = $12; if ($2 == "S") sd++; else cs++; if ($12 == 1) td++; next }
	{ if ($5 != "") ex++; else if (k[$1] == "C") ch++; else { sh++; if (tm[$1] == 1) th++ } }
	END { printf "%d %d %d %d %d %d %d\n", sd, cs, sh, ch, ex, td, th > out }
' "$OUT/targets.psv" "$OUT/hours.psv"
read -r N_SD N_CS N_SH N_CH N_EX N_TD N_TH <"$OUT/counts.tmp"
rm -f "$OUT/counts.tmp"
{
	printf 'stream_days=%s\n' "$N_SD"
	printf 'control_streams=%s\n' "$N_CS"
	printf 'hours_sampled=%s\n' "$N_SH"
	printf 'hours_control=%s\n' "$N_CH"
	printf 'hours_left_out_recent=%s\n' "$N_EX"
	printf 'timed_stream_days=%s\n' "$N_TD"
	printf 'timed_calls=%s\n' "$N_TH"
} >>"$OUT/run.txt"
N_BATCHES=$(( (N_TARGETS + BATCH - 1) / BATCH ))
EST=$(awk -v h="$((N_SH + N_CH))" -v t="$N_TH" -v d="$N_TARGETS" -v p="$PAUSE" -v b="$N_BATCHES" \
	'BEGIN { printf "%.0f", (h * 0.05 + t * 0.04 + d * (p + 0.1) + b * 3) / 60 + 1 }')
# reads: at most one page for each datum and hourly row of the sampled days
EST_GB=$(awk -F'|' 'NR > 1 && $2 == "S" { n += $9 + $10 } END { printf "%.1f", n * 8192 / 1e9 }' "$OUT/targets.psv")
printf 'estimate_minutes=%s\nestimate_read_gb_at_most=%s\n' "$EST" "$EST_GB" >>"$OUT/run.txt"
note "$N_SD stream-days ($N_SH hours, $N_TH timed) and $N_CS control streams ($N_CH hours); $N_EX recent hours left out"
note "$N_BATCHES sessions of $BATCH stream-days, $PAUSE s pause after each; about $EST minutes at 50 ms an hour"
note "The sampled days hold rows on at most about $EST_GB GB of pages, all of it read only if none is in memory"

# -----------------------------------------------------------------------------
# The batches: one psql session for each -B stream-days
# -----------------------------------------------------------------------------

# the warm-up hour: the last hour of the first control stream, else the first
# hour of the first stream-day that is not timed
WARM=$(awk -F'|' '
	FNR == 1 { f++; next }
	f == 1 { if (!($2 in first)) first[$2] = $1; sid[$1] = $4; if ($2 == "S" && $12 == 0 && un == "") un = $1; if (any == "") any = $1; next }
	$5 == "" { if (!($1 in h0)) h0[$1] = $3 "|" $4; hl[$1] = $3 "|" $4 }
	END {
		if (("C" in first) && (first["C"] in hl)) { t = first["C"]; print sid[t] "|" hl[t] }
		else if (un != "" && (un in h0)) print sid[un] "|" h0[un]
		else if (any in h0) print sid[any] "|" h0[any]
	}' "$OUT/targets.psv" "$OUT/hours.psv")
printf 'warmup=%s\n' "$WARM" >>"$OUT/run.txt"

# gen_batches PREFIX TIMING [WANTFILE] - write sql/PREFIX-NNNN.sql and list them
# in sql/PREFIX.list; WANTFILE limits the hours to the tid|hi pairs in it
gen_batches() {
	awk -F'|' -v q="'" -v out="$OUT/sql" -v prefix="$1" -v timing="$2" -v batch="$BATCH" \
		-v pause="$PAUSE" -v bnd="${CTL_BND:-infinity}" -v warm="$WARM" '
		FNR == 1 { f++; next }
		f == 1 { tid[++nt] = $1; sid[$1] = $4; d0[$1] = $7; d1[$1] = $8; tm[$1] = $12; next }
		f == 2 { if ($5 == "") { nh[$1]++; hh[$1, nh[$1]] = $2 "|" $3 "|" $4 } ; next }
		f == 3 { want[$1, $2] = 1; usewant = 1; next }
		function hour(i, t,   x) {
			split(hh[t, i], x, "|")
			printf "\\set hi %s\n\\set t0 %s%s%s\n\\set t1 %s%s%s\n", x[1], q, x[2], q, q, x[3], q > file
		}
		END {
			list = out "/" prefix ".list"
			printf "" > list
			split(warm, w, "|")
			n = 0
			for (j = 1; j <= nt; j++) {
				t = tid[j]
				m = 0
				for (i = 1; i <= nh[t]; i++) {
					split(hh[t, i], x, "|")
					if (!usewant || ((t, x[1]) in want)) { m++; use[t, i] = 1 } else use[t, i] = 0
				}
				if (m == 0) continue
				if (n % batch == 0) {
					if (file != "") close(file)
					file = sprintf("%s/%s-%04d.sql", out, prefix, n / batch + 1)
					print file > list
					printf "\\set bnd %s%s%s\n", q, bnd, q > file
					if (warm != "") {
						printf "\\set tg W\n\\set sid %s\n\\set hi 0\n\\set t0 %s%s%s\n\\set t1 %s%s%s\n", w[1], q, w[2], q, q, w[3], q > file
						print "\\ir compare.sql\n\\ir compare.sql\n\\ir compare.sql" > file
						if (timing) print "\\ir time.sql" > file
					}
				}
				n++
				printf "\\set tg %s\n\\set sid %s\n\\set d0 %s%s%s\n\\set d1 %s%s%s\n", t, sid[t], q, d0[t], q, q, d1[t], q > file
				if (timing && tm[t] == 1)
					for (i = 1; i <= nh[t]; i++) if (use[t, i]) { hour(i, t); print "\\ir time.sql" > file }
				for (i = 1; i <= nh[t]; i++) if (use[t, i]) { hour(i, t); print "\\ir compare.sql" > file }
				if (!usewant) print "\\ir day.sql" > file
				if (pause + 0 > 0) print "SELECT " q "P" q " FROM pg_sleep(:pause);" > file
			}
			if (file != "") close(file)
			close(list)
		}' "$OUT/targets.psv" "$OUT/hours.psv" ${3:+"$3"}
}

# run_batches PREFIX - run every batch in sql/PREFIX.list, one at a time
run_batches() {
	_total=$(awk 'END { print NR }' "$OUT/sql/$1.list")
	_i=0
	while IFS= read -r _f; do
		_i=$((_i + 1))
		_b=${_f##*/}
		_b=${_b%.sql}
		_t0=$(date +%s)
		psql_ro -v ON_ERROR_STOP=0 -v pause="$PAUSE" -f "$_f" >"$OUT/out/$_b.out" 2>"$OUT/out/$_b.err"
		_rc=$?
		_errs=$(awk '/ERROR:/ { n++ } END { print n + 0 }' "$OUT/out/$_b.err")
		# keep the plan of the session's first timed call (the warm-up) whole, and of
		# the others only the lines the timing is read from
		awk '
			/^X\|/ { x++; inx = 1; print; next }
			/^[CDP]\|/ || /^P$/ { inx = 0; print; next }
			inx && x > 1 { if ($0 ~ /Buffers:|I\/O Timings:|Planning:|Planning Time:|Execution Time:/) print; next }
			{ print }
		' "$OUT/out/$_b.out" >"$OUT/out/$_b.slim" && mv "$OUT/out/$_b.slim" "$OUT/out/$_b.out"
		_secs=$(( $(date +%s) - _t0 ))
		printf '%s|%s|%s|%s\n' "$_b" "$_rc" "$_errs" "$_secs" >>"$OUT/batches.psv"
		printf '%s\n' "$OUT/out/$_b.out" >>"$OUT/out/outputs.list"
		if [ "$_rc" -ne 0 ] || [ "$_errs" -gt 0 ]; then
			note "$1 $_i/${_total}: psql exit $_rc, $_errs statement errors (see out/${_b}.err), ${_secs}s"
		else
			note "$1 $_i/$_total done in ${_secs}s"
		fi
		[ "$INTERRUPTED" -eq 0 ] || break
	done <"$OUT/sql/$1.list"
}

# parse - turn what the sessions printed into compare, details, timing and days
parse() {
	awk -F'|' -v list="$OUT/out/outputs.list" -v cmp="$OUT/compare.psv" -v det="$OUT/details.psv" \
		-v tim="$OUT/timing.psv" -v days="$OUT/days.psv" '
		BEGIN {
			# the files to read are listed one to a line, so that no path is split
			while ((getline f < list) > 0) if (f != "") ARGV[ARGC++] = f
			close(list)
			OFS = "|"
			print "tid|hi|start|stored|today|live|class|signature|zero_stored|zero_today|q2|f15|rows_15m_stored|rows_15m_today|raw|raw_a|resets|gap_before_s|gap_after_s|stale|off_hour_rows|a_abs|a_rel|a_props|a_dir|r_abs|r_rel|i_rel" > cmp
			print "tid|hi|stored|today|live|stored_15m|today_15m" > det
			print "tid|hi|planning_ms|execution_ms|shared_hit|shared_read|read_ms|planning_hit|planning_read" > tim
			print "tid|raw_datum" > days
		}
		function kv(s, k) {
			if (match(s, k "=[0-9.]+")) return substr(s, RSTART + length(k) + 1, RLENGTH - length(k) - 1)
			return ""
		}
		function shared(s) {
			if (!match(s, "shared [^,]*")) return ""
			return substr(s, RSTART, RLENGTH)
		}
		function num(s) {
			if (match(s, "[0-9][0-9.]*")) return substr(s, RSTART, RLENGTH)
			return ""
		}
		FNR == 1 { inx = 0 }
		/^C\|/ {
			inx = 0
			if ($2 == "W" || NF < 34) next
			line = $2
			for (i = 3; i <= 29; i++) line = line "|" $i
			print line > cmp
			if ($30 != "" || $31 != "" || $32 != "" || $33 != "" || $34 != "") print $2, $3, $30, $31, $32, $33, $34 > det
			next
		}
		/^X\|/ { inx = 1; tg = $2; hi = $3; gb = 0; gp = 0; gi = 0; bh = 0; br = 0; io = ""; ph = 0; pr = 0; pt = ""; inplan = 0; next }
		/^D\|/ { inx = 0; print $2, $3 > days; next }
		inx {
			if ($0 ~ /^ *Planning:/) { inplan = 1; next }
			if ($0 ~ /Buffers:/) {
				s = shared($0)
				if (inplan) { if (!gp) { gp = 1; ph = kv(s, "hit") + 0; pr = kv(s, "read") + 0 } }
				else if (!gb) { gb = 1; bh = kv(s, "hit") + 0; br = kv(s, "read") + 0 }
				next
			}
			if ($0 ~ /I\/O Timings:/ && !inplan && !gi) { gi = 1; io = kv($0, "read"); next }
			if ($0 ~ /^ *Planning Time:/) { pt = num($0); next }
			if ($0 ~ /^ *Execution Time:/) {
				if (tg != "W") print tg, hi, pt, num($0), bh, br, io, ph, pr > tim
				inx = 0
				next
			}
		}
	' /dev/null </dev/null
}

INTERRUPTED=0
trap 'INTERRUPTED=1; note "Interrupted; summarising what was collected"' INT TERM

: >"$OUT/batches.psv"
: >"$OUT/out/outputs.list"
gen_batches batch "$DO_TIMING"
run_batches batch

# what is missing is tried once more, without timing
parse
awk -F'|' 'FNR == 1 { f++; next } f == 1 { got[$1 "|" $2] = 1; next }
	$5 == "" && !(($1 "|" $2) in got) { print $1 "|" $2 }' \
	"$OUT/compare.psv" "$OUT/hours.psv" >"$OUT/missing.tmp"
N_MISSING1=$(awk 'END { print NR }' "$OUT/missing.tmp")
printf 'hours_failed_first_pass=%s\n' "$N_MISSING1" >>"$OUT/run.txt"
if [ "$N_MISSING1" -gt 0 ] && [ "$INTERRUPTED" -eq 0 ]; then
	note "Trying again the $N_MISSING1 hours that could not be compared"
	{ printf 'tid|hi\n'; cat "$OUT/missing.tmp"; } >"$OUT/missing.psv"
	gen_batches retry 0 "$OUT/missing.psv"
	run_batches retry
	parse
fi
rm -f "$OUT/missing.tmp"
{
	printf 'tid|hi\n'
	awk -F'|' 'FNR == 1 { f++; next } f == 1 { got[$1 "|" $2] = 1; next }
		$5 == "" && !(($1 "|" $2) in got) { print $1 "|" $2 }' "$OUT/compare.psv" "$OUT/hours.psv"
} >"$OUT/failed.psv"

awk -F'|' -v out="$OUT/counts.tmp" '
	{ n++; if ($2 != 0) bad++; e += $3 }
	END { printf "%d %d %d\n", n, bad, e > out }' "$OUT/batches.psv"
read -r N_SESSIONS N_SESSIONS_BAD N_ERRORS <"$OUT/counts.tmp"
rm -f "$OUT/counts.tmp"
N_FAILED=$(awk 'NR > 1' "$OUT/failed.psv" | awk 'END { print NR }')
N_TIMED=$(awk 'NR > 1' "$OUT/timing.psv" | awk 'END { print NR }')
N_TIMED_MISSING=$((N_TH - N_TIMED))
[ "$N_TIMED_MISSING" -ge 0 ] || N_TIMED_MISSING=0
{
	printf 'sessions=%s\n' "$N_SESSIONS"
	printf 'sessions_failed=%s\n' "$N_SESSIONS_BAD"
	printf 'statement_errors=%s\n' "$N_ERRORS"
	printf 'hours_failed=%s\n' "$N_FAILED"
	printf 'timed_calls_done=%s\n' "$N_TIMED"
	printf 'timed_calls_failed=%s\n' "$N_TIMED_MISSING"
	printf 'interrupted=%s\n' "$INTERRUPTED"
} >>"$OUT/run.txt"

# -----------------------------------------------------------------------------
# The summaries
# -----------------------------------------------------------------------------

awk -F'|' -v bnd="$CTL_BND" -v outdir="$OUT" -v prod="$PROD_HOURS" -v rawshare="$PROD_RAW_SHARE" \
	-v iot="$(setting track_io_timing)" '
	BEGIN {
		OFS = "|"
		ng = split("stored_raw stored_no_raw not_stored", GN, " ")
		nc = split("same value zero_or_nothing read_layout status rounding format stored_only stored_only_no_raw today_only today_only_no_raw neither", CN, " ")
		nb = split("0 <=1e-9 1e-9..1e-6 1e-6..1e-3 1e-3..0.01 0.01..0.1 0.1..1 >=1", BN, " ")
		split("+ - ~", DN, " ")
	}
	function rb(x) {
		x += 0
		if (x == 0) return "0"
		if (x <= 1e-9) return "<=1e-9"
		if (x <= 1e-6) return "1e-9..1e-6"
		if (x <= 1e-3) return "1e-6..1e-3"
		if (x <= 1e-2) return "1e-3..0.01"
		if (x <= 1e-1) return "0.01..0.1"
		if (x < 1) return "0.1..1"
		return ">=1"
	}
	function ab(x,   e) {
		x += 0
		if (x == 0) return "0"
		e = int(log(x) / log(10) + 100) - 100
		if (10 ^ e > x) e--
		return sprintf("1e%d..1e%d", e, e + 1)
	}
	function isort(a, n,   i, j, v) {
		for (i = 2; i <= n; i++) { v = a[i]; for (j = i - 1; j >= 1 && a[j] > v; j--) a[j + 1] = a[j]; a[j + 1] = v }
	}
	function pct(a, n, p,   k) {
		if (n == 0) return ""
		k = int(p * (n - 1) + 0.5) + 1
		return a[k]
	}
	FNR == 1 { f++; next }
	# targets
	f == 1 {
		K[$1] = $2; Y[$1] = $3; SID[$1] = $4; DC[$1] = $9; PDC[$1] = $11
		if ($2 == "S") { SD[$3]++; YR[$3] = 1 }
		next
	}
	# hours
	f == 2 {
		if (K[$1] == "C") { if ($5 != "") ctl_recent++; next }
		if ($5 != "") RECENT[Y[$1]]++
		HOURS[Y[$1]]++
		next
	}
	# raw datum of each day
	f == 3 { RAWDAY[$1] = $2; next }
	# compare
	f == 4 {
		t = $1; yr = Y[t]; sid = SID[t]; cls = $7; sig = $8
		N15T[t "|" $2] = $14
		Q2[yr, $11]++
		if ($11 == "DIFFERENT") {
			q2bad++
			if (!((sid) in q2s)) { q2s[sid] = 1; q2bad_s++ }
			if (!q2h) { q2h = 1; print "year|tid|hi|stream_id|start|class|signature" > (outdir "/q2-different.psv") }
			print yr, t, $2, sid, $3, cls, sig > (outdir "/q2-different.psv")
		}
		ctl = (K[t] == "C" || (bnd != "" && $3 >= bnd))
		if ($20 > 0) { if (ctl) ctl_stale++; else STALE[yr]++; next }
		if (ctl) {
			ctl_n++; CTLC[cls]++; CTLF[$12]++
			if (K[t] == "S") CTLS[yr]++
			if (!((sid) in ctls)) { ctls[sid] = 1; ctl_s++ }
			if ((cls != "same" && cls != "neither") || ($12 != "same" && $12 != "none")) {
				if (!cbh) { cbh = 1; print "what|tid|hi|stream_id|start|class|signature|f15" > (outdir "/control-not-same.psv") }
				if (cls != "same" && cls != "neither") { ctl_bad++; print "class", t, $2, sid, $3, cls, sig, $12 > (outdir "/control-not-same.psv") }
				if ($12 != "same" && $12 != "none") { ctl15_bad++; print "15m", t, $2, sid, $3, cls, sig, $12 > (outdir "/control-not-same.psv") }
			}
			next
		}
		if (K[t] != "S") next
		grp = ($4 == 1 ? ($15 > 0 ? "stored_raw" : "stored_no_raw") : "not_stored")
		CMP[yr]++
		G[yr, grp]++
		C[yr, grp, cls]++
		if (!((yr, grp, cls, sid) in s1)) { s1[yr, grp, cls, sid] = 1; CS[yr, grp, cls]++ }
		if (!((yr, grp, sid) in s2)) { s2[yr, grp, sid] = 1; GS[yr, grp]++ }
		if (grp == "stored_raw" && cls != "same" && !((yr, sid) in s3)) { s3[yr, sid] = 1; NSS[yr]++ }
		F15[$12]++
		key = yr SUBSEP grp SUBSEP cls SUBSEP sig
		if (!(key in S)) { nkeys++; KEYS[nkeys] = key }
		S[key]++
		if (!((key, sid) in s4)) { s4[key, sid] = 1; SS[key]++ }
		if ($17 > 0) SR[key]++
		if ($18 == -1 || $18 > 3600 || $19 == -1 || $19 > 3600) SG[key]++
		if (PDC[t] == "0") SE[key]++
		if ((t in RAWDAY) && DC[t] != "" && RAWDAY[t] + 0 < DC[t] + 0) SDY[key]++
		ko = grp SUBSEP cls SUBSEP sig
		if (!(ko in O)) { nko++; KO[nko] = ko }
		O[ko]++
		if (!((ko, sid) in s5)) { s5[ko, sid] = 1; OS[ko]++ }
		if (!((ko, yr) in s6)) { s6[ko, yr] = 1; OY[ko]++ }
		if (cls == "value") {
			V[yr, grp, "a_rel", rb($23)]++
			V[yr, grp, "r_rel", rb($27)]++
			V[yr, grp, "i_rel", rb($28)]++
			V[yr, grp, "a_abs", ab($22)]++
			V[yr, grp, "r_abs", ab($26)]++
			if ($25 != "") VA[yr, grp, $25]++
			if (grp == "stored_raw") {
				VT[yr]++
				if ($23 + 0 > 1e-6 || $27 + 0 > 1e-6) VT6[yr]++
				if ($23 + 0 > 1e-2 || $27 + 0 > 1e-2) VT2[yr]++
				if ($28 + 0 > 1e-6) VI6[yr]++
				if ($28 + 0 > 1e-2) VI2[yr]++
				if ($18 == -1 || $18 > 3600 || $19 == -1 || $19 > 3600 || PDC[t] == "0" \
					|| ((t in RAWDAY) && DC[t] != "" && RAWDAY[t] + 0 < DC[t] + 0)) VEDGE[yr]++
			}
		}
		if (cls != "same" && EX[key] < 3) { EX[key]++; print yr, grp, cls, sig, t, $2, sid, $3 > (outdir "/examples.tmp") }
		next
	}
	# timing
	f == 5 {
		t = $1; yr = Y[t]
		pos = ((t in FT) ? "later" : "first")
		FT[t] = 1
		tot = $3 + $4
		# with track_io_timing on, a call that read nothing prints no read time
		if ($7 == "" && iot == "on") $7 = 0
		n = ++TN[yr, pos]; TV[yr, pos, n] = tot
		TP[yr, pos] += $3; TE[yr, pos] += $4; TH[yr, pos] += $5; TR[yr, pos] += $6
		if ($7 != "") { TIO[yr, pos] += $7; TION[yr, pos]++ }
		sl = N15T[t "|" $2]
		if (sl != "") { TSL[yr, pos] += sl; TSLN[yr, pos]++ }
		if (pos == "later") { m = ++LN; LV[m] = tot; LR += $6; LH += $5; if ($7 != "") { LIO += $7; LION++ } }
		else { m = ++FN; FV[m] = tot; FR += $6 }
		TY[yr] = 1
		next
	}
	# failed hours
	f == 6 { if (K[$1] == "S") FAILED[Y[$1]]++; nfailed++; next }
	END {
		# years in order
		ny = 0
		for (y in YR) { ny++; YS[ny] = y }
		for (y in TY) if (!(y in YR)) { ny++; YS[ny] = y }
		isort(YS, ny)

		fy = outdir "/by-year.psv"
		print "year|stream_days|hours|left_out_recent|left_out_stale|failed|control|compared|stored_with_raw|same|same_pct|value|zero_or_nothing|read_layout|status|rounding|format|stored_only|streams_with_raw|streams_not_same|stored_no_raw|not_stored|today_only|today_only_no_raw|neither|value_over_1e-6|value_over_1e-2|value_avg_over_1e-6|value_avg_over_1e-2|value_at_gap_or_deleted" > fy
		for (i = 1; i <= ny; i++) {
			y = YS[i]
			if (!(y in YR)) continue
			sr = G[y, "stored_raw"] + 0
			printf "%s|%d|%d|%d|%d|%d|%d|%d|%d|%d|%s", y, SD[y], HOURS[y], RECENT[y], STALE[y], FAILED[y], CTLS[y], CMP[y], sr, C[y, "stored_raw", "same"], (sr ? sprintf("%.2f", 100 * C[y, "stored_raw", "same"] / sr) : "") > fy
			printf "|%d|%d|%d|%d|%d|%d|%d", C[y, "stored_raw", "value"], C[y, "stored_raw", "zero_or_nothing"], C[y, "stored_raw", "read_layout"], C[y, "stored_raw", "status"], C[y, "stored_raw", "rounding"], C[y, "stored_raw", "format"], C[y, "stored_raw", "stored_only"] > fy
			printf "|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d\n", GS[y, "stored_raw"], NSS[y], G[y, "stored_no_raw"], G[y, "not_stored"], C[y, "not_stored", "today_only"], C[y, "not_stored", "today_only_no_raw"], C[y, "not_stored", "neither"], VT6[y], VT2[y], VI6[y], VI2[y], VEDGE[y] > fy
		}
		close(fy)

		fc = outdir "/by-year-class.psv"
		print "year|group|class|hours|streams" > fc
		for (i = 1; i <= ny; i++) for (g = 1; g <= ng; g++) for (c = 1; c <= nc; c++) {
			y = YS[i]
			if (C[y, GN[g], CN[c]] > 0) print y, GN[g], CN[c], C[y, GN[g], CN[c]], CS[y, GN[g], CN[c]] > fc
		}
		close(fc)

		fs = outdir "/by-year-signature.tmp"
		for (i = 1; i <= nkeys; i++) {
			split(KEYS[i], k, SUBSEP)
			print k[1], k[2], k[3], k[4], S[KEYS[i]], SS[KEYS[i]], SR[KEYS[i]] + 0, SG[KEYS[i]] + 0, SE[KEYS[i]] + 0, SDY[KEYS[i]] + 0 > fs
		}
		close(fs)

		fv = outdir "/value-size.psv"
		print "year|group|measure|bucket|hours" > fv
		nm = split("a_rel r_rel i_rel", MN, " ")
		for (i = 1; i <= ny; i++) for (g = 1; g <= 2; g++) {
			y = YS[i]
			for (m = 1; m <= nm; m++) for (b = 1; b <= nb; b++)
				if (V[y, GN[g], MN[m], BN[b]] > 0) print y, GN[g], MN[m], BN[b], V[y, GN[g], MN[m], BN[b]] > fv
			# a_dir: + today larger for every property that differs, - smaller, ~ mixed
			for (m = 1; m <= 3; m++) if (VA[y, GN[g], DN[m]] > 0) print y, GN[g], "a_dir", DN[m], VA[y, GN[g], DN[m]] > fv
			for (kk in V) {
				split(kk, z, SUBSEP)
				if (z[1] == y && z[2] == GN[g] && (z[3] == "a_abs" || z[3] == "r_abs")) print y, GN[g], z[3], z[4], V[kk] > (outdir "/value-abs.tmp")
			}
		}
		close(fv)

		fq = outdir "/q2.psv"
		print "year|same|DIFFERENT" > fq
		for (i = 1; i <= ny; i++) { y = YS[i]; print y, Q2[y, "same"] + 0, Q2[y, "DIFFERENT"] + 0 > fq }
		close(fq)

		fk = outdir "/control.psv"
		print "what|value|hours" > fk
		print "boundary", (bnd == "" ? "none" : bnd), "" > fk
		print "hours", "compared", ctl_n + 0 > fk
		print "hours", "left_out_stale", ctl_stale + 0 > fk
		print "hours", "left_out_recent", ctl_recent + 0 > fk
		print "streams", "compared", ctl_s + 0 > fk
		for (c = 1; c <= nc; c++) if (CTLC[CN[c]] > 0) print "class", CN[c], CTLC[CN[c]] > fk
		for (v in CTLF) print "f15", v, CTLF[v] > fk
		close(fk)

		ft = outdir "/cost-by-year.psv"
		print "year|position|calls|total_ms_median|total_ms_p90|total_ms_mean|planning_ms_mean|execution_ms_mean|shared_hit_mean|shared_read_mean|read_ms_mean|rows_15m_mean" > ft
		for (i = 1; i <= ny; i++) {
			y = YS[i]
			for (pp = 1; pp <= 2; pp++) {
				pos = (pp == 1 ? "first" : "later")
				n = TN[y, pos] + 0
				if (n == 0) continue
				delete A
				for (j = 1; j <= n; j++) A[j] = TV[y, pos, j]
				isort(A, n)
				printf "%s|%s|%d|%.1f|%.1f|%.1f|%.1f|%.1f|%.0f|%.1f|%s|%s\n", y, pos, n, pct(A, n, 0.5), pct(A, n, 0.9), (TP[y, pos] + TE[y, pos]) / n, TP[y, pos] / n, TE[y, pos] / n, TH[y, pos] / n, TR[y, pos] / n, (TION[y, pos] ? sprintf("%.2f", TIO[y, pos] / TION[y, pos]) : ""), (TSLN[y, pos] ? sprintf("%.2f", TSL[y, pos] / TSLN[y, pos]) : "") > ft
			}
		}
		close(ft)

		# question 3 scaled to production: the mean of later hours by year, weighted by
		# production hourly rows of that year (2017 standing for all before it)
		np = split(prod, PR, " ")
		wsum = 0; wms = 0; wrd = 0; whave = 0
		for (j = 1; j <= np; j++) {
			split(PR[j], z, "=")
			py = z[1] + 0; w = z[2] * 1e6 * rawshare
			n = 0; sm = 0; rd = 0
			for (i = 1; i <= ny; i++) {
				y = YS[i] + 0
				if ((py == 2017 && y <= 2017) || y == py) { n += TN[YS[i], "later"]; sm += TP[YS[i], "later"] + TE[YS[i], "later"]; rd += TR[YS[i], "later"] }
			}
			wsum += w
			if (n > 0) { wms += w * sm / n; wrd += w * rd / n; whave += w }
		}

		fo = outdir "/summary-body.tmp"
		# question 1
		print "QUESTION 1: stored hours with raw datum that are the same as today'"'"'s rollup, by year" > fo
		print "" > fo
		printf "  %-6s %6s %7s %8s %7s  %6s %6s %6s %6s %6s %6s %6s  %7s %7s\n", "year", "days", "hours", "w/ raw", "same%", "value", "zero", "layout", "status", "round", "format", "s_only", "streams", "!same" > fo
		for (i = 1; i <= ny; i++) {
			y = YS[i]
			if (!(y in YR)) continue
			sr = G[y, "stored_raw"] + 0
			printf "  %-6s %6d %7d %8d %7s  %6d %6d %6d %6d %6d %6d %6d  %7d %7d\n", y, SD[y], CMP[y], sr, (sr ? sprintf("%.2f", 100 * C[y, "stored_raw", "same"] / sr) : "-"), C[y, "stored_raw", "value"], C[y, "stored_raw", "zero_or_nothing"], C[y, "stored_raw", "read_layout"], C[y, "stored_raw", "status"], C[y, "stored_raw", "rounding"], C[y, "stored_raw", "format"], C[y, "stored_raw", "stored_only"], GS[y, "stored_raw"], NSS[y] > fo
			tsr += sr; tsame += C[y, "stored_raw", "same"]; tcmp += CMP[y]
		}
		printf "  %-6s %6s %7d %8d %7s\n", "all", "", tcmp, tsr, (tsr ? sprintf("%.2f", 100 * tsame / tsr) : "-") > fo
		print "" > fo
		print "  hours = compared (left out: recent, stale, failed); w/ raw = stored rows whose hour" > fo
		print "  has raw datum, the base of same%; streams = streams with such hours; !same = those" > fo
		print "  with any hour not same. Years are local years of the stream. by-year.psv has more." > fo
		print "" > fo
		print "  The value hours with raw datum, by largest relative difference:" > fo
		printf "  %-6s %7s %11s %11s %11s %11s %9s\n", "year", "value", "acc >1e-6", "acc >1e-2", "avg >1e-6", "avg >1e-2", "at a gap" > fo
		for (i = 1; i <= ny; i++) {
			y = YS[i]
			if (!(y in YR) || VT[y] == 0) continue
			printf "  %-6s %7d %11d %11d %11d %11d %9d\n", y, VT[y], VT6[y], VT2[y], VI6[y], VI2[y], VEDGE[y] > fo
		}
		print "  acc = accumulation or reading difference, avg = averages, each as" > fo
		print "  |stored - today| / max(|stored|, |today|) for the property that differs most." > fo
		print "  at a gap = more than an hour (or no datum within a year) to the datum before or" > fo
		print "  after, or a day short of its audit count, or the day after an expired day: where" > fo
		print "  raw datum may have gone rather than the rule changed. value-size.psv has the rest." > fo
		print "" > fo
		print "  Hours without raw datum or without a stored row (not in same%):" > fo
		printf "  %-6s %14s %11s %18s %9s\n", "year", "stored_no_raw", "today_only", "today_only_no_raw", "neither" > fo
		for (i = 1; i <= ny; i++) {
			y = YS[i]
			if (!(y in YR)) continue
			printf "  %-6s %14d %11d %18d %9d\n", y, G[y, "stored_no_raw"], C[y, "not_stored", "today_only"], C[y, "not_stored", "today_only_no_raw"], C[y, "not_stored", "neither"] > fo
		}
		print "" > fo
		# the most common signatures
		print "  The 30 most common shapes of difference, all years (by-year-signature.psv has all):" > fo
		printf "  %-13s %-18s %-30s %7s %7s %5s\n", "group", "class", "signature", "hours", "streams", "years" > fo
		no = 0
		for (i = 1; i <= nko; i++) { split(KO[i], k, SUBSEP); if (k[2] == "same" || k[2] == "neither") continue; OO[++no] = sprintf("%012d", O[KO[i]]) SUBSEP KO[i] }
		isort(OO, no)
		for (i = no; i >= 1 && i > no - 30; i--) {
			split(OO[i], k, SUBSEP)
			ko = k[2] SUBSEP k[3] SUBSEP k[4]
			printf "  %-13s %-18s %-30s %7d %7d %5d\n", k[2], k[3], k[4], O[ko], OS[ko], OY[ko] > fo
		}
		print "" > fo
		print "QUESTION 3: cost of one rollup_datm_15m_for_hour() call, by year" > fo
		print "" > fo
		printf "  %-6s %-6s %6s %8s %8s %8s %8s %8s %8s %7s\n", "year", "hour", "calls", "med ms", "p90 ms", "mean ms", "hit", "read", "read ms", "15m" > fo
		for (i = 1; i <= ny; i++) {
			y = YS[i]
			for (pp = 1; pp <= 2; pp++) {
				pos = (pp == 1 ? "first" : "later")
				n = TN[y, pos] + 0
				if (n == 0) continue
				delete A
				for (j = 1; j <= n; j++) A[j] = TV[y, pos, j]
				isort(A, n)
				printf "  %-6s %-6s %6d %8.1f %8.1f %8.1f %8.0f %8.1f %8s %7s\n", y, pos, n, pct(A, n, 0.5), pct(A, n, 0.9), (TP[y, pos] + TE[y, pos]) / n, TH[y, pos] / n, TR[y, pos] / n, (TION[y, pos] ? sprintf("%.2f", TIO[y, pos] / TION[y, pos]) : "-"), (TSLN[y, pos] ? sprintf("%.2f", TSL[y, pos] / TSLN[y, pos]) : "-") > fo
			}
		}
		print "" > fo
		print "  first = the first timed hour of a stream-day (its first touch), later = the rest," > fo
		print "  in time order; ms = planning + execution; hit, read = shared blocks; read ms only" > fo
		print "  with track_io_timing; 15m = 15 minute rows returned for the hour." > fo
		if (LN > 0) {
			delete A
			for (j = 1; j <= LN; j++) A[j] = LV[j]
			isort(A, LN)
			lmean = 0; for (j = 1; j <= LN; j++) lmean += LV[j]; lmean /= LN
			hrs = 214e6
			print "" > fo
			printf "  Scaled to 214 million hours, one session, later hours only (%d calls):\n", LN > fo
			printf "    median %.1f ms: %.0f hours; mean %.1f ms: %.0f hours; reads %.1f blocks an hour: %.1f TB\n", pct(A, LN, 0.5), hrs * pct(A, LN, 0.5) / 3.6e6, lmean, hrs * lmean / 3.6e6, LR / LN, hrs * (LR / LN) * 8192 / 1e12 > fo
			if (whave > 0)
				printf "    weighted by production hourly rows of each year (%.0f%% of them with a measured year): mean %.1f ms, %.0f hours; %.1f TB read\n", 100 * whave / wsum, wms / whave, wsum * (wms / whave) / 3.6e6, wsum * (wrd / whave) * 8192 / 1e12 > fo
			if (FN > 0) printf "    every hour a first touch instead: %.1f ms mean, %.1f blocks read an hour\n", FMEAN(), FR / FN > fo
			print "  These leave out writing the 15 minute rows and their WAL, the backfill'"'"'s own" > fo
			print "  queries and commits, and any hour without an hourly row; and the share of blocks" > fo
			print "  the operating system'"'"'s cache serves, which only read ms shows." > fo
		}
		close(fo)

		ff = outdir "/findings.tmp"
		printf "%d %d %d %d %d %d %d\n", q2bad, q2bad_s, ctl_n, ctl_bad, ctl15_bad, nfailed, F15["DIFFERENT"] + F15["extra"] > ff
		close(ff)
	}
	function FMEAN(   j, s) { s = 0; for (j = 1; j <= FN; j++) s += FV[j]; return s / FN }
' "$OUT/targets.psv" "$OUT/hours.psv" "$OUT/days.psv" "$OUT/compare.psv" "$OUT/timing.psv" "$OUT/failed.psv"

{
	printf 'year|group|class|signature|hours|streams|with_reset|at_gap|after_expired_day|day_short\n'
	sort -t'|' -k1,1 -k2,2 -k3,3 -k5,5nr "$OUT/by-year-signature.tmp" 2>/dev/null
} >"$OUT/by-year-signature.psv"
{
	printf 'year|group|class|signature|tid|hi|stream_id|start\n'
	sort -t'|' -k1,1 -k2,2 -k3,3 -k4,4 "$OUT/examples.tmp" 2>/dev/null
} >"$OUT/examples.psv"
[ ! -f "$OUT/value-abs.tmp" ] || sort -t'|' -k1,1 -k2,2 -k3,3 -k4,4 "$OUT/value-abs.tmp" >>"$OUT/value-size.psv"
read -r Q2_BAD Q2_BAD_STREAMS CTL_N CTL_BAD CTL15_BAD _NF HIST15_BAD <"$OUT/findings.tmp"

if [ "$Q2_BAD" -gt 0 ] || [ "$CTL_BAD" -gt 0 ] || [ "$CTL15_BAD" -gt 0 ]; then
	EXIT_STATUS=1
elif [ "$N_FAILED" -gt 0 ] || [ "$N_TIMED_MISSING" -gt 0 ] || [ "$INTERRUPTED" -ne 0 ]; then
	EXIT_STATUS=3
fi
{
	printf 'q2_different_hours=%s\n' "$Q2_BAD"
	printf 'q2_different_streams=%s\n' "$Q2_BAD_STREAMS"
	printf 'control_hours=%s\n' "$CTL_N"
	printf 'control_not_same=%s\n' "$CTL_BAD"
	printf 'control_15m_not_same=%s\n' "$CTL15_BAD"
	printf 'history_15m_different_or_extra=%s\n' "$HIST15_BAD"
} >>"$OUT/run.txt"

{
	printf 'NET-540 stored hours against today'"'"'s rollup (plan section 12.4, D18)\n'
	printf 'net540-history-compare.sh version %s, %s\n' "$SCRIPT_VERSION" "$(setting started)"
	printf 'server: %s, database %s, %s, PostgreSQL %s, TimescaleDB %s\n' "${PGHOST:-local}" \
		"$(setting database)" "$(if [ "$IN_RECOVERY" = true ]; then printf 'standby'; else printf 'primary'; fi)" \
		"$(setting server_version)" "$(setting timescaledb)"
	printf 'rollup_datm_for_time_span: %s (%s); rollup_datm_15m_for_hour: %s (%s)\n' \
		"$LIVE_HAS" "$LIVE_KNOWN" "$STEP1_HAS" "$STEP1_KNOWN"
	printf 'step 1 boundary: %s; control group from: %s\n' "$(setting boundary)" "${CTL_BND:-none}"
	printf 'plan_cache_mode %s (default %s), track_io_timing %s, jit %s (default %s), pause %s s, statement timeout %s s\n' \
		"$(setting plan_cache_mode)" "$(setting plan_cache_mode_default)" "$(setting track_io_timing)" \
		"$(setting jit)" "$(setting jit_default)" "$PAUSE" "$STMT_TIMEOUT"
	printf '\n'
	if [ "$Q2_BAD" -gt 0 ]; then
		printf '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n'
		printf '!! QUESTION 2: THE TWO ROLLUPS DISAGREE on %s hours of %s streams.\n' "$Q2_BAD" "$Q2_BAD_STREAMS"
		printf '!! rollup_datm_15m_for_hour() does not return the hour rollup_datm_for_time_span()\n'
		printf '!! does. The backfill would compute these hours differently from processing.\n'
		printf '!! Every such hour is in q2-different.psv (q2.psv counts them by year), and\n'
		printf '!! both rows as text are in details.psv. The first 40:\n'
		printf '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n'
		sed -n '1,41s/^/  /p' "$OUT/q2-different.psv"
		printf '\n'
	fi
	printf 'FINDINGS\n'
	if [ "$Q2_BAD" -gt 0 ]; then
		printf '  question 2: the two rollups DISAGREE on %s hours (see above)\n' "$Q2_BAD"
	else
		printf '  question 2: the two rollups agree, as text, on every one of the %s hours compared\n' \
			"$(awk 'NR > 1' "$OUT/compare.psv" | awk 'END { print NR }')"
	fi
	if [ -z "$CTL_BND" ]; then
		printf '  control: none (no finite boundary)\n'
	elif [ "$CTL_BAD" -gt 0 ] || [ "$CTL15_BAD" -gt 0 ]; then
		printf '  control: %s of %s hours NOT SAME, and %s with 15 minute rows that differ;\n' "$CTL_BAD" "$CTL_N" "$CTL15_BAD"
		printf '  the script or the functions are wrong somewhere. They are in control-not-same.psv;\n'
		printf '  the first 40:\n'
		sed -n '1,41s/^/  /p' "$OUT/control-not-same.psv"
	else
		printf '  control: all %s hours at or after the boundary are same, and their stored 15\n' "$CTL_N"
		printf '  minute rows match the function'"'"'s (control.psv)\n'
	fi
	if [ "$N_FAILED" -gt 0 ]; then
		printf '  NOT COMPLETE: %s hours could not be compared (failed.psv, out/*.err)\n' "$N_FAILED"
	fi
	[ "$INTERRUPTED" -eq 0 ] || printf '  NOT COMPLETE: the run was interrupted\n'
	if [ "$HIST15_BAD" -gt 0 ]; then
		printf '  note: %s hours before the boundary have stored 15 minute rows that differ from the\n' "$HIST15_BAD"
		printf '  function'"'"'s slots, or that it does not return (f15 in compare.psv)\n'
	fi
	printf '\n'
	cat "$OUT/summary-body.tmp"
	printf '\nFiles: see the header of net540-history-compare.sh. Exit status %s.\n' "$EXIT_STATUS"
} >"$OUT/summary.txt"
rm -f "$OUT/summary-body.tmp" "$OUT/findings.tmp" "$OUT/by-year-signature.tmp" "$OUT/examples.tmp" \
	"$OUT/value-abs.tmp"

if [ "$Q2_BAD" -gt 0 ]; then
	note "!!! QUESTION 2: THE TWO ROLLUPS DISAGREE on $Q2_BAD hours of $Q2_BAD_STREAMS streams (q2-different.psv) !!!"
else
	note "Question 2: the two rollups agree on every hour compared"
fi
note "Control: $CTL_N hours, $CTL_BAD not same, $CTL15_BAD with 15 minute rows that differ"
[ "$N_FAILED" -eq 0 ] || note "$N_FAILED hours could not be compared"
note "Read $OUT/summary.txt"
finish "$EXIT_STATUS"
exit "$EXIT_STATUS"
