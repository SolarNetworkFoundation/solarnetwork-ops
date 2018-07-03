# ZFS Mirror Setup

A ZFS mirror of the database has been created for disaster recovery purposes.
The mirror runs FreeBSD, and the database server creates ZFS snapshots that
it copies to the mirror via `zfs send` compressed with `lz4` over a `ssh`
connection.

# Mirror OS Setup

The mirror OS is a vanilla FreeBSD 11.2 system. The following tweaks have
been made:

## lz4 support

Installed the `liblz4` package:

```sh
pkg install liblz4
```

## SSH

The root user is allowed to connect via SSH, so `zfs receive` can be used.
The `/etc/ssh/sshd_config` file has been modified like:

```
PermitRootLogin yes
```

Then a `/root/.ssh/authorized_keys` file has been created with the public
key of the data system user that will be using `zfs send` to allow
password-less connections.

## `rc.conf`

The following have been added to `/etc/rc.conf`:

```
### SolarNetwork configuration follows.
zfs_enable="YES"
sendmail_outbound_enable="NO"
```

## Periodic

A new `/etc/periodic.conf` file was created to not mail the daily stats:

```
daily_output="/dev/null"
daily_status_security_output="/dev/null"
weekly_output="/var/log/weekly.log"
weekly_status_security_output="/var/log/weekly.security.log"
monthly_output="/var/log/monthly.log"
monthly_status_security_output="/var/log/monthly.security.log"
```

## MOTD

The `/etc/motd` file has been modified with

```
FreeBSD 11.2-RELEASE (GENERIC) #0 r335510: Fri Jun 22 04:32:14 UTC 2018

SolarNetwork Data Replicant
```

## ZFS

An EBS volume has been attached to the instance, which has a ZFS pool
named `sndb` already on it. Then the pool was imported:

```sh
zpool import sndb
```

# Master OS Setup

## Cron job

A cron job has been added like the following:

```
PATH = /usr/bin:/bin:/sbin:/usr/sbin:/usr/local/bin

@hourly /root/bin/solo -port=65000 /root/bin/backup-solarnetwork-zfs -c zfsreplicant sndb
```

The `solo` script was taken from http://timkay.com/solo/. The `zfsreplicant` host name
is added to `/etc/hosts` to resolve to the actual host to connect to.
