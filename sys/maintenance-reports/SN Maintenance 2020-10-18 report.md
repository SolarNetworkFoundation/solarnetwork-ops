# SN DB Maintenance 2020-10-18

This maintenance is to update the VMs running the SN Postgres cluster:

 * update FreeBSD to 12.1p10
 * update Postgres to 9.6.19
 * update Timescale to 1.7.4
 
Additionally the swap configuration will be modified so 4GB is available, and the WAL-E cron
configuration will change so full backups occur on the 1st and 15th of each month and 3 full
backups will be preserved via a cleanup on the 5th and 20th of each month.

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


# Update DB packages

Replica:

```sh
snssh ec2-user@solardb-a
su -
service postgresql stop
sed -i '' -e 's/postgresql_enable="YES"/postgresql_enable="NO"/' /etc/rc.conf
freebsd-update fetch
freebsd-update install
pkg update
pkg unlock databases/timescaledb
pkg upgrade
pkg lock databases/timescaledb
pkg clean -a
reboot

snssh ec2-user@solardb-a
su -
rm -r /var/db/freebsd-update/*
swapoff -a
dd if=/dev/zero of=/usr/swap0 bs=1m count=4096
rm -f /usr/swap1
swapon -aL
```

Output:

```
The following 120 package(s) will be affected (of 0 checked):

New packages to be INSTALLED:
	p5-Clone: 0.45 [snf]

Installed packages to be UPGRADED:
	amazon-ssm-agent: 2.3.612.0_1 -> 2.3.1205.0 [FreeBSD]
	awscli: 1.16.270 -> 1.18.150 [FreeBSD]
	bash: 5.0.17 -> 5.0.18_3 [snf]
	ca_root_nss: 3.54 -> 3.57 [FreeBSD]
	curl: 7.69.1 -> 7.72.0 [FreeBSD]
	firstboot-pkgs: 1.5 -> 1.6 [FreeBSD]
	gettext-runtime: 0.20.1 -> 0.21 [FreeBSD]
	isc-dhcp44-client: 4.4.2 -> 4.4.2_1 [FreeBSD]
	libevent: 2.1.11 -> 2.1.12 [FreeBSD]
	libffi: 3.2.1_3 -> 3.3_1 [FreeBSD]
	libnghttp2: 1.40.0 -> 1.41.0 [FreeBSD]
	libxml2: 2.9.10 -> 2.9.10_1 [snf]
	munin-common: 2.0.60 -> 2.0.64 [snf]
	munin-node: 2.0.60_1 -> 2.0.64 [snf]
	openssl: 1.1.1g,1 -> 1.1.1h_1,1 [snf]
	p5-DBD-Pg: 3.11.1 -> 3.14.2 [snf]
	p5-DateTime-HiRes: 0.01_1 -> 0.04 [snf]
	p5-DateTime-Locale: 1.25 -> 1.28 [snf]
	p5-DateTime-TimeZone: 2.38,1 -> 2.41,1 [snf]
	p5-File-Listing: 6.04_1 -> 6.11 [snf]
	p5-HTML-Parser: 3.72 -> 3.75 [snf]
	p5-HTTP-Daemon: 6.06 -> 6.12 [snf]
	p5-HTTP-Message: 6.22 -> 6.26 [snf]
	p5-Log-Log4perl: 1.49 -> 1.53 [snf]
	p5-Mozilla-CA: 20180117 -> 20200520 [snf]
	p5-Net-DNS: 1.23,1 -> 1.27,1 [snf]
	p5-TimeDate: 2.30_2,1 -> 2.33,1 [snf]
	p5-XML-LibXML: 2.0204,1 -> 2.0206,1 [snf]
	p5-libwww: 6.44 -> 6.49 [snf]
	pcre: 8.43_2 -> 8.44 [snf]
	perl5: 5.30.2 -> 5.32.0 [snf]
	postfix: 3.5.1_1,1 -> 3.5.7,1 [snf]
	postgresql96-client: 9.6.17 -> 9.6.19 [snf]
	postgresql96-contrib: 9.6.17 -> 9.6.19 [snf]
	postgresql96-plv8js: 1.4.8_5 -> 1.4.8_6 [snf]
	postgresql96-server: 9.6.17_2 -> 9.6.19 [snf]
	py37-botocore: 1.13.6 -> 1.18.9 [FreeBSD]
	py37-certifi: 2019.11.28 -> 2020.6.20 [FreeBSD]
	py37-cffi: 1.14.0 -> 1.14.3 [FreeBSD]
	py37-colorama: 0.4.1 -> 0.4.3 [FreeBSD]
	py37-jmespath: 0.9.5 -> 0.10.0 [FreeBSD]
	py37-pip: 19.1.1 -> 20.2.3 [snf]
	py37-pycparser: 2.19 -> 2.20 [FreeBSD]
	py37-s3transfer: 0.2.1 -> 0.3.3 [FreeBSD]
	py37-six: 1.14.0 -> 1.15.0 [FreeBSD]
	py37-urllib3: 1.25.7,1 -> 1.25.10,1 [FreeBSD]
	python27: 2.7.17_1 -> 2.7.18_1 [snf]
	python37: 3.7.7 -> 3.7.9 [FreeBSD]
	tmux: 3.0a_1 -> 3.1b [FreeBSD]
	utf8proc: 2.4.0 -> 2.5.0 [FreeBSD]

Installed packages to be REINSTALLED:
	p5-Algorithm-C3-0.10_1 [snf] (direct dependency changed: perl5)
	p5-Authen-NTLM-1.09_1 [snf] (direct dependency changed: perl5)
	p5-B-Hooks-EndOfScope-0.24 [snf] (direct dependency changed: perl5)
	p5-Cache-2.11 [snf] (direct dependency changed: perl5)
	p5-Cache-Cache-1.08 [snf] (direct dependency changed: perl5)
	p5-Class-C3-0.34 [snf] (direct dependency changed: perl5)
	p5-Class-Data-Inheritable-0.08_1 [snf] (direct dependency changed: perl5)
	p5-Class-Inspector-1.36 [snf] (direct dependency changed: perl5)
	p5-Class-Method-Modifiers-2.13 [snf] (direct dependency changed: perl5)
	p5-Class-Singleton-1.5_1 [snf] (direct dependency changed: perl5)
	p5-DBI-1.643 [snf] (direct dependency changed: perl5)
	p5-Data-OptList-0.110 [snf] (direct dependency changed: perl5)
	p5-DateTime-1.52 [snf] (direct dependency changed: perl5)
	p5-Devel-StackTrace-2.04 [snf] (direct dependency changed: perl5)
	p5-Digest-HMAC-1.03_1 [snf] (direct dependency changed: perl5)
	p5-Digest-SHA1-2.13_1 [snf] (direct dependency changed: perl5)
	p5-Dist-CheckConflicts-0.11_1 [snf] (direct dependency changed: perl5)
	p5-Encode-Locale-1.05 [snf] (direct dependency changed: perl5)
	p5-Error-0.17029 [snf] (direct dependency changed: perl5)
	p5-Eval-Closure-0.14 [snf] (direct dependency changed: perl5)
	p5-Exception-Class-1.44 [snf] (direct dependency changed: perl5)
	p5-Exporter-Tiny-1.002002 [snf] (direct dependency changed: perl5)
	p5-File-NFSLock-1.29 [snf] (direct dependency changed: perl5)
	p5-File-ShareDir-1.116 [snf] (direct dependency changed: perl5)
	p5-HTML-Tagset-3.20_1 [snf] (direct dependency changed: perl5)
	p5-HTTP-Cookies-6.08 [snf] (direct dependency changed: perl5)
	p5-HTTP-Date-6.05 [snf] (direct dependency changed: perl5)
	p5-HTTP-Negotiate-6.01_1 [snf] (direct dependency changed: perl5)
	p5-Heap-0.80_1 [snf] (direct dependency changed: perl5)
	p5-IO-HTML-1.001_1 [snf] (direct dependency changed: perl5)
	p5-IO-Multiplex-1.16 [snf] (direct dependency changed: perl5)
	p5-IO-Socket-INET6-2.72_1 [snf] (direct dependency changed: perl5)
	p5-IO-Socket-SSL-2.068 [snf] (direct dependency changed: perl5)
	p5-IO-String-1.08_1 [snf] (direct dependency changed: perl5)
	p5-IPC-ShareLite-0.17_1 [snf] (direct dependency changed: perl5)
	p5-LWP-MediaTypes-6.04 [snf] (direct dependency changed: perl5)
	p5-List-MoreUtils-0.428 [snf] (direct dependency changed: perl5)
	p5-List-MoreUtils-XS-0.428 [snf] (direct dependency changed: perl5)
	p5-MRO-Compat-0.13 [snf] (direct dependency changed: perl5)
	p5-Module-Implementation-0.09_1 [snf] (direct dependency changed: perl5)
	p5-Module-Runtime-0.016 [snf] (direct dependency changed: perl5)
	p5-Net-CIDR-0.20 [snf] (direct dependency changed: perl5)
	p5-Net-HTTP-6.19 [snf] (direct dependency changed: perl5)
	p5-Net-IP-1.26_1 [snf] (direct dependency changed: perl5)
	p5-Net-SSLeay-1.88 [snf] (direct dependency changed: perl5)
	p5-Net-Server-2.009 [snf] (direct dependency changed: perl5)
	p5-Package-Stash-0.38 [snf] (direct dependency changed: perl5)
	p5-Package-Stash-XS-0.29 [snf] (direct dependency changed: perl5)
	p5-Params-Util-1.07_2 [snf] (direct dependency changed: perl5)
	p5-Params-Validate-1.29 [snf] (direct dependency changed: perl5)
	p5-Params-ValidationCompiler-0.30_1 [snf] (direct dependency changed: perl5)
	p5-Role-Tiny-2.001004 [snf] (direct dependency changed: perl5)
	p5-Socket6-0.29 [snf] (direct dependency changed: perl5)
	p5-Specio-0.46 [snf] (direct dependency changed: perl5)
	p5-Sub-Exporter-0.987_1 [snf] (direct dependency changed: perl5)
	p5-Sub-Exporter-Progressive-0.001013 [snf] (direct dependency changed: perl5)
	p5-Sub-Identify-0.14 [snf] (direct dependency changed: perl5)
	p5-Sub-Install-0.928_1 [snf] (direct dependency changed: perl5)
	p5-Sub-Quote-2.006006 [snf] (direct dependency changed: perl5)
	p5-Try-Tiny-0.30 [snf] (direct dependency changed: perl5)
	p5-URI-1.76 [snf] (direct dependency changed: perl5)
	p5-Variable-Magic-0.62 [snf] (direct dependency changed: perl5)
	p5-WWW-RobotRules-6.02_1 [snf] (direct dependency changed: perl5)
	p5-XML-NamespaceSupport-1.12 [snf] (direct dependency changed: perl5)
	p5-XML-Parser-2.44 [snf] (direct dependency changed: perl5)
	p5-XML-SAX-1.02 [snf] (direct dependency changed: perl5)
	p5-XML-SAX-Base-1.09 [snf] (direct dependency changed: perl5)
	p5-namespace-autoclean-0.29 [snf] (direct dependency changed: perl5)
	p5-namespace-clean-0.27 [snf] (direct dependency changed: perl5)

Number of packages to be installed: 1
Number of packages to be upgraded: 50
Number of packages to be reinstalled: 69

87 MiB to be downloaded.
```

