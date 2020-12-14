#!/bin/sh

HOST="tsdb"
PORT="5432"
USER="solarnet"
DB="solarnetwork"

while getopts ":d:h:p:U:" opt; do
	case $opt in
		d) solarnetwork="${OPTARG}";;
		h) HOST="${OPTARG}";;
		p) PORT="${OPTARG}";;
		U) USER="${OPTARG}";;
		*)
			echo "Unknown argument: ${OPTARG}"
			exit 1
	esac
done
shift $(($OPTIND - 1))

create_aud_hypertable () {
	local agg="$1"
	local days="$2"

	echo `date` "Creating aud_acc_datm_$agg hypertable"

	psql -q -h $HOST -p $PORT -U $USER -d $DB -c \
		"SELECT * FROM public.create_hypertable(
		'solardatm.aud_acc_datm_$agg'::regclass,
		'ts_start'::name,
		chunk_time_interval => interval '$days days',
		create_default_indexes => FALSE)"
}

migrate_aud_acc_datum_range () {
	local agg="$1"
	local start_date="$2"
	local end_date="$3"
	local interval="$4"

	local s="$start_date"
	local e=""

	local cols="datum_count,datum_hourly_count,datum_daily_count,datum_monthly_count,processed"

	while true; do
		[ "$s" \< "$end_date" ] || break
		e=$(date -j -v+$interval -f '%Y-%m-%d' "$s" '+%Y-%m-%d')
		echo `date` "Migrating $agg audit acc datum range $s - $e... "
		time psql -At -h $HOST -p $PORT -U $USER -d $DB -c '\pset pager off' -c \
			"INSERT INTO solardatm.aud_acc_datm_$agg (stream_id,ts_start,$cols)
			SELECT stream_id,ts_start,$cols
			FROM solaragg.aud_acc_datum_$agg a
			INNER JOIN solardatm.da_datm_meta m ON m.node_id = a.node_id AND m.source_id = a.source_id
			WHERE a.ts_start >= '$s'::timestamptz AND a.ts_start < '$e'::timestamptz
			ON CONFLICT (stream_id, ts_start) DO NOTHING" 2>&1 || exit 1
		s="$e"
	done
}

migrate_aud_acc_daily () {
	create_aud_hypertable 'daily' '3650'

	echo `date` "Starting daily audit acc datum migration"

	migrate_aud_acc_datum_range 'daily' '2000-01-01' '2019-01-01' '1y'

	# now bump down chunk interval smaller as data volume increased
	psql -q -h $HOST -p $PORT -U $USER -d $DB -c \
		"SELECT public.set_chunk_time_interval('solardatm.aud_acc_datm_daily', INTERVAL '1825 days')"

	# load remaining data into smaller chunks
	migrate_aud_acc_datum_range 'daily' '2019-01-01' '2022-01-01' '1y'

	echo `date` 'Finished daily audit cc adatum migration'
}

migrate_aud_acc_daily
