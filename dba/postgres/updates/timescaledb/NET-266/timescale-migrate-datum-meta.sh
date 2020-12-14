#!/bin/sh
#
# Migrate the da_meta and da_loc_meta tables
#
# NOTE: requires datum to have been migrated FIRST

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

migrate_datum_meta () {
	time psql -At -h $HOST -p $PORT -U $USER -d $DB -c '\pset pager off' -c \
		"UPDATE solardatm.da_datm_meta SET jdata = a.jdata
		FROM solardatum.da_meta a
		WHERE da_datm_meta.node_id = a.node_id AND da_datm_meta.source_id = a.source_id" 2>&1 || exit 1
}

migrate_loc_datum_meta () {
	time psql -At -h $HOST -p $PORT -U $USER -d $DB -c '\pset pager off' -c \
		"UPDATE solardatm.da_loc_datm_meta SET jdata = a.jdata
		FROM solardatum.da_loc_meta a
		WHERE da_loc_datm_meta.loc_id = a.loc_id AND da_loc_datm_meta.source_id = a.source_id" 2>&1 || exit 1
}

migrate_datum_meta
migrate_loc_datum_meta
