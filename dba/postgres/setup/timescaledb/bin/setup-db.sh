#!/usr/bin/env sh

# Script for creating or re-creating the SolarNetwork database in its TimescaleDB form.
# The resulting database is suitable for production deployments.
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
PG_DB="solarnetwork"
PG_DB_TABLESPACE=""
PG_DB_TABLESPACE_PATH=""
PG_DB_TABLESPACE_OPTS=""
PG_ADMIN_USER="postgres"
PG_ADMIN_DB="postgres"
PG_TEMPLATE_DB="template0"
USER_ROLE_SCRIPT="tsdb-init-roles.sql"
USER_SCRIPT=""
PERMISSION_SCRIPT="tsdb-init-permissions.sql"
RECREATE_DB=""
CREATE_USER=""
INDEX_TABLESPACE=""
INDEX_TABLESPACE_PATH=""
INDEX_TABLESPACE_OPTS=""
DRY_RUN=""
VERBOSE=""

while getopts ":a:c:d:D:e:E:f:i:I:j:L:mrtT:u:U:v" opt; do
	case $opt in
		c) PSQL_CONN_ARGS="${OPTARG}";;
		d) PG_DB="${OPTARG}";;
		D) PG_ADMIN_DB="${OPTARG}";;
		e) PG_DB_TABLESPACE="${OPTARG}";;
		E) PG_DB_TABLESPACE_PATH="${OPTARG}";;
		f) PG_DB_TABLESPACE_OPTS="${OPTARG}";;
		i) INDEX_TABLESPACE="${OPTARG}";;
		I) INDEX_TABLESPACE_PATH="${OPTARG}";;
		j) INDEX_TABLESPACE_OPTS="${OPTARG}";;
		L) USER_SCRIPT="${OPTARG}";;
		m) CREATE_USER='TRUE';;
		P) PERMISSION_SCRIPT="${OPTARG}";;
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
	echo
	if [ -n "$VERBOSE" ]; then
		echo "Dropping database [$PG_DB]..."
	fi
	if [ -n "$DRY_RUN" ]; then
		echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -c 'DROP DATABASE IF EXISTS $PG_DB'"
	else
		psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -c "DROP DATABASE IF EXISTS $PG_DB" || exit 3
	fi
fi

if [ -n "$CREATE_USER" ]; then
	echo
	if [ -n "$VERBOSE" ]; then
		echo "Creating database owner..."
	fi
	if [ -n "$DRY_RUN" ]; then
		echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -c 'CREATE USER $PG_DB_OWNER WITH LOGIN NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION'"
	else
		psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -P pager=off -qAtc "CREATE USER $PG_DB_OWNER WITH LOGIN NOSUPERUSER INHERIT NOCREATEDB NOCREATEROLE NOREPLICATION"
	fi
	
	echo
	if [ ! -e "$USER_ROLE_SCRIPT" ]; then
		echo "$USER_ROLE_SCRIPT DDL not found.";
		exit 4;
	fi
	if [ -n "$VERBOSE" ]; then
		echo "Creating database users via [$USER_ROLE_SCRIPT]..."
	fi
	if [ -n "$DRY_RUN" ]; then
		echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -f $USER_ROLE_SCRIPT"
	else
		psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -P pager=off -qAtf "$USER_ROLE_SCRIPT" || exit 4
	fi
fi

if [ -n "$PG_DB_TABLESPACE" -a -n "$PG_DB_TABLESPACE_PATH" ]; then
	echo
	if [ -n "$VERBOSE" ]; then
		echo "Creating DB tablespace $PG_DB_TABLESPACE => $PG_DB_TABLESPACE_PATH..."
	fi
	if [ -n "$DRY_RUN" ]; then
		echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -c 'CREATE TABLESPACE $PG_DB_TABLESPACE OWNER $PG_DB_OWNER LOCATION '$PG_DB_TABLESPACE_PATH' $PG_DB_TABLESPACE_OPTS'"
	else		
		psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -P pager=off -Atc "CREATE TABLESPACE $PG_DB_TABLESPACE OWNER $PG_DB_OWNER LOCATION '$PG_DB_TABLESPACE_PATH'"
	fi
fi

if [ -n "$PG_DB_TABLESPACE_OPTS" ]; then
	echo
	if [ -n "$VERBOSE" ]; then
		echo "Setting index tablespace $PG_DB_TABLESPACE options ($PG_DB_TABLESPACE_OPTS)..."
	fi
	if [ -n "$DRY_RUN" ]; then
		echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -c 'ALTER TABLESPACE $PG_DB_TABLESPACE SET ($PG_DB_TABLESPACE_OPTS)'"
	else		
		psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -P pager=off -Atc "ALTER TABLESPACE $PG_DB_TABLESPACE SET ($PG_DB_TABLESPACE_OPTS)"
	fi
