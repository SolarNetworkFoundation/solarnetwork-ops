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

# Create EC2 AMIs

Create new AMIs of primary and replicate servers, **including only the root drives** in the image.
The current AMIs for these servers include the data volumes, which we do not want included because
they take up a lot of space and are not necessary with the data backed up in S3 with pgBackRest.

The AMI names are **SolarDB-0 v4a** and **SolarDB-A v4a**.

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
