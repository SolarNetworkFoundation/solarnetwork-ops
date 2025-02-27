#!/bin/sh -e
#
# Upgrade TSDB (dev) Postgres 12 -> 15

PKG_HOME=/var/tmp/pgupgrade
PKG_PKG=$PKG_HOME/pkg
PKG_ROOT=$PKG_HOME/root

service postgresql onestart || true

# make 'postgres' OID 10, to satisfy pg_upgrade
su -l postgres -c 'psql -c "CREATE ROLE temp WITH SUPERUSER CREATEDB CREATEROLE REPLICATION BYPASSRLS LOGIN PASSWORD '"'temp'"'"'
su -l postgres -c 'psql -d postgres -U temp -c "ALTER ROLE pgsql RENAME TO pgsql_"'
su -l postgres -c 'psql -d postgres -U temp -c "ALTER ROLE postgres RENAME TO pgsql"'
su -l postgres -c 'psql -d postgres -U temp -c "ALTER ROLE pgsql_ RENAME TO postgres"'
su -l postgres -c 'psql -d postgres -c "DROP ROLE temp"'

service postgresql onestop

# create backup packages
echo "Creating Postgres 12 backup packages in $PKG_PKG"
mkdir -p $PKG_PKG
pkg create -o $PKG_PKG postgresql12-server postgresql12-contrib timescaledb211 postgresql-aggs_for_vecs

# install 12 packages into temp location
echo "Installing Postgres 12 binaries into $PKG_ROOT"
mkdir -p $PKG_ROOT
tar xf $PKG_PKG/postgresql12-server-12.22.pkg -C $PKG_ROOT
tar xf $PKG_PKG/postgresql12-contrib-12.22.pkg -C $PKG_ROOT
tar xf $PKG_PKG/timescaledb211-2.11.2.pkg -C $PKG_ROOT
tar xf $PKG_PKG/postgresql-aggs_for_vecs-1.3.0_1.pkg -C $PKG_ROOT

echo "Deleting Postgres 12 packages"
pkg delete -fy databases/postgresql12-server databases/postgresql12-contrib databases/postgresql12-client databases/timescaledb211 databases/postgresql-aggs_for_vecs

# point pkg to PG 15 repo
sed -ie 's/url: "\(.*\)"/url: "http:\/\/poudriere\/packages\/solardb_142x64-tsdb3"/' \
    /usr/local/etc/pkg/repos/poudriere.conf
pkg update

# install PG 15
echo "Installing Postgres 15 packages"
pkg install -y databases/postgresql15-server databases/postgresql15-contrib databases/postgresql15-client databases/timescaledb211 databases/postgresql-aggs_for_vecs

# init new cluster
echo "Initializing Postgres 15 cluster"
sed -ie 's/\/tsdb\/data\/12/\/tsdb\/data\/15/' /etc/rc.conf
service postgresql oneinitdb

echo "Creating WAL filesystem"

# Create WAL dataset, and move init WAL there
mkdir /tsdb/wal/15
chown postgres:postgres /tsdb/wal/15
chmod 700 /tsdb/wal/15
mv /tsdb/data/15/pg_wal/* /tsdb/wal/15
rmdir /tsdb/data/15/pg_wal
ln -s /tsdb/wal/15 /tsdb/data/15/pg_wal

echo "Configuring Postgres 15 cluster"

# Setup shared preload
sed -ie "/shared_preload_libraries =/c\\
shared_preload_libraries = 'timescaledb,pg_stat_statements'\\
" /tsdb/data/15/postgresql.conf

# Copy settings
mv /tsdb/data/15/pg_hba.conf /tsdb/data/15/pg_hba.conf.default
cp -a /tsdb/data/12/pg_hba.conf /tsdb/data/15/
cp -a /tsdb/data/12/postgresql.conf /tsdb/data/15/postgresql.conf.12backup
chmod ugo-w /tsdb/data/15/postgresql.conf.12backup
