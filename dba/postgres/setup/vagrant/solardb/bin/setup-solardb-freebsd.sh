#!/usr/bin/env sh
set -e

BASE_DIR="/vagrant"
BASE_DIR_DB_INIT="/db-init"
DB_INDEX_TSPACE_PATH="/solar/idx"
DB_INDEX_TSPACE_OPTS="random_page_cost=1, effective_io_concurrency=10"
DB_USER_PATH="example/tsdb-init-users.sql"
DB_OWNER="solarnet"
DB_OWNER_PASSWORD="solarnet"
DRY_RUN=""
HOSTNAME="db.solarnetworkdev.net"
OS_LOADER_CONF="example/loader.conf"
OS_SYSCTL_CONF="example/sysctl.conf"
PG_CONF_AWK="example/pg-conf.awk"
PG_DATA_DIR="/solar/dat"
PG_HBA_CONF="example/pg_hba.conf"
PG_IDENT_MAP="cert"
PG_IDENT_CONF="example/pg_ident.conf"
PG_LISTEN_ADDR="*"
PG_PRELOAD_LIB="auto_explain,pg_stat_statements,timescaledb"
PG_RECREATE=""
PG_SSL_CA="tls/ca.crt"
PG_SSL_CERT="tls/server.crt"
PG_SSL_CIPHERS="ECDH+AESGCM:ECDH+CHACHA20:ECDH+AES256:ECDH+AES128:!aNULL:!SHA1"
PG_SSL_KEY="tls/server.key"
PG_USER="postgres"
PG_WAL_DIR="/solar/wal"
PKG_REPO_CONF="example/solarnet.conf"
PKG_REPO_CERT="example/solarnet-repo.cert"
UPDATE_PKGS=""
VERBOSE=""
Z_POOLS="snjournal:da0 sndata:da1 snindex:da2"
Z_MOUNTS="sndata/dat:/solar/dat snjournal/wal:/solar/wal snindex/idx:/solar/idx"
Z_MOUNT_STDPROPS="atime=off exec=off setuid=off compression=lz4 recordsize=128k"

if [ $(id -u) -ne 0 ]; then
	echo "This script must be run as root."
	exit 1
fi

do_help () {
	cat 1>&2 <<EOF
Usage: $0 [-nuv]

Arguments:
 -A <pg ident mapname>  - the Postgres pg_ident.conf map name to test for; defaults to cert
 -a <pg ident conf>     - relative path to file to copy to Postgres pg_ident.conf; defaults to
                          example/pg_hba.conf
 -B <pg custom awk>     - relative path to an awk script to run on the Postgres configuration file
                          after all other customizations are performed; defaults to example/pg-conf.awk
 -b <base dir>          - base dir for relative paths; defaults to /vagrant
 -C <db init base dir>  - base dir for the DB init scripts; defaults to /db-init
 -c <pg preload lib>    - value for the Postgres shared_preload_libraries; defaults to
                          auto_explain,pg_stat_statements,timescaledb
 -D <pg data dir>       - directory to initialize Postgres data; defaults to /solar/dat
 -d <pg listen addr>    - the Postgres address to listen to; defaults to *
 -d <pg listen addr>    - the Postgres address to listen on; defaults to *
 -E <pg ssl cert>       - relative path to the Postgres SSL public certificate; defaults to tls/server.crt
 -e <pg ssl key>        - relative path to the Postgres SSL private key; defaults to tls/server.key
 -F <pg ssl ca>         - Postgres SSL CA certificate bundle; defaults to tls/ca.crt
 -f <pg ssl ciphers>    - Postgres SSL ciphers to enable; define as empty string to skip SSL configuration
 -G                     - always re-create the Postgres database
 -g <pg hba conf>       - relative path to file to copy to Postgres pg_hba.conf; defaults to
                          example/pg_hba.conf
 -h <hostname>          - the hostname to use; defaults to solardb
 -I <idx tspace opts>   - the SQL options to use for the index tablespace; defaults to
                          'random_page_cost=1, effective_io_concurrency=10'
 -i <idx tspace path>   - the tablespace path; defaults to /solar/idx
 -J <loader conf path>  - relative path to /boot/loader.conf settings to add; defaults to example/loader.conf
 -j <sysctl conf path>  - relative path to /etc/sysctl.conf settings to add; defaults to example/sysctl.conf
 -n                     - dry run; do not make any actual changes
 -o                     - database owner; defaults to 'solarnet'
 -O                     - database owner password; defaults to 'solarnet'
 -P <pkg conf>          - relative path to the pkg configuration to add; defaults to example/solarnet.conf
 -p <pkg cert>          - relative path to the pkg certificate to add; defaults to example/solarnet-repo.cert
 -U <db user sql path>  - path relative to -C for SQL to create database users; defaults to example/tsdb-init-users.sql
 -u                     - update package cache
 -v                     - verbose mode; print out more verbose messages
 -Z <zpools>            - space delimited pairs of ZFS pool names and associated devices;
                          defaults to 'snjournal:da0 sndata:da1 snindex:da2'
 -z <zfs mounts>        - space delimited pairs of ZFS filesystems and associated mount points to create;
                          defaults to 'sndata/dat:/solar/dat snjournal/wal:/solar/dat snindex/idx:/solar/idx'
EOF
}

