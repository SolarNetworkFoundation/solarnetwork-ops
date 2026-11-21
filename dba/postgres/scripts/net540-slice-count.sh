#!/bin/sh
# NET-540: count the raw datum stored as array slices on the stream-days that a
# run of net540-history-compare.sh sampled (plan section 12.4).
#
# A datum that lacks its stream's first property was stored, until central
# bbd88b8b2 (2021-02-09) for node datum and to this day for location datum, as
# an array with a lower bound above 1, such as [2:3]={102700,13.8}. pad_vec()
# and the vec_agg functions ignore the lower bound, so the hourly rollup and
# rollup_datm_15m_for_hour() put those values one or more places early, under
# the wrong property.
#
# Read-only: every statement is a SELECT on solardatm.da_datm for one stream
# and one day, through the primary key, with the stream and times as literals.
# It reads the rows the compare run already read, once.
#
# Usage:
#   net540-slice-count.sh [-h host] [-p port] [-U user] [-d dbname]
#                         [-P pause] [-t timeout] RUN_DIRECTORY
#
#   -P  seconds to pause after every 20 stream-days (default 0.5)
#   -t  statement timeout in seconds (default 60)
#
# RUN_DIRECTORY is the output directory of net540-history-compare.sh. This
# reads its targets.psv and writes there:
#   sql/slices.sql   the statements (holds stream ids)
#   slices.psv       tid|datum|slice_i|slice_a|slice_s|slice_any
#   slices.txt       the table below, counts only
#
# Needs psql and awk. Exit status: 0 done, 2 did not run, 3 incomplete.

set -u

HOST=''
PORT=''
DBUSER=''
DBNAME=''
PAUSE=0.5
TIMEOUT=60

die() {
	printf '%s\n' "$*" >&2
	exit 2
}

while getopts 'h:p:U:d:P:t:' opt; do
	case $opt in
	h) HOST=$OPTARG ;;
	p) PORT=$OPTARG ;;
	U) DBUSER=$OPTARG ;;
	d) DBNAME=$OPTARG ;;
	P) PAUSE=$OPTARG ;;
	t) TIMEOUT=$OPTARG ;;
	*) die "usage: $0 [-h host] [-p port] [-U user] [-d dbname] [-P pause] [-t timeout] RUN_DIRECTORY" ;;
	esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || die "usage: $0 [-h host] [-p port] [-U user] [-d dbname] [-P pause] [-t timeout] RUN_DIRECTORY"
RUN=${1%/}
[ -r "$RUN/targets.psv" ] || die "no targets.psv in $RUN"
case $PAUSE in '' | *[!0-9.]*) die "-P takes seconds" ;; esac
case $TIMEOUT in '' | *[!0-9]*) die "-t takes whole seconds" ;; esac
mkdir -p "$RUN/sql" || die "cannot write to $RUN"

SQL=$RUN/sql/slices.sql
OUT=$RUN/slices.psv
TXT=$RUN/slices.txt
ERR=$RUN/slices.err

# one statement for each stream-day; anything that is not a uuid or a timestamp
# stops the run before it connects
awk -F'|' -v pause="$PAUSE" -v timeout="$TIMEOUT" '
	BEGIN {
		print "\\set ON_ERROR_STOP 1"
		print "SET default_transaction_read_only = on;"
		print "SET statement_timeout = \047" timeout "s\047;"
		print "SET lock_timeout = \0475s\047;"
		print "SET jit = off;"
		print "SET timezone = \047UTC\047;"
	}
	NR == 1 {
		for (i = 1; i <= NF; i++) col[$i] = i
		if (!("tid" in col) || !("stream_id" in col) || !("start" in col) || !("end" in col)) { print "targets.psv: columns missing" > "/dev/stderr"; bad = 1; exit }
		next
	}
	{
		tid = $col["tid"]; sid = $col["stream_id"]; s = $col["start"]; e = $col["end"]
		if (tid !~ /^[A-Z][0-9]+$/ || sid !~ /^[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+$/ || length(sid) != 36 \
				|| s !~ /^[0-9]+-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9][+][0-9][0-9]$/ \
				|| e !~ /^[0-9]+-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9][+][0-9][0-9]$/) {
			print "targets.psv line " NR ": not a stream-day" > "/dev/stderr"; bad = 1; exit
		}
		printf "SELECT \047%s\047, count(*)", tid
		printf ", count(*) FILTER (WHERE array_lower(data_i, 1) > 1)"
		printf ", count(*) FILTER (WHERE array_lower(data_a, 1) > 1)"
		printf ", count(*) FILTER (WHERE array_lower(data_s, 1) > 1)"
		printf ", count(*) FILTER (WHERE array_lower(data_i, 1) > 1 OR array_lower(data_a, 1) > 1 OR array_lower(data_s, 1) > 1)"
		printf " FROM solardatm.da_datm WHERE stream_id = \047%s\047::uuid AND ts >= \047%s\047::timestamptz AND ts < \047%s\047::timestamptz;\n", sid, s, e
		if (++n % 20 == 0 && pause + 0 > 0) print "SELECT pg_sleep(" pause ") \\g /dev/null"
	}
	END { if (bad) exit 1 }
