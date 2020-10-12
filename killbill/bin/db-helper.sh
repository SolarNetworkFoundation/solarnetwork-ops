#!/usr/bin/env sh

MYSQL_HOME="${MYSQL_HOME}"
DRY_RUN=""
DB_HOST="localhost"
DB_NAME="killbill"
DB_USER_ROOT="root"
DB_PASS_ROOT=""
DB_USER="killbill"
DB_PASS="killbill"

do_help () {
	cat 1>&2 <<EOF
Usage: $0 <action> [options]

Actions:
  restore  <file>    - SQL dump (from mysqldump) to restore
  sql <file>         - execute a SQL script

Options:
 -d <db name>        - MySQL database name; defaults to 'killbill'
 -h <db host>        - MySQL host; defaults to 'localhost'   
 -m <path>           - MySQL binary home directory; defaults to MYSQL_HOME or `which mysql`
 -n                  - dry run; do not actually make any changes
 -P <db root pass>   - MySQL root user password
 -p <db pass>        - MySQL user password; defaults to 'killbill'
 -U <db root user>   - MySQL root user name; defaults to 'root'
 -u <db user>        - MySQL user name; defaults to 'killbill'
 -v                  - verbose mode; print out more verbose messages
EOF
}

while getopts ":d:m:nP:p:U:u:v" opt; do
	case $opt in
		d) DB_NAME="${OPTARG}";;
		m) MYSQL_HOME="${OPTARG}";;
		n) DRY_RUN='TRUE';;
		P) DB_PASS_ROOT="${OPTARG}";;
		p) DB_PASS="${OPTARG}";;
		U) DB_USER_ROOT="${OPTARG}";;
		u) DB_USER="${OPTARG}";;
		v) VERBOSE='TRUE';;
		*)
			echo "Unknown argument ${OPTARG}" >&2
			do_help
			exit 1
	esac
done
shift $(($OPTIND - 1))

action="$1"
if [ -z "$action" ]; then
	do_help
	exit 1
fi
shift 1

