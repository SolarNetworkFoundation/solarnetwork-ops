# SN DB Maintenance 2020-10-18

This maintenance is to update the VMs running the SN Postgres cluster:

 * update FreeBSD from 12.1 to 12.2
 * update Postgres from 9.6 to 12.6
 * update Timescale from 1.7 to 2.1
 * switch from WAL-E to pgbackrest for backups/streaming
 
# OS Upgrade, part 1

For this first part, left system running so the update files could be downloaded. First configured
Postgres not to start up automatically, in `/etc/rc.conf`, then executed upgrade:

```sh
sed -i '' -e 's/postgresql_enable="YES"/postgresql_enable="NO"/' /etc/rc.conf

# free up RAM for removal of swapfile
sysctl vfs.zfs.arc_max=2147483648
swapoff -a

# COMMEND OUT md99 LINE IN /etc/fstab, THEN
# free up disk space for upgrade
rm /usr/swap0

freebsd-update -r 12.2-RELEASE upgrade
```
 
# Stop apps

Shutdown ECS apps SolarJobs, SolarQuery, SolarUser:

```sh
for c in solarjobs solarquery solaruser; do \
aws ecs list-services --profile snf --output json --cluster $c |grep 'arn:aws' |tr -d \"; done \
|while read s; do aws ecs update-service --desired-count 0 --profile snf --cluster ${s##*/} --service $s; done
```

Shutdown SolarIn proxy:

```sh
snssh ec2-user@solarin-proxy
su -
service nginx stop
```

Shutdown SolarIn:

```sh
snssh ec2-user@solarin-a
sudo systemctl stop virgo@solarin
```

# OS Upgrade, part 2

```sh
/usr/sbin/freebsd-update install
```

Which output:

```
Installing updates...
Kernel updates have been installed.  Please reboot and run
"/usr/sbin/freebsd-update install" again to finish installing updates.
```

Updated SNF repo URL in `/usr/local/etc/pkg/repos/snf.conf` with

```
url: "http://snf-freebsd-repo.s3-website-us-west-2.amazonaws.com/solardb_pg96_122x64-tsdb1"
```

Then reboot and continue:

```
reboot

# when back up, continue with
/usr/sbin/freebsd-update install

# Remove v8/plv8
pkg remove v8

pkg update
pkg install -r snf postgresql96-client postgresql96-contrib postgresql96-server
```

# Prepare for Postgres upgrade

```sh
# Create unififed ZFS datasets for pg_upgrade to work with hard links
zfs create -o mountpoint=/sndb/dat dat/dat
zfs create -o mountpoint=/sndb/home dat/home
zfs create -o mountpoint=/sndb/idx idx/idx
zfs create -o mountpoint=/sndb/wal wal/wal
chown postgres:postgres /sndb/dat
chown postgres:postgres /sndb/home
chown postgres:postgres /sndb/idx
chown postgres:postgres /sndb/wal

cp -a /sndb/9.6/home /sndb/home/9.6
mv /sndb/9.6/dat/PG_9.6_201608131 /sndb/dat/
mv /sndb/9.6/idx/PG_9.6_201608131 /sndb/idx/

cd /sndb/home/9.6/pg_tblspc
rm 16400 16401
ln -s /sndb/dat 16400
ln -s /sndb/idx 16401

mkdir /var/tmp/pg-upgrade
cd /var/tmp/pg-upgrade

fetch http://snf-freebsd-repo.s3-website-us-west-2.amazonaws.com/solardb_pg96_122x64-tsdb1/All/timescaledb-1.7.4_1.txz
tar xf /var/cache/pkg/postgresql96-server-9.6.21.txz -C /var/tmp/pg-upgrade
tar xf /var/cache/pkg/postgresql96-contrib-9.6.21.txz -C /var/tmp/pg-upgrade
tar xf /var/tmp/pg-upgrade/timescaledb-1.7.4_1.txz -C /var/tmp/pg-upgrade
```

Update pkg repo to PG12:

Updated SNF repo URL in `/usr/local/etc/pkg/repos/snf.conf` with

```
url: "http://snf-freebsd-repo.s3-website-us-west-2.amazonaws.com/solardb_pg12_122x64-tsdb1"
```

Upgrade:

```sh
pkg delete -fy databases/postgresql96-server databases/postgresql96-contrib databases/postgresql96-client
pkg install -r snf databases/postgresql12-server databases/postgresql12-contrib databases/postgresql12-client

cd /var/tmp
pkg unlock timescaledb
fetch http://snf-freebsd-repo.s3-website-us-west-2.amazonaws.com/solardb_pg12_122x64-tsdb1/All/timescaledb-1.7.4_1.txz
pkg add -f ./timescaledb-1.7.4_1.txz
```

Edit `/etc/rc.conf` to change to PG 12:

```
postgresql_data="/sndb/home/12"
```

Init cluster:

```
service postgresql oneinitdb
```

Update `/sndb/home/12/postgresql.conf`

