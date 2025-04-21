# Postgres 12 to 17 upgrade packages plan

See the [12 to 17 upgrade](./Postgres-12-to-17-upgrade.md) for a general overview of the upgrade
plan. This guide describes how Poudriere is used to publish various FreeBSD package repositories
required to support the upgrade process.

Following the same [tsdb1 setup](./FreeBSD-setup-tsdb1-poudriere-portshaker.md) process already in
place, create a `tsdb2` ports tree that is a merge of the `freebsd-12` and `sn-custom` trees,
followed by a `tsdb3` ports tree that is a merge of the `freebsd-14` and `sn-custom` trees, for
Postgres 15, then a `tsdb4` ports tree that is a merge of the `freebsd` (head) and `sn-custom`
trees, for Postgres 15 + Timescale 2.19, and then `tsdb5` for Postgers 17 + Timescale 2.19.

# Portshaker

Set up some ZFS datasets:

```sh
sudo zfs create -o mountpoint=/usr/local/poudriere/ports/tsdb2 zpoud/poudriere/ports/tsdb2
sudo zfs create -o mountpoint=/usr/local/poudriere/ports/tsdb3 zpoud/poudriere/ports/tsdb3
sudo zfs create -o mountpoint=/usr/local/poudriere/ports/tsdb4 zpoud/poudriere/ports/tsdb4
sudo zfs create -o mountpoint=/usr/local/poudriere/ports/tsdb5 zpoud/poudriere/ports/tsdb5
```

Create self-managed ports tree for poudriere:

```sh
sudo poudriere ports -c -m null -M /usr/local/poudriere/ports/tsdb2 -p tsdb2
sudo poudriere ports -c -m null -M /usr/local/poudriere/ports/tsdb3 -p tsdb3
sudo poudriere ports -c -m null -M /usr/local/poudriere/ports/tsdb4 -p tsdb4
sudo poudriere ports -c -m null -M /usr/local/poudriere/ports/tsdb5 -p tsdb5
```

Configured `/usr/local/etc/portshaker.conf` with:

```
# vim:set syntax=sh:

#---[ Base directory for mirrored Ports Trees ]---
mirror_base_dir="/var/cache/portshaker"

#---[ Directories where to merge ports ]---
ports_trees="tsdb1 tsdb2 tsdb3 tsdb4 tsdb5"

# FreeBSD 12, Postgres 12, TS 2.10
tsdb1_ports_tree="/usr/local/poudriere/ports/tsdb1"
tsdb1_merge_from="freebsd-12 sn-custom"

# FreeBSD 14, Postgres 12, TS 2.10
tsdb2_ports_tree="/usr/local/poudriere/ports/tsdb2"
tsdb2_merge_from="freebsd-14 sn-custom"

# FreeBSD 14, Postgres 15, TS 2.10
tsdb3_ports_tree="/usr/local/poudriere/ports/tsdb3"
tsdb3_merge_from="freebsd-14 sn-custom"

# FreeBSD 14, Postgres 15, TS 2.19
tsdb4_ports_tree="/usr/local/poudriere/ports/tsdb4"
tsdb4_merge_from="freebsd sn-custom"

# FreeBSD 14, Postgres 17, TS 2.19
tsdb4_ports_tree="/usr/local/poudriere/ports/tsdb5"
tsdb4_merge_from="freebsd sn-custom"
```

## FreeBSD portshaker trees

(Re)configured `/usr/local/etc/portshaker.d/freebsd` with:

```sh
#!/bin/sh
. /usr/local/share/portshaker/portshaker.subr
if [ "$1" != '--' ]; then
  err 1 "Extra arguments"
fi
shift
method="git"
git_clone_uri="https://github.com/freebsd/freebsd-ports.git"
git_branch=main
run_portshaker_command $*
```

Then need to use a stable snapshot of the ports tree from the time of FreeBSD 14.
Decided that the `2024Q4` branch works for this purpose (last quarterly release
with Postgres 12).

