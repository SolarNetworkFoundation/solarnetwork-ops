#!/bin/sh

HOST="tsdb"
PORT="5432"
USER="solarnet"
DB="solarnetwork"

migrate_range () {
	local start_date="$1"
	local end_date="$2"
	for chunk in $(psql -Aqt -h $HOST -p $PORT -U $USER -d $DB -c \
			"SELECT chunk_table FROM chunk_relation_size_pretty('solardatum.da_datum')
			WHERE lower(ranges[1]::tstzrange) >= '$start_date'::timestamptz
			AND lower(ranges[1]::tstzrange) < '$end_date'::timestamptz
			ORDER BY lower(ranges[1]::tstzrange)"); do
		echo `date` "Migrating chunk $chunk..."
		time psql -q -h $HOST -p $PORT -U $USER -d $DB -c '\pset pager off' -c \
			"WITH months AS (
				SELECT d.node_id, date_trunc('month', d.ts) AS ts_start, d.source_id
				FROM $chunk d
				GROUP BY d.node_id, date_trunc('month', d.ts), d.source_id
			)
			SELECT * FROM months, solardatm.migrate_datum(months.node_id, months.source_id,
				months.ts_start, months.ts_start + interval '1 month') AS migrated"
	done
}

echo `date` Creating da_datm hypertable

psql -q -h $HOST -p $PORT -U $USER -d $DB -c \
	"SELECT * FROM public.create_hypertable(
	'solardatm.da_datm'::regclass,
	'ts'::name,
	chunk_time_interval => interval '360 days',
	create_default_indexes => FALSE)"

echo `date` Starting datum migration

migrate_range '2009-12-01 13:00:00+13' '2015-11-01 13:00:00+13'

psql -q -h $HOST -p $PORT -U $USER -d $DB -c \
	"SELECT public.set_chunk_time_interval('solardatm.da_datm', INTERVAL '60 days')"

migrate_range '2015-11-01 13:00:00+13' '2020-12-04 13:00:00+13'

echo `date` Finished datum migration