while getopts ":A:a:B:b:C:c:D:d:E:e:F:f:Gg:h:I:i:J:j:no:O:P:p:U:uvZ:z:" opt; do
	case $opt in
		A) PG_IDENT_MAP="${OPTARG}";;
		a) PG_IDENT_CONF="${OPTARG}";;
		B) PG_CONF_AWK="${OPTARG}";;
		b) BASE_DIR="${OPTARG}";;
		C) BASE_DIR_DB_INIT="${OPTARG}";;
		c) PG_PRELOAD_LIB="${OPTARG}";;
		D) PG_DATA_DIR="${OPTARG}";;
		d) PG_LISTEN_ADDR="${OPTARG}";;
		E) PG_SSL_CERT="${OPTARG}";;
		e) PG_SSL_KEY="${OPTARG}";;
		F) PG_SSL_CA="${OPTARG}";;
		f) PG_SSL_CIPHERS="${OPTARG}";;
		G) PG_RECREATE='TRUE';;
		g) PG_HBA_CONF="${OPTARG}";;
		h) HOSTNAME="${OPTARG}";;
		I) DB_INDEX_TSPACE_OPTS="${OPTARG}";;
		i) DB_INDEX_TSPACE_PATH="${OPTARG}";;
		J) OS_LOADER_CONF="${OPTARG}";;
		j) OS_SYSCTL_CONF="${OPTARG}";;
		O) DB_OWNER_PASSWORD="${OPTARG}";;
		o) DB_OWNER="${OPTARG}";;
		P) PKG_REPO_CONF="${OPTARG}";;
		p) PKG_REPO_CERT="${OPTARG}";;
		n) DRY_RUN='TRUE';;
		U) DB_USER_PATH="${OPTARG}";;
		u) UPDATE_PKGS='TRUE';;
		v) VERBOSE='TRUE';;
		Z) Z_POOLS="${OPTARG}";;
		z) Z_MOUNTS="${OPTARG}";;
		?)
			echo "Unknown argument ${OPTARG}"
			do_help
			exit 1
	esac
done
shift $(($OPTIND - 1))

# install package if not already installed
pkg_install () {
	if pkg info --quiet $1 >/dev/null 2>&1; then
		echo "Package $1 already installed."
	else
		echo "Installing package $1 ..."
		if [ -z "$DRY_RUN" ]; then
			pkg install --no-repo-update --yes $1
		fi
	fi
}

