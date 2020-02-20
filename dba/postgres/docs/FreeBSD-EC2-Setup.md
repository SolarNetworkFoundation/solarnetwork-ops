# SolarNetwork Postgres on FreeBSD EC2 VM Setup

This guide outlines how the main Postgres database for SolarNetwork has been deployed, using FreeBSD
in a virtual machine on AWS EC2. The ZFS file system is used for data integrity and compression.

# Poudriere repository

Postgres needs to be installed with specific options, so we set up Poudriere to build and publish a
package repository with the needed software. These packages will be installed into a FreeBSD jail so
they don't conflict with any system packages. The following packages are included:

```
# For Postgres, the following:
databases/postgresql96-contrib
databases/postgresql96-server
databases/postgresql-plv8js
databases/py-psycopg2
databases/timescaledb

# For system administration support, the following:
archivers/liblz4
ftp/curl
ports-mgmt/pkg
sysutils/munin-node
sysutils/zfs-periodic

# For wal-e, the following:
archivers/lzop
devel/git
devel/py-pip
lang/python
sysutils/daemontools
sysutils/pv
```

The make configuration used looks like this:

```
DEFAULT_VERSIONS+=pgsql=9.6 ssl=openssl
OPTIONS_UNSET+= DOCS EXAMPLES TEST
```

The output repository has been copied to `s3://snf-freebsd-repo/solardb_pg96_121x64-HEAD`. The
bucket policy on `snf-freebsd-repo` allows public read access:

```
{
    "Version": "2012-10-17",
    "Id": "Policy1510258494370",
    "Statement": [
        {
            "Sid": "AllowListingOfBucket",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::snf-freebsd-repo"
        },
        {
            "Sid": "AllowPublicReadAccess",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": [
                "arn:aws:s3:::snf-freebsd-repo",
                "arn:aws:s3:::snf-freebsd-repo/**"
            ]
        }
    ]
}
```

A Cloud Front distribution has been created in front of this S3 bucket so it can be accessed via
https://freebsd.repo.solarnetwork.org.nz.

# EBS Volume Setup

Created a 50 GB `io1` volume to hold the database WAL (transaction log). That leaves plenty of
room for the current level of tranaction bursts, of upwards of 1000 16MB log files. With `lz4`
encryption enabled, this should hold plenty of log segments. Attached to instance as `/dev/sdf`.

Created a 100 GB `io1` volume to hold the database indexes (via the `solarindex` tablespace).
Attached to instance as `/dev/sdg`.

Created a 100 GB `io1` volume to hold the database tables (via the `solar` tablespace).
Attached to instance as `/dev/sdh`.

These appear in FreeBSD as pairs of `/dev/nvdX` and `/dev/nvmeX` devices, where `X` is a number
(e.g. 1-3). They **do not** directly correlate to the `/dev/sdX` naming shown in the AWS console. To
identify a device, run

```
$ nvmecontrol identify nvme1

Controller Capabilities/Features
================================
Vendor ID:                   1d0f
Subsystem Vendor ID:         1d0f
Serial Number:               vol0e66e82462fb547d3
Model Number:                Amazon Elastic Block Store
```

The **Serial Number** will match the **Volume ID** reported by AWS.

# FreeBSD Setup

Created a FreeBSD 12.1 `m5.xlarge` instance named _SolarDB_.

## System packages & SNF repository setup

The following packages are installed:

```
ftp/curl
sysutils/tmux
```

Configured the SNF repo:

```sh
mkdir -p /usr/local/etc/ssl/certs 
curl -s  https://freebsd.repo.solarnetwork.org.nz/snf.cert \
  >/usr/local/etc/ssl/certs/snf.cert
mkdir -p /usr/local/etc/pkg/repos
```

Created `/usr/local/etc/pkg/repos/snf.conf` with:

```
snf: {
	url: "https://freebsd.repo.solarnetwork.org.nz/solardb_pg96_121x64-HEAD",
	mirror_type: "http",
	signature_type: "pubkey",
	pubkey: "/usr/local/etc/ssl/certs/snf.cert",
	enabled: yes,
	priority: 100
}
```

## OS settings

Set up desired options in `/boot/loader.conf`:

```
zfs_load="YES"

# Crypto support
aesni_load="YES"
cryptodev_load="YES"

# Cap ZFS ARC to give room to database
vfs.zfs.arc_max="8G"

# Postgres
kern.ipc.semmni="256"
kern.ipc.semmns="512"
kern.ipc.semmnu="256"
```

Set up desired options in `/etc/sysctl.conf`:

```
# Hide other user processes
security.bsd.see_other_uids=0

# Postgres shared memory settings
kern.ipc.shmmax=2142375936
kern.ipc.shmall=523041

# Harden PID allocation
kern.randompid=100

# Force 4k alignment on vdev creation
vfs.zfs.min_auto_ashift=12
```

Set up desired options in `/etc/rc.conf`:

```
# Mount ZFS
zfs_enable="YES"

# Prevent syslog to open sockets
syslogd_flags="-ss"
 
# Prevent sendmail to try to connect to localhost
sendmail_enable="NO"
sendmail_submit_enable="NO"
sendmail_outbound_enable="NO"
sendmail_msp_queue_enable="YES"
 
# Postgres  
postgresql_enable="NO"
postgresql_data="/sndb/9.6/home"
postgresql_flags="-w -s -m fast"
postgresql_initdb_flags="--encoding=utf-8 --locale=C"
postgresql_class="postgres"
postgresql_user="postgres"
```

Set up a login class for Postgres in `/etc/login.conf`:

