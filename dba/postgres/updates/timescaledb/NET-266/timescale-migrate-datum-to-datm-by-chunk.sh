#!/bin/sh

HOST="tsdb"
PORT="5432"
USER="solarnet"
DB="solarnetwork"

STAGE2="false"
STAGE1_DATE="2020-11-15 00:00:00+13"

do_help () {
	cat 1>&2 <<EOF
Usage: $0 -d <db name> -h <host> -p <port> -U <user> [-E <date>] [-2]

Migrate date in two stages. In the first stage, hypertables are created and all data up to a cutoff
date is migrated. In the second stage (by passing the -2 argument) all data after the cutoff date
is migrated. This process is to allow for migrating most data while SolarNetwork is still online.
The second stage is meant to be done when SolarNetwork is offline.

Arguments:

 -2                  - stage 2 mode; if not provided then stage 1 is assumed
 -d <db name>        - the database name; defaults to 'solarnetwork'
 -h <host>           - the host name; defaults to 'tsdb'
 -p <port>           - the port; defaults to '5432'
 -U <user>           - the user; defaults to 'solarnet'
 -E <date>           - the stage cutoff date, in YYYY-MM-dd HH:mm:ss+ZZ format;
                       defaults to '2020-11-15 00:00:00+13'
EOF
}

while getopts ":2d:E:h:p:U:" opt; do
	case $opt in
		d) solarnetwork="${OPTARG}";;
		E) STAGE1_DATE="${OPTARG}";;
		2) STAGE2='true';;
		h) HOST="${OPTARG}";;
		p) PORT="${OPTARG}";;
		U) USER="${OPTARG}";;
		*)
			echo "Unknown argument: ${OPTARG}"
			do_help
			exit 1
	esac
done
shift $(($OPTIND - 1))

migrate_datum_range () {
	local start_date="$1"
	local end_date="$2"
	for chunk in $(psql -Aqt -h $HOST -p $PORT -U $USER -d $DB -c \
			"SELECT chunk_table FROM chunk_relation_size_pretty('solardatum.da_datum')
			WHERE lower(ranges[1]::tstzrange) >= '$start_date'::timestamptz
			AND lower(ranges[1]::tstzrange) < '$end_date'::timestamptz
			ORDER BY lower(ranges[1]::tstzrange)"); do
		echo `date` "Migrating chunk $chunk..."
		time psql -q -h $HOST -p $PORT -U $USER -d $DB -c '\pset pager off' -c \
			"WITH ranges AS (
				SELECT d.node_id, d.source_id, min(d.ts) AS ts_min, max(d.ts) AS ts_max
				FROM $chunk d
				GROUP BY d.node_id, d.source_id
			)
			SELECT * FROM ranges, solardatm.migrate_datum(ranges.node_id, ranges.source_id,
				ranges.ts_min, ranges.ts_max + interval '1 ms') AS migrated" 2>&1
	done
}

migrate_loc_datum_range () {
	local start_date="$1"
	local end_date="$2"
	for chunk in $(psql -Aqt -h $HOST -p $PORT -U $USER -d $DB -c \
			"SELECT chunk_table FROM chunk_relation_size_pretty('solardatum.da_loc_datum')
			WHERE lower(ranges[1]::tstzrange) >= '$start_date'::timestamptz
			AND lower(ranges[1]::tstzrange) < '$end_date'::timestamptz
			ORDER BY lower(ranges[1]::tstzrange)"); do
		echo `date` "Migrating chunk $chunk..."
		time psql -q -h $HOST -p $PORT -U $USER -d $DB -c '\pset pager off' -c \
			"WITH ranges AS (
				SELECT d.loc_id, d.source_id, min(d.ts) AS ts_min, max(d.ts) AS ts_max
				FROM $chunk d
				GROUP BY d.loc_id, d.source_id
			)
			SELECT * FROM ranges, solardatm.migrate_loc_datum(ranges.loc_id, ranges.source_id,
				ranges.ts_min, ranges.ts_max + interval '1 ms') AS migrated" 2>&1
	done
}

if [ "$STAGE2" != 'true' ]; then
	echo `date` "Creating da_datm hypertable"

	# initial hypertable chunk size 1 year; drop extra index first for faster insert
	psql -q -h $HOST -p $PORT -U $USER -d $DB -c \
		"SELECT * FROM public.create_hypertable(
		'solardatm.da_datm'::regclass,
		'ts'::name,
		chunk_time_interval => interval '360 days',
		create_default_indexes => FALSE)"

	echo `date` "Starting Stage 1 datum migration to ${STAGE1_DATE}..."

	# load oldest data into 1-year chunks
	migrate_datum_range '2009-12-01 13:00:00+13' '2015-11-01 13:00:00+13'

	# now bump down chunk interval to 60 days as data volume increased
	psql -q -h $HOST -p $PORT -U $USER -d $DB -c \
		"SELECT public.set_chunk_time_interval('solardatm.da_datm', INTERVAL '60 days')"

	# load remaining data into 60-day chunks
	migrate_datum_range '2015-11-01 13:00:00+13' "$STAGE1_DATE"

	# migrate location datum
	migrate_loc_datum_range '2008-01-02 01:00:00+13' "$STAGE1_DATE"

	echo `date` "Finished Stage 1 datum migration to ${STAGE1_DATE}."
else
	echo `date` "Starting Stage 2 datum migration from ${STAGE1_DATE}..."

	# load remaining datum
	migrate_datum_range "$STAGE1_DATE" '2222-01-01 00:00:00+13'

	# migrate location datum
	migrate_loc_datum_range "$STAGE1_DATE" '2222-01-01 00:00:00+13'

	echo `date` "Finished Stage 2 datum migration from ${STAGE1_DATE}."
fi