```
shared_preload_libraries = 'timescaledb,pg_stat_statements'
```

Setup WAL:

```sh
cd /sndb/home/12
mv pg_wal /sndb/wal/12
ln -s /sndb/wal/12 pg_wal
```

# Postgres upgrade

```sh
su - postgres
cd /var/tmp

/var/tmp/pg-upgrade/usr/local/bin/pg_ctl -w -l "postgres-user-update.log" -D "/sndb/home/9.6" \
	-o "-p 50432 -c listen_addresses='' -c unix_socket_permissions=0700 -c unix_socket_directories='/var/db/postgres'" \
	start

psql -p 50432 -h /var/db/postgres -U pgsql -d postgres -c 'alter user postgres rename to postgres_'
psql -p 50432 -h /var/db/postgres -U postgres_ -d postgres -c 'alter user pgsql rename to postgres'

/var/tmp/pg-upgrade/usr/local/bin/pg_ctl -w -l "postgres-user-update.log" -D "/sndb/home/9.6" \
    -o "-p 50432 -c listen_addresses='' -c unix_socket_permissions=0700 -c unix_socket_directories='/var/db/postgres'" \
    -m fast stop

pg_upgrade -U postgres -k \
	-b /var/tmp/pg-upgrade/usr/local/bin \
	-d /sndb/home/9.6 \
	-B /usr/local/bin \
	-D /sndb/home/12 \
	-O "-c timescaledb.restoring='on'" \
	--check
```

Now execute:


Create snapshot:

```
zfs snapshot -r wal@pre-pg12-upgrade; zfs snapshot -r idx@pre-pg12-upgrade; zfs snapshot -r dat@pre-pg12-upgrade
```

If need to rollback to start again:

```sh
# rollback
zfs rollback dat@pre-pg12-upgrade
zfs rollback dat/9.6@pre-pg12-upgrade
zfs rollback dat/9.6/home@pre-pg12-upgrade
zfs rollback dat/9.6/home/logs@pre-pg12-upgrade
zfs rollback dat/9.6/tmp@pre-pg12-upgrade
zfs rollback dat/dat@pre-pg12-upgrade
zfs rollback dat/home@pre-pg12-upgrade
zfs rollback idx@pre-pg12-upgrade
zfs rollback idx/9.6@pre-pg12-upgrade
zfs rollback idx/idx@pre-pg12-upgrade
zfs rollback wal@pre-pg12-upgrade
zfs rollback wal/9.6@pre-pg12-upgrade
zfs rollback wal/wal@pre-pg12-upgrade

# re-create snapshots after fix issue
```

Do upgrade:

```
su - postgres
pg_upgrade -U postgres -k \
	-b /var/tmp/pg-upgrade/usr/local/bin \
	-d /sndb/home/9.6 \
	-B /usr/local/bin \
	-D /sndb/home/12 \
	-O "-c timescaledb.restoring='on'"

Upgrade Complete
----------------
Optimizer statistics are not transferred by pg_upgrade so,
once you start the new server, consider running:
    ./analyze_new_cluster.sh

Running this script will delete the old cluster's data files:
    ./delete_old_cluster.sh
```

# Configure pgbackrest

```sh
zfs create -o compression=gzip -o mountpoint=/sndb/log dat/log
mkdir /sndb/log/12
chown postgres:postgres /sndb/log/12

su - postgres
envdir ~/pgbackrest.d/env pgbackrest stanza-create

# create first full backup
envdir ~/pgbackrest.d/env pgbackrest stanza-create
```

# Setup replia new; restore from backup

Note the TLS link mapping is required because the TLS files are not owned by the `postgres` user.

```
mkdir /var/tmp/pgrestore
envdir ~/pgbackrest.d/env pgbackrest --link-all --process-max=4 \
 --tablespace-map=16400=/sndb/dat \
 --tablespace-map=16401=/sndb/idx \
 --link-map=pg_wal=/sndb/wal/12 \
--link-map=tls/server.crt=/var/tmp/pgrestore/server.crt \
 --link-map=tls/server.key=/var/tmp/pgrestore/server.key \  
 --log-level-console=info \
restore
```


# Setup small swap

On both primary and replica:

```sh
dd if=/dev/zero of=/usr/swap0 bs=1m count=1024

# note enable in /etc/fstab
# md99   none    swap    sw,file=/usr/swap0,late 0       0

swapon -aL

```

# Restart apps

Start SolarIn:

```sh
snssh ec2-user@solarin-a
sudo systemctl start virgo@solarin
```

Start SolarIn proxy:

```sh
snssh ec2-user@solarin-proxy
su -
service nginx start
```

Start ECS apps SolarJobs, SolarQuery, SolarUser:

```sh
for c in solarjobs solarquery solaruser; do \
aws ecs list-services --profile snf --output json --cluster $c |grep 'arn:aws' |tr -d \"; done \
|while read s; do aws ecs update-service --desired-count 1 --profile snf --cluster ${s##*/} --service $s; done
```
