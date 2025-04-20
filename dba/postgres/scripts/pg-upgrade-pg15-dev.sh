#!/bin/sh -e
#
# Upgrade SNDB (dev) Postgres 12 -> 15

PKG_HOME=/var/tmp/pgupgrade/15
PKG_PKG=$PKG_HOME/pkg
PKG_ROOT=$PKG_HOME/root

# Because on production the package name is different ('timescaledb' v 'timescaledb210')
TSPKG_OLDNAME="timescaledb210"
TSPKG_NEWNAME="timescaledb210"

# Because on production the version differs (2.10.1 v 2.10.2)
TSPKG_OLDVERS=2.10.2

PGPKG_OLDSERVER_VERS=12.22
PGPKG_OLDCONTRIB_VERS=12.22

A4V_OLDVERS=1.3.2_1

service postgresql onestop || true

# create backup packages
echo "Creating Postgres 12 backup packages in $PKG_PKG"
mkdir -p $PKG_PKG
pkg create -o $PKG_PKG postgresql12-server postgresql12-contrib $TSPKG_OLDNAME postgresql-aggs_for_vecs

# install 12 packages into temp location
echo "Installing Postgres 12 binaries into $PKG_ROOT"
mkdir -p $PKG_ROOT
tar xf $PKG_PKG/postgresql12-server-$PGPKG_OLDSERVER_VERS.pkg -C $PKG_ROOT
tar xf $PKG_PKG/postgresql12-contrib-$PGPKG_OLDCONTRIB_VERS.pkg -C $PKG_ROOT
tar xf $PKG_PKG/$TSPKG_OLDNAME-$TSPKG_OLDVERS.pkg -C $PKG_ROOT
tar xf $PKG_PKG/postgresql-aggs_for_vecs-$A4V_OLDVERS.pkg -C $PKG_ROOT

echo "Deleting Postgres 12 packages"
pkg delete -fy databases/postgresql12-server databases/postgresql12-contrib databases/postgresql12-client databases/$TSPKG_OLDNAME databases/postgresql-aggs_for_vecs

# point pkg to PG 15 repo
sed -ie 's/url: "\(.*\)"/url: "http:\/\/poudriere\/packages\/solardb_142x64-tsdb3"/' \
    /usr/local/etc/pkg/repos/snf.conf
pkg update

# install PG 15
echo "Installing Postgres 15 packages"
pkg install -r snf -y databases/postgresql15-server databases/postgresql15-contrib databases/postgresql15-client databases/$TSPKG_NEWNAME databases/postgresql-aggs_for_vecs

# init new cluster
echo "Initializing Postgres 15 cluster"
sed -ie 's/\/sndb\/home\/12/\/sndb\/home\/15/' /etc/rc.conf
service postgresql oneinitdb

echo "Creating WAL filesystem"

# Create WAL dataset, and move init WAL there
mkdir /sndb/wal/15
chown postgres:postgres /sndb/wal/15
chmod 700 /sndb/wal/15
mv /sndb/home/15/pg_wal/* /sndb/wal/15
rmdir /sndb/home/15/pg_wal
ln -s /sndb/wal/15 /sndb/home/15/pg_wal

echo "Configuring Postgres 15 cluster"

# Setup shared preload
sed -ie "/shared_preload_libraries =/c\\
shared_preload_libraries = 'timescaledb,pg_stat_statements'\\
" /sndb/home/15/postgresql.conf

# Copy settings
mv /sndb/home/15/pg_hba.conf /sndb/home/15/pg_hba.conf.orig
cp -a /sndb/home/12/pg_hba.conf /sndb/home/15/
cp -a /sndb/home/12/postgresql.conf /sndb/home/15/postgresql.conf.12backup
chmod ugo-w /sndb/home/15/postgresql.conf.12backup
