#!/bin/sh -e
#
# Upgrade SNDB (dev) Postgres 15 -> 17

PGPKG_OLDSERVER_VERS=15.12_1
PGPKG_OLDCONTRIB_VERS=15.12
TSPKG_OLDVERS=2.19.1

PKG_HOME=/var/tmp/pgupgrade/17
PKG_PKG=$PKG_HOME/pkg
PKG_ROOT=$PKG_HOME/root

service postgresql onestop || true

# create backup packages
echo "Creating Postgres 15 backup packages in $PKG_PKG"
mkdir -p $PKG_PKG
pkg create -o $PKG_PKG postgresql15-server postgresql15-contrib timescaledb postgresql-aggs_for_vecs

# install 12 packages into temp location
echo "Installing Postgres 15 binaries into $PKG_ROOT"
rm -rf $PKG_ROOT
mkdir -p $PKG_ROOT
tar xf $PKG_PKG/postgresql15-server-$PGPKG_OLDSERVER_VERS.pkg -C $PKG_ROOT
tar xf $PKG_PKG/postgresql15-contrib-$PGPKG_OLDCONTRIB_VERS.pkg -C $PKG_ROOT
tar xf $PKG_PKG/timescaledb-$TSPKG_OLDVERS.pkg -C $PKG_ROOT
tar xf $PKG_PKG/postgresql-aggs_for_vecs-1.3.2_1.pkg -C $PKG_ROOT

echo "Deleting Postgres 15 packages"
pkg delete -fy databases/postgresql15-server databases/postgresql15-contrib databases/postgresql15-client databases/timescaledb databases/postgresql-aggs_for_vecs

# point pkg to PG 17 repo
sed -ie 's/url: "\(.*\)"/url: "http:\/\/poudriere\/packages\/solardb_142x64-tsdb5"/' \
    /usr/local/etc/pkg/repos/snf.conf
pkg update

# install PG 17
echo "Installing Postgres 17 packages"
pkg install -r snf -y databases/postgresql17-server databases/postgresql17-contrib databases/postgresql17-client databases/timescaledb databases/postgresql-aggs_for_vecs

# init new cluster
echo "Initializing Postgres 17 cluster"
sed -ie 's/\/sndb\/home\/15/\/sndb\/home\/17/' /etc/rc.conf
service postgresql oneinitdb

echo "Creating WAL filesystem"

# Create WAL dataset, and move init WAL there
mkdir /sndb/wal/17
chown postgres:postgres /sndb/wal/17
chmod 700 /sndb/wal/17
mv /sndb/home/17/pg_wal/* /sndb/wal/17
rmdir /sndb/home/17/pg_wal
ln -s /sndb/wal/17 /sndb/home/17/pg_wal

# Create log dir
mkdir /sndb/log/17
chown postgres:postgres /sndb/log/17

echo "Configuring Postgres 17 cluster"

# create backup of original configuration
cp -a /sndb/home/17/postgresql.conf /sndb/home/17/postgresql.conf.orig

# Setup shared preload
sed -ie "/shared_preload_libraries =/c\\
shared_preload_libraries = 'timescaledb,pg_stat_statements'\\
" /sndb/home/17/postgresql.conf

# Copy settings
cp -a /sndb/home/17/pg_hba.conf /sndb/home/17/pg_hba.conf.orig
cp -a /sndb/home/15/pg_hba.conf /sndb/home/17/
cp -a /sndb/home/12/postgresql.conf /sndb/home/17/postgresql.conf.12backup
chmod ugo-w /sndb/home/17/postgresql.conf.12backup
