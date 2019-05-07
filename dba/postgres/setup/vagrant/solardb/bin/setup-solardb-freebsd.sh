#!/usr/bin/env sh

BASE_DIR="/vagrant"
DRY_RUN=""
HOSTNAME="solardb"
PG_CONF_AWK="example/pg-conf.awk"
PG_DATA_DIR="/var/db/postgres/data96"
PG_IDENT_MAP="cert"
PG_IDENT_CONF="example/pg_ident.conf"
PG_LISTEN_ADDR="*"
PG_PRELOAD_LIB="auto_explain,pg_stat_statements,timescaledb"
PG_RECREATE=""
PG_SSL_CA="tls/ca.crt"
PG_SSL_CERT="tls/server.crt"
PG_SSL_CIPHERS="ECDH+AESGCM:ECDH+CHACHA20:ECDH+AES256:ECDH+AES128:!aNULL:!SHA1"
PG_SSL_KEY="tls/server.key"
PKG_REPO_CONF="example/solarnet.conf"
PKG_REPO_CERT="example/solarnet-repo.cert"
UPDATE_PKGS=""
VERBOSE=""

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
 -c <pg preload lib>    - value for the Postgres shared_preload_libraries; defaults to
                          auto_explain,pg_stat_statements,timescaledb
 -D <pg data dir>       - directory to initialize Postgres data; defaults to /var/db/postgres/data96
 -d <pg listen addr>    - the Postgres address to listen to; defaults to *
 -d <pg listen addr>    - the Postgres address to listen on; defaults to *
 -E <pg ssl cert>       - relative path to the Postgres SSL public certificate; defaults to tls/server.crt
 -e <pg ssl key>        - relative path to the Postgres SSL private key; defaults to tls/server.key
 -F <pg ssl ca>         - Postgres SSL CA certificate bundle; defaults to tls/ca.crt
 -f <pg ssl ciphers>    - Postgres SSL ciphers to enable; define as empty string to skip SSL configuration
 -G                     - always re-create the Postgres database
 -h <hostname>          - the hostname to use; defaults to solardb
 -n                     - dry run; do not make any actual changes
 -P <pkg conf>          - relative path to the pkg configuration to add; defaults to example/solarnet.conf
 -p <pkg cert>          - relative path to the pkg certificate to add; defaults to example/solarnet-repo.cert
 -u                     - update package cache
 -v                     - verbose mode; print out more verbose messages
EOF
}

while getopts ":A:a:B:b:c:D:d:E:e:F:f:Gh:nP:p:uv" opt; do
	case $opt in
		A) PG_IDENT_MAP="${OPTARG}";;
		a) PG_IDENT_CONF="${OPTARG}";;
		B) PG_CONF_AWK="${OPTARG}";;
		b) BASE_DIR="${OPTARG}";;
		c) PG_PRELOAD_LIB="${OPTARG}";;
		D) PG_DATA_DIR="${OPTARG}";;
		d) PG_LISTEN_ADDR="${OPTARG}";;
		E) PG_SSL_CERT="${OPTARG}";;
		e) PG_SSL_KEY="${OPTARG}";;
		F) PG_SSL_CA="${OPTARG}";;
		f) PG_SSL_CIPHERS="${OPTARG}";;
		G) PG_RECREATE='TRUE';;
		h) HOSTNAME="${OPTARG}";;
		P) PKG_REPO_CONF="${OPTARG}";;
		p) PKG_REPO_CERT="${OPTARG}";;
		n) DRY_RUN='TRUE';;
		u) UPDATE_PKGS='TRUE';;
		v) VERBOSE='TRUE';;
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

setup_postgres () {
	pkg_install postgresql96-plv8js
	pkg_install postgresql96-server
	pkg_install postgresql96-contrib
	pkg_install timescaledb
	if grep -q postgresql_enable /etc/rc.conf >/dev/null; then
		echo "Postgres already configured to start at boot."
	else
		echo "Configuring Postgres to start at boot..."
		if [ -z "$DRY_RUN" ]; then
			echo 'postgresql_enable="YES"' >>/etc/rc.conf
			echo 'postgresql_data="'"$PG_DATA_DIR"'"' >>/etc/rc.conf
			echo 'postgresql_initdb_flags="--encoding=utf-8 --lc-collate=C"' >> /etc/rc.conf
		fi	
	fi
	if [ -d "$PG_DATA_DIR" ]; then
		echo "Postgres already initialized at $PG_DATA_DIR."
	else
		echo "Initializing Postgres at $PG_DATA_DIR..."
		if [ -z "$DRY_RUN" ]; then
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
	
	if grep -q plv8.start_proc "$PG_DATA_DIR/postgresql.conf" >/dev/null; then
		echo "plv8 startup procedure already configured."
	else
		echo "Configuring plv8 startup procedure..."
		if [ -z "$DRY_RUN" ]; then
			echo "plv8.start_proc = 'plv8_startup'" >>"$PG_DATA_DIR/postgresql.conf"
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
				chown -R postgres:postgres "$PG_DATA_DIR/tls"
			fi
			if [ -n "$PG_SSL_CERT" ]; then
				echo "Configuring Postgres SSL certificate, private key..."
				sed -Ei '' -e "s|#?ssl_cert_file = '.*'|ssl_cert_file = '$PG_SSL_CERT'|" \
					-e "s|#?ssl_key_file = '.*'|ssl_key_file = '$PG_SSL_KEY'|" \
					"$PG_DATA_DIR/postgresql.conf"
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
		echo "Configuring pg_ident.conf map for $PG_IDENT_MAP..."
		if [ -z "$DRY_RUN" ]; then
			if [ -e "$BASE_DIR/$PG_IDENT_CONF" ]; then
				cat "$BASE_DIR/$PG_IDENT_CONF" >>"$PG_DATA_DIR/pg_ident.conf"
			else
				echo "pg_ident file $PG_IDENT_CONF not found."
				exit 1
			fi
		fi
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
	
	if diff -q "$PG_DATA_DIR/postgresql.conf" "$PG_DATA_DIR/postgresql.conf.orig" >/dev/null; then
		echo "Postgres configuration unchanged from $PG_DATA_DIR/postgresql.conf.orig"
	else
		echo "Postgres configuration changes from $PG_DATA_DIR/postgresql.conf.orig:"
		diff "$PG_DATA_DIR/postgresql.conf" "$PG_DATA_DIR/postgresql.conf.orig" 
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
	if [ ! -d /db-init ]; then
		echo "Missing /db-init setup directory.";
	else
		su postgres -c "psql -d solarnetwork -c 'SELECT now()'" >/dev/null 2>&1
		if [ -n "$PG_RECREATE" -o $? -ne 0 ]; then
			echo "Creating Postgres database solarnetwork..."
			cd /db-init
			./bin/setup-db.sh -mrv -d solarnetwork -L example/tsdb-init-users.sql
		else
			echo "Postgres database solarnetwork already exists."
		fi
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
setup_postgres
setup_db
show_results
