#!/bin/sh -e

PG_USER="pgsql"
PG_GROUP="pgsql"
PG12_HOME="/solar93/12"
PKG_CONF="/usr/local/etc/pkg/repos/poudriere.conf"
PG12_REPO="http://poudriere/packages/postgres12_122x64-tsdb1"
POOLS="db/solar93 db2/data93 solar/wal96"
PG12_WAL_DATASET="solar/wal12"
PG_TMP_BIN="/var/tmp/pg-upgrade"
RC_CONF="/etc/rc.conf.full"

service postgresql onestop || true

# Initial snapshot
for p in $POOLS; do
	if ! zfs list -Hpt snapshot "$p@pre-pg12" >/dev/null 2>&1; then
		echo "Creating ZFS snapshot $p@pre-pg12"
		zfs snapshot -r "$p@pre-pg12"
	fi
done

if [ ! -d "${PG12_HOME}" ]; then
	echo "Creating PG12 home ${PG12_HOME}"
	mkdir "${PG12_HOME}"
	chown -R "${PG_USER}:${PG_GROUP}" "${PG12_HOME}"
	chmod -R 755 "${PG12_HOME}"
fi

# point postgres to 12 dir
if ! grep -q "${PG12_HOME}" /etc/rc.conf; then
	echo "Updating postgresql_data in /etc/rc.conf..."
	sed -i '' -e '/postgresql_data/c\
postgresql_data="'"${PG12_HOME}"'"\
' "${RC_CONF}"
fi

# point pkg to PG 12 repo
if ! grep -q "${PG12_REPO}" "${PKG_CONF}"; then
	echo "Updating pkg repo configuration ${PKG_CONF} to use ${PG12_REPO}"
	sed -ie '/url:/c\
	url: "'"${PG12_REPO}"'"\
' "${PKG_CONF}"
	pkg update
fi

# install 9.6 into temp location
if [ ! -d "${PG_TMP_BIN}" ]; then
	echo "Installing Postgres 9.6 binaries into ${PG_TMP_BIN}"
	mkdir "${PG_TMP_BIN}"
	tar xf /var/cache/pkg/postgresql96-server-9.6.20.txz -C "${PG_TMP_BIN}"
	tar xf /var/cache/pkg/postgresql96-contrib-9.6.20.txz -C "${PG_TMP_BIN}"
	tar xf /var/cache/pkg/timescaledb-1.7.4_1.txz -C "${PG_TMP_BIN}"
fi

pkg delete -fy databases/postgresql96-server databases/postgresql96-contrib databases/postgresql96-client postgresql96-plv8js

# install PG 12
pkg install -y databases/postgresql12-server databases/postgresql12-contrib databases/postgresql12-client databases/timescaledb1

# init new cluster
service postgresql oneinitdb

# Setup shared preload
if ! grep -q timescaledb "${PG12_HOME}/postgresql.conf"; then
	echo "Configuring shared_preload_libraries in ${PG12_HOME}/postgresql.conf"
	sed -ie "/shared_preload_libraries =/c\\
shared_preload_libraries = 'timescaledb,pg_stat_statements'\\
" "${PG12_HOME}/postgresql.conf"
fi

# Create WAL dataset
if [ ! -d "${PG12_HOME}/pg_xlog" ]; then
	echo "Creating WAL dataset ${PG12_WAL_DATASET}"
	zfs create -o "mountpoint=${PG12_HOME}/pg_xlog" "${PG12_WAL_DATASET}"
	chown postgres:postgres "${PG12_HOME}/pg_xlog"
	mv "${PG12_HOME}/pg_wal/*" "${PG12_HOME}/pg_xlog/"
	rmdir "${PG12_HOME}/pg_wal"
	zfs set "mountpoint=${PG12_HOME}/pg_wal" "${PG12_WAL_DATASET}"
fi