fi

echo
if [ -n "$VERBOSE" ]; then
	echo "Creating database [$PG_DB] with owner [$PG_DB_OWNER]..."
fi
if [ -n "$DRY_RUN" ]; then
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -c 'CREATE DATABASE $PG_DB WITH ENCODING='UTF8' OWNER=$PG_DB_OWNER TEMPLATE=$PG_TEMPLATE_DB LC_COLLATE='C' LC_CTYPE='C' ${PG_DB_TABLESPACE:+TABLESPACE=$PG_DB_TABLESPACE}'"
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c 'CREATE EXTENSION IF NOT EXISTS plv8 WITH SCHEMA pg_catalog'"
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c 'CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public'"
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c 'CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public'"
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c 'CREATE EXTENSION IF NOT EXISTS timescaledb WITH SCHEMA public'"
else
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -c "CREATE DATABASE $PG_DB WITH ENCODING='UTF8' OWNER=$PG_DB_OWNER TEMPLATE=$PG_TEMPLATE_DB LC_COLLATE='C' LC_CTYPE='C' ${PG_DB_TABLESPACE:+TABLESPACE=$PG_DB_TABLESPACE}" || exit 5
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c "CREATE EXTENSION IF NOT EXISTS plv8 WITH SCHEMA pg_catalog" || exit 6
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c "CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public" || exit 7
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c "CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public" || exit 8
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c "CREATE EXTENSION IF NOT EXISTS timescaledb WITH SCHEMA public" || exit 9
fi

echo
if [ -n "$VERBOSE" ]; then
	echo "Creating plv8 scripts..."
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

if [ -n "$INDEX_TABLESPACE" -a -n "$INDEX_TABLESPACE_PATH" ]; then
	echo
	if [ -n "$VERBOSE" ]; then
		echo "Creating index tablespace $INDEX_TABLESPACE => $INDEX_TABLESPACE_PATH..."
	fi
	if [ -n "$DRY_RUN" ]; then
		echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -c 'CREATE TABLESPACE $INDEX_TABLESPACE OWNER $PG_DB_OWNER LOCATION '$INDEX_TABLESPACE_PATH' $INDEX_TABLESPACE_OPTS'"
	else		
		psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -P pager=off -Atc "CREATE TABLESPACE $INDEX_TABLESPACE OWNER $PG_DB_OWNER LOCATION '$INDEX_TABLESPACE_PATH'"
	fi
fi

if [ -n "$INDEX_TABLESPACE_OPTS" ]; then
	echo
	if [ -n "$VERBOSE" ]; then
		echo "Setting index tablespace $INDEX_TABLESPACE options ($INDEX_TABLESPACE_OPTS)..."
	fi
	if [ -n "$DRY_RUN" ]; then
		echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -c 'ALTER TABLESPACE $INDEX_TABLESPACE SET ($INDEX_TABLESPACE_OPTS)'"
	else		
		psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_ADMIN_DB -P pager=off -Atc "ALTER TABLESPACE $INDEX_TABLESPACE SET ($INDEX_TABLESPACE_OPTS)"
	fi
fi

echo
if [ -n "$VERBOSE" ]; then
	echo "Creating SolarNetwork database tables and functions..."
fi
if [ -n "$DRY_RUN" ]; then
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -f tsdb-init.sql"
else		
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -P pager=off -Atf tsdb-init.sql || exit 10
fi

echo
if [ -n "$VERBOSE" ]; then
	echo "Setting ownership of database objects..."
fi
if [ -n "$DRY_RUN" ]; then
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c 'SELECT res.* FROM (SELECT unnest(ARRAY['_timescaledb_solarnetwork', 'quartz', 'solaragg', 'solarcommon', 'solardatum', 'solarnet', 'solaruser']) AS schem) AS s, LATERAL (SELECT * FROM public.set_ownership(s.schem, '$PG_DB_OWNER')) AS res'"
else		
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -P pager=off -qAtc "SELECT stmt || ';' FROM (SELECT unnest(ARRAY['_timescaledb_solarnetwork', 'quartz', 'solaragg', 'solarcommon', 'solardatum', 'solarnet', 'solaruser']) AS schem) AS s, LATERAL (SELECT * FROM public.set_ownership(s.schem, '$PG_DB_OWNER')) AS res" || exit 11
fi

echo
if [ -n "$VERBOSE" ]; then
	echo "Creating hypertables..."
