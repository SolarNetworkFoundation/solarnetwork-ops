# SolarNetwork Maintenance Guide

This guide outlines how various maintenance procedures related to the SolarNetwork production
deployment.


# Pausing/restarting SN Apps

If the maintenance requires stopping access to SolarNetwork (for example when the DB is to be 
upgraded) then pause the ECS/EC2 apps like this:


## ECS apps

The ECS app services can be listed like this:

```sh
for c in solarjobs solarquery solaruser; do aws ecs list-services --profile snf --cluster $c; done
```

To **stop** the ECS services set their _desired instance count_ to `0`, via the
`aws ecs update-service --desired-count 0` command like this (**note** that the cluster names are 
assumed to equal the service names):

```sh
for c in solarjobs solarquery solaruser; do \
aws ecs list-services --profile snf --output json --cluster $c |grep 'arn:aws' |tr -d \"; done \
|while read s; do aws ecs update-service --desired-count 0 --profile snf --cluster ${s##*/} --service $s; done
```

To **start** the ECS services set their _desired instance count_ back to their original value
(e.g. 1):

```sh
for c in solarjobs solarquery solaruser; do \
aws ecs list-services --profile snf --output json --cluster $c |grep 'arn:aws' |tr -d \"; done \
|while read s; do aws ecs update-service --desired-count 1 --profile snf --cluster ${s##*/} --service $s; done
```


# Postgres updates

When an updated Postgres package has been published to the SNF S3 package repo, then on each
DB server run:

```sh
service postgresql onestop
pkg update
pkg upgrade
```

## Timescale extension updates

If the Timescale extension has been updated, one additional step is required immediately after 
starting up the **primary** database server. Connect to the DB with `psql -X` and execute

```sql
ALTER EXTENSION timescaledb UPDATE;
```

This can be accomplished as the `postgres` user on the DB server itself like this:

```sh
psql -X -c 'ALTER EXTENSION timescaledb UPDATE' solarnetwork

# verify
psql -X -c '\dx' solarnetwork
```
