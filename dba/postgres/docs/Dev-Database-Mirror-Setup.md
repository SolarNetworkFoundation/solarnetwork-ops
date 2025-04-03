# Dev SNDB Setup

Prod disk setup:

```
$ df -h
Filesystem                                              Size    Used   Avail Capacity  Mounted on
/dev/gpt/rootfs                                         9.7G    5.3G    3.6G    60%    /
devfs                                                   1.0K    1.0K      0B   100%    /dev
wal/wal                                                  48G    103M     48G     0%    /sndb/wal
dat/dat                                                 385G    164G    221G    43%    /sndb/dat
dat/home                                                221G    560M    221G     0%    /sndb/home
dat/log                                                 221G     37M    221G     0%    /sndb/log
idx/idx                                                  96G     57G     39G    60%    /sndb/idx
us-west-2a.fs-2b965081.efs.us-west-2.amazonaws.com:/    8.0E    168K    8.0E     0%    /mnt/cert-support
$ zpool list
NAME   SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP  HEALTH  ALTROOT
dat    398G   165G   233G        -         -    54%    41%  1.00x  ONLINE  -
idx   99.5G  57.4G  42.1G        -         -    77%    57%  1.00x  ONLINE  -
wal   49.5G   121M  49.4G        -         -    27%     0%  1.00x  ONLINE  -
```

# Create VM

First created a VM using the [12.3 virtual machine image][vmdk] available on the FreeBSD website.
Set the boot disk size to 10GB to match production. Added `dat`, `idx`, and `wal` SCSI drives sized
200GB, 100GB, and 50GB.

## Setup dev user

First create `matt` user for personal use. Log in as `root` (there is no password), then:

```sh
pw groupadd matt -g 1001

# create user and add to wheel group to all admin tasks
pw useradd matt -c 'Matt Magoffin' -s /bin/sh -u 1001 -m -g matt -G wheel

# set password
passwd matt
```

Then enable SSH/zfs and update hostname in `/etc/rc.conf` with this content:

```
hostname="sndb"

sshd_enable="YES"
zfs_enable="YES"
```

Then `reboot` and can then log in via `ssh` to perform remaining tasks. To ease login, create an
_authorized ssh key_:

```sh
mkdir .ssh
chmod 700 .ssh
touch .ssh/authorized_keys
chmod 600 .ssh/authorized_keys
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG/XKQPlOP1szB+6AAck49yS70e4w5FCywQ++PxtiMut matt@Tanooki' >.ssh/authorized_keys
```

## Setup ec2-user

To mirror production as closely as possible, create an `ec2-user` account, similar to the previous
`matt` account:

```sh
su -
pw groupadd ec2-user -g 1002
pw useradd ec2-user -c 'User &' -s /bin/sh -u 1002 -m -g ec2-user -G wheel

su - ec2-user
mkdir .ssh
chmod 700 .ssh
touch .ssh/authorized_keys
chmod 600 .ssh/authorized_keys
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG/XKQPlOP1szB+6AAck49yS70e4w5FCywQ++PxtiMut matt@Tanooki' >.ssh/authorized_keys
```

To be pedantic, log out fully now and then ssh back in as `ec2-user`:

```sh
exit # ec2-user
exit # root
exit # matt

ssh ec2-user@sndb
```

## Setup kernel settings

Update `/boot/loader.conf` with:

```
# Cap ZFS ARC to give room to database
vfs.zfs.arc_max="7G"

# Postgres
kern.ipc.semmni="256"
kern.ipc.semmns="512"
kern.ipc.semmnu="256"
```

Update `/etc/sysctl.conf` with:

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

Setup swap:

```sh
dd if=/dev/zero of=/usr/swap0 bs=1m count=1024

# note enable in /etc/fstab
# md99   none    swap    sw,file=/usr/swap0,late 0       0
# 
# also comment out vmdk swap partition

swapon -aL
```

Set up desired options in `/etc/rc.conf`:

```
# Mount ZFS
zfs_enable="YES"

ntpd_enable="YES"
ntpd_sync_on_start="YES"

# Prevent syslog to open sockets
syslogd_flags="-ss"
 
# MTA
sendmail_enable="NONE"

# Postgres
postgresql_enable="NO"
postgresql_data="/sndb/home/12"
postgresql_flags="-w -s -m fast"
postgresql_initdb_flags="--encoding=utf-8 --locale=C"
postgresql_class="postgres"
postgresql_user="postgres"
```

## Setup package repo

Setup a `snf` package repository in `/usr/local/etc/pkg/repos/snf.conf` with this content:

```
snf: {
	url: "http://poudriere/packages/solardb_pg12_123x64-tsdb1",
	mirror_type: "http",
	signature_type: "pubkey",
	pubkey: "/usr/local/etc/ssl/certs/poudriere.cert",
	enabled: yes,
	priority: 100
}
```

Copy certificate:

```sh
mkdir -p /usr/local/etc/ssl/certs

fetch -o /usr/local/etc/ssl/certs/poudriere.cert http://poudriere/poudriere.cert
```

Since FreeBSD 12.3 is no long supported, disable that repository by creating a 
`/usr/local/etc/pkg/repos/freebsd.conf` file with:

```
FreeBSD: {
	enabled: no
}
```

Now can bootstrap `pkg`:

