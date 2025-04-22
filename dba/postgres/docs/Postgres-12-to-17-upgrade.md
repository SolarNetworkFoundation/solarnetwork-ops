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

# Packages setup

See the [12 to 17 upgrade packages](./Postgres-12-to-17-upgrade-packages.md) guide.


# Pre upgrade prep

Some prep tasks must be done:

##  Disable cron

Disable `cron` to be safe. Edit `/etc/rc.conf`

```
# Cron
cron_enable="NO"
```

Then `service cron onestop`.


## Remove adminpack

The `adminpack` module is removed from PG 17, and the upgrade will fail if that extension is
installed in any database. So check to remove it, e.g.

```sh
# check
for db in template1 postgres solarnetwork; do su -l postgres -c "psql -d $db -c '\\dx'"; done

# remove
for db in template1 postgres solarnetwork; do su -l postgres -c "psql -d $db -c 'DROP EXTENSION IF EXISTS adminpack'"; done
```

## Create pgbackrest backup

```sh
su -l postgres -c 'envdir ~/pgbackrest.d/env pgbackrest --log-level-console=info --type=diff --start-fast backup'
```

## Disable Timescale jobs

```sh
su -l postgres -c "psql -d solarnetwork -c 'SELECT alter_job(job_id, scheduled => false) FROM timescaledb_information.jobs'"
```


# Upgrade to FreeBSD 14.2

Using the [past update from Postgres 9 to 12](../../../sys/maintenance-reports/SN%20Maintenance%202021-03-21%20report.md)
as a guide, the following general procedure is used.

```sh

# free up RAM for removal of swapfile
swapoff -a

# comment out md99 LINE IN /etc/fstab
sed -i '' -e 's/md99/#md99/' /etc/fstab

# free up disk space for upgrade
rm /usr/swap0

# Start OS upgrade (downloads about 2GB of files)
freebsd-update -r 14.2-RELEASE upgrade

# merge updates... then install updates
/usr/sbin/freebsd-update install
```

## Merge notes

The `sshd_conf` merge updates a variable name:

```diff
# Change to no to disable PAM authentication
<<<<<<< current version
ChallengeResponseAuthentication no
=======
#KbdInteractiveAuthentication yes
>>>>>>> 14.2-RELEASE
```

The desired outcome is:

```
KbdInteractiveAuthentication no
```

## Reboot, finish upgrade

Now have to reboot, then run install again:

```sh
reboot

# log back in...

/usr/sbin/freebsd-update install
```

## Adjust loader.conf

The ZFS ARC max setting named changed:

```sh
# update ZFS ARC max setting
sed -i '' -e 's/arc_max/arc.max/' /boot/loader.conf
```

## Upgrade packages

Now have to update packages, so edit `/usr/local/etc/pkg/repos/snf.conf` to point to 14.2
and `tsdb2` URL (for example `http://poudriere/packages/solardb_142x64-tsdb2`). Then:


```sh
# update repo location
sed -i '' -e 's|url:.*|url: "http://snf-freebsd-repo.s3-website-us-west-2.amazonaws.com/solardb_142x64-tsdb2",|' \
  /usr/local/etc/pkg/repos/snf.conf   

# bootstrap
pkg bootstrap -f

# upgrade (this will remove timescaledb package, possibly python39)
pkg upgrade -r snf

# reinstall timescaledb
pkg install timescaledb210

# can remove python39 (if not already, replaced by python311)
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

# Recreate swap

```sh
dd if=/dev/zero of=/usr/swap0 bs=1m count=1024
chmod 600 /usr/swap0

# enable in /etc/fstab
sed -i '' -e 's/#md99/md99/' /etc/fstab

swapon -aL
```

# Import zpools (if necessary)

```sh
# can verify pools available with
zpool import

# then import pools by name
zpool import dat
zpool import idx
zpool import wal
```

# Update Postgres extensions

```sh
service postgresql onestart
su -l postgres -c "psql -x -d solarnetwork -c 'ALTER EXTENSION timescaledb UPDATE'"
su -l postgres -c "psql -x -d solarnetwork -c 'ALTER EXTENSION aggs_for_vecs UPDATE'"
service postgresql onestop
```

# Create AMI

Create a fallback AMI, for Postgres 12.22, Timescale 2.10.2, aggs_for_vecs 1.3.2

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

# Upgrade to Postgres 15

Run the [upgrade prep script](../scripts/pg-upgrade-pg15-prod.sh) first. Then:

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

If need to rollback to start again:

```sh
# rollback
for f in dat dat/dat dat/home dat/log idx idx/idx wal wal/wal; do zfs rollback $f@pre-pg17-upgrade; done
```


# Upgrade to Postgres 17

Run the [upgrade prep script](../scripts/pg-upgrade-pg17-prod.sh) first. Then:

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

First update configuration to take advantage of block-delta configuration:

```sh
su - postgres
echo y >~/pgbackrest.d/env/PGBACKREST_REPO1_BUNDLE
echo y >~/pgbackrest.d/env/PGBACKREST_REPO1_BLOCK
exit
```

Then perform full backup:

```sh
su -l postgres -c 'envdir ~/pgbackrest.d/env pgbackrest --log-level-console=info --type=full --start-fast backup'
```


# ZFS snapshots (Post PG 17)

Create ZFS snapshots to allow rollback:

```sh
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


# Final tasks

Re-enable cron (and all needed services) by changing `/etc/rc.conf` with

```
cron_enable="YES"
```

followed by `service cron start`.

## Reenable Timescale jobs

```sh
su -l postgres -c "psql -d solarnetwork -c 'SELECT alter_job(job_id, scheduled => true) FROM timescaledb_information.jobs'"
```

# Post upgrade near-term cleanup

Remove ZFS snapshots:

```sh
for f in dat idx wal; do zfs destroy -r $f@pre-pg15-upgrade; zfs destroy -r $f@pre-pg17-upgrade; zfs destroy -r $f@post-pg17-upgrade; done
```

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

On the replica, need to manually run the PG15 cleanup:

```sh
su -l postgres -c 'rm -rf /sndb/dat/PG_12_201909212'
su -l postgres -c 'rm -rf /sndb/idx/PG_12_201909212'
```

[rep-rsync]: https://www.postgresql.org/docs/current/pgupgrade.html#PGUPGRADE-STEP-REPLICAS