Configured `/usr/local/etc/portshaker.d/freebsd-14` with:

```sh
#!/bin/sh
. /usr/local/share/portshaker/portshaker.subr
if [ "$1" != '--' ]; then
  err 1 "Extra arguments"
fi
shift
method="git"
git_clone_uri="https://github.com/freebsd/freebsd-ports.git"
git_branch=2024Q4
run_portshaker_command $*
```

Then set permissions:

```sh
sudo chmod 755 /usr/local/etc/portshaker.d/freebsd-14
```

## Update Portshaker

```sh
sudo portshaker -UM
```

# Poudriere jail

Create the 14.2 build jail:

```sh
# create jail
sudo poudriere jail -c -j solardb_142x64 -v 14.2-RELEASE
```

## tsdb2 build

This is Postgres 12 + Timescale 2.10.2

```
# copy settings for new jail
sudo cp -a /usr/local/etc/poudriere.d/solardb_pg12_123x64-make.conf /usr/local/etc/poudriere.d/solardb_142x64-tsdb2-make.conf
sudo cp -a /usr/local/etc/poudriere.d/solardb_pg12_123x64-tsdb1-options /usr/local/etc/poudriere.d/solardb_142x64-tsdb2-options
sudo cp -a /usr/local/etc/poudriere.d/solardb_pg12-port-list /usr/local/etc/poudriere.d/solardb-tsdb2-port-list
```
 
Run through build options:

```sh
sudo poudriere options -j solardb_142x64 -p tsdb2 -f /usr/local/etc/poudriere.d/solardb-tsdb2-port-list
```

Build:

```sh
sudo poudriere bulk -j solardb_142x64 -p tsdb2 -f /usr/local/etc/poudriere.d/solardb-tsdb2-port-list
``` 

## tsdb3 build

This is Postgres 15 + Timescale 2.10.2 + Timescale 2.19.3

Set up `tsdb3` build:

```sh
# copy settings for new jail
sudo cp -a /usr/local/etc/poudriere.d/solardb_142x64-tsdb2-options /usr/local/etc/poudriere.d/solardb_142x64-tsdb3-options
sudo cp -a /usr/local/etc/poudriere.d/solardb_142x64-tsdb2-make.conf /usr/local/etc/poudriere.d/solardb_142x64-tsdb3-make.conf
sudo cp -a /usr/local/etc/poudriere.d/solardb_pg12-port-list /usr/local/etc/poudriere.d/solardb-tsdb3-port-list
```
 
Set `/usr/local/etc/poudriere.d/solardb_142x64-tsdb3-make.conf` to:

```
DEFAULT_VERSIONS+=pgsql=15 ssl=openssl

OPTIONS_UNSET+= DOCS EXAMPLES TEST

ALLOW_UNSUPPORTED_SYSTEM=yes
```

Set `/usr/local/etc/poudriere.d/solardb-tsdb3-port-list` to:

```
archivers/liblz4
archivers/lzop
archivers/zstd
databases/pgbackrest
databases/postgresql15-contrib
databases/postgresql15-server
databases/postgresql-aggs_for_vecs
databases/timescaledb 
databases/timescaledb210
databases/timescaledb211
devel/git
devel/py-awscli
ftp/curl
mail/postfix
net/rsync
ports-mgmt/pkg
security/py-certbot
security/py-certbot-dns-route53
sysutils/daemontools
sysutils/munin-contrib
sysutils/munin-node
sysutils/tmux
sysutils/pv
```

Run through build options:

```sh
sudo poudriere options -j solardb_142x64 -p tsdb3 -f /usr/local/etc/poudriere.d/solardb-tsdb3-port-list
```

Build:

```sh
sudo poudriere bulk -j solardb_142x64 -p tsdb3 -f /usr/local/etc/poudriere.d/solardb-tsdb3-port-list
``` 

## tsdb4 build

This is Postgres 15 + Timescale 2.19.3

Set up `tsdb4` build:

