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
compression enabled, this should hold plenty of log segments. Attached to instance as `/dev/sdf`.

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
vfs.zfs.arc_max="6G"

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
postgresql_enable="YES"
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

Create `wal`, `idx`, and `dat` pools. To discover device names:

```
$ nvmecontrol devlist

 nvme0: Amazon Elastic Block Store
    nvme0ns1 (10240MB)              <-- boot volume
 nvme1: Amazon Elastic Block Store
    nvme1ns1 (102400MB)
 nvme2: Amazon Elastic Block Store
    nvme2ns1 (102400MB)
 nvme3: Amazon Elastic Block Store
    nvme3ns1 (51200MB)              <!-- wal volume
```

The boot and `wal` volumes can be easily identified by their sizes. The `dat` and `idx` volumes
must be discovered by looking at their volume identifier:

```
$ nvmecontrol identify nvme1

Controller Capabilities/Features
================================
Vendor ID:                   1d0f
Subsystem Vendor ID:         1d0f
Serial Number:               vol05a875893ee5351dd
```

The **Serial Number** property corresponds to the volume identifier assigned by AWS, which you can
see in the AWS console.

```sh 
zpool create -O canmount=off -m none wal /dev/nvd1
zpool create -O canmount=off -m none idx /dev/nvd2
zpool create -O canmount=off -m none dat /dev/nvd3
```

### Attaching volumes while running

If expanding the number of volumes on a running instance later, after attaching the volume to the
instance you must run the following for FreeBSD to "see" the new volume:

```sh
devctl rescan pci0
```

Afterwards, `nvmecontrol devlist` will show the new volume.

## Install Postgres

```sh
pkg install -r snf postgresql96-server postgresql96-plv8js postgresql96-contrib postgresql96-client timescaledb

# assign to postgres login class
pw usermod postgres -L postgres
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

Then continue:

```
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
TMPDIR
WALE_S3_PREFIX
WALE_S3_STORAGE_CLASS
```

Each file contains the associated value. The `WALE_S3_PREFIX` is `s3://snf-internal/backups/postgres/96`.
The `WALE_S3_STORAGE_CLASS` is `STANDARD_IA`. The `TMPDIR` is set so the root filesystem does not
fill up and run out of space; currently this is set to `/sndb/9.6/tmp`.


## Configure Postgres

Create log dir:

```sh
mkdir /var/log/postgres
chgrp postgres /var/log/postgres
chmod g+w /var/log/postgres
```

Setup `pg_hba.conf` with user/certificate authentication support.

## Configure Certbot

```
pkg install py37-certbot py37-certbot-dns-route53
echo 'weekly_certbot_enable="YES"' >>/etc/periodic.conf
```

Set up credentials for AWS:

```sh
mkdir ~/.aws
touch ~/.aws/config
chmod 600 ~/.aws/config
```

Then configured AWS credentials `~/.aws/config` like

```
[default]
aws_access_key_id=AKIAIOSFODNN7EXAMPLE
aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

Created initial certificate via:

```sh
certbot certonly --dns-route53 -d db.solarnetwork.net
```

Created renewal hook script `/usr/local/etc/letsencrypt/renewal-hooks/deploy/solardb.sh`

```
#!/bin/sh

set -e

daemon_cert_root=/sndb/9.6/home/tls
for domain in $RENEWED_DOMAINS; do
		# Make sure the certificate and private key files are
		# never world readable, even just for an instant while
		# we're copying them into daemon_cert_root.
		umask 077

		cp -f "$RENEWED_LINEAGE/fullchain.pem" "$daemon_cert_root/$domain.fullchain"
		cp -f "$RENEWED_LINEAGE/privkey.pem" "$daemon_cert_root/$domain.key"

		# Apply the proper file ownership and permissions for
		# the daemon to read its certificate and key.
		chmod 440 "$daemon_cert_root/$domain.fullchain" \
				"$daemon_cert_root/$domain.key"
				
		chgrp postgres "$daemon_cert_root/$domain.fullchain" \
				"$daemon_cert_root/$domain.key"
