#!/bin/sh
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

migrate_datum_aux () {
	time psql -At -h $HOST -p $PORT -U $USER -d $DB -c '\pset pager off' -c \
		"INSERT INTO solardatm.da_datm_aux (stream_id,ts,atype,updated,notes,jdata_af,jdata_as,jmeta)
		SELECT stream_id,ts,atype::text::solardatm.da_datm_aux_type,a.updated,notes,jdata_af,jdata_as,jmeta
		FROM solardatum.da_datum_aux a
		INNER JOIN solardatm.da_datm_meta m ON m.node_id = a.node_id AND m.source_id = a.source_id
		ON CONFLICT (stream_id, ts, atype) DO NOTHING" 2>&1 || exit 1
}

migrate_datum_aux
