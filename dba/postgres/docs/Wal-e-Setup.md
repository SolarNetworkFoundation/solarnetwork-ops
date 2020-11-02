# Wal-e Setup on FreeBSD

This guide outlines how [wal-e][wal-e] has been configured for Postgres continuous archiving to S3.
This guide assumes Postgres has already been deployed. The following additional FreeBSD packages are
needed:

 * `devel/py-pip`
 * `sysutils/daemontools`
 * `archivers/lzop`
 * `sysutils/pv`

## Install

```
ezjail-admin console postgres96
pkg install py37-pip
su - pgsql
python3 -m pip install awscli boto --user
```

**Note** found that couldn't install `wal-e` in above, because of problem in Python 3.6:

https://github.com/wal-e/wal-e/issues/322

The work-around in that ticket is to:

```
python3 -m pip install git+https://github.com/wal-e/wal-e.git@master --user
```

```
  WARNING: The scripts pyrsa-decrypt, pyrsa-decrypt-bigfile, pyrsa-encrypt, pyrsa-encrypt-bigfile, pyrsa-keygen, pyrsa-priv2pub, pyrsa-sign and pyrsa-verify are installed in '/usr/local/pgsql/.local/bin' which is not on PATH.
  Consider adding this directory to PATH or, if you prefer to suppress this warning, use --no-warn-script-location.
Successfully installed PyYAML-5.1.2 awscli-1.16.266 botocore-1.13.2 colorama-0.4.1 docutils-0.15.2 gevent-1.4.0 greenlet-0.4.15 jmespath-0.9.4 pyasn1-0.4.7 python-dateutil-2.8.0 rsa-3.4.2 s3transfer-0.2.1 six-1.12.0 urllib3-1.25.6 wal-e-1.1.0
```

Updated `/etc/login.conf` to change PATH of `postgres` login class:

```
postgres:\
        :path=/sbin /bin /usr/sbin /usr/bin /usr/games /usr/local/sbin /usr/local/bin ~/bin ~/.local/bin:\
        :lang=en_US.UTF-8:\
        :setenv=LC_COLLATE=C:\
        :tc=default:
```

# Setup envdir

Created `~pgsql/wal-e.d/env` directory with files:

```
AWS_ACCESS_KEY_ID
AWS_REGION
AWS_SECRET_ACCESS_KEY
PGPORT
WALE_S3_PREFIX
WALE_S3_STORAGE_CLASS
```

Each file contains the associated value. The `WALE_S3_PREFIX` is `s3://snf-internal/backups/postgres/96`.
The `WALE_S3_STORAGE_CLASS` is `STANDARD_IA`.

# Create base backup

As the `pgsql` user:

```
envdir ~/wal-e.d/env wal-e backup-push /solar93/9.6
```

# Configure WAL archiving

In /solar93/9.6/postgresql.conf:

```
archive_mode = on
archive_command = '/usr/local/bin/envdir /usr/local/pgsql/wal-e.d/env /usr/local/pgsql/.local/bin/wal-e wal-push %p'
archive_timeout = 60
```

# Configure periodic jobs

In the `pgsql` user's cron, added:

```
# create base backup every Saturday
0 3 * * Sat /usr/local/bin/envdir /usr/local/pgsql/wal-e.d/env /usr/local/pgsql/.local/bin/wal-e backup-push /solar93/9.6

# cleanup old backups every Sunday (keep last 9)
0 4 * * Sun /usr/local/bin/envdir /usr/local/pgsql/wal-e.d/env /usr/local/pgsql/.local/bin/wal-e delete --confirm retain 9
```

[wal-e]: https://github.com/wal-e/wal-e
