#!/usr/bin/env bash

# Script for creating or re-creating the SolarNetwork database in its TimescaleDB form.
# The resulting database is suitable for production deployments.
#
# To create a database 'solarnet_prod' and all associated users:
#
#     ./bin/setup-db.sh -mrv
#
# To create a database 'solarnetwork' and all associated users:
#
#     ./bin/setup-db.sh -mrv -d solarnetwork
#
# If Postgres is running on a non-standard port, or on a remote host, pass `psql` connection
# arguments via the -c switch:
#
#     ./bin/setup-db.sh -mrv -c '-p 5496 -h postgres96.example.com'

PSQL_CONN_ARGS=""
PG_DB_OWNER="solarnet"
PG_DB="solarnet_prod"
PG_ADMIN_USER="postgres"
PG_ADMIN_DB="postgres"
PG_TEMPLATE_DB="template0"
USER_ROLE_SCRIPT="tsdb-init-roles.sql"
RECREATE_DB=""
CREATE_USER=""
DRY_RUN=""
VERBOSE=""

while getopts ":c:d:D:mrtT:u:U:v" opt; do
	case $opt in
		c) PSQL_CONN_ARGS="${OPTARG}";;
		d) PG_DB="${OPTARG}";;
		D) PG_ADMIN_DB="${OPTARG}";;
		m) CREATE_USER='TRUE';;
		r) RECREATE_DB='TRUE';;
		R) USER_ROLE_SCRIPT="${OPTARG}";;
		t) DRY_RUN='TRUE';;
		T) PG_TEMPLATE_DB="${OPTARG}";;
		u) PG_DB_OWNER="${OPTARG}";;
		U) PG_ADMIN_USER="${OPTARG}";;
		v) VERBOSE='TRUE';;
		?)
			echo "Unknown argument ${OPTARG}"
			exit 1
	esac
done
shift $(($OPTIND - 1))

# Check that PostgreSQL is available
type psql &>/dev/null || { echo "psql command not found."; exit 1; }

# Check we appear to be in correct directory
if [ ! -e "tsdb-init.sql" ]; then
	echo "tsdb-init.sql DDL not found; please run this script in the same directory as that file.";
	exit 2;
fi
# Check we appear to be in correct directory
if [ ! -e "init/postgres-init.sql" ]; then
	echo "init/postgres-init.sql DDL not found; please make sure to link the solarnetwork-central/solarnet-db-setup/postgres";
	echo "directory as 'init', e.g. `ln -sf ~/solarnetwork-central/solarnet-db-setup/postgres init`.";
	exit 2;
fi


if [ -n "$RECREATE_DB" ]; then
	if [ -n "$VERBOSE" ]; then
		echo "Dropping database [$PG_DB]"
	fi
	if [ -n "$DRY_RUN" ]; then
		echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -c 'DROP DATABASE IF EXISTS $PG_DB'"
	else
		psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -c "DROP DATABASE IF EXISTS $PG_DB" || exit 3
	fi
fi

if [ -n "$CREATE_USER" ]; then
	if [ -n "$VERBOSE" ]; then
		echo "Creating database users via [$USER_ROLE_SCRIPT]"
	fi
	if [ -n "$DRY_RUN" ]; then
		echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -f $USER_ROLE_SCRIPT"
	else
		psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -f "$USER_ROLE_SCRIPT" || exit 4
	fi
fi

if [ -n "$VERBOSE" ]; then
	echo "Creating database [$PG_DB] with owner [$PG_DB_OWNER]"
fi
if [ -n "$DRY_RUN" ]; then
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -c 'CREATE DATABASE $PG_DB WITH ENCODING='UTF8' OWNER=$PG_DB_OWNER TEMPLATE=$PG_TEMPLATE_DB LC_COLLATE='C' LC_CTYPE='C''"
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c 'CREATE EXTENSION IF NOT EXISTS plv8 WITH SCHEMA pg_catalog'"
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c 'CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public'"
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public'"
else
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -c "CREATE DATABASE $PG_DB WITH ENCODING='UTF8' OWNER=$PG_DB_OWNER TEMPLATE=$PG_TEMPLATE_DB LC_COLLATE='C' LC_CTYPE='C'" || exit 5
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c "CREATE EXTENSION IF NOT EXISTS plv8 WITH SCHEMA pg_catalog" || exit 6
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c "CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public" || exit 7
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c "CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public" || exit 8
fi

if [ -n "$VERBOSE" ]; then
	echo "Creating plv8 scripts"
fi
if [ -n "$DRY_RUN" ]; then
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -f postgres-init-plv8.sql"
else		
	# for some reason, plv8 often chokes on the inline comments, so strip them out
	cd init
	sed -e '/^\/\*/d' -e '/^ \*/d' postgres-init-plv8.sql \
		| psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB || exit 9
	cd ..
fi

if [ -n "$VERBOSE" ]; then
	echo "Creating SolarNetwork database tables and functions"
fi
if [ -n "$DRY_RUN" ]; then
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -f tsdb-init.sql"
else		
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -P pager=off -qAtf tsdb-init.sql || exit 10
fi

if [ -n "$VERBOSE" ]; then
	echo "Applying production permissions"
fi
if [ -n "$DRY_RUN" ]; then
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c 'SELECT res.* FROM (SELECT unnest(ARRAY['quartz', 'solaragg', 'solarcommon', 'solardatum', 'solarnet', 'solaruser']) AS schem) AS s, LATERAL (SELECT * FROM public.set_ownership(s.schem, '$PG_DB_OWNER')) AS res;"
else		
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -P pager=off -qAtc "SELECT stmt || ';' FROM (SELECT unnest(ARRAY['quartz', 'solaragg', 'solarcommon', 'solardatum', 'solarnet', 'solaruser']) AS schem) AS s, LATERAL (SELECT * FROM public.set_ownership(s.schem, '$PG_DB_OWNER')) AS res;" || exit 11
fi

