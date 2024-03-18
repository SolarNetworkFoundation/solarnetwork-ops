# Upgrade to Timescale 2.11 on FreeBSD 12.3

Production Postgres systems are running on FreeBSD 12.3 with Postgres 12.14 and Timescale 2.10.1.
Eventually these will be upgraded to more recent versions, but a first step is to upgrade 
Timescale to version 2.11.2, the last version to support Postgres 12.

As the FreeBSD `databases/timescaledb` port has moved onto versions higher than 2.11.2, SNF has
created a `databases/timescaledb211` port fixed at version 2.11.2. To upgrade to this, the new
port needs to be installed, which will replace the `databases/timescale` port.

## Update software 

```
$ sudo pkg install timescaledb211

The following 9 package(s) will be affected (of 0 checked):

Installed packages to be REMOVED:
	timescaledb: 2.10.1

New packages to be INSTALLED:
	timescaledb211: 2.11.2 [poudriere]

Installed packages to be UPGRADED:
	curl: 7.87.0_1 -> 8.6.0 [poudriere]
	icu: 72.1,1 -> 74.2,1 [poudriere]
	openssl: 1.1.1t,1 -> 3.0.13,1 [poudriere]
	pgbackrest: 2.35_2 -> 2.47 [poudriere]
	postgresql12-client: 12.14 -> 12.17 [poudriere]
	postgresql12-contrib: 12.14 -> 12.17 [poudriere]
	postgresql12-server: 12.14 -> 12.17_2 [poudriere]

Number of packages to be removed: 1
Number of packages to be installed: 1
Number of packages to be upgraded: 7

The process will require 9 MiB more space.
26 MiB to be downloaded.

...

Checking integrity... done (1 conflicting)
  - timescaledb211-2.11.2 [poudriere] conflicts with timescaledb-2.10.1 [installed] on /usr/local/lib/postgresql/timescaledb.so
Checking integrity... done (0 conflicting)
Conflicts with the existing packages have been found.
One more solver iteration is needed to resolve them.
The following 10 package(s) will be affected (of 0 checked):

Installed packages to be REMOVED:
	timescaledb: 2.10.1

New packages to be INSTALLED:
	timescaledb211: 2.11.2 [poudriere]

Installed packages to be UPGRADED:
	curl: 7.87.0_1 -> 8.6.0 [poudriere]
	icu: 72.1,1 -> 74.2,1 [poudriere]
	openssl: 1.1.1t,1 -> 3.0.13,1 [poudriere]
	pgbackrest: 2.35_2 -> 2.47 [poudriere]
	postgresql12-client: 12.14 -> 12.17 [poudriere]
	postgresql12-contrib: 12.14 -> 12.17 [poudriere]
	postgresql12-server: 12.14 -> 12.17_2 [poudriere]

Installed packages to be REINSTALLED:
	pkg-1.20.9 [poudriere]

Number of packages to be removed: 1
Number of packages to be installed: 1
Number of packages to be upgraded: 7
Number of packages to be reinstalled: 1

The process will require 9 MiB more space.
```

## Update Timescale extension

```sh
service postgresql onestart

su - postgres

psql -X -c 'ALTER EXTENSION timescaledb UPDATE' solarnetwork

# verify
psql -X -c '\dx' solarnetwork
```