Primary:

```sh
snssh ec2-user@solardb-0
su -
service postgresql stop
sed -i '' -e 's/postgresql_enable="YES"/postgresql_enable="NO"/' /etc/rc.conf
freebsd-update fetch
freebsd-update install
pkg update
pkg unlock databases/timescaledb
pkg upgrade
pkg lock databases/timescaledb
pkg clean -a
reboot

snssh ec2-user@solardb-a
su -
rm -r /var/db/freebsd-update/*

zfs create dat/9.6/home/logs
chown postgres /sndb/9.6/home/logs
chmod 700 /sndb/9.6/home/logs
mv /var/log/postgres /var/log/postgres.bak
cd /var/log
ln -s /sndb/9.6/home/logs postgres
mv postgres.bak/* postgres/
rm -rf postgres.bak

swapoff -a
rm /usr/swap0
dd if=/dev/zero of=/usr/swap0 bs=1m count=4096
chmod 0600 /usr/swap0
swapon -aL

```

Output:

```
The following 129 package(s) will be affected (of 0 checked):

New packages to be INSTALLED:
	p5-Clone: 0.45 [snf]

Installed packages to be UPGRADED:
	amazon-ssm-agent: 2.3.612.0_1 -> 2.3.1205.0 [FreeBSD]
	awscli: 1.16.270 -> 1.18.150 [FreeBSD]
	bash: 5.0.17 -> 5.0.18_3 [snf]
	ca_root_nss: 3.52 -> 3.57 [FreeBSD]
	curl: 7.69.1 -> 7.72.0 [FreeBSD]
	firstboot-pkgs: 1.5 -> 1.6 [FreeBSD]
	gettext-runtime: 0.20.1 -> 0.21 [FreeBSD]
	isc-dhcp44-client: 4.4.2 -> 4.4.2_1 [FreeBSD]
	libevent: 2.1.11 -> 2.1.12 [FreeBSD]
	libffi: 3.2.1_3 -> 3.3_1 [FreeBSD]
	libnghttp2: 1.40.0 -> 1.41.0 [FreeBSD]
	libxml2: 2.9.10 -> 2.9.10_1 [snf]
	munin-common: 2.0.60 -> 2.0.64 [snf]
	munin-node: 2.0.60_1 -> 2.0.64 [snf]
	openssl: 1.1.1g,1 -> 1.1.1h_1,1 [snf]
	p5-DBD-Pg: 3.11.1 -> 3.14.2 [snf]
	p5-DateTime-HiRes: 0.01_1 -> 0.04 [snf]
	p5-DateTime-Locale: 1.25 -> 1.28 [snf]
	p5-DateTime-TimeZone: 2.38,1 -> 2.41,1 [snf]
	p5-File-Listing: 6.04_1 -> 6.11 [snf]
	p5-HTML-Parser: 3.72 -> 3.75 [snf]
	p5-HTTP-Daemon: 6.06 -> 6.12 [snf]
	p5-HTTP-Message: 6.22 -> 6.26 [snf]
	p5-Log-Log4perl: 1.49 -> 1.53 [snf]
	p5-Mozilla-CA: 20180117 -> 20200520 [snf]
	p5-Net-DNS: 1.23,1 -> 1.27,1 [snf]
	p5-TimeDate: 2.30_2,1 -> 2.33,1 [snf]
	p5-XML-LibXML: 2.0204,1 -> 2.0206,1 [snf]
	p5-libwww: 6.44 -> 6.49 [snf]
	pcre: 8.43_2 -> 8.44 [snf]
	perl5: 5.30.2 -> 5.32.0 [snf]
	postfix: 3.5.1_1,1 -> 3.5.7,1 [snf]
	postgresql96-client: 9.6.17 -> 9.6.19 [snf]
	postgresql96-contrib: 9.6.17 -> 9.6.19 [snf]
	postgresql96-plv8js: 1.4.8_5 -> 1.4.8_6 [snf]
	postgresql96-server: 9.6.17_2 -> 9.6.19 [snf]
	py37-acme: 1.3.0,1 -> 1.8.0,1 [FreeBSD]
	py37-boto3: 1.10.6 -> 1.15.8 [FreeBSD]
	py37-botocore: 1.13.6 -> 1.18.9 [FreeBSD]
	py37-certbot: 1.3.0,1 -> 1.8.0,1 [FreeBSD]
	py37-certbot-dns-route53: 1.3.0 -> 1.8.0 [FreeBSD]
	py37-certifi: 2019.11.28 -> 2020.6.20 [FreeBSD]
	py37-cffi: 1.14.0 -> 1.14.3 [FreeBSD]
	py37-colorama: 0.4.1 -> 0.4.3 [FreeBSD]
	py37-configargparse: 1.1 -> 1.2.3 [FreeBSD]
	py37-jmespath: 0.9.5 -> 0.10.0 [FreeBSD]
	py37-josepy: 1.3.0 -> 1.4.0 [FreeBSD]
	py37-parsedatetime: 2.5 -> 2.6 [FreeBSD]
	py37-pip: 19.1.1 -> 20.2.3 [snf]
	py37-pycparser: 2.19 -> 2.20 [FreeBSD]
	py37-requests-toolbelt: 0.8.0_1 -> 0.9.1 [FreeBSD]
	py37-s3transfer: 0.2.1 -> 0.3.3 [FreeBSD]
	py37-six: 1.14.0 -> 1.15.0 [FreeBSD]
	py37-urllib3: 1.25.7,1 -> 1.25.10,1 [FreeBSD]
	python27: 2.7.17_1 -> 2.7.18_1 [snf]
	python37: 3.7.7 -> 3.7.9 [FreeBSD]
	timescaledb: 1.7.0 -> 1.7.4 [snf]
	tmux: 3.0a_1 -> 3.1b [FreeBSD]
	utf8proc: 2.4.0 -> 2.5.0 [FreeBSD]

Installed packages to be REINSTALLED:
	p5-Algorithm-C3-0.10_1 [snf] (direct dependency changed: perl5)
	p5-Authen-NTLM-1.09_1 [snf] (direct dependency changed: perl5)
	p5-B-Hooks-EndOfScope-0.24 [snf] (direct dependency changed: perl5)
	p5-Cache-2.11 [snf] (direct dependency changed: perl5)
	p5-Cache-Cache-1.08 [snf] (direct dependency changed: perl5)
	p5-Class-C3-0.34 [snf] (direct dependency changed: perl5)
	p5-Class-Data-Inheritable-0.08_1 [snf] (direct dependency changed: perl5)
	p5-Class-Inspector-1.36 [snf] (direct dependency changed: perl5)
	p5-Class-Method-Modifiers-2.13 [snf] (direct dependency changed: perl5)
	p5-Class-Singleton-1.5_1 [snf] (direct dependency changed: perl5)
	p5-DBI-1.643 [snf] (direct dependency changed: perl5)
	p5-Data-OptList-0.110 [snf] (direct dependency changed: perl5)
	p5-DateTime-1.52 [snf] (direct dependency changed: perl5)
	p5-Devel-StackTrace-2.04 [snf] (direct dependency changed: perl5)
	p5-Digest-HMAC-1.03_1 [snf] (direct dependency changed: perl5)
	p5-Digest-SHA1-2.13_1 [snf] (direct dependency changed: perl5)
	p5-Dist-CheckConflicts-0.11_1 [snf] (direct dependency changed: perl5)
	p5-Encode-Locale-1.05 [snf] (direct dependency changed: perl5)
	p5-Error-0.17029 [snf] (direct dependency changed: perl5)
	p5-Eval-Closure-0.14 [snf] (direct dependency changed: perl5)
	p5-Exception-Class-1.44 [snf] (direct dependency changed: perl5)
	p5-Exporter-Tiny-1.002002 [snf] (direct dependency changed: perl5)
	p5-File-NFSLock-1.29 [snf] (direct dependency changed: perl5)
	p5-File-ShareDir-1.116 [snf] (direct dependency changed: perl5)
	p5-HTML-Tagset-3.20_1 [snf] (direct dependency changed: perl5)
	p5-HTTP-Cookies-6.08 [snf] (direct dependency changed: perl5)
	p5-HTTP-Date-6.05 [snf] (direct dependency changed: perl5)
	p5-HTTP-Negotiate-6.01_1 [snf] (direct dependency changed: perl5)
	p5-Heap-0.80_1 [snf] (direct dependency changed: perl5)
	p5-IO-HTML-1.001_1 [snf] (direct dependency changed: perl5)
	p5-IO-Multiplex-1.16 [snf] (direct dependency changed: perl5)
	p5-IO-Socket-INET6-2.72_1 [snf] (direct dependency changed: perl5)
	p5-IO-Socket-SSL-2.068 [snf] (direct dependency changed: perl5)
	p5-IO-String-1.08_1 [snf] (direct dependency changed: perl5)
	p5-IPC-ShareLite-0.17_1 [snf] (direct dependency changed: perl5)
	p5-LWP-MediaTypes-6.04 [snf] (direct dependency changed: perl5)
	p5-List-MoreUtils-0.428 [snf] (direct dependency changed: perl5)
	p5-List-MoreUtils-XS-0.428 [snf] (direct dependency changed: perl5)
	p5-MRO-Compat-0.13 [snf] (direct dependency changed: perl5)
	p5-Module-Implementation-0.09_1 [snf] (direct dependency changed: perl5)
	p5-Module-Runtime-0.016 [snf] (direct dependency changed: perl5)
	p5-Net-CIDR-0.20 [snf] (direct dependency changed: perl5)
	p5-Net-HTTP-6.19 [snf] (direct dependency changed: perl5)
	p5-Net-IP-1.26_1 [snf] (direct dependency changed: perl5)
	p5-Net-SSLeay-1.88 [snf] (direct dependency changed: perl5)
	p5-Net-Server-2.009 [snf] (direct dependency changed: perl5)
	p5-Package-Stash-0.38 [snf] (direct dependency changed: perl5)
	p5-Package-Stash-XS-0.29 [snf] (direct dependency changed: perl5)
	p5-Params-Util-1.07_2 [snf] (direct dependency changed: perl5)
	p5-Params-Validate-1.29 [snf] (direct dependency changed: perl5)
	p5-Params-ValidationCompiler-0.30_1 [snf] (direct dependency changed: perl5)
	p5-Role-Tiny-2.001004 [snf] (direct dependency changed: perl5)
	p5-Socket6-0.29 [snf] (direct dependency changed: perl5)
	p5-Specio-0.46 [snf] (direct dependency changed: perl5)
	p5-Sub-Exporter-0.987_1 [snf] (direct dependency changed: perl5)
	p5-Sub-Exporter-Progressive-0.001013 [snf] (direct dependency changed: perl5)
	p5-Sub-Identify-0.14 [snf] (direct dependency changed: perl5)
	p5-Sub-Install-0.928_1 [snf] (direct dependency changed: perl5)
	p5-Sub-Quote-2.006006 [snf] (direct dependency changed: perl5)
	p5-Try-Tiny-0.30 [snf] (direct dependency changed: perl5)
	p5-URI-1.76 [snf] (direct dependency changed: perl5)
	p5-Variable-Magic-0.62 [snf] (direct dependency changed: perl5)
	p5-WWW-RobotRules-6.02_1 [snf] (direct dependency changed: perl5)
	p5-XML-NamespaceSupport-1.12 [snf] (direct dependency changed: perl5)
	p5-XML-Parser-2.44 [snf] (direct dependency changed: perl5)
	p5-XML-SAX-1.02 [snf] (direct dependency changed: perl5)
	p5-XML-SAX-Base-1.09 [snf] (direct dependency changed: perl5)
	p5-namespace-autoclean-0.29 [snf] (direct dependency changed: perl5)
	p5-namespace-clean-0.27 [snf] (direct dependency changed: perl5)

Number of packages to be installed: 1
Number of packages to be upgraded: 59
Number of packages to be reinstalled: 69

The process will require 1 MiB more space.
93 MiB to be downloaded.
```