' "$RUN/targets.psv" > "$SQL" || die "could not build $SQL"

WANT=$(grep -c "^SELECT '[A-Z][0-9]*', count" "$SQL")
[ "$WANT" -gt 0 ] || die "no stream-days in $RUN/targets.psv"

set -- -X -q -A -t -F '|' -v ON_ERROR_STOP=1
[ -n "$HOST" ] && set -- "$@" -h "$HOST"
[ -n "$PORT" ] && set -- "$@" -p "$PORT"
[ -n "$DBUSER" ] && set -- "$@" -U "$DBUSER"
[ -n "$DBNAME" ] && set -- "$@" -d "$DBNAME"

printf '%s stream-days to read\n' "$WANT" >&2
psql "$@" -f "$SQL" > "$OUT.tmp" 2> "$ERR"
RC=$?
{
	echo 'tid|datum|slice_i|slice_a|slice_s|slice_any'
	grep '^[A-Z][0-9]*|' "$OUT.tmp"
} > "$OUT"
rm -f "$OUT.tmp"
GOT=$(($(wc -l < "$OUT") - 1))

awk -F'|' '
	FNR == 1 { f++; if (f == 1) for (i = 1; i <= NF; i++) col[$i] = i; next }
	f == 1 { year[$col["tid"]] = ($col["kind"] == "C" ? "ctl" : $col["year"]); obj[$col["tid"]] = $col["obj"]; next }
	{
		k = year[$1] SUBSEP obj[$1]
		if (!(k in days)) { order[++nk] = k }
		days[k]++; datum[k] += $2; si[k] += $3; sa[k] += $4; ss[k] += $5; any[k] += $6
		if ($6 > 0) dany[k]++
		if ($2 > 0) dwith[k]++
	}
	END {
		printf "%-5s %-4s %6s %9s %10s %9s %8s %8s %8s %8s\n", "year", "kind", "days", "with_raw", "with_slice", "datum", "slice_i", "slice_a", "slice_s", "any"
		# sort the keys: year, then kind
		for (i = 1; i <= nk; i++) for (j = i + 1; j <= nk; j++) if (order[j] < order[i]) { t = order[i]; order[i] = order[j]; order[j] = t }
		for (i = 1; i <= nk; i++) {
			k = order[i]; split(k, p, SUBSEP)
			printf "%-5s %-4s %6d %9d %10d %9d %8d %8d %8d %8d\n", p[1], p[2], days[k], dwith[k], dany[k], datum[k], si[k], sa[k], ss[k], any[k]
			T[p[2], "days"] += days[k]; T[p[2], "dwith"] += dwith[k]; T[p[2], "dany"] += dany[k]; T[p[2], "datum"] += datum[k]
			T[p[2], "si"] += si[k]; T[p[2], "sa"] += sa[k]; T[p[2], "ss"] += ss[k]; T[p[2], "any"] += any[k]; seen[p[2]] = 1
		}
		for (o in seen) printf "%-5s %-4s %6d %9d %10d %9d %8d %8d %8d %8d\n", "all", o, T[o, "days"], T[o, "dwith"], T[o, "dany"], T[o, "datum"], T[o, "si"], T[o, "sa"], T[o, "ss"], T[o, "any"]
		print ""
		print "kind: n node, l location; ctl: the control group, the last hours before the"
		print "compare run. days: stream-days read; with_raw: those with raw datum;"
		print "with_slice: those with a datum stored as a slice; slice_i, slice_a, slice_s:"
		print "datum whose instantaneous, accumulating or status array is a slice."
	}
' "$RUN/targets.psv" "$OUT" > "$TXT"
cat "$TXT"

if [ "$RC" -ne 0 ] || [ "$GOT" -ne "$WANT" ]; then
	printf 'incomplete: %s of %s stream-days read (psql exit %s); see %s\n' "$GOT" "$WANT" "$RC" "$ERR" >&2
	exit 3
fi
[ -s "$ERR" ] || rm -f "$ERR"
exit 0