```sh
# copy settings for new jail
sudo cp -a /usr/local/etc/poudriere.d/solardb_142x64-tsdb3-options /usr/local/etc/poudriere.d/solardb_142x64-tsdb4-options
sudo cp -a /usr/local/etc/poudriere.d/solardb_142x64-tsdb3-make.conf /usr/local/etc/poudriere.d/solardb_142x64-tsdb4-make.conf
sudo cp -a /usr/local/etc/poudriere.d/solardb-tsdb3-port-list /usr/local/etc/poudriere.d/solardb-tsdb4-port-list
```
 
Set `/usr/local/etc/poudriere.d/solardb_142x64-tsdb4-make.conf` to:

```
DEFAULT_VERSIONS+=pgsql=15 ssl=openssl

OPTIONS_UNSET+= DOCS EXAMPLES TEST

ALLOW_UNSUPPORTED_SYSTEM=yes
```

Set `/usr/local/etc/poudriere.d/solardb-tsdb4-port-list` to:

```
archivers/liblz4
archivers/lzop
archivers/zstd
databases/pgbackrest
databases/postgresql15-contrib
databases/postgresql15-server
databases/postgresql-aggs_for_vecs
databases/timescaledb 
devel/git
devel/py-awscli
ftp/curl
mail/postfix
net/rsync
ports-mgmt/pkg
security/py-certbot
security/py-certbot-dns-route53
sysutils/daemontools
sysutils/munin-contrib
sysutils/munin-node
sysutils/tmux
sysutils/pv
```

```sh
sudo poudriere options -j solardb_142x64 -p tsdb4 -f /usr/local/etc/poudriere.d/solardb-tsdb4-port-list
```

Build:

```sh
sudo poudriere bulk -j solardb_142x64 -p tsdb4 -f /usr/local/etc/poudriere.d/solardb-tsdb4-port-list
``` 

## tsdb5 build

This is Postgres 17 + Timescale 2.19.3

Set up `tsdb5` build:

```sh
# copy settings for new jail
sudo cp -a /usr/local/etc/poudriere.d/solardb_142x64-tsdb4-options /usr/local/etc/poudriere.d/solardb_142x64-tsdb5-options
sudo cp -a /usr/local/etc/poudriere.d/solardb_142x64-tsdb4-make.conf /usr/local/etc/poudriere.d/solardb_142x64-tsdb5-make.conf
sudo cp -a /usr/local/etc/poudriere.d/solardb-tsdb4-port-list /usr/local/etc/poudriere.d/solardb-tsdb5-port-list
```
 
Set `/usr/local/etc/poudriere.d/solardb_142x64-tsdb5-make.conf` to:

```
DEFAULT_VERSIONS+=pgsql=17 ssl=openssl

OPTIONS_UNSET+= DOCS EXAMPLES TEST

ALLOW_UNSUPPORTED_SYSTEM=yes
```

Set `/usr/local/etc/poudriere.d/solardb-tsdb5-port-list` to:

```
archivers/liblz4
archivers/lzop
archivers/zstd
databases/pgbackrest
databases/postgresql17-contrib
databases/postgresql17-server
databases/postgresql-aggs_for_vecs
databases/timescaledb 
devel/git
devel/py-awscli
ftp/curl
mail/postfix
net/rsync
ports-mgmt/pkg
security/py-certbot
security/py-certbot-dns-route53
sysutils/daemontools
sysutils/munin-contrib
sysutils/munin-node
sysutils/tmux
sysutils/pv
```

```sh
sudo poudriere options -j solardb_142x64 -p tsdb5 -f /usr/local/etc/poudriere.d/solardb-tsdb5-port-list
```

Build:

```sh
sudo poudriere bulk -j solardb_142x64 -p tsdb5 -f /usr/local/etc/poudriere.d/solardb-tsdb5-port-list
``` 

# Build all

```sh
sudo su -
zsh
for v in 2 3 4 5; do poudriere bulk -j solardb_142x64 -p tsdb$v -f /usr/local/etc/poudriere.d/solardb-tsdb$v-port-list; done
```
