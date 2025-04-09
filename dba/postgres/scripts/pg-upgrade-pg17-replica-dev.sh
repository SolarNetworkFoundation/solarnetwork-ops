#!/bin/sh -e
#
# Upgrade SNDB Replica (dev) Postgres 12 -> 17

PGPKG_OLDSERVER_VERS=12.22
PGPKG_OLDCONTRIB_VERS=12.22
TSPKG_OLDVERS=2.10.2

TSPKG_OLDNAME="timescaledb210"

service postgresql onestop || true

echo "Deleting Postgres 12 packages"
pkg delete -fy databases/postgresql12-server databases/postgresql12-contrib databases/postgresql12-client databases/$TSPKG_OLDNAME databases/postgresql-aggs_for_vecs

# point pkg to PG 17 repo
sed -ie 's/url: "\(.*\)"/url: "http:\/\/poudriere\/packages\/solardb_142x64-tsdb5"/' \
    /usr/local/etc/pkg/repos/snf.conf
pkg update

# install PG 17
echo "Installing Postgres 17 packages"
pkg install -r snf -y databases/postgresql17-server databases/postgresql17-contrib databases/postgresql17-client databases/timescaledb databases/postgresql-aggs_for_vecs

# upgrade packages
pkg upgrade -r snf -y

# create log dir
mkdir /sndb/log/17
chown postgres:postgres /sndb/log/17
