#!/bin/sh

# Perform chunk index maintenance by iterating over the rows returned from
# the find_chunk_index_need_reindex_maint() function and
# calling perform_one_chunk_reindex_maintenance() on each of those, followed
# by calling the find_chunk_index_need_cluster_maint() function and calling
# perform_one_chunk_cluster_maintenance() on each of those.
#
# Note that the -n command line switch must be provided to actually perform
# the maintenance, otherwise just the indexes requiring the maintenance will
# be printed out.

PSQL=$(which psql)
PSQL_CONN_ARGS='-h tsdb -d solarnetwork -U postgres'
CHUNK_MIN_AGE='1 week'
CHUNK_MAX_AGE='24 weeks'
REINDEX_MIN_AGE='11 weeks'
NOT_DRY_RUN='FALSE'

while getopts ":c:e:np:r:s:" opt; do
	case $opt in
		c) PSQL_CONN_ARGS="${OPTARG}";;
		e) CHUNK_MAX_AGE="${OPTARG}";;
		n) NOT_DRY_RUN='TRUE';;
		p) PSQL="${OPTARG}";;
		r) REINDEX_MIN_AGE="${OPTARG}";;
		s) CHUNK_MIN_AGE="${OPTARG}";;
		?)
			echo "Unknown argument: ${OPTARG}"
			exit 1
	esac
done
shift $(($OPTIND - 1))

maint_tables=$($PSQL -A -t ${PSQL_CONN_ARGS} -F ' ' -c "SELECT schema_name,table_name,index_name FROM _timescaledb_solarnetwork.find_chunk_index_need_reindex_maint(chunk_max_age => interval '${CHUNK_MAX_AGE}', chunk_min_age => interval '${CHUNK_MIN_AGE}', reindex_min_age => interval '${REINDEX_MIN_AGE}')")

echo "$maint_tables" |while read c_schema c_table c_index; do
	if [ -z "${c_schema}" ]; then
		continue;
	fi
	if [ "${NOT_DRY_RUN}" = 'FALSE' ]; then
		printf '[DRY RUN] '
	fi
	echo "Performing reindex maintenance on ${c_schema}.${c_table} [${c_index}]"
	$PSQL ${PSQL_CONN_ARGS} -c "SELECT * FROM _timescaledb_solarnetwork.perform_one_chunk_reindex_maintenance('${c_schema}','${c_table}','${c_index}',$NOT_DRY_RUN)"
done

maint_tables=$($PSQL -A -t ${PSQL_CONN_ARGS} -F ' ' -c "SELECT schema_name,table_name,index_name FROM _timescaledb_solarnetwork.find_chunk_index_need_cluster_maint(chunk_max_age => interval '${CHUNK_MAX_AGE}', chunk_min_age => interval '${CHUNK_MIN_AGE}', reindex_min_age => interval '${REINDEX_MIN_AGE}')")

echo "$maint_tables" |while read c_schema c_table c_index; do
	if [ -z "${c_schema}" ]; then
		continue;
	fi
	if [ "${NOT_DRY_RUN}" = 'FALSE' ]; then
		printf '[DRY RUN] '
	fi
	echo "Performing cluster maintenance on ${c_schema}.${c_table} [${c_index}]"
	$PSQL ${PSQL_CONN_ARGS} -c "SELECT * FROM _timescaledb_solarnetwork.perform_one_chunk_cluster_maintenance('${c_schema}','${c_table}','${c_index}',$NOT_DRY_RUN)"
done
