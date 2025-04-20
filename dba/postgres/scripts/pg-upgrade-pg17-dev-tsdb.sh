#!/bin/sh -e
#
# Upgrade TSDB (dev) Postgres 15 -> 17

PKG_HOME=/var/tmp/pgupgrade
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
tar xf $PKG_PKG/postgresql15-server-15.12_1.pkg -C $PKG_ROOT
tar xf $PKG_PKG/postgresql15-contrib-15.12.pkg -C $PKG_ROOT
tar xf $PKG_PKG/timescaledb-2.18.1.pkg -C $PKG_ROOT
tar xf $PKG_PKG/postgresql-aggs_for_vecs-1.3.2_1.pkg -C $PKG_ROOT

echo "Deleting Postgres 15 packages"
pkg delete -fy databases/postgresql15-server databases/postgresql15-contrib databases/postgresql15-client databases/timescaledb databases/postgresql-aggs_for_vecs

# point pkg to PG 17 repo
sed -ie 's/url: "\(.*\)"/url: "http:\/\/poudriere\/packages\/solardb_142x64-tsdb5"/' \
    /usr/local/etc/pkg/repos/poudriere.conf
pkg update

# install PG 17
echo "Installing Postgres 17 packages"
pkg install -r poudriere -y databases/postgresql17-server databases/postgresql17-contrib databases/postgresql17-client databases/timescaledb databases/postgresql-aggs_for_vecs

# init new cluster
echo "Initializing Postgres 17 cluster"
sed -ie 's/\/tsdb\/data\/15/\/tsdb\/data\/17/' /etc/rc.conf
service postgresql oneinitdb

echo "Creating WAL filesystem"

# Create WAL dataset, and move init WAL there
mkdir /tsdb/wal/17
chown postgres:postgres /tsdb/wal/17
chmod 700 /tsdb/wal/17
mv /tsdb/data/17/pg_wal/* /tsdb/wal/17
rmdir /tsdb/data/17/pg_wal
ln -s /tsdb/wal/17 /tsdb/data/17/pg_wal

echo "Configuring Postgres 17 cluster"

# Setup shared preload
sed -ie "/shared_preload_libraries =/c\\
shared_preload_libraries = 'timescaledb,pg_stat_statements'\\
" /tsdb/data/17/postgresql.conf

# Copy settings
mv /tsdb/data/17/pg_hba.conf /tsdb/data/17/pg_hba.conf.default
cp -a /tsdb/data/15/pg_hba.conf /tsdb/data/17/
cp -a /tsdb/data/15/postgresql.conf /tsdb/data/17/postgresql.conf.15backup
chmod ugo-w /tsdb/data/17/postgresql.conf.15backup
