# SN DB Maintenance 2020-10-18

This maintenance is to update the VMs running the SN Postgres cluster:

 * update FreeBSD from 12.2 to 12.3
 * update Postgres from 12.7 to 12.9
 * update Timescale from 2.3.1 to 2.5.1
 * install `aggs_for_vecs` Postgres extension 1.3
 
# OS Upgrade, part 1

For this first part, left system running so the update files could be downloaded. First configured
Postgres not to start up automatically, in `/etc/rc.conf`, then executed upgrade:

```sh
# Start tmux session
tmux

su -

sed -i '' -e 's/postgresql_enable="YES"/postgresql_enable="NO"/' /etc/rc.conf

freebsd-update -r 12.3-RELEASE upgrade
```

**Repeat on replica server.**
 
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

Back on DB server:

```sh
shutdown -p now
```

**Repeat on replica server.**

Then create snapshots of OS disks **and** data disks, so can restore if needed.

Then start up DB server, and continue:

```sh
/usr/sbin/freebsd-update install
```

Which output:

```sh
Installing updates...
Kernel updates have been installed.  Please reboot and run
"/usr/sbin/freebsd-update install" again to finish installing updates.
```

Updated SNF repo URL in `/usr/local/etc/pkg/repos/snf.conf` with

```sh
url: "http://snf-freebsd-repo.s3-website-us-west-2.amazonaws.com/solardb_pg12_123x64-tsdb1"
```

Then reboot and continue:

```sh
reboot

# when back up, continue with
/usr/sbin/freebsd-update install

pkg update
pkg upgrade
pkg install -r snf postgresql-aggs_for_vecs
```

**Repeat on replica server.**

# Update Postgres extensions

Start postgres on main server, followed by replica.

```sh
service postgresql onestart
```

As the `postgres` user, update the Timescale extension and install `aggs_for_vecs`:

```sh
su - postgres

psql -X -c 'ALTER EXTENSION timescaledb UPDATE' solarnetwork
psql -X -c 'CREATE EXTENSION IF NOT EXISTS aggs_for_vecs' solarnetwork

# verify
psql -X -c '\dx' solarnetwork

# stop postgres
service postgresql onestop
```

```sh
# enable Postgres to start on boot
sed -i '' -e 's/postgresql_enable="NO"/postgresql_enable="YES"/' /etc/rc.conf
```

# Create new AMIs

Create new versioned AMIs **SolarDB-0 v3** and **SolarDB-A v3**. The description is
**FreeBSD 12.3p1 Postgres 12.9 Timescale 2.5.1 aggs_for_vecs 1.3**. This will reboot the systems.

Once rebooted, start Postgres and enable staring at boot:

```
su - 
service postgres onestart

# enable Postgres to start on boot
sed -i '' -e 's/postgresql_enable="NO"/postgresql_enable="YES"/' /etc/rc.conf
```

# Spot check DB queries as needed

Run some queries in `psql` to verify the database is running normally. Verify that replication is
working normally.


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
