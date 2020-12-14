#!/bin/sh
#
# Update the database to add support for NET-266 datm tables and supporting functions. Existing
# tables/functions are left unchanged.

HOST="tsdb"
PORT="5432"
USER="solarnet"

DRY_RUN=""
INDEX_TABLESPACE="solarindex"
PG_ADMIN_USER="postgres"
PG_DB="solarnetwork"
PSQL_CONN_ARGS=""
VERBOSE=""

while getopts ":d:h:i:p:U:v" opt; do
	case $opt in
		d) PG_DB="${OPTARG}";;
		h) HOST="${OPTARG}";;
		i) INDEX_TABLESPACE="${OPTARG}";;
		p) PORT="${OPTARG}";;
		U) USER="${OPTARG}";;
		v) VERBOSE='TRUE';;
		*)
			echo "Unknown argument: ${OPTARG}"
			exit 1
	esac
done
shift $(($OPTIND - 1))

PSQL_CONN_ARGS="-h $HOST -p $PORT"

START_DIR="$PWD"

# ---------

if [ ! -f ../../../setup/timescaledb/tsdb-init-utilities.sql ]; then
	echo 'The ../../../setup/timescaledb/tsdb-init-utilities.sql DDL is not found.'
	exit 1;
fi
if [ ! -f ../../../setup/timescaledb/init/postgres-init-datm-schema.sql ]; then
	echo 'The ../../../setup/timescaledb/init/postgres-init-datm-schema.sql DDL is not found.'
	exit 1;
fi

echo `date` "Creating datm schema..."
psql $PSQL_CONN_ARGS -U $USER -d $PG_DB -P pager=off \
	-f ../../../setup/timescaledb/tsdb-init-utilities.sql \
	-f ../../../setup/timescaledb/init/postgres-init-datm-schema.sql

# ---------

echo `date` "Adding datm support..."
psql $PSQL_CONN_ARGS -U $USER -d $PG_DB -P pager=off -f NET-266-add-datm.sql

# ---------

if [ -n "$INDEX_TABLESPACE" ]; then
	echo
	if [ -n "$VERBOSE" ]; then
		echo "Moving indexes to tablespace $INDEX_TABLESPACE..."
	fi
	if [ -n "$DRY_RUN" ]; then
		echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c 'SELECT * FROM public.set_index_tablespace(ARRAY[...], '$INDEX_TABLESPACE')'"
	else
		psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -P pager=off -At <<-EOF
			SELECT stmt || ';' FROM (SELECT unnest(ARRAY['solardatm']) AS schem) AS s,
			LATERAL (SELECT * FROM public.set_index_tablespace(s.schem, '$INDEX_TABLESPACE')) AS res;
		EOF
	fi
fi

# ---------

if [ -n "$VERBOSE" ]; then
	echo "Setting up permissions on solardatm schema..."
fi
if [ -n "$DRY_RUN" ]; then
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -f NET-266-add-permissions.sql"
else
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -P pager=off -f NET-266-add-permissions.sql
fi


echo `date` "Finished adding datm support."