```
postgres:\
        :path=/sbin /bin /usr/sbin /usr/bin /usr/local/sbin /usr/local/bin ~/bin ~/.local/bin:\
        :lang=en_US.UTF-8:\
        :setenv=LC_COLLATE=C:\
        :tc=default:
```

Then update the cap db:

```
cap_mkdb /etc/login.conf
```

## ZFS Setup

Create `wal`, `idx`, and `dat` pools:

```sh 
zpool create -O canmount=off -m none wal /dev/nvd1
zpool create -O canmount=off -m none idx /dev/nvd2
zpool create -O canmount=off -m none dat /dev/nvd3
```

Setup common dataset properties and create Postgres 9.6 filesystems:

```sh 
#!/bin/sh
POOLS="wal idx dat"
HOME_POOL="dat"
VER="9.6"
for p in $POOLS; do
   	zfs set atime=off $p
	zfs set exec=off $p
	zfs set setuid=off $p
	zfs set recordsize=128k $p
	zfs set compression=lz4 $p
	zfs create -o mountpoint=/sndb/$VER/$p $p/$VER
done
zfs create -o mountpoint=/sndb/$VER/home $HOME_POOL/$VER/home
chown -R postgres:postgres /sndb/$VER
```

## Install Postgres

```sh
pkg install -r snf postgresql96-server postgresql96-plv8js postgresql96-contrib postgresql96-client timescaledb

# assign to postgres login class
pw usermod postgres -L postgres

# init db
/usr/local/etc/rc.d/postgresql oneinitdb

# Move WAL to wal dataset
mv /sndb/9.6/home/pg_xlog/* /sndb/9.6/wal/
zfs set mountpoint=/sndb/9.6/home/pg_xlog wal/9.6
```

In the end we end up with this:

```
# df -h
Filesystem         Size    Used   Avail Capacity  Mounted on
/dev/gpt/rootfs    9.7G    3.9G    5.0G    44%    /
devfs              1.0K    1.0K      0B   100%    /dev
idx/9.6             96G     88K     96G     0%    /sndb/9.6/idx
dat/9.6             96G     88K     96G     0%    /sndb/9.6/dat
dat/9.6/home        96G    5.8M     96G     0%    /sndb/9.6/home
wal/9.6             48G    2.0M     48G     0%    /sndb/9.6/home/pg_xlog

# zpool list
NAME   SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP  HEALTH  ALTROOT
dat   99.5G  6.47M  99.5G        -         -     0%     0%  1.00x  ONLINE  -
idx   99.5G   632K  99.5G        -         -     0%     0%  1.00x  ONLINE  -
wal   49.5G  2.59M  49.5G        -         -     0%     0%  1.00x  ONLINE  -

# zfs list
NAME           USED  AVAIL  REFER  MOUNTPOINT
dat           6.31M  96.4G    88K  none
dat/9.6       5.88M  96.4G    88K  /sndb/9.6/dat
dat/9.6/home  5.79M  96.4G  5.79M  /sndb/9.6/home
idx            512K  96.4G    88K  none
idx/9.6         88K  96.4G    88K  /sndb/9.6/idx
wal           2.43M  48.0G    88K  none
wal/9.6       2.02M  48.0G  2.02M  /sndb/9.6/home/pg_xlog 
```

## Install wal-e

First install supporting packages:

```
pkg install sysutils/daemontools archivers/lzop sysutils/pv
```

Then install wal-e:

```sh
su - postgres
pkg install -r snf python3 py37-pip
su - postgres
python3 -m pip install wal-e[aws] --user
```

Created `~postgres/wal-e.d/env` directory with files:

```
AWS_ACCESS_KEY_ID
AWS_REGION
AWS_SECRET_ACCESS_KEY
PGPORT
WALE_S3_PREFIX
```

Each file contains the associated value. The `WALE_S3_PREFIX` is `s3://snf-internal/backups/postgres/96`.


## Configure Postgres

Create log dir:

```sh
mkdir /var/log/postgres
chgrp postgres /var/log/postgres
chmod g+w /var/log/postgres
```

Setup `pg_hba.conf` with user/certificate authentication support.


## Initial database restore

To restore the database from the latest wal-e backup, need to create a `recovery.conf` file:

```
restore_command = 'envdir ~/wal-e.d/env wal-e wal-fetch %f %p'
standby_mode = on
```

Created a wal-e restore specification to support the `solar` and `solarindex` tablespaces used,
which look like this on the original database server:

```
lrwx------  1 pgsql  pgsql  12 Dec  6  2018 16400 -> /data96/data
lrwx------  1 pgsql  pgsql  14 Mar 12  2017 16401 -> /solar93/index
```

The JSON file looks like this:

```json
{
    "16400": {
        "loc": "/sndb/9.6/dat/",
        "link": "pg_tblspc/16400"
    },
    "16401": {
        "loc": "/sndb/9.6/idx/",
        "link": "pg_tblspc/16401"
    },
    "tablespaces": [
        "16400",
        "16401"
    ]
}
```

Because the paths differ from the source server, some additional links are necessary:

```sh
mkdir /data96 /solar93
cd /data96
ln -s /sndb/9.6/dat data
cd /solar93
ln -s /sndb/9.6/idx index
ln -s /sndb/9.6/home 9.6
```

```
zfs rollback wal/9.6@pre-fetch; zfs rollback idx/9.6@pre-fetch; zfs rollback -r dat/9.6@pre-fetch
zfs snapshot wal/9.6@pre-fetch; zfs snapshot idx/9.6@pre-fetch; zfs snapshot -r dat/9.6@pre-fetch
```

Then ran restore like this:

```
envdir ~/wal-e.d/env wal-e backup-fetch --restore-spec ~/wal-e-restore-spec.json /sndb/9.6/home LATEST
```