if [ -z "$MYSQL_HOME" ]; then
	MYSQL_HOME=$(which mysql)
	MYSQL_HOME=${MYSQL_HOME%/*}
	if [ -z "$MYSQL_HOME" ]; then
		echo 'mysql not found; please specify via -m argument or MYSQL_HOME environment value.' >&2
		exit 1
	fi
fi

echo "MySQL home: $MYSQL_HOME"

do_sql () {
	local sql_file="$1"
	if [ -z "$sql_file" ]; then
		echo "Must specify SQL file to execute." >&2
		exit 1
	fi
	if [ ! -e "$sql_file" ]; then
		echo "SQL file [$sql_file] not found." >&2
		exit 2
	fi
	if [ -n "$DRY_RUN" ]; then
		echo "[DRY RUN]: $MYSQL_HOME/mysql -u $DB_USER -p $DB_NAME <$sql_file"
	else
		echo "Executing SQL $sql_file; enter $DB_USER password if prompted..."
		"$MYSQL_HOME"/mysql -u "$DB_USER" "-p$DB_PASS" "$DB_NAME" <"$sql_file"
	fi
}

do_flyway_baseline () {
	if [ -n "$DRY_RUN" ]; then
		echo "[DRY RUN]: flyway -url='jdbc:mariadb://$DB_HOST/$DB_NAME' -user=$DB_USER -password= -table=schema_version baseline"
	else
		echo "Creating flyway baseline"
		flyway \
    		-url="jdbc:mariadb://$DB_HOST/$DB_NAME" -user=$DB_USER -password=$DB_PASS \
    		-table=schema_version baseline
	fi
}

do_flyway_migrate() {
	local mig_dir="$1"
	if [ -z "$mig_dir" ];then
		echo "The SQL migrations directory must be specified." >&2
		exit 1
	elif [ ! -d "$mig_dir" ]; then
		echo "The SQL migrations directory [$mig_dir] was not found." >&2
		exit 2
	fi
	
	# check if we need to do a baseline
	echo "Checking for flyway baseline; enter $DB_USER password if prompted..."
	local base=$("$MYSQL_HOME"/mysql -u "$DB_USER" "-p$DB_PASS" "$DB_NAME" -e "SELECT table_name FROM information_schema.tables WHERE table_schema = '$DB_NAME'  AND table_name = 'schema_version'")
	if [ -z "$base" ]; then
		do_flyway_baseline
	fi
	
	if [ -n "$DRY_RUN" ]; then
		echo "[DRY RUN]: flyway -locations=filesystem:$mig_dir -url='jdbc:mariadb://$DB_HOST/$DB_NAME' -user=$DB_USER -password= -table=schema_version migrate"
	else
		echo "Executing flyway migrations"
		flyway -locations="filesystem:$mig_dir" \
    		-url="jdbc:mariadb://$DB_HOST/$DB_NAME" -user=$DB_USER -password=$DB_PASS \
    		-table=schema_version migrate
	fi
}

do_restore () {
	local dump_file="$1"
	local sql_file="$2"
	local mig_dir="$3"
	if [ -z "$dump_file" ]; then
		echo "Must specify mysqldump file to restore." >&2
		exit 1
	fi
	if [ ! -e "$dump_file" ]; then
		echo "Dump file [$dump_file] not found." >&2
		exit 2
	fi
	if [ -n "$DRY_RUN" ]; then
		echo "[DRY RUN]: $MYSQL_HOME/mysql -u $DB_USER_ROOT -p -e 'DROP DATABASE IF EXISTS $DB_NAME'"
		echo "[DRY RUN]: $MYSQL_HOME/mysql -u $DB_USER_ROOT -p -e 'CREATE DATABASE killbill CHARACTER SET = 'utf8''"
	else
		echo "Dropping database $DB_NAME; enter $DB_USER_ROOT password if prompted..."
		"$MYSQL_HOME"/mysql -u "$DB_USER_ROOT" "-p$DB_PASS_ROOT" -e "DROP DATABASE IF EXISTS $DB_NAME"
		echo "Creating database $DB_NAME; enter $DB_USER_ROOT password if prompted..."
		"$MYSQL_HOME"/mysql -u "$DB_USER_ROOT" "-p$DB_PASS_ROOT" -e "CREATE DATABASE $DB_NAME CHARACTER SET = 'utf8'"
	fi
	if [ "${dump_file%.xz}" != "${dump_file}" ]; then
		if [ -n "$DRY_RUN" ]; then
			echo "[DRY RUN]: xzcat $dump_file | $MYSQL_HOME/mysql -u $DB_USER -p $DB_NAME"
		else
			echo "Restoring database $DB_NAME from $dump_file; enter $DB_USER password if prompted..."
			xzcat "$dump_file" |"$MYSQL_HOME"/mysql -u "$DB_USER" "-p$DB_PASS" "$DB_NAME"
		fi
	else
		if [ -n "$DRY_RUN" ]; then
			echo "[DRY RUN]: $MYSQL_HOME/mysql -u $DB_USER -p $DB_NAME <$dump_file"
		else
			echo "Restoring database $DB_NAME from $dump_file; enter $DB_USER password if prompted..."
			"$MYSQL_HOME"/mysql -u "$DB_USER" "-p$DB_PASS" "$DB_NAME" <"$dump_file"
		fi
	fi
	if [ -e "$sql_file" ]; then
		do_sql "$sql_file"
	fi
	if [ -e "$mig_dir" ]; then
		do_flyway_migrate "$mig_dir"
	fi
}

# Parse command line parameters.
case $action in
	restore) do_restore "$@" ;;
	
	sql) do_sql "$@" ;;
	
	flyway-baseline) do_flyway_baseline "$@" ;;
	
	flyway-migrate) do_flyway_migrate "$@" ;;
	
	*)
		echo "Unknown action [$action]" >&2
		do_help
		exit 1
		;;
esac

exit 0