# Start up Postgres, update Timescale

On primary:

```sh
service postgresql onestart
su - postgres
psql -U postgres -d solarnetwork -X -c 'ALTER EXTENSION timescaledb UPDATE; \dx'
exit
sed -i '' -e 's/postgresql_enable="NO"/postgresql_enable="YES"/' /etc/rc.conf
```

Verified in logs that all was well, then on replica:

```sh
service postgresql onestart
sed -i '' -e 's/postgresql_enable="NO"/postgresql_enable="YES"/' /etc/rc.conf
```

Watched logs and waited for streaming replication to catch up. Then verified Timescale 
had been updated in Postgres via replication:

```sh
su - postgres
psql -U postgres -d solarnetwork -X -c '\dx'
```

# Update WAL-E cron configuration

On primary DB, changed cron settings for WAL-E full backups via

```sh
crontab -u postgres -e
```

to

```
# create base backup 1st and 15th of every month
0 3 1,15 * * /usr/local/bin/envdir /var/db/postgres/wal-e.d/env /var/db/postgres/.local/bin/wal-e backup-push /sndb/9.6/home

# cleanup old backups every Sunday (keep last 9)
0 3 5,20 * * /usr/local/bin/envdir /var/db/postgres/wal-e.d/env /var/db/postgres/.local/bin/wal-e delete --confirm retain 3
```

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
service nginx stop
```

Start ECS apps SolarJobs, SolarQuery, SolarUser:

```sh
for c in solarjobs solarquery solaruser; do \
aws ecs list-services --profile snf --output json --cluster $c |grep 'arn:aws' |tr -d \"; done \
|while read s; do aws ecs update-service --desired-count 1 --profile snf --cluster ${s##*/} --service $s; done
```
