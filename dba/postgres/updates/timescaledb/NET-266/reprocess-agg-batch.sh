#!/bin/sh

HOST="tsdb"
PORT="5432"
USER="solarnet"
DB="solarnetwork"

MIN_DATE=""
MAX_DATE="2021-02-01 00:00:00+13"
BATCH_SIZE="1000"

do_help () {
	cat 1>&2 <<EOF
Usage: $0 -d <db name> -h <host> -p <port> -U <user> [-E <date>] [-2]

Migrate date in two stages. In the first stage, hypertables are created and all data up to a cutoff
date is migrated. In the second stage (by passing the -2 argument) all data after the cutoff date
is migrated. This process is to allow for migrating most data while SolarNetwork is still online.
The second stage is meant to be done when SolarNetwork is offline.

Arguments:

 -d <db name>        - the database name; defaults to 'solarnetwork'
 -h <host>           - the host name; defaults to 'tsdb'
 -p <port>           - the port; defaults to '5432'
 -U <user>           - the user; defaults to 'solarnet'
 -e <date>           - the optional minimum date to process
 -E <date>           - the maximum aggregate date to process
 -S <size>           - the maximum batch size (number of rows per transaction)
EOF
}

while getopts ":d:e:E:h:p:S:U:" opt; do
	case $opt in
		d) solarnetwork="${OPTARG}";;
		e) MIN_DATE="${OPTARG}";;
		E) MAX_DATE="${OPTARG}";;
		h) HOST="${OPTARG}";;
		p) PORT="${OPTARG}";;
		S) BATCH_SIZE="${OPTARG}";;
		U) USER="${OPTARG}";;
		*)
			echo "Unknown argument: ${OPTARG}"
			do_help
			exit 1
	esac
done
shift $(($OPTIND - 1))

reprocess_agg () {
	local agg_kind="$1"
	local n="0"
	while true; do
		printf '%s Processing %s max %d: ' "$(date)" "$agg_kind" "$BATCH_SIZE"
		if [ -n "$MIN_DATE" ]; then
			n=$(psql -Aqt -h $HOST -p $PORT -U $USER -d $DB -F $'\t' \
				-c '\pset pager off' \
				-c \
				"SELECT solardatm.reprocess_agg_stale_datm('${agg_kind}',
				'${MAX_DATE}'::timestamptz, ${BATCH_SIZE}, '${MIN_DATE}'::timestamptz)")
		else
			n=$(psql -Aqt -h $HOST -p $PORT -U $USER -d $DB -F $'\t' \
				-c '\pset pager off' \
				-c \
				"SELECT solardatm.reprocess_agg_stale_datm('${agg_kind}',
				'${MAX_DATE}'::timestamptz, ${BATCH_SIZE})")
		fi
		printf '%4d\n' "$n"
		[ ${n:-0} -le 0 ] && break
	done
}

if [ -n "$MIN_DATE" ]; then
	echo `date` "Starting agg reprocessing from ${MIN_DATE} to ${MAX_DATE}..."
else
	echo `date` "Starting agg reprocessing to ${MAX_DATE}..."
fi

reprocess_agg 'h'
reprocess_agg 'd'
reprocess_agg 'M'

if [ -n "$MIN_DATE" ]; then
	echo `date` "Finished agg reprocessing from ${MIN_DATE} to ${MAX_DATE}."
else
	echo `date` "Finished agg reprocessing to ${MAX_DATE}."
fi
