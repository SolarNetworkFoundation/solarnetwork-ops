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

create_hypertable () {
	local agg="$1"
	local days="$2"

	echo `date` "Creating agg_datm_hourly hypertable"

	psql -q -h $HOST -p $PORT -U $USER -d $DB \
		-c \
		"ALTER INDEX solardatm.agg_datm_$agg_pkey SET TABLESPACE solarindex" \
		-c \
		"SELECT * FROM public.create_hypertable(
		'solardatm.agg_datm_$agg'::regclass,
		'ts_start'::name,
		chunk_time_interval => interval '$days days',
		create_default_indexes => FALSE)"
}

migrate_agg_datum_range () {
	local agg="$1"
	local start_date="$2"
	local end_date="$3"
	local interval="$4"

	local s="$start_date"
	local e=""
	while true; do
		[ "$s" \< "$end_date" ] || break
		e=$(date -j -v+$interval -f '%Y-%m-%d' "$s" '+%Y-%m-%d')
		echo `date` "Migrating $agg datum range $s - $e... "
		time psql -At -h $HOST -p $PORT -U $USER -d $DB -c '\pset pager off' -c \
			"INSERT INTO solardatm.agg_datm_$agg (stream_id, ts_start, data_i, data_a, data_s, data_t, stat_i, read_a)
			SELECT a.stream_id, a.ts_start, a.data_i, a.data_a, a.data_s, a.data_t, a.stat_i, a.read_a
			FROM solardatm.da_datm_meta m
			INNER JOIN solaragg.agg_datum_$agg d ON d.node_id = m.node_id AND d.source_id = m.source_id
			INNER JOIN solardatm.agg_json_datum_to_datm(m.stream_id, d.ts_start, d.jdata_i, d.jdata_a,
				d.jdata_s, d.jdata_t, d.jmeta, d.jdata_as, d.jdata_af, d.jdata_ad, m.names_i, m.names_a, m.names_s
			) a ON TRUE
			WHERE d.ts_start >= '$s'::timestamptz AND d.ts_start < '$e'::timestamptz
			ON CONFLICT (stream_id, ts_start) DO UPDATE
			SET data_i = EXCLUDED.data_i, data_a = EXCLUDED.data_a, data_s = EXCLUDED.data_s, data_t = EXCLUDED.data_t,
				stat_i = EXCLUDED.stat_i, read_a = EXCLUDED.read_a" 2>&1 || exit 1
		s="$e"
	done
}

migrate_agg_loc_datum_range () {
	local agg="$1"
	local start_date="$2"
	local end_date="$3"
	local interval="$4"

	local s="$start_date"
	local e=""
	while true; do
		[ "$s" \< "$end_date" ] || break
		e=$(date -j -v+$interval -f '%Y-%m-%d' "$s" '+%Y-%m-%d')
		echo `date` "Migrating $agg loc datum range $s - $e... "
		time psql -At -h $HOST -p $PORT -U $USER -d $DB -c '\pset pager off' -c \
			"INSERT INTO solardatm.agg_datm_$agg (stream_id, ts_start, data_i, data_a, data_s, data_t, stat_i, read_a)
			SELECT a.stream_id, a.ts_start, a.data_i, a.data_a, a.data_s, a.data_t, a.stat_i, a.read_a
			FROM solardatm.da_loc_datm_meta m
			INNER JOIN solaragg.agg_loc_datum_$agg d ON d.loc_id = m.loc_id AND d.source_id = m.source_id
			INNER JOIN solardatm.agg_json_datum_to_datm(m.stream_id, d.ts_start, d.jdata_i, d.jdata_a,
				d.jdata_s, d.jdata_t, d.jmeta, NULL::jsonb, NULL::jsonb, NULL::jsonb, m.names_i, m.names_a, m.names_s
			) a ON TRUE
			WHERE d.ts_start >= '$s'::timestamptz AND d.ts_start < '$e'::timestamptz
			ON CONFLICT (stream_id, ts_start) DO UPDATE
			SET data_i = EXCLUDED.data_i, data_a = EXCLUDED.data_a, data_s = EXCLUDED.data_s, data_t = EXCLUDED.data_t,
				stat_i = EXCLUDED.stat_i, read_a = EXCLUDED.read_a" 2>&1 || exit 1
		s="$e"
	done
}

migrate_hourly () {
	create_hypertable 'hourly' '730'

	echo `date` "Starting hourly datum migration"

	migrate_agg_datum_range 'hourly' '2000-01-01' '2019-01-05' '1w'

	# now bump down chunk interval smaller as data volume increased
	psql -q -h $HOST -p $PORT -U $USER -d $DB -c \
		"SELECT public.set_chunk_time_interval('solardatm.agg_datm_hourly', INTERVAL '180 days')"

	# load remaining data into smaller chunks
	migrate_agg_datum_range 'hourly' '2019-01-05' '2022-01-01' '1d'

	# migrate location datum
	migrate_agg_loc_datum_range 'hourly' '2000-01-01' '2022-01-01' '1w'

	echo `date` 'Finished hourly datum migration'
}

migrate_daily () {
	create_hypertable 'daily' '1460'

	echo `date` "Starting daily datum migration"

	migrate_agg_datum_range 'daily' '2000-01-01' '2018-01-01' '1m'

	# now bump down chunk interval smaller as data volume increased
	psql -q -h $HOST -p $PORT -U $USER -d $DB -c \
		"SELECT public.set_chunk_time_interval('solardatm.agg_datm_daily', INTERVAL '720 days')"

	# load remaining data into smaller chunks
	migrate_agg_datum_range 'daily' '2019-01-01' '2022-01-01' '1w'

	# migrate location datum
	migrate_agg_loc_datum_range 'daily' '2000-01-01' '2022-01-01' '1m'

	echo `date` 'Finished daily datum migration'
}

migrate_monthly () {
	create_hypertable 'monthly' '3650'

	echo `date` "Starting monthly datum migration"

	migrate_agg_datum_range 'monthly' '2000-01-01' '2022-01-01' '10y'

	migrate_agg_loc_datum_range 'monthly' '2000-01-01' '2022-01-01' '1y'

	echo `date` 'Finished monthly datum migration'
}


migrate_hourly
migrate_daily
migrate_monthly