setup_pkgs () {
	pkg_install ca_root_nss
	if [ -e /usr/local/etc/ssl/certs/solarnet-repo.cert ]; then
		echo "pkg repo solarnet certificate already configured."
	else
		echo "Configuring pkg repo solarnet cert from ${PKG_REPO_CERT}";
		if [ -z "$DRY_RUN" ]; then
			if [ ! -d /usr/local/etc/ssl/certs ]; then
				mkdir -p /usr/local/etc/ssl/certs
			fi
			cp "$BASE_DIR/${PKG_REPO_CERT}" /usr/local/etc/ssl/certs/solarnet-repo.cert
		fi
	fi
	if [ -e /usr/local/etc/pkg/repos/solarnet.conf ]; then
		echo "pkg repo solarnet already configured."
	else
		echo "Configuring pkg repo solarnet from ${PKG_REPO_CONF}";
		if [ -z "$DRY_RUN" ]; then
			if [ ! -d /usr/local/etc/pkg/repos ]; then
				mkdir -p /usr/local/etc/pkg/repos
			fi
			cp "$BASE_DIR/${PKG_REPO_CONF}" /usr/local/etc/pkg/repos/solarnet.conf
		fi
	fi
	if [ -n "$UPDATE_PKGS" ]; then
		echo 'Upgrading OS packages...'
		if [ -z "$DRY_RUN" ]; then
			pkg update
			pkg upgrade --yes
		fi
	fi
}

setup_hostname () {
	if grep -q "hostname="'"'"$HOSTNAME"'"' /etc/rc.conf >/dev/null; then
		echo "Hostname already set to $HOSTNAME."
	else
		echo "Setting hostname to $HOSTNAME..."
		if [ -z "$DRY_RUN" ]; then
			hostname "$HOSTNAME"
			sed -Ei '' -e 's/hostname=.*/hostname="'"$HOSTNAME"'"/' /etc/rc.conf
		fi
	fi

	# Setup DNS to resolve hostname
	if grep -q "$HOSTNAME" /etc/hosts >/dev/null; then
		echo "$HOSTNAME already configured in /etc/hosts."
	else
		echo "Setting up $HOSTNAME host entry in /etc/hosts..."
		if [ -z "$DRY_RUN" ]; then
			sed "s/^127.0.0.1[[:space:]]*localhost/127.0.0.1 $HOSTNAME localhost/" /etc/hosts >/tmp/hosts.new
			if diff -q /etc/hosts /tmp/hosts.new >/dev/null; then
				# didn't change anything, try 127.0.1.0
				sed "s/^127.0.1.1.*/127.0.1.1 $HOSTNAME/" /etc/hosts >/tmp/hosts.new
			else
			fi
			if diff -q /etc/hosts /tmp/hosts.new >/dev/null; then
				echo "No change made to /etc/hosts."
			else
				chmod 644 /tmp/hosts.new
				cp -a /etc/hosts /etc/hosts.bak
				mv -f /tmp/hosts.new /etc/hosts
			fi
		fi
	fi
}

setup_sendmail() {
	if grep -q sendmail_outbound_enable /etc/rc.conf >/dev/null; then
		echo "Sendmail outbound already disabled."
	else
		echo "Disabling sendmail outbound..."
		if [ -z "$DRY_RUN" ]; then
			echo 'sendmail_outbound_enable="NO"' >>/etc/rc.conf
		fi
	fi
}

setup_zpool () {
	local pool="$1"
	local drive="$2"
	if zpool list -H "$pool" 2>/dev/null; then
		echo "ZFS pool $pool already exists."
	else
		echo "Creating ZFS pool $pool using $drive..."
		if [ -z "$DRY_RUN" ]; then
			zpool create -m none "$pool" $drive
			local zprop=""
			for zprop in $Z_MOUNT_STDPROPS; do
				zfs set $zprop "$pool"
			done
		fi
	fi
}

setup_zfs_mount () {
	local fs="$1"
	local mpoint="$2"
	if zfs list -H "$fs" 2>/dev/null; then
		echo "ZFS filesystem $fs already exists."
	else
		echo "Creating ZFS filesystem $fs mounted on $mpoint..."
		if [ -z "$DRY_RUN" ]; then
			zfs create -o "mountpoint=$mpoint" "$fs"
		fi
	fi
}

