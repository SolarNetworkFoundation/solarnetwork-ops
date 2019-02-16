#!/usr/bin/env bash

# Script to mark aggregate datum as "stale" over a time range, by
# iterating backwards in time over months, marking all records for
# each month as stale and then waiting for those records to be processed
# before moving on to the next month.
#
# Designed for use on BSD (including macOS).

s="${1:-2018-06-01}"
e="${2:-2017-01-01}"
psql_args=${3:--h postgres96 -d solarnetwork -U solarnet -p 5496}
stale_done_threshold=500
stale_check_delay_secs=60
stale_count_sql="select count(*) from solaragg.agg_stale_datum where agg_kind = 'h'"

# convert end date into epoch, for -ge comparison later
endEpoch=$(date -j -f '%Y-%m-%d %H:%M:%S %Z' "$e 00:00:00 GMT" '+%s')

# copy start date into "current" date
d="$s"

# convert current date into epoch, for -ge comparison later and -r arg to date
dEpoch=$(date -j -f '%Y-%m-%d %H:%M:%S %Z' "$s 00:00:00 GMT" '+%s')

tsMsg () {
	echo "$(date '+%Y-%m-%d %H:%M:%S %Z') : $1"
}

tsMsgIntermediate () {
	echo -n "$(date '+%Y-%m-%d %H:%M:%S %Z') : $1... "
}

waitForStaleProcessed () {
	stale_count=$(psql $psql_args -t -A -c "$stale_count_sql")
	while [ "$stale_count" -gt "$stale_done_threshold" ]; do
		tsMsg "Waiting for $stale_count stale records to fall below $stale_done_threshold $1"
		sleep $stale_check_delay_secs
		stale_count=$(psql $psql_args -t -A -c "$stale_count_sql")
	done
}

handleDateRange () {
	tsMsgIntermediate "Marking datum from $1 to $2 stale"
	psql $psql_args -t -A <<EOF
insert into solaragg.agg_stale_datum (ts_start, node_id, source_id, agg_kind, created)
select ts_start, node_id, source_id, 'h', CURRENT_TIMESTAMP
from (
	select distinct date_trunc('hour', ts) as ts_start, node_id, source_id
	from solardatum.da_datum
	where ts >= '$1 00:00Z'::timestamptz and ts < '$2 00:00Z'::timestamptz
) d
on conflict do nothing
EOF
}

# loop backwards in time
while [ "$dEpoch" -ge "$endEpoch" ]; do

	# create d2 as d + 1 month
	d2=$(date -j -r $dEpoch -v +1m '+%Y-%m-%d')
	
	waitForStaleProcessed "before processing $d"
	
	handleDateRange "$d" "$d2"
	
	# subtract one month from d1
	d=$(date -j -r $dEpoch -v -1m '+%Y-%m-%d')
	dEpoch=$(date -j -f '%Y-%m-%d %H:%M:%S %Z' "$d 00:00:00 GMT" '+%s')
done
