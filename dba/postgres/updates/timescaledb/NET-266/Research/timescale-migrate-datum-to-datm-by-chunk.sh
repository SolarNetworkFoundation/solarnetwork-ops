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

echo `date` "Creating da_datm hypertable"

# initial hypertable chunk size 1 year; drop extra index first for faster insert
psql -q -h $HOST -p $PORT -U $USER -d $DB \
	-c \
	"DROP INDEX IF EXISTS solardatm.da_datm_unq_reverse" \
	-c \
	"ALTER INDEX solardatm.da_datm_pkey SET TABLESPACE solarindex" \
	-c \
	"SELECT * FROM public.create_hypertable(
	'solardatm.da_datm'::regclass,
	'ts'::name,
	chunk_time_interval => interval '360 days',
	create_default_indexes => FALSE)"

echo `date` "Starting datum migration"

# load oldest data into 1-year chunks
migrate_datum_range '2009-12-01 13:00:00+13' '2015-11-01 13:00:00+13'

# now bump down chunk interval to 60 days as data volume increased
psql -q -h $HOST -p $PORT -U $USER -d $DB -c \
	"SELECT public.set_chunk_time_interval('solardatm.da_datm', INTERVAL '60 days')"

# load remaining data into 60-day chunks
migrate_datum_range '2015-11-01 13:00:00+13' '2021-01-01 00:00:00+13'

# migrate location datum
migrate_loc_datum_range '2008-01-02 01:00:00+13' '2022-01-01 00:00:00+13'

# recreate dropped index
echo `date` "Recreating da_datm_unq_reverse index"
time psql -q -h $HOST -p $PORT -U $USER -d $DB \
	-c \
	"CREATE UNIQUE INDEX IF NOT EXISTS da_datm_unq_reverse
	ON solardatm.da_datm (stream_id, ts DESC) TABLESPACE solarindex"

echo `date` Finished datum migration
