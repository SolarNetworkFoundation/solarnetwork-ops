#!/usr/bin/env sh

DRY_RUN=""
HOSTNAME="solardb"
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
 -h <hostname>          - the hostname to use; defaults to solardb
 -n                     - dry run; do not make any actual changes
 -P <pkg conf>          - relative path to the pkg configuration to add; defaults to example/solarnet.conf
 -p <pkg cert>          - relative path to the pkg certificate to add; defaults to example/solarnet-repo.cert
 -u                     - update package cache
 -v                     - verbose mode; print out more verbose messages
EOF
}

while getopts ":h:nP:p:uv" opt; do
	case $opt in
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
			cp "/vagrant/${PKG_REPO_CERT}" /usr/local/etc/ssl/certs/solarnet-repo.cert
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
			cp "/vagrant/${PKG_REPO_CONF}" /usr/local/etc/pkg/repos/solarnet.conf
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
			sed -i -e 's/hostname=.*/hostname="'"$HOSTNAME"'"/' /etc/rc.conf
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
			echo 'postgresql_data="/var/db/postgres/data96"' >>/etc/rc.conf
			echo 'postgresql_initdb_flags="--encoding=utf-8 --lc-collate=C"' >> /etc/rc.conf
		fi	
	fi
	if [ -d /var/db/postgres/data96 ]; then
		echo "Postgres already initialized at /var/db/postgres/data96."
	else
		echo "Initializing Postgres at /var/db/postgres/data96..."
		if [ -z "$DRY_RUN" ]; then
			service postgresql initdb
		fi
	fi
	
	if grep -q 'shared_preload_libraries.*timescaledb' /var/db/postgres/data96/postgresql.conf >/dev/null; then
		echo "TimescaleDB extension already configured in postgresql.conf."
	else
		echo "Configuring TimescaleDB in postgresql.conf"
		if [ -z "$DRY_RUN" ]; then
			sed -Ei -e 's/#?shared_preload_libraries = '"''"'/shared_preload_libraries = '"'timescaledb'/" \
				/var/db/postgres/data96/postgresql.conf
		fi
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
	#pkg_install bash
	if [ ! -d /db-init ]; then
		echo "Missing /db-init setup directory.";
	else
		cd /db-init
		./bin/setup-db.sh -mrv -d solarnetwork -L example/tsdb-init-users.sql
	fi
	
}

setup_pkgs
setup_hostname
setup_postgres
setup_db
