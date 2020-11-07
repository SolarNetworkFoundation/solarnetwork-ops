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

	echo `date` "Creating aud_datm_$agg hypertable"

	psql -q -h $HOST -p $PORT -U $USER -d $DB \
		-c \
		"ALTER INDEX solardatm.aud_datm_${agg}_pkey SET TABLESPACE solarindex" \
		-c \
		"SELECT * FROM public.create_hypertable(
		'solardatm.aud_datm_$agg'::regclass,
		'ts_start'::name,
		chunk_time_interval => interval '$days days',
		create_default_indexes => FALSE)"
}

migrate_aud_datum_range () {
	local agg="$1"
	local start_date="$2"
	local end_date="$3"
	local interval="$4"

	local s="$start_date"
	local e=""

	local cols="prop_count,datum_q_count,datum_count"

	if [ "$agg" = "daily" ]; then
		cols="$cols,datum_hourly_count,datum_daily_pres,processed_count,processed_hourly_count,processed_io_count"
	elif [ "$agg" = "monthly" ]; then
		cols="$cols,datum_hourly_count,datum_daily_count,datum_monthly_pres,processed"
	fi

	while true; do
		[ "$s" \< "$end_date" ] || break
		e=$(date -j -v+$interval -f '%Y-%m-%d' "$s" '+%Y-%m-%d')
		echo `date` "Migrating $agg audit datum range $s - $e... "
		time psql -At -h $HOST -p $PORT -U $USER -d $DB -c '\pset pager off' -c \
			"INSERT INTO solardatm.aud_datm_$agg (stream_id,ts_start,$cols)
			SELECT stream_id,ts_start,$cols
			FROM solaragg.aud_datum_$agg a
			INNER JOIN solardatm.da_datm_meta m ON m.node_id = a.node_id AND m.source_id = a.source_id
			WHERE a.ts_start >= '$s'::timestamptz AND a.ts_start < '$e'::timestamptz
			ON CONFLICT (stream_id, ts_start) DO NOTHING" 2>&1 || exit 1
		s="$e"
	done
}

migrate_aud_hourly () {
	create_aud_hypertable 'hourly' '3650'

	echo `date` "Starting hourly audit datum migration"

	migrate_aud_datum_range 'hourly' '2000-01-01' '2019-01-05' '1w'

	# now bump down chunk interval smaller as data volume increased
	psql -q -h $HOST -p $PORT -U $USER -d $DB -c \
		"SELECT public.set_chunk_time_interval('solardatm.aud_datm_hourly', INTERVAL '720 days')"

	# load remaining data into smaller chunks
	migrate_aud_datum_range 'hourly' '2019-01-05' '2022-01-01' '1w'

	echo `date` 'Finished hourly audit datum migration'
}

migrate_aud_daily () {
	create_aud_hypertable 'daily' '3650'

	echo `date` "Starting daily audit datum migration"

	migrate_aud_datum_range 'daily' '2000-01-01' '2019-01-01' '1y'

	# now bump down chunk interval smaller as data volume increased
	psql -q -h $HOST -p $PORT -U $USER -d $DB -c \
		"SELECT public.set_chunk_time_interval('solardatm.aud_datm_daily', INTERVAL '1825 days')"

	# load remaining data into smaller chunks
	migrate_aud_datum_range 'daily' '2019-01-01' '2022-01-01' '1y'

	echo `date` 'Finished daily audit datum migration'
}

migrate_aud_monthly () {
	create_aud_hypertable 'monthly' '3650'

	echo `date` "Starting monthly audit datum migration"

	migrate_aud_datum_range 'monthly' '2000-01-01' '2022-01-01' '10y'

	echo `date` 'Finished monthly audit datum migration'
}


migrate_aud_stale () {
	echo `date` "Migrating stale aud datum ... "
	time psql -At -h $HOST -p $PORT -U $USER -d $DB -c '\pset pager off' -c \
		"INSERT INTO solardatm.aud_stale_datm_daily (stream_id, ts_start, aud_kind, created)
		SELECT m.stream_id, s.ts_start, CASE s.aud_kind WHEN 'm' THEN 'M' ELSE s.aud_kind END AS aud_kind, s.created
		FROM solaragg.aud_datum_daily_stale s
		INNER JOIN solardatm.da_datm_meta m ON m.node_id = s.node_id AND m.source_id = s.source_id
		ON CONFLICT (aud_kind, ts_start, stream_id) DO NOTHING" 2>&1 || exit 1
}

migrate_aud_hourly
migrate_aud_daily
migrate_aud_monthly
migrate_aud_stale