setup_kmods () {
	if kldstat -m zfs -q; then
		echo "ZFS kernel module already loaded."
	else
		echo "Loading ZFS kernel module..."
		if [ -z "$DRY_RUN" ]; then
			kldload zfs
		fi
	fi
}

setup_zfs () {
	if grep -q zfs_enable /etc/rc.conf >/dev/null; then
		echo "ZFS already configured to start at boot."
	else
		echo "Configuring ZFS to start at boot..."
		if [ -z "$DRY_RUN" ]; then
			echo 'zfs_enable="YES"' >>/etc/rc.conf
		fi
	fi
	local pair=""
	for pair in $Z_POOLS; do
		setup_zpool "${pair%:*}" "${pair#*:}"
	done
	for pair in $Z_MOUNTS; do
		setup_zfs_mount "${pair%:*}" "${pair#*:}"
	done
}

setup_postgres () {
	pkg_install postgresql12-server
	pkg_install postgresql12-contrib
	pkg_install postgresql-aggs_for_vecs
	pkg_install timescaledb
	if grep -q postgresql_enable /etc/rc.conf >/dev/null; then
		echo "Postgres already configured to start at boot."
	else
		echo "Configuring Postgres to start at boot..."
		if [ -z "$DRY_RUN" ]; then
			echo 'postgresql_enable="YES"' >>/etc/rc.conf
			echo 'postgresql_data="'"$PG_DATA_DIR"'"' >>/etc/rc.conf
			echo 'postgresql_initdb_flags="--encoding=utf-8 --lc-collate=C --auth-local=peer --auth-host=md5 --waldir='"$PG_WAL_DIR"'"' >> /etc/rc.conf
		fi
	fi
	if [ -f "$PG_DATA_DIR/postgresql.conf" ]; then
		echo "Postgres already initialized at $PG_DATA_DIR."
	else
		echo "Initializing Postgres at $PG_DATA_DIR..."
		if [ -z "$DRY_RUN" ]; then
			chown $PG_USER:$PG_USER "$PG_DATA_DIR"
			chown $PG_USER:$PG_USER "$PG_WAL_DIR"
			chown $PG_USER:$PG_USER "$DB_INDEX_TSPACE_PATH"
			service postgresql initdb
		fi
	fi

	if [ ! -e "$PG_DATA_DIR/postgresql.conf.orig" ];then
		echo "Making backup of Postgres configuration to postgresql.conf.orig..."
		if [ -z "$DRY_RUN" ]; then
			cp -a "$PG_DATA_DIR/postgresql.conf" "$PG_DATA_DIR/postgresql.conf.orig"
		fi
	fi

	if grep -q "^listen_addresses = '$PG_LISTEN_ADDR'" "$PG_DATA_DIR/postgresql.conf" >/dev/null; then
		echo "Postgres already configured with listen address $PG_LISTEN_ADDR"
	else
		echo "Configuring Postgres listen address to $PG_LISTEN_ADDR..."
		if [ -z "$DRY_RUN" ]; then
			sed -Ei '' -e "s/#?listen_addresses = '.*'/listen_addresses = '$PG_LISTEN_ADDR'/" \
				"$PG_DATA_DIR/postgresql.conf"
		fi
	fi

	if grep -q "shared_preload_libraries.*$PG_PRELOAD_LIB" "$PG_DATA_DIR/postgresql.conf" >/dev/null; then
		echo "shared_preload_libraries already configured in postgresql.conf."
	else
		echo "Configuring shared_preload_libraries in postgresql.conf"
		if [ -z "$DRY_RUN" ]; then
			sed -Ei '' -e 's/#?shared_preload_libraries = '"'.*'"'/shared_preload_libraries = '"'$PG_PRELOAD_LIB'/" \
				"$PG_DATA_DIR/postgresql.conf"
		fi
	fi

	if grep -q "^ssl = on" "$PG_DATA_DIR/postgresql.conf">/dev/null; then
		echo "Postgres SSL already enabled."
	elif [ -n "$PG_SSL_CIPHERS" ]; then
		echo "Configuring Postgres SSL"
		if [ -z "$DRY_RUN" ]; then
			sed -Ei '' -e 's/#?ssl = [[:alpha:]]+/ssl = on/' \
				-e "s/#?ssl_ciphers = '.*'/ssl_ciphers = '$PG_SSL_CIPHERS'/" \
				"$PG_DATA_DIR/postgresql.conf"
			if [ -d "$BASE_DIR/tls" ];then
				rsync -aq "$BASE_DIR/tls" "$PG_DATA_DIR/"
				chown -R $PG_USER:$PG_USER "$PG_DATA_DIR/tls"
				chmod 700 "$PG_DATA_DIR/tls"
			fi
			if [ -n "$PG_SSL_CERT" ]; then
				echo "Configuring Postgres SSL certificate, private key..."
				sed -Ei '' -e "s|#?ssl_cert_file = '.*'|ssl_cert_file = '$PG_SSL_CERT'|" \
					-e "s|#?ssl_key_file = '.*'|ssl_key_file = '$PG_SSL_KEY'|" \
					"$PG_DATA_DIR/postgresql.conf"
				if [ -e "$PG_DATA_DIR/$PG_SSL_KEY" ]; then
					chmod 600 "$PG_DATA_DIR/$PG_SSL_KEY"
				fi
			fi
			if [ -n "$PG_SSL_CA" ]; then
				echo "Configuring Postgres SSL CA certificate..."
				sed -Ei '' -e "s|#?ssl_ca_file = '.*'|ssl_ca_file = '$PG_SSL_CA'|" \
					"$PG_DATA_DIR/postgresql.conf"
			fi
		fi
	fi

	if grep -q "^$PG_IDENT_MAP\b" "$PG_DATA_DIR/pg_ident.conf" >/dev/null; then
		echo "Postgres pg_ident.conf already contains map $PG_IDENT_MAP."
	else
		echo "Configuring Postgres pg_ident.conf map for $PG_IDENT_MAP..."
		if [ -z "$DRY_RUN" ]; then
			if [ -e "$BASE_DIR/$PG_IDENT_CONF" ]; then
				cat "$BASE_DIR/$PG_IDENT_CONF" >>"$PG_DATA_DIR/pg_ident.conf"
			else
				echo "Postgres pg_ident file $PG_IDENT_CONF not found."
				exit 1
			fi
		fi
	fi

	if [ -e "$BASE_DIR/$PG_HBA_CONF" ]; then
		if diff -q "$PG_DATA_DIR/pg_hba.conf" "$BASE_DIR/$PG_HBA_CONF" >/dev/null; then
			echo "Postgres pg_hba.conf already configured."
		else
			echo "Configuring Postgres pg_hba.conf..."
			if [ -z "$DRY_RUN" ]; then
				cat "$BASE_DIR/$PG_HBA_CONF" >"$PG_DATA_DIR/pg_hba.conf"
			fi
		fi
	else
		echo "Postgres pg_hba file $PG_HBA_CONF not found."
		exit 1
	fi

	if [ -n "$PG_CONF_AWK" ]; then
		if [ ! -e "$BASE_DIR/$PG_CONF_AWK" ]; then
			echo "Custom Postgres awk configuration script $PG_CONF_AWK not found."
			exit 1
		else
			echo "Executing custom Postgres awk configuration script $PG_CONF_AWK..."
			if [ -z "$DRY_RUN" ]; then
				awk -F '[[:space:]]=[[:space:]]' -f "$BASE_DIR/$PG_CONF_AWK" "$PG_DATA_DIR/postgresql.conf" \
					>"$PG_DATA_DIR/postgresql.conf.new"
				if diff -q "$PG_DATA_DIR/postgresql.conf" "$PG_DATA_DIR/postgresql.conf.new" >/dev/null; then
					echo "No change to Postgres configuration from custom awk script $PG_CONF_AWK"
					rm -f "$PG_DATA_DIR/postgresql.conf.new"
				else
					mv -f "$PG_DATA_DIR/postgresql.conf.new" "$PG_DATA_DIR/postgresql.conf"
				fi
			fi
		fi
	fi

	if diff -q "$PG_DATA_DIR/postgresql.conf.orig" "$PG_DATA_DIR/postgresql.conf" >/dev/null; then
		echo "Postgres configuration unchanged from $PG_DATA_DIR/postgresql.conf.orig"
	else
		echo "Postgres configuration changes from $PG_DATA_DIR/postgresql.conf.orig:"
		diff "$PG_DATA_DIR/postgresql.conf.orig" "$PG_DATA_DIR/postgresql.conf" || true
	fi

	if  service postgresql status; then
		echo "Restarting Postgres..."
		if [ -z "$DRY_RUN" ]; then
			service postgresql restart
		fi
	else
		echo "Starting Postgres..."
		if [ -z "$DRY_RUN" ]; then
			service postgresql start
		fi
	fi
}