fi
if [ -n "$DRY_RUN" ]; then
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c '...'"
else		
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -P pager=off -qAt <<-EOF
		SELECT _timescaledb_solarnetwork.change_to_hypertable('solardatum',	'da_datum',				'ts',		'6 months'${INDEX_TABLESPACE:+,'$INDEX_TABLESPACE'});
		
		SELECT _timescaledb_solarnetwork.change_to_hypertable('solardatum',	'da_loc_datum',			'ts',		'1 years'${INDEX_TABLESPACE:+,'$INDEX_TABLESPACE'});
		
		SELECT _timescaledb_solarnetwork.change_to_hypertable('solaragg',	'agg_datum_hourly',		'ts_start',	'6 months'${INDEX_TABLESPACE:+,'$INDEX_TABLESPACE'});
		SELECT _timescaledb_solarnetwork.change_to_hypertable('solaragg',	'agg_datum_daily',		'ts_start',	'1 years'${INDEX_TABLESPACE:+,'$INDEX_TABLESPACE'});
		SELECT _timescaledb_solarnetwork.change_to_hypertable('solaragg',	'agg_datum_monthly',	'ts_start',	'5 years'${INDEX_TABLESPACE:+,'$INDEX_TABLESPACE'});

		SELECT _timescaledb_solarnetwork.change_to_hypertable('solaragg',	'agg_loc_datum_hourly',	'ts_start',	'1 years'${INDEX_TABLESPACE:+,'$INDEX_TABLESPACE'});
		SELECT _timescaledb_solarnetwork.change_to_hypertable('solaragg',	'agg_loc_datum_daily',	'ts_start',	'5 years'${INDEX_TABLESPACE:+,'$INDEX_TABLESPACE'});
		SELECT _timescaledb_solarnetwork.change_to_hypertable('solaragg',	'agg_loc_datum_monthly','ts_start',	'10 years'${INDEX_TABLESPACE:+,'$INDEX_TABLESPACE'});

		SELECT _timescaledb_solarnetwork.change_to_hypertable('solaragg',	'aud_datum_hourly',		'ts_start',	'6 months'${INDEX_TABLESPACE:+,'$INDEX_TABLESPACE'});
		SELECT _timescaledb_solarnetwork.change_to_hypertable('solaragg',	'aud_datum_daily',		'ts_start',	'1 years'${INDEX_TABLESPACE:+,'$INDEX_TABLESPACE'});
		SELECT _timescaledb_solarnetwork.change_to_hypertable('solaragg',	'aud_datum_monthly',	'ts_start',	'5 years'${INDEX_TABLESPACE:+,'$INDEX_TABLESPACE'});

		SELECT _timescaledb_solarnetwork.change_to_hypertable('solaragg',	'aud_loc_datum_hourly',	'ts_start',	'1 years'${INDEX_TABLESPACE:+,'$INDEX_TABLESPACE'});
		
		SELECT _timescaledb_solarnetwork.change_to_hypertable('solaragg',	'aud_acc_datum_daily',	'ts_start',	'1 years'${INDEX_TABLESPACE:+,'$INDEX_TABLESPACE'});
	EOF
fi

if [ -n "$INDEX_TABLESPACE" ]; then
	echo
	if [ -n "$VERBOSE" ]; then
		echo "Moving indexes to tablespace $INDEX_TABLESPACE..."
	fi
	if [ -n "$DRY_RUN" ]; then
		echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -c 'SELECT * FROM public.set_index_tablespace(ARRAY[...], '$INDEX_TABLESPACE')'"
	else		
		psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -P pager=off -At <<-EOF
			SELECT stmt || ';' FROM (SELECT unnest(ARRAY['solaragg', 'solardatum', 'solarnet', 'solaruser']) AS schem) AS s,
			LATERAL (SELECT * FROM public.set_index_tablespace(s.schem, '$INDEX_TABLESPACE')) AS res;
		EOF
	fi
fi

echo
if [ ! -e "$PERMISSION_SCRIPT" ]; then
	echo "$PERMISSION_SCRIPT DDL not found.";
	exit 11
fi
if [ -n "$VERBOSE" ]; then
	echo "Applying database permissions via [$PERMISSION_SCRIPT]..."
fi
if [ -n "$DRY_RUN" ]; then
	echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -f $PERMISSION_SCRIPT"
else
	psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -P pager=off -Atf "$PERMISSION_SCRIPT" || exit 11
fi


if [ -n "$USER_SCRIPT" ]; then
	echo
	if [ ! -e "$USER_SCRIPT" ]; then
		echo "$USER_SCRIPT DDL not found.";
		exit 12
	fi
	if [ -n "$VERBOSE" ]; then
		echo "Executing user script [$USER_SCRIPT]..."
	fi
	if [ -n "$DRY_RUN" ]; then
		echo "psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -f $USER_SCRIPT"
	else
		psql $PSQL_CONN_ARGS -U $PG_ADMIN_USER -d $PG_DB -P pager=off -Atf "$USER_SCRIPT" || exit 12
	fi
fi
