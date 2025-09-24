#!/usr/bin/env bash

# Script to populate the new solardatm.da_datm has_a column
#
# Designed for use on BSD (including macOS).

s="${1:-2008-01-01}"
e="${2:-2025-08-01}"
psql_args=${3:--h sndb -d solarnetwork -U solarnet -p 5432}

# convert end date into epoch, for -le comparison later
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

handleDateRange () {
	tsMsgIntermediate "Populdating da_datm $1 to $2 has_a column"

	psql $psql_args -t -A <<EOF
UPDATE solardatm.da_datm
SET has_a = CARDINALITY(data_a) > 0
WHERE ts >= '$1 00:00Z'::timestamptz
	AND ts < '$2 00:00Z'::timestamptz
EOF
}

# loop backwards in time
while [ "$dEpoch" -lt "$endEpoch" ]; do

	# create d2 as d + 1 day
	d2=$(date -j -r $dEpoch -v +1d '+%Y-%m-%d')

	handleDateRange "$d" "$d2"

	# add one month from d
	d="$d2"
	dEpoch=$(date -j -f '%Y-%m-%d %H:%M:%S %Z' "$d2 00:00:00 GMT" '+%s')
done

tsMsg "Done."
