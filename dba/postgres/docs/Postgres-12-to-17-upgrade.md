# Postgres 12 to 17 upgrade plan

The production Postgres systems are running on FreeBSD 12.3 with Postgres 12.14 and Timescale 2.10.1.
Postgres 12 is no longer supported, so this document outlines the plan for upgrading to Postgres
17 (the latest release at the time of this writing).

Complicating this upgrade is the TimescaleDB extension. Version 2.10.1 only supports Postgres up
to version 15. So first Postgres must be upgraded to version 15. Then Timescale can be updated to
version 2.19.x (the latest release at the time of this writing). Then Postgres can be updated to
version 17.

See [the Timescale docs](https://docs.timescale.com/self-hosted/latest/upgrades/major-upgrade/#plan-your-upgrade-path)
for reference.

Finally, FreeBSD 12.3 is no longer supported. A secondary goal is to update the OS to a more 
recent, supported version, which is 14.2 at the time of this writing.

So overall, the upgrade plan looks like this:

 1. Upgrade FreeBSD to 14.2, using custom `timescaledb210` port to stay on Timescale 2.10.1 and
    updating to the latest Postgres 12.x release.
 2. Upgrade Postgres to latest 15.x release. Upgrade pgBackRest stanza.
 3. Upgrade Timescale to 2.19.x release. Perform full pgBackRest backup.
 4. Upgrade Postgres to latest 17.x release. Upgrade pgBackRest stanza.

See [this blog post](https://pgstef.github.io/2019/03/01/postgresql_major_version_upgrade_impact_on_pgbackrest.html)
for a helpful example of upgrading pgBackRest's stanza, which must be done with each Postgres major
upgrade.

# Poudriere setup

Following the same [tsdb1 setup](./FreeBSD-setup-tsdb1-poudriere-portshaker.md) process, create
a `tsdb2` ports tree that is a merge of the `freebsd-12` and `sn-custom` trees, followed
by a `tsdb3` ports tree that is a merge of the `freebsd-14` and `sn-custom` trees, for Postgres 15,
then a `tsdb4` ports tree that is a merge of the `freebsd` (head) and `sn-custom` trees, for
Postgres 15 + Timescale 2.19, and then `tsdb5` for Postgers 17 + Timescale 2.19.

## Portshaker

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

### FreeBSD portshaker trees

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

### Update Portshaker

```sh
sudo portshaker -UM
```

## Poudriere jail

Create the 14.2 build jail:

```sh
# create jail
sudo poudriere jail -c -j solardb_142x64 -v 14.2-RELEASE
```

### tsdb2 build

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

### tsdb3 jail

This is Postgres 15 + Timescale 2.10.2 + Timescale 2.19.1

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

### tsdb4 jail

This is Postgres 15 + Timescale 2.19.1

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

### Build all

```sh
sudo su -
zsh
for v in 2 3 4 5; do poudriere bulk -j solardb_142x64 -p tsdb$v -f /usr/local/etc/poudriere.d/solardb-tsdb$v-port-list; done
```

### tsdb5 jail

This is Postgres 17 + Timescale 2.19.1

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

### Build all

```sh
sudo su -
zsh
for v in 2 3 4; do poudriere bulk -j solardb_142x64 -p tsdb$v -f /usr/local/etc/poudriere.d/solardb_pg12-tsdb$v-port-list; done
```

# Pre upgrade prep

The `adminpack` module is removed from PG 17, and the upgrade will fail if that extension is
installed in any database. So check to remove it, e.g.

```sh
# check
for db in template1 postgres solarnetwork; do su -l postgres -c "psql -d $db -c '\\dx'"; done

# remove
for db in template1 postgres solarnetwork; do su -l postgres -c "psql -d $db -c 'DROP EXTENSION IF EXISTS adminpack'"; done
```

# Upgrade to FreeBSD 14.2

Using the [past update from Postgres 9 to 12](../../../sys/maintenance-reports/SN%20Maintenance%202021-03-21%20report.md)
as a guide, the following general procedure is used.

```sh
# Start OS upgrade (downloads about 2GB of files)
freebsd-update -r 14.2-RELEASE upgrade

# merge updates... then install updates
/usr/sbin/freebsd-update install
```

Now have to reboot, then run install again:

```sh
reboot

# log back in...

/usr/sbin/freebsd-update install
```

Now have to update packages, so edit `/usr/local/etc/pkg/repos/snf.conf` to point to 14.2
and `tsdb2` URL (for example `http://poudriere/packages/solardb_142x64-tsdb2`). Then:


```sh
pkg update

pkg upgrade

# can remove python39 (replaced by python311)
pkg remove python39
```

Finally, run update again:

```sh
/usr/sbin/freebsd-update install
```

And finally, found that `sshd` should be restarted for new connections to work:

```sh
service sshd restart
```

Free up rollback files to free up space:

```sh
rm -r /var/db/freebsd-update/*
```

# ZFS snapshots (Pre PG 15)

Create ZFS snapshots to allow rollback:

```
for f in dat idx wal; do zfs snapshot -r $f@pre-pg15-upgrade; done
```

If need to rollback to start again:

```sh
# rollback
for f in dat dat/dat dat/home dat/log idx idx/idx wal wal/wal; do zfs rollback $f@pre-pg15-upgrade; done
```

# Pre Upgrade prep

Disable `cron` to be safe. Add to `/etc/rc.conf`

```
# Cron
cron_enable="NO"
```

Then `service cron stop`.

# Upgrade to Postgres 15

Run the [upgrade prep script](../scripts/pg-upgrade-pg15-dev.sh) first. Then:

```
su - postgres

# create dir for upgrade output
mkdir up15
cd up15

pg_upgrade -U postgres -k \
	-b /var/tmp/pgupgrade/15/root/usr/local/bin \
	-d /sndb/home/12 \
	-B /usr/local/bin \
	-D /sndb/home/15 \
	-O "-c timescaledb.restoring='on'" \
	--check
```

Assuming all OK, re-run without the `--check`.

## Update extensions

Then start the server to update extensions:

```sh
# go back to root user, if still postgres
exit

service postgresql onestart

# run update_extensions.sql generated by pg_upgrade
su -l postgres -c 'psql -d solarnetwork -f up15/update_extensions.sql'
```

# Upgrade to Timescale 2.19

First update repo to `tsdb4` to get latest PG 15 + TS 2.19 packages. Then update packages and
switch to TS 2.19:

```sh
# stop postgres
service postgresql onestop

# point pkg to PG 15 + TS 2.19 repo
sed -ie 's/url: "\(.*\)"/url: "http:\/\/poudriere\/packages\/solardb_142x64-tsdb4"/' \
    /usr/local/etc/pkg/repos/snf.conf
pkg update

pkg upgrade -r snf
pkg install -r snf timescaledb

service postgresql onestart
su -l postgres -c "psql -x -d solarnetwork -c 'ALTER EXTENSION timescaledb UPDATE'"
service postgresql onestop
```

# ZFS snapshots (Pre PG 17)

Create ZFS snapshots to allow rollback:

```
for f in dat idx wal; do zfs snapshot -r $f@pre-pg17-upgrade; done
```

If need to rollback to start again:

```sh
# rollback
for f in dat dat/dat dat/home dat/log idx idx/idx wal wal/wal; do zfs rollback $f@pre-pg17-upgrade; done
```


# Upgrade to Postgres 17

Run the [upgrade prep script](../scripts/pg-upgrade-pg17-dev.sh) first. Then:

```
su - postgres

# create dir for upgrade output
mkdir up17
cd up17

pg_upgrade -U postgres -k \
	-b /var/tmp/pgupgrade/17/root/usr/local/bin \
	-d /sndb/home/15 \
	-B /usr/local/bin \
	-D /sndb/home/17 \
	-O "-c timescaledb.restoring='on'" \
	--check
```

Assuming all OK, re-run without the `--check`.

## Apply custom configuration

See the [configuration diff](../freebsd/postgresql.conf.12.diff) and apply changes to the PG17
configuration.

## Update pgBackRest

Update `~/pgbackrest.d/env` for new Postgres version, namely:

 1. `PGBACKREST_LOG_PATH` to `/sndb/log/17`
 2. `PGBACKREST_PG1_PATH` to `/sndb/home/17`

Run `stanza-upgrade`:

```sh
# as postgres user still...

envdir ~/pgbackrest.d/env pgbackrest --no-online stanza-upgrade
```

## Update extensions

Then start the server to update extensions:

```sh
# go back to root user, if still postgres
exit

service postgresql onestart

# run update_extensions.sql generated by pg_upgrade
su -l postgres -c 'psql -d solarnetwork -f up17/update_extensions.sql'
```

Then, verify pgBackRest:

```sh
su -l postgres -c 'envdir ~/pgbackrest.d/env pgbackrest --log-level-console=info check'
```

## Update statistics

Need to update all statistics:

```sh
# regenerate stats
su -l postgres -c '/usr/local/bin/vacuumdb -U postgres --all --analyze-in-stages'
```


# Perform full backup

```sh
su -l postgres -c 'envdir ~/pgbackrest.d/env pgbackrest --log-level-console=info --type=full --start-fast backup'
```


# ZFS snapshots (Post PG 17)

Create ZFS snapshots to allow rollback:

```
for f in dat idx wal; do zfs snapshot -r $f@post-pg17-upgrade; done
```

If need to rollback to start again:

```sh
# rollback
for f in dat dat/dat dat/home dat/log idx idx/idx wal wal/wal; do zfs rollback $f@post-pg17-upgrade; done
```

After a simulated upgrade, found not much space required by the snapshots:

```
zfs list -t snapshot
NAME                         USED  AVAIL  REFER  MOUNTPOINT
dat@pre-pg15-upgrade           0B      -    96K  -
dat@pre-pg17-upgrade           0B      -    96K  -
dat@post-pg17-upgrade          0B      -    96K  -
dat/dat@pre-pg15-upgrade    1.42M      -   179G  -
dat/dat@pre-pg17-upgrade    2.84M      -   179G  -
dat/dat@post-pg17-upgrade      8K      -   179G  -
dat/home@pre-pg15-upgrade    356K      -   571M  -
dat/home@pre-pg17-upgrade   1.68M      -  1.07G  -
dat/home@post-pg17-upgrade     8K      -  1.58G  -
dat/log@pre-pg15-upgrade      72K      -   164K  -
dat/log@pre-pg17-upgrade       0B      -   172K  -
dat/log@post-pg17-upgrade      0B      -   172K  -
idx@pre-pg15-upgrade           0B      -    96K  -
idx@pre-pg17-upgrade           0B      -    96K  -
idx@post-pg17-upgrade          0B      -    96K  -
idx/idx@pre-pg15-upgrade     192K      -  72.9G  -
idx/idx@pre-pg17-upgrade     184K      -  72.9G  -
idx/idx@post-pg17-upgrade      8K      -  72.9G  -
wal@pre-pg15-upgrade           0B      -    96K  -
wal@pre-pg17-upgrade           0B      -    96K  -
wal@post-pg17-upgrade          0B      -    96K  -
wal/wal@pre-pg15-upgrade     140K      -  12.5M  -
wal/wal@pre-pg17-upgrade     148K      -  15.7M  -
wal/wal@post-pg17-upgrade      8K      -    18M  -
```

# Update replica

Now is the time to update the replica, trying the [`rsync` method][rep-rsync] and falling back to
a full restore from pgBackRest if needed.

## Install rsync

Install `rsync` to validate rsync-style "fast" replica sync.

```sh
pkg install -r snf rsync
```

## Configure SSH access for postgres OS user

The `rsync` process will use `ssh` to connect, and will run as the `postgres` user, so
set up password-less access in `~/.ssh/authorized_keys` on the replica.

First generate key on **primary** server (without password):

```sh
ssh-keygen -t ed25519
```

Then on the **replica** server add the `~/.ssh/id_ed25519.pub` to `~/.ssh/authorized_keys`.

## Sync database

```sh
# sync home
rsync --archive --delete --hard-links --size-only --no-inc-recursive \
 /sndb/home/12 /sndb/home/17 sndb-a:/sndb/home \
 --verbose --dry-run 

# sync dat tablespace
rsync --archive --delete --hard-links --size-only --no-inc-recursive \
 /sndb/dat/PG_12_201909212 /sndb/dat/PG_17_202406281 sndb-a:/sndb/dat \
 --verbose --dry-run 

# sync idx tablespace
rsync --archive --delete --hard-links --size-only --no-inc-recursive \
 /sndb/idx/PG_12_201909212 /sndb/idx/PG_17_202406281 sndb-a:/sndb/idx \
 --verbose --dry-run 

# sync wal
rsync --archive --delete --hard-links --size-only --no-inc-recursive \
 /sndb/wal/12 /sndb/wal/17 sndb-a:/sndb/wal \
 --verbose --dry-run 
```

## Configure replica settings

Edited `postgresql.auto.conf` on **replica** with additions:

```
primary_conninfo = 'host=sndb port=5432 user=replicator'
restore_command = 'envdir ~/pgbackrest.d/env pgbackrest archive-get %f "%p"'
recovery_target = ''
```

Then setup archive mode:

```sh
su -l postgres -c 'touch /sndb/home/17/standby.signal'
```

Finally, update `/etc/rc.conf` to point to PG17:

```
postgresql_data="/sndb/home/17"
```

## Startup primary

```sh
service postgresql onestart
```

## Update pgBackRest

On **replica** update `~postgres/pgbackrest.d/env` for new Postgres version, namely:

 1. `PGBACKREST_LOG_PATH` to `/sndb/log/17`
 2. `PGBACKREST_PG1_PATH` to `/sndb/home/17`

<!-- 
Run `check`:

```sh
# as postgres user still...

su -l postgres -c 'envdir ~/pgbackrest.d/env pgbackrest --log-level-console=info check'
```
 -->

# Final tasks

Re-enable cron by changing `/etc/rc.conf` with

```
cron_enable="YES"
```

followed by `service cron start`.

# Post upgrade cleanup

After time has passed, modify the `up15/delete_old_cluster.sh` scripts to comment out the removal
of the home dirs, as might need to reference the original configuration later:

```sh
#!/bin/sh

#rm -rf '/sndb/home/12'
rm -rf '/sndb/dat/PG_12_201909212'
rm -rf '/sndb/idx/PG_12_201909212'
```

Then run the script:

```sh
su -l postgres -c 'up15/delete_old_cluster.sh'
su -l postgres -c 'up17/delete_old_cluster.sh'
```

[rep-rsync]: https://www.postgresql.org/docs/current/pgupgrade.html#PGUPGRADE-STEP-REPLICAS