done
service postgresql reload >/dev/null
```

Ensure proper execute permissions set:

```sh
chmod 755 /usr/local/etc/letsencrypt/renewal-hooks/deploy/solardb.sh
```

Run the renew post-hook manually (**note** command below is for `sh`, **not** `csh`):

```sh
RENEWED_DOMAINS="db.solarnetwork.net" RENEWED_LINEAGE="/usr/local/etc/letsencrypt/live/db.solarnetwork.net" /usr/local/etc/letsencrypt/renewal-hooks/deploy/solardb.sh
```

Then configure links in `/sndb/9.6/home/tls`:

```sh
su - postgres
cd /sndb/9.6/home/tls
ln -s db.solarnetwork.net.fullchain server.crt
ln -s db.solarnetwork.net.key server.key
```

# Install Munin

```sh
pkg install munin-node munin-contrib
```

Set up Postgres settings in `/usr/local/etc/munin/plugin-conf.d/plugins.conf` by adding:

```
[postgres_*]
user postgres
env.PGUSER postgres
env.PGHOST /tmp
env.PGPORT 5432
```

Then created appropriate links in `/usr/local/etc/munin/plugins`.

# Initial database restore

To restore the database from the latest wal-e backup, need to create a `recovery.conf` file:

```
restore_command = 'envdir ~/wal-e.d/env ~/.local/bin/wal-e wal-fetch %f %p'
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
envdir ~/wal-e.d/env ~/.local/bin/wal-e backup-fetch --restore-spec ~/wal-e-restore-spec.json /sndb/9.6/home LATEST
```

Once complete, can adjust `postgresql.conf` to suit the VM.

# Setup periodic maintenance support

Create `~postgres/bin/index-chunk-maintenance.sh` and `~postgres/bin/solar-jobs.sh` scripts. Create
`~postgres/netrc/solarjobs-admin` file with:

```
machine solarjobs.solarnetwork
login solarnet-job-admin
password <<PASSWORD>>
```

Then set permissions:

```sh
chmod 400 ~postgres/netrc/solarjobs-admin
```

# Cron jobs

Set up some cronjobs for the `postgres` user:

```sh
echo 'cron_enable="YES"' >>/etc/rc.conf
echo 'cron_flags="$cron_flags -J 15"' >>/etc/rc.conf
```

Then edit crontab  via `crontab -e -u postgres` with:

```
# Update statistics weekly
0 4 * * Mon /usr/local/bin/vacuumdb -p 5432 --all --analyze-only

# create base backup 1st and 15th of every month
0 3 1,15 * * /usr/local/bin/envdir /var/db/postgres/wal-e.d/env /var/db/postgres/.local/bin/wal-e backup-push /sndb/9.6/home

# cleanup old backups every Sunday (keep last 9)
0 3 5,20 * * /usr/local/bin/envdir /var/db/postgres/wal-e.d/env /var/db/postgres/.local/bin/wal-e delete --confirm retain 3

# Run Hypertable reindex maintenance task weekly
#0 4 * * Sun /var/db/postgres/bin/index-chunk-maintenance.sh -c '-p 5432 -d solarnetwork' -n
```

# Postfix MTA

The built-in Sendmail with FreeBSD does not support SASL which is required to use the SES smart host.
Installed Postfix instead:

```
pkg install postfix
sysrc postfix_enable="YES"
sysrc sendmail_enable="NONE"
mkdir -p /usr/local/etc/mail
install -m 0644 /usr/local/share/postfix/mailer.conf.postfix /usr/local/etc/mail/mailer.conf
```

Add the following lines to /etc/periodic.conf:

```
daily_clean_hoststat_enable="NO"
daily_status_mail_rejects_enable="NO"
daily_status_include_submit_mailq="NO"
daily_submit_queuerun="NO"
```

See [the SES Postfix guide](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/postfix.html)	for
more details.

Created `/usr/local/etc/postfix/sasl_passwd` file like

```
[email-smtp.us-west-2.amazonaws.com]:587 USERNAME:PASSWORD
```

Then added this to `/usr/local/etc/postfix/main.cf`:

```
alias_maps = hash:/etc/aliases
relayhost = [email-smtp.us-west-2.amazonaws.com]:587
smtp_tls_note_starttls_offer = yes
smtp_tls_security_level = encrypt
smtp_sasl_password_maps = hash:/usr/local/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_sasl_auth_enable = yes
smtp_use_tls = yes
smtp_tls_CAfile = /usr/local/share/certs/ca-root-nss.crt
```

In `/etc/aliases` set:

```
root:	operations@solarnetwork.net
```