setup_db () {
	if [ ! -d "$BASE_DIR_DB_INIT" ]; then
		echo "Missing $BASE_DIR_DB_INIT setup directory.";
	else
		local dbExists=""
		if su $PG_USER -c "psql -d solarnetwork -c 'SELECT CURRENT_DATE'" >/dev/null 2>&1; then
			echo "Postgres database solarnetwork already exists."
			dbExists=1
		fi
		if [ -n "$PG_RECREATE" -o -z "$dbExists" ]; then
			echo "Creating Postgres database solarnetwork..."
			su $PG_USER -c "cd $BASE_DIR_DB_INIT && ./bin/setup-db.sh -mrv -d solarnetwork -i solarindex \
				-I '$DB_INDEX_TSPACE_PATH' -j '$DB_INDEX_TSPACE_OPTS' -L '$DB_USER_PATH' \
				-u '$DB_OWNER' -O '$DB_OWNER_PASSWORD'"
		fi
	fi
}

configure_conf_setting () {
	local conffile="$1"
	local confkey="$2"
	local confline="$3"
	if grep "^$confkey" "$1" >/dev/null; then
		echo "$conffile already contains $confkey, not changing."
	else
		echo "Updating $conffile to add: $confline"
		if [ -z "$DRY_RUN" ]; then
			echo "$confline" >> "$conffile"
			if [ "$conffile" = "/etc/sysctl.conf" ]; then
				sysctl $confline
			fi
		fi
	fi
}

