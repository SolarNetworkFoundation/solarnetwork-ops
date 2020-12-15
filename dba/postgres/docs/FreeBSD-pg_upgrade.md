# pg_upgrade Guide on FreeBSD

TODO. For now, these notes from UPDATING are helpful:

Upgrade instructions:

  First stop your PostgreSQL, create PostgreSQL-binaries and backup your data.
  If you have another Version of PostgreSQL installed, for example 11.9, your
  files are named according to this.

```
# service postgresql stop
# pkg create postgresql96-server postgresql96-contrib
# mkdir /tmp/pg-upgrade
# tar xf postgresql96-server-9.6.18.txz -C /tmp/pg-upgrade
# tar xf postgresql96-contrib-9.6.18.txz -C /tmp/pg-upgrade
# pkg delete -f databases/postgresql96-server databases/postgresql96-contrib databases/postgresql96-client
```
  Now update PostgreSQL:

```
# pkg install databases/postgresql12-server databases/postgresql12-contrib
# pkg upgrade
```

  After installing the new PostgreSQL version you need to convert
  all your databases to new version:

```
# su -l postgres -c "/usr/local/bin/initdb --encoding=utf-8 --lc-collate=C -D /var/db/postgres/data12 -U postgres"
# su -l postgres -c "pg_upgrade -b /tmp/pg-upgrade/usr/local/bin/ -d /var/db/postgres/data11/ -B /usr/local/bin/ -D /var/db/postgres/data12/ -U postgres "
```
