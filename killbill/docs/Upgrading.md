# Upgrade 0.18 to 0.22

This update requires some database migrations to be applied. The `killbill/util` project produces
a `killbill-flyway.jar` utility that we use to help do this.

## Testing

Download a `mysqldump` of the production database, then create local database for testing:

```sh
# ssh to server... then
$ mysqldump -h kbmaria.XYZ.us-west-2.rds.amazonaws.com -P 3306 -u kbroot -p killbill \
    | xz > snf-killbill-20200602.sql.xz
    
# scp snf-killbill-20200602.sql.xz to local machine and uncompress...

# create DB
$ /usr/local/opt/mariadb@10.1/bin/mysql -u root
> CREATE DATABASE killbill CHARACTER SET = 'utf8';
> GRANT ALL PRIVILEGES ON killbill.* TO 'killbill'@localhost;
> FLUSH PRIVILEGES;

# load data
$ /usr/local/opt/mariadb@10.1/bin/mysql -u killbill -p killbill <snf-killbill-20200602.sql

# update emails
$ /usr/local/opt/mariadb@10.1/bin/mysql -u killbill -p killbill
> SET sql_mode = 'PIPES_AS_CONCAT';
> UPDATE accounts SET email = replace(email,'@','-AT-') || '@localhost';
```

## Download migrations

The `kpm` tool can be used to download the migrations. This tool does not work on current versions
of macOS without Gatekeeper disabled, so used a Linux VM to do it,  like this:

```sh
$ cd kpm-0.8.1-linux-x86_64
$ ./kpm migrations killbill killbill-0.18.20 killbill-0.22.10 --token=GITHUB_API_TOKEN_HERE
I, [2020-07-02T15:23:31.450453 #3457]  INFO -- : Looking for migrations repository=killbill/killbill, version=killbill-0.18.20
I, [2020-07-02T15:23:32.785097 #3457]  INFO -- : Looking for migrations repository=killbill/killbill, version=killbill-0.22.10
I, [2020-07-02T15:23:51.702703 #3457]  INFO -- : Migration to run: V20170915165117__external_key_not_null.sql
...
Migrations can be found at /tmp/d20200702-3457-1rgux52
```

## Set up Flyway

Because this is the first upgrade with a database migration, Flyway support must be initialised by
using the `baseline` command:

```sh
$ flyway -locations=filesystem:killbill-0.18.20-0.22.10-migrations \
    -url='jdbc:mariadb://localhost/killbill' -user=killbill -password=killbill \
    -table=schema_version baseline

Flyway Community Edition 6.5.0 by Redgate
Database: jdbc:mariadb://localhost/killbill (MariaDB 10.4)
Creating Schema History table `killbill`.`schema_version` with baseline ...
WARNING: DB: Name 'schema_version_pk' ignored for PRIMARY key. (SQL State:  - Error Code: 1280)
Successfully baselined schema with version: 1
```

## Run migration

```sh
$ flyway -url='jdbc:mariadb://localhost/killbill' -user=killbill -password=killbill \
    -table=schema_version -locations=filesystem:killbill-0.18.20-0.22.10-migrations migrate
```

## Discovered errors

Some duplicate `external_key` values are found in the `bundles` table:

```sql
select external_key,count(*) from bundles group by external_key having count(*) > 1;
+--------------+----------+
| external_key | count(*) |
+--------------+----------+
| IN_253       |        2 |
| IN_264       |        2 |
| IN_389       |        2 |
+--------------+----------+
```

cc57ffd6-f549-4c49-9b34-d7915fad2f72 21
2297b5aa-fbad-43af-88d4-93ee4fc8de06 23
7350b9ef-72a1-4ca4-ae18-95386d2491e0 92

