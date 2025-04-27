# SN DB Maintenance 2025-04-27

This maintenance is to update the VMs running the SN Postgres cluster (`solardb-0 `and `solardb-a`):

 * update FreeBSD from 12.3-RELEASE-p12 to 14.2p3
 * update Postgres from 12.14 to 17.4
 * update Timescale from 2.10.1 to 2.19.3

Refer to [Postgres 12 to 17 upgrade](../../dba/postgres/docs/Postgres-12-to-17-upgrade.md) for more
details.

# Downtime prep

Scheduled maintenance downtime windows in [Icinga](https://apps.solarnetwork.net/icingaweb2/) and
[upptime](https://github.com/SolarNetworkFoundation/upptime/issues).

# Admin reference

Some commands use aliases:

| Alias | Command |
|:------|:--------|
| `snssh`  | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i /path/to/matt-solarnetwork.pem |
| `snsshj` | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i /path/to/matt-solarnetwork.pem -J admin@argus.solarnetwork.net |

# Stop apps

Shutdown SolarIn proxy:

```sh
snssh ec2-user@solarin-proxy
su -
service nginx stop
```

Shutdown SolarQuery proxy:

```sh
snsshj ec2-user@solarquery-proxy-a.solarnetwork.net
su -
service nginx stop
```

Shutdown ECS apps SolarIn, SolarJobs, SolarQuery, SolarUser, OSCP FP, SolarOCPP, SolarDIN:

```sh
for c in solarin solarjobs solarquery solaruser oscp-fp solarocpp solardin; do \
aws ecs list-services --profile snf --output json --cluster $c |grep 'arn:aws' |tr -d \"; done \
|while read s; do aws ecs update-service --desired-count 0 --profile snf --cluster ${s##*/} --service $s; done
```

Shutdown SolarFlux auth server:

```sh
snsshj admin@solarflux.solarnetwork
sudo systemctl stop vernemq
sudo systemctl stop fluxhook
```

> :warning: Monitor logs in CloudWatch to wait for ECS applications to actually terminate.


# Start tmux sessions on DBs

```sh
snssh ec2-user@solardb-0
tmux
su - 
```

Repeat on replica:

```sh
snssh ec2-user@solardb-a
tmux
su - 
```

The subsequent sections assume these root sessions are active.

# Switch DBs to minimal mode

Change the DB servers to "minimal" mode so services do not automatically start on boot.

```sh
# solardb-0
ln -sfh rc.conf.min /etc/rc.conf
```

Repeat on replica:

```sh
# solardb-a
ln -sfh rc.conf.min /etc/rc.conf
```

# Create Postgres differential backup

Create a pgBackRest differential backup (on primary) before any changes performed:

```sh
# solardb-0
su -l postgres -c 'envdir ~/pgbackrest.d/env pgbackrest --log-level-console=info --type=diff --start-fast backup'
```

# Disable Timescale jobs

```sh
su -l postgres -c "psql -d solarnetwork -c 'SELECT alter_job(job_id, scheduled => false) FROM timescaledb_information.jobs'"
```

Time: Sat Apr 26 20:46:19 UTC 2025

# Create EC2 AMIs

Create new AMIs of primary and replicate servers, **including only the root drives** in the image.
The current AMIs for these servers include the data volumes, which we do not want included because
they take up a lot of space and are not necessary with the data backed up in S3 with pgBackRest.

The AMI names are **SolarDB-0 v4b** and **SolarDB-A v4b**.

Allow the image process to restart the servers to take a snapshot, then wait for servers to restart.
When the servers restart, they will be in "minimal" mode.

# Restart tmux sessions

Start new tmux sessions on both primary and replica servers:

```sh
snssh ec2-user@solardb-0
tmux
su - 
```

Repeat on replica:

```sh
snssh ec2-user@solardb-a
tmux
su - 
```

The subsequent sections assume these root sessions are active.

# Remove swap file

To free up 1GB for upgrade, on primary:

```sh
# free up RAM for removal of swapfile
swapoff -a

# comment out md99 LINE IN /etc/fstab
sed -i '' -e 's/md99/#md99/' /etc/fstab

# free up disk space for upgrade
rm /usr/swap0
```

The disk situation at this point on primary:

```
# df -h
Filesystem                                              Size    Used   Avail Capacity  Mounted on
/dev/gpt/rootfs                                         9.7G    4.1G    4.8G    46%    /
devfs                                                   1.0K    1.0K      0B   100%    /dev
dat/home                                                207G    540M    206G     0%    /sndb/home
wal/wal                                                  48G    375K     48G     0%    /sndb/wal
idx/idx                                                  96G     61G     35G    63%    /sndb/idx
dat/log                                                 206G     28M    206G     0%    /sndb/log
dat/dat                                                 385G    179G    206G    46%    /sndb/dat
us-west-2a.fs-2b965081.efs.us-west-2.amazonaws.com:/    8.0E    168K    8.0E     0%    /mnt/cert-support
```

> :bulb: Repeat on replica

The disk situation at this point on replica:

```
# df -h
Filesystem                                              Size    Used   Avail Capacity  Mounted on
/dev/gpt/rootfs                                         9.7G    4.3G    4.6G    48%    /
devfs                                                   1.0K    1.0K      0B   100%    /dev
wal/wal                                                  48G    648K     48G     0%    /sndb/wal
dat/home                                                192G    541M    192G     0%    /sndb/home
dat/dat                                                 385G    193G    192G    50%    /sndb/dat
dat/log                                                 192G     31M    192G     0%    /sndb/log
idx/idx                                                  96G     78G     18G    81%    /sndb/idx
us-west-2b.fs-2b965081.efs.us-west-2.amazonaws.com:/    8.0E    168K    8.0E     0%    /mnt/cert-support
```

# Upgrade FreeBSD

On **both** primary and replica:

```sh
# Start OS upgrade (downloads about 2GB of files)
freebsd-update -r 14.2-RELEASE upgrade

# merge updates... then install updates
/usr/sbin/freebsd-update install
```

## Reboot, finish upgrade

Now have to reboot, then run install again:

```sh
reboot

# log back in...

/usr/sbin/freebsd-update install
```

## Adjust loader.conf

The ZFS ARC max setting named changed, and can move to sysctl.conf.

Remove from `/boot/loader.conf`:

```
# Cap ZFS ARC to give room to database
vfs.zfs.arc_max="7G"
```

and add to `/etc/sysctl.conf`:

```sh
# Cap ZFS ARC to give room to database
vfs.zfs.arc.max=7516192768
```

## Upgrade packages

Now have to update packages, so edit `/usr/local/etc/pkg/repos/snf.conf` to point to 14.2
and `tsdb2` URL:

```sh
# update repo location
sed -i '' -e 's|url:.*|url: "http://snf-freebsd-repo.s3-website-us-west-2.amazonaws.com/solardb_142x64-tsdb2",|' \
  /usr/local/etc/pkg/repos/snf.conf   

# bootstrap
PACKAGESITE=http://pkg.FreeBSD.org/FreeBSD:14:amd64/latest pkg bootstrap -f

# upgrade (this will remove timescaledb package, possibly python39)
pkg upgrade -r snf

# reinstall timescaledb
pkg install timescaledb210

# had to reinstall awscli
pkg install devel/py-awscli

# then remove some old packages
pkg remove py38*
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

## Recreate swap

On **both** servers:

```sh
dd if=/dev/zero of=/usr/swap0 bs=1m count=1024
chmod 600 /usr/swap0

# enable in /etc/fstab
sed -i '' -e 's/#md99/md99/' /etc/fstab

swapon -aL
```

The disk situation at this point on primary:

```
# df -h
Filesystem                                              Size    Used   Avail Capacity  Mounted on
/dev/gpt/rootfs                                         9.7G    5.9G    3.0G    66%    /
devfs                                                   1.0K      0B    1.0K     0%    /dev
us-west-2a.fs-2b965081.efs.us-west-2.amazonaws.com:/    8.0E    168K    8.0E     0%    /mnt/cert-support
```

The disk situation at this point on replica:

```
# df -h
Filesystem                                              Size    Used   Avail Capacity  Mounted on
/dev/gpt/rootfs                                         9.7G    6.0G    2.9G    67%    /
devfs                                                   1.0K      0B    1.0K     0%    /dev
us-west-2b.fs-2b965081.efs.us-west-2.amazonaws.com:/    8.0E    168K    8.0E     0%    /mnt/cert-support
```

# Import zpools

```sh
# can verify pools available with
zpool import

# then import pools by name
for n in dat idx wal; do zpool import $n; done
```

# ZFS snapshots (Pre Anything)

Create ZFS snapshots to allow rollback:

```
for f in dat idx wal; do zfs snapshot -r $f@pre-pg15-start; done
```

# Update Postgres extensions

On primary **and** replica, start Postgres:

```sh
service postgresql onestart
```

Then on **primary** update:

```sh
su -l postgres -c "psql -x -d solarnetwork -c 'ALTER EXTENSION timescaledb UPDATE'"
su -l postgres -c "psql -x -d solarnetwork -c 'ALTER EXTENSION aggs_for_vecs UPDATE'"
```

Then on primary **and** replica, start Postgres:

```sh
service postgresql onestop
```

# Create AMI

Create a fallback AMI, for Postgres 12.22, Timescale 2.10.2, aggs_for_vecs 1.3.2.

The AMI names are **SolarDB-0 v4c** and **SolarDB-A v4c**; the description is
**FreeBSD 14.2p3 Postgres 12.22 Timescale 2.10.2 aggs_for_vecs 1.3.2**.

Allow the image process to restart the servers to take a snapshot, then wait for servers to restart.

# ZFS snapshots (Pre PG 15)

Create ZFS snapshots to allow rollback:

```
for f in dat idx wal; do zfs snapshot -r $f@pre-pg15-upgrade; done
```

# Copy DB upgrade scripts to primary

Copied the production upgrade scripts to primary server:

 * [pg-upgrade-pg15-prod.sh](../../dba/postgres/scripts/pg-upgrade-pg15-prod.sh)
 * [pg-upgrade-pg17-prod.sh](../../dba/postgres/scripts/pg-upgrade-pg17-prod.sh)

```sh
% snscp pg-upgrade-*prod.sh ec2-user@solardb-0:/var/tmp/
pg-upgrade-pg15-prod.sh
pg-upgrade-pg17-prod.sh
```

# Upgrade to Postgres 15

Run the [upgrade prep script](../../dba/postgres/scripts/pg-upgrade-pg15-prod.sh) first. Then:

```sh
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

service postgresql onestop
```

# Upgrade to Timescale 2.19

First update repo to `tsdb4` to get latest PG 15 + TS 2.19 packages. Then update packages and
switch to TS 2.19:

```sh
# stop postgres
service postgresql onestop

# point pkg to PG 15 + TS 2.19 repo
sed -i '' -e 's/tsdb3/tsdb4/' /usr/local/etc/pkg/repos/snf.conf
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

# Upgrade to Postgres 17

Run the [upgrade prep script](../../dba/postgres/scripts/pg-upgrade-pg17-prod.sh) first. Then:

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

Time: Sat Apr 26 22:46:36 UTC 2025

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

Update configuration to take advantage of block-delta configuration:

```sh
echo y >~/pgbackrest.d/env/PGBACKREST_REPO1_BUNDLE
echo y >~/pgbackrest.d/env/PGBACKREST_REPO1_BLOCK
exit
```

## Update extensions

Then start the server to update extensions:

```sh
# go back to root user, if still postgres
exit

# copy TLS
cp -a /sndb/home/12/tls /sndb/home/17/

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

This takes a while...

Time: Sun Apr 27 01:13:46 UTC 2025

# Update Certbot

The Certbot deploy script in `/usr/local/etc/letsencrypt/renewal-hooks/deploy/solardb.sh`
needs to change:

```sh
sed -i -e 's|home/12|home/17|' /usr/local/etc/letsencrypt/renewal-hooks/deploy/solardb.sh
```

# Create full backup:

```sh
su -l postgres -c 'envdir ~/pgbackrest.d/env pgbackrest --log-level-console=info --type=full --start-fast --process-max=4 backup'
```

This takes a while...

Time: Sun Apr 27 02:25:18 UTC 2025

# ZFS snapshots (Post PG 17)

Create ZFS snapshots to allow rollback:

```sh
for f in dat idx wal; do zfs snapshot -r $f@post-pg17-upgrade; done
```

# Update replica

Update Postgres on the replica:

```sh
# create snapshots
for f in dat idx wal; do zfs snapshot -r $f@pre-pg17-upgrade; done

# delete old software
pkg delete -fy databases/postgresql12-server databases/postgresql12-contrib databases/postgresql12-client databases/timescaledb210 databases/postgresql-aggs_for_vecs

sed -ie 's/url: "\(.*\)"/url: "http:\/\/snf-freebsd-repo.s3-website-us-west-2.amazonaws.com\/solardb_142x64-tsdb5"/' \
    /usr/local/etc/pkg/repos/snf.conf
pkg update

# install new software
pkg install -r snf -y rsync databases/postgresql17-server databases/postgresql17-contrib databases/postgresql17-client databases/timescaledb databases/postgresql-aggs_for_vecs

pkg upgrade -r snf -y

# update Postgres home location
sed -i '' -e 's/\/sndb\/home\/12/\/sndb\/home\/17/' /etc/rc.conf.min
sed -i '' -e 's/\/sndb\/home\/12/\/sndb\/home\/17/' /etc/rc.conf.full

# create Postgres log dir
mkdir /sndb/log/17
chown postgres:postgres /sndb/log/17

su - postgres
echo y >~/pgbackrest.d/env/PGBACKREST_REPO1_BUNDLE
echo y >~/pgbackrest.d/env/PGBACKREST_REPO1_BLOCK

# Created `~postgres/.pgpass` with content like
echo 'solardb-rw.solarnetwork:*:replication:replicator:PASSWORD' >>~/.pgpass
chmod 600 ~/.pgpass
```

# Sync database to replica

```sh
service postgresql onestop

# continue as postgres user...
su - postgres

# sync home
rsync --archive --delete --hard-links --size-only --no-inc-recursive \
 /sndb/home/12 /sndb/home/17 solardb-ro.solarnetwork:/sndb/home \
 --verbose --dry-run 

# sync dat tablespace
rsync --archive --delete --hard-links --size-only --no-inc-recursive \
 /sndb/dat/PG_12_201909212 /sndb/dat/PG_17_202406281 solardb-ro.solarnetwork:/sndb/dat \
 --verbose --dry-run 

# sync idx tablespace
rsync --archive --delete --hard-links --size-only --no-inc-recursive \
 /sndb/idx/PG_12_201909212 /sndb/idx/PG_17_202406281 solardb-ro.solarnetwork:/sndb/idx \
 --verbose --dry-run 

# sync wal
rsync --archive --delete --hard-links --size-only --no-inc-recursive \
 /sndb/wal/12 /sndb/wal/17 solardb-ro.solarnetwork:/sndb/wal \
 --verbose --dry-run 
```

> :bulb: Repeat each command without `--dry-run`

## Configure replica settings

Edited `postgresql.auto.conf` on **replica** with additions:

```
primary_conninfo = 'host=solardb-rw.solarnetwork port=5432 user=replicator'
restore_command = 'envdir ~/pgbackrest.d/env pgbackrest archive-get %f "%p"'
recovery_target = ''
```

Then fix TLS ownership:

```sh
cd /sndb/home/17/tls
chown root db.solarnetwork.net.fullchain db.solarnetwork.net.key solarnetwork-ca.crt
```

Then setup archive mode:

```sh
su -l postgres -c 'touch /sndb/home/17/standby.signal'
```

# Create AMI

Create new AMI, for Postgres 12.22, Timescale 2.10.2, aggs_for_vecs 1.3.2.

The AMI names are **SolarDB-0 v5** and **SolarDB-A v5**; the description is
**FreeBSD 14.2p3 Postgres 17.4 Timescale 2.19.3 aggs_for_vecs 1.3.2**.

Allow the image process to restart the servers to take a snapshot, then wait for servers to restart.

# Start Postgres

On primary:

```sh
service postgresql onestart
```

On replica:

```sh
service postgresql onestart
```

# Restore "full" mode

On both servers:

```sh
ln -sfh rc.conf.full /etc/rc.conf
```

## Reenable Timescale jobs

```sh
su -l postgres -c "psql -d solarnetwork -c 'SELECT alter_job(job_id, scheduled => true) FROM timescaledb_information.jobs'"
```

# Replica problems

The replica failed to start after syncing data. Restore from backup:

```sh
su - postgres
envdir ~/pgbackrest.d/env pgbackrest --link-all --process-max=4 \
 --tablespace-map=16400=/sndb/dat \
 --tablespace-map=16401=/sndb/idx \
 --link-map=pg_wal=/sndb/wal/17 \
 --log-level-console=info \
 --delta \
 --target-timeline=current \
 --type=standby \
 --recovery-option="primary_conninfo=host=solardb-rw.solarnetwork port=5432 user=replicator" \
 --recovery-option='restore_command=envdir ~/pgbackrest.d/env pgbackrest archive-get %f "%p"' \
 --recovery-option="recovery_target=" \
  restore
```

# Post upgrade cleanup

On primary, first edit `up15/delete_old_cluster.sh` scripts to comment out the removal
of the home dir, as might need to reference the original configuration later:

```sh
#!/bin/sh

#rm -rf '/sndb/home/12'
rm -rf '/sndb/dat/PG_12_201909212'
rm -rf '/sndb/idx/PG_12_201909212'
```

Then run the scripts:

```sh
su -l postgres -c 'up15/delete_old_cluster.sh'
su -l postgres -c 'up17/delete_old_cluster.sh'
```

# Start apps

Start SolarFlux auth server:

```sh
snsshj admin@solarflux.solarnetwork
sudo systemctl start fluxhook
sudo systemctl start vernemq
```

Start SolarQuery proxy:

```sh
snsshj ec2-user@solarquery-proxy-a.solarnetwork.net
su -
service nginx start
```

Start ECS apps SolarIn, SolarJobs, SolarUser, OSCP FP, SolarOCPP, SolarDIN (not SolarQuery,
because of replica restoration!):

```sh
for c in solarin solarjobs solaruser oscp-fp solarocpp solardin; do \
aws ecs list-services --profile snf --output json --cluster $c |grep 'arn:aws' |tr -d \"; done \
|while read s; do aws ecs update-service --desired-count 1 --profile snf --cluster ${s##*/} --service $s; done
```

Start SolarIn proxy:

```sh
snssh ec2-user@solarin-proxy
su -
service nginx start
```

# Cleanup ZFS snapshots

Remove ZFS snapshots on primary:

```sh
for f in dat idx wal; do \
  zfs destroy -r $f@pre-pg15-start; \
  zfs destroy -r $f@pre-pg15-upgrade; \
  zfs destroy -r $f@pre-pg17-upgrade; \
  zfs destroy -r $f@post-pg17-upgrade; \
  done
```

# Clean up temporary files

On primary:

```sh
cd /var/tmp
rm -rf pgupgrade

# pkg cleanup
pkg-clean -ay
```

Now the filesystems look like:

```
# df -h
Filesystem                                              Size    Used   Avail Capacity  Mounted on
/dev/gpt/rootfs                                         9.7G    5.8G    3.1G    65%    /
devfs                                                   1.0K      0B    1.0K     0%    /dev
dat/dat                                                 384G    179G    206G    46%    /sndb/dat
wal/wal                                                  48G    248M     48G     1%    /sndb/wal
dat/log                                                 206G     28M    206G     0%    /sndb/log
dat/home                                                207G    1.0G    206G     0%    /sndb/home
idx/idx                                                  96G     61G     35G    63%    /sndb/idx
us-west-2a.fs-2b965081.efs.us-west-2.amazonaws.com:/    8.0E    168K    8.0E     0%    /mnt/cert-support
```

# Start SolarQuery

Once replica restored, start SolarQuery:

```sh
for c in solarquery; do \
aws ecs list-services --profile snf --output json --cluster $c |grep 'arn:aws' |tr -d \"; done \
|while read s; do aws ecs update-service --desired-count 1 --profile snf --cluster ${s##*/} --service $s; done
```

Time: Sun Apr 27 05:53:36 UTC 2025
