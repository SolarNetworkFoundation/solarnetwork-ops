# SolarNetwork SolarDB FreeBSD EC2 NET-266 Migration

This guide outlines how the main Postgres database for SolarNetwork has tweaked to support the
NET-266 data migration process.

The main ZFS pool is not sufficiently large enough to perform the migration, but once the migration
is complete it would be. Rather than simply expand the ZFS pool by adding another volume, we will
add a new volume as a new _zpool_ and then create a new _tablespace_ in Postgres and then move the
legacy data to that tablespace. Once the migration is complete, the legacy data will be dropped, so
then the tablespace and then new zpool can be dropped as well.

# Attaching temporary volume

After attaching the volume to the instance you must run the following for FreeBSD to "see" the new
volume:

```sh
devctl rescan pci0
```

Afterwards, `nvmecontrol devlist` will show the new volume.

```
$ nvmecontrol devlist
 nvme0: Amazon Elastic Block Store
    nvme0ns1 (10240MB)
 nvme1: Amazon Elastic Block Store
    nvme1ns1 (51200MB)
 nvme2: Amazon Elastic Block Store
    nvme2ns1 (102400MB)
 nvme3: Amazon Elastic Block Store
    nvme3ns1 (102400MB)
 nvme4: Amazon Elastic Block Store
    nvme4ns1 (102400MB)

# nvme4 is the new temp volume, can verify Serial Number matches AWS Console Volume ID

$ nvmecontrol identify nvme4
Controller Capabilities/Features
================================
Vendor ID:                   1d0f
Subsystem Vendor ID:         1d0f
Serial Number:               vol05c264631f9b4bdaf
```

# Create temporary zpool and dataset

Create the new zpool and dataset (**note** this is done on both the primary and secondary servers):

```sh 
zpool create -O canmount=off -m none tmp /dev/nvd4

zfs set atime=off tmp
zfs set exec=off tmp
zfs set setuid=off tmp
zfs set recordsize=8K tmp
zfs set compression=lz4 tmp
zfs create -o mountpoint=/sndb/9.6/dattmp tmp/9.6
chown postgres:postgres /sndb/9.6/dattmp
```

## Configure munin

```sh
cd /usr/local/etc/munin/plugins
ln -s /usr/local/share/examples/munin-contrib/plugins/zfs/zfs-filesystem-graph zfs_fs_tmp
service munin-node restart
```

# Create temporary tablespace

Create the new temporary tablespace `solartmp`:

```sql
CREATE TABLESPACE solartmp OWNER solarnet LOCATION '/sndb/9.6/dattmp';
ALTER TABLESPACE solartmp SET (random_page_cost=1, effective_io_concurrency=10);
```

# Move legacy data

Assign the legacy data to the new temporary tablespace, after pausing scheduler:

```sh
su - postgres
. bin/solar-jobs.sh
pause_scheduler
tmux
psql -U postgres -d solarnetwork -c 'ALTER TABLE solardatum.da_datum SET TABLESPACE solartmp'
exit

resume_scheduler
```
