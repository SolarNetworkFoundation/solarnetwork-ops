#!/usr/bin/env bash

# Perform chunk index maintenance by iterating over the rows returned from
# the find_chunk_index_need_reindex_maint() function and
# calling perform_one_chunk_reindex_maintenance() on each of those, followed
# by calling the find_chunk_index_need_cluster_maint() function and calling
# perform_one_chunk_cluster_maintenance() on each of those.
#
# Note that the -n command line switch must be provided to actually perform
# the maintenance, otherwise just the indexes requiring the maintenance will
# be printed out.
#
# Note this script has a single bash-ism, by using the <<< "here string" redirection.
# That was added to work around the previous sub-shell approach that prevented changing
# the PAUSED variable inside the sub-shell.

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

# pull in solar-jobs.sh so we can pause/resume the SolarNet job scheduler during the maintenance
NETRC_FILE="/usr/local/pgsql/netrc/solarjobs-admin"
PRETTYJSON="/usr/local/bin/python2.7 -m json.tool"
if [ -e /solar93/share/solar-jobs.sh ]; then
	. /solar93/share/solar-jobs.sh
fi

PAUSED=0

maint_tables=$($PSQL -A -t ${PSQL_CONN_ARGS} -F ' ' -c "SELECT schema_name,table_name,index_name FROM _timescaledb_solarnetwork.find_chunk_index_need_reindex_maint(chunk_max_age => interval '${CHUNK_MAX_AGE}', chunk_min_age => interval '${CHUNK_MIN_AGE}', reindex_min_age => interval '${REINDEX_MIN_AGE}')")

while read c_schema c_table c_index; do
	if [ -z "${c_schema}" ]; then
		continue;
	fi
	if [ "${NOT_DRY_RUN}" = 'FALSE' ]; then
		printf '[DRY RUN] '
	elif [ "${PAUSED}" -eq 0 -a -n "${JOBAPI_BASE}" ]; then
		echo "Pausing SolarNet job scheduler..."
		pause_scheduler
		do_job_status
		wait_all_jobs_complete
		PAUSED=1
	fi
	echo "Performing reindex maintenance on ${c_schema}.${c_table} [${c_index}]"
	$PSQL ${PSQL_CONN_ARGS} -c "SELECT * FROM _timescaledb_solarnetwork.perform_one_chunk_reindex_maintenance('${c_schema}','${c_table}','${c_index}',$NOT_DRY_RUN)"
done <<< "$maint_tables"

maint_tables=$($PSQL -A -t ${PSQL_CONN_ARGS} -F ' ' -c "SELECT schema_name,table_name,index_name FROM _timescaledb_solarnetwork.find_chunk_index_need_cluster_maint(chunk_max_age => interval '${CHUNK_MAX_AGE}', chunk_min_age => interval '${CHUNK_MIN_AGE}', reindex_min_age => interval '${REINDEX_MIN_AGE}')")

while read c_schema c_table c_index; do
	if [ -z "${c_schema}" ]; then
		continue;
	fi
	if [ "${NOT_DRY_RUN}" = 'FALSE' ]; then
		printf '[DRY RUN] '
	fi
	echo "Performing cluster maintenance on ${c_schema}.${c_table} [${c_index}]"
	$PSQL ${PSQL_CONN_ARGS} -c "SELECT * FROM _timescaledb_solarnetwork.perform_one_chunk_cluster_maintenance('${c_schema}','${c_table}','${c_index}',$NOT_DRY_RUN)"
done <<< "$maint_tables"

if [ "${PAUSED}" -eq 1 ]; then
	echo "Resuming SolarNet job scheduler..."
	resume_scheduler
	do_job_status
else
	echo "SolarNet job scheduler was not paused, no need to resume."
fi
