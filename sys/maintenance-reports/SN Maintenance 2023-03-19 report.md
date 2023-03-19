# SN DB Maintenance 2023-03-19

This maintenance is to update the VMs running the SN Postgres cluster:

 * update FreeBSD from 12.3-p1 to 12.3-p12
 * update Postgres from 12.9 to 12.14
 * update Timescale from 2.5.1 to 2.10.1
 
# OS Upgrade, part 1

For this first part, left system running so the update files could be downloaded. First configured
Postgres not to start up automatically, in `/etc/rc.conf`, then executed upgrade:

```sh
# Start tmux session
tmux

su -

sed -i '' -e 's/postgresql_enable="YES"/postgresql_enable="NO"/' /etc/rc.conf

freebsd-update fetch
```

> :warning: Repeat on replica server.
 
# Stop apps

Shutdown SolarIn proxy:

```sh
snssh ec2-user@solarin-proxy
su -
service nginx stop
```

Shutdown ECS apps SolarIn, SolarJobs, SolarQuery, SolarUser, OSCP FP:

```sh
for c in solarin solarjobs solarquery solaruser oscp-fp; do \
aws ecs list-services --profile snf --output json --cluster $c |grep 'arn:aws' |tr -d \"; done \
|while read s; do aws ecs update-service --desired-count 0 --profile snf --cluster ${s##*/} --service $s; done
```

> :warning: Monitor logs in CloudWatch to wait for ECS applications to actually terminate.

# OS Upgrade, part 2

Back on DB server:

```sh
service postgresql onestop
shutdown -p now
```

> :warning: Repeat on replica server.

Then create snapshots of OS disks **and** data disks, so can restore if needed. Gave each snapshot
a common date element in its name, e.g. `SolarDB_0 boot 20230319`.

Then start up DB server, and continue:

```sh
/usr/sbin/freebsd-update install
```

Which output:

```sh
Installing updates...
src component not installed, skipped
Installing updates...Scanning //usr/share/certs/blacklisted for certificates...
Scanning //usr/share/certs/trusted for certificates...
Scanning //usr/local/share/certs for certificates...
Scanning //usr/local/etc/ssl/certs for certificates...
 done.
```

Then continue and then reboot:

```sh
pkg clean -a
pkg update
pkg upgrade
reboot
```

> :warning: Repeat on replica server.

# Update Postgres extensions

Start postgres on main server, **followed by replica**.

```sh
service postgresql onestart

# repeat on replica; check replication in logs is OK
```

Back on **main server**:

As the `postgres` user, update the Timescale extension:

```sh
su - postgres

psql -X -c 'ALTER EXTENSION timescaledb UPDATE' solarnetwork

# verify
psql -X -c '\dx' solarnetwork
```

Check that **replica** has updated Timescale extension, e.g.

```sh
su - postgres
psql -X -c '\dx' solarnetwork
```

Then shutdown **main and replica** databases:

```sh
# stop postgres
service postgresql onestop

# repeat on replica
```

# Clean up

Clean up rollback files to free up image space:

```sh
rm -r /var/db/freebsd-update/*
```

**Repeat on replica server.**


# Create new AMIs

Create new versioned AMIs **SolarDB-0 v4** and **SolarDB-A v4**. The description is
**FreeBSD 12.3p12 Postgres 12.14 Timescale 2.10.1 aggs_for_vecs 1.3**. This will reboot the systems.

Once rebooted, start Postgres and enable starting at boot:

```sh
su - 
service postgresql onestart

# enable Postgres to start on boot
sed -i '' -e 's/postgresql_enable="NO"/postgresql_enable="YES"/' /etc/rc.conf
```

**Repeat on replica server.**

# Spot check DB queries as needed

Run some queries in `psql` to verify the database is running normally. Verify that replication is
working normally.

# Restart apps

Start ECS apps SolarIn, SolarJobs, SolarQuery, SolarUser, OSCP FP:

```sh
for c in solarin solarjobs solarquery solaruser oscp-fp; do \
aws ecs list-services --profile snf --output json --cluster $c |grep 'arn:aws' |tr -d \"; done \
|while read s; do aws ecs update-service --desired-count 1 --profile snf --cluster ${s##*/} --service $s; done
```

Start SolarIn proxy:

```sh
snssh ec2-user@solarin-proxy
su -
service nginx start
```

# Clean up temporary EC2 snapshots

Deleted all the EC2 temporary snapshots; easily found by filtering on common date element `20230319`.

# Notes

 * Errors reported by SolarIn/SolarUser on startup about Dogtag connection failing. Found that 
   restarting Dogtag Tomcat fixed the issue.
 * SolarIn async buffer queue seems to mis-report removals and/or lag after the initial rush of
   backed-up datum when SolarIn was restored. Unclear where the issue is.