```sh
setenv PACKAGESITE http://poudriere/packages/solardb_pg12_123x64-tsdb1
pkg update
```

## Setup postgres login class

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


## Setup zfs

Create 3 pools to match production: `dat`, `idx`, and `wal`. Using the `dmesg` output as a guide to
the drive names:

```
da1 at mpt0 bus 0 scbus2 target 1 lun 0
da1: <VMware, VMware Virtual S 1.0> Fixed Direct Access SCSI-2 device
da1: 320.000MB/s transfers (160.000MHz, offset 127, 16bit)
da1: Command Queueing enabled
da1: 204800MB (419430400 512 byte sectors)
da1: quirks=0x140<RETRY_BUSY,STRICT_UNMAP>
da2 at mpt0 bus 0 scbus2 target 2 lun 0
da2: <VMware, VMware Virtual S 1.0> Fixed Direct Access SCSI-2 device
da2: 320.000MB/s transfers (160.000MHz, offset 127, 16bit)
da2: Command Queueing enabled
da2: 102400MB (209715200 512 byte sectors)
da2: quirks=0x140<RETRY_BUSY,STRICT_UNMAP>
da3 at mpt0 bus 0 scbus2 target 3 lun 0
da3: <VMware, VMware Virtual S 1.0> Fixed Direct Access SCSI-2 device
da3: 320.000MB/s transfers (160.000MHz, offset 127, 16bit)
da3: Command Queueing enabled
da3: 51200MB (104857600 512 byte sectors)
da3: quirks=0x140<RETRY_BUSY,STRICT_UNMAP>
```

Here `da1` is `dat`, `da2` is `idx`, and `da3` is `wal`.

```sh
zpool create -O canmount=off -m none dat /dev/da1
zpool create -O canmount=off -m none idx /dev/da2
zpool create -O canmount=off -m none wal /dev/da3
```

## Install Postgres

Install Postgres, along with supporting packages required by pgBackRest:

```sh
pkg install -r snf postgresql12-server postgresql12-contrib postgresql12-client timescaledb210 postgresql-aggs_for_vecs daemontools pgbackrest ca_root_nss

# assign to postgres login class
pw usermod postgres -L postgres
```

Setup common dataset properties and create Postgres 12 filesystems:

```sh 
#!/bin/sh -e

POOLS="dat idx wal"

for p in $POOLS; do
   	zfs set atime=off $p
	zfs set exec=off $p
	zfs set setuid=off $p
	zfs set compression=lz4 $p
	if [ "$p" = "dat" ]; then
		zfs set recordsize=32k $p
	else
		zfs set recordsize=8k $p
	fi
	zfs create -o mountpoint=/sndb/$p $p/$p
done

zfs create -o mountpoint=/sndb/home dat/home
zfs create -o mountpoint=/sndb/log dat/log
zfs set compression=gzip dat/log
zfs set recordsize=128k dat/log

mkdir /sndb/log/12

chown -R postgres:postgres /sndb/*
chmod 700 /sndb/dat
chmod 700 /sndb/idx
```

Initialize Postgres cluster:

```sh
service postgresql oneinitdb
```

Move WAL:

```sh
mv /sndb/home/12/pg_wal /sndb/wal/12
ln -s /sndb/wal/12 /sndb/home/12/pg_wal
```

## pgbackrest restore

Copy setting files to `~postgres/pgbackrest.d`.

```
su - postgres
mkdir /sndb/home/12/tls
chown -h postgres /sndb/home/12/pg_wal
mkdir /var/tmp/pgrestore
envdir ~/pgbackrest.d/env pgbackrest --link-all --process-max=4 \
 --tablespace-map=16400=/sndb/dat \
 --tablespace-map=16401=/sndb/idx \
 --link-map=pg_wal=/sndb/wal/12 \
 --link-map=tls/db.solarnetwork.net.fullchain=/var/tmp/pgrestore/tls/db.solarnetwork.net.fullchain \
 --link-map=tls/db.solarnetwork.net.key=/var/tmp/pgrestore/tls/db.solarnetwork.net.key\
 --log-level-console=info \
 --delta \
restore
```

## Setup Postgres settings

Copy settings from `solardb-a` (replica), but comment out `primary_conninfo` and WAL settings
`archive_command`, `restore_command` and change

```
archive_mode = off
```

Then fix pgBackRest's default restore settings in `/sndb/home/12/postgresql.auto.conf`, by inserting
`envdir ~/pgbackrest.d/env` in front of `pgbackrest` in the `restore_command`. Also add
`recovery_target_action` to immediately promote to primary and stop recovery.

```
# Recovery settings generated by pgBackRest restore on 2025-02-26 15:41:43
restore_command = 'envdir ~/pgbackrest.d/env pgbackrest archive-get %f "%p"'
recovery_target_action = 'promote'
```

## Development finishing touches

As the timescaledb package is slightly different, it must be updated in the Postgres cluster:

```sh
service postgresql onestart

su -l postgres -c 'psql -xd solarnetwork -c "alter extension timescaledb update"'
```

See the [docs on handling streaming replication servers][rep-rsync], how `rsync` can be used to 
quickly upgrade the replica.

[vmdk]: http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/VM-IMAGES/12.3-RELEASE/amd64/Latest/
[rep-rsync]: https://www.postgresql.org/docs/current/pgupgrade.html#PGUPGRADE-STEP-REPLICAS
