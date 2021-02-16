#!/bin/sh -e

service postgresql onestart
su -l postgres -c "psql -U pgsql -d postgres -c 'alter user postgres rename to postgres_'"
su -l postgres -c "psql -U postgres_ -d postgres -c 'alter user pgsql rename to postgres'"
su -l postgres -c "psql -d solarnetwork -c 'drop extension plv8 cascade'"

service postgresql onestop
zfs create -o mountpoint=/tsdb/data tsdb-data/data
mkdir /tsdb/data/12
chown -R postgres:postgres /tsdb/data
chmod -R 755 /tsdb/data

# Move data96 dataset into parent
echo "Moving 9.6 database to parent ZFS dataset..."
cp -a /tsdb/data96 /tsdb/data/9.6
rm -rf /tsdb/data/9.6/pg_xlog

# point postgres to 12 dir
sed -ie 's/\/tsdb\/data96/\/tsdb\/data\/12/' /etc/rc.conf

# point pkg to PG 12 repo
sed -ie 's/url: "\(.*\)"/url: "http:\/\/poudriere\/packages\/postgres12_122x64-tsdb1"/' \
    /usr/local/etc/pkg/repos/poudriere.conf
pkg update

# install 9.6 into temp location
echo "Installing Postgres 9.6 binaries into /var/tmp/pg-upgrade"
mkdir /var/tmp/pg-upgrade
tar xf /var/cache/pkg/postgresql96-server-9.6.20.txz -C /var/tmp/pg-upgrade
tar xf /var/cache/pkg/postgresql96-contrib-9.6.20.txz -C /var/tmp/pg-upgrade
tar xf /var/cache/pkg/timescaledb-1.7.4_1.txz -C /var/tmp/pg-upgrade
pkg delete -fy databases/postgresql96-server databases/postgresql96-contrib databases/postgresql96-client

# install PG 12
pkg install -y databases/postgresql12-server databases/postgresql12-contrib databases/postgresql12-client databases/timescaledb1

# init new cluster
service postgresql oneinitdb

# Setup shared preload
sed -ie "/shared_preload_libraries =/c\\
shared_preload_libraries = 'timescaledb,pg_stat_statements'\\
" /tsdb/data/12/postgresql.conf

# Copy settings
mv /tsdb/data/12/pg_hba.conf /tsdb/data/12/pg_hba.conf.default
cp -a /tsdb/data/9.6/pg_hba.conf /tsdb/data/12/
cp -a /tsdb/data/9.6/postgresql.conf /tsdb/data/12/postgresql.conf.96backup
chmod ugo-w /tsdb/data/12/postgresql.conf.96backup

# Create WAL dataset
zfs create -o mountpoint=/tsdb/data/12/pg_xlog wal96/wal12
chown postgres:postgres /tsdb/data/12/pg_xlog
zfs set mountpoint=/tsdb/data/9.6/pg_xlog wal96/wal96