setup_loder_conf () {
	if [ ! -e "$BASE_DIR/$OS_LOADER_CONF" ]; then
		echo "OS loader.conf file not available: $OS_LOADER_CONF"
	else
		echo "Configuring OS loader.conf settings from $OS_LOADER_CONF..."
		while IFS= read -r line; do
			configure_conf_setting /boot/loader.conf "${line%=*}" "$line"
		done < "$BASE_DIR/$OS_LOADER_CONF"
	fi
}

setup_sysctl_conf () {
	if [ ! -e "$BASE_DIR/$OS_SYSCTL_CONF" ]; then
		echo "OS sysctl.conf file not available: $OS_SYSCTL_CONF"
	else
		echo "Configuring OS loader.conf settings from $OS_SYSCTL_CONF..."
		while IFS= read -r line; do
			configure_conf_setting /etc/sysctl.conf "${line%=*}" "$line"
		done < "$BASE_DIR/$OS_SYSCTL_CONF"
	fi
}

show_results () {
	cat <<-EOF

		*******************************************************************************************
		INSTALLATION REPORT
		*******************************************************************************************

		To access services, you may need to add a hosts entry for $HOSTNAME
		from one of these IP addresses:

		`ifconfig |grep 'inet ' |grep -v '127\.0' |awk -F ' ' '{ print $2 }'`

	EOF
}

setup_pkgs
setup_hostname
setup_sendmail
setup_kmods
setup_loder_conf
setup_sysctl_conf
setup_zfs
setup_postgres
setup_db
show_results
