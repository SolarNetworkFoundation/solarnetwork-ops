# SolarDB FreeBSD Server Setup

TODO

## Manually installed packages

On FreeBSD 12 server, found these packages installed:

```sh
archivers/lzop
databases/pgbackrest
databases/postgresql-aggs_for_vecs
databases/postgresql12-client
databases/postgresql12-contrib
databases/postgresql12-server
databases/timescaledb
ftp/curl
mail/postfix
net/dual-dhclient
net/rsync
ports-mgmt/pkg
security/py-certbot-dns-route53
sysutils/amazon-ssm-agent
sysutils/daemontools
sysutils/ec2-scripts
sysutils/firstboot-freebsd-update
sysutils/firstboot-pkgs
sysutils/munin-contrib
sysutils/munin-node
sysutils/pv
sysutils/tmux
```

On a new FreeBSD 14 server, found these packages installed at the start,
using `pkg query -e '%a = 0' %o | sort`:

```
devel/py-awscli
net/isc-dhcp44-client
ports-mgmt/pkg
sysutils/amazon-ssm-agent
sysutils/ebsnvme-id
sysutils/ec2-scripts
sysutils/firstboot-freebsd-update
sysutils/firstboot-pkgs
```

Comparing these lists in `old.txt` and `new.txt` using `comm -23 old.txt new.txt` found these
actually manually installed packages:

```
archivers/lzop
databases/pgbackrest
databases/postgresql-aggs_for_vecs
databases/postgresql12-client
databases/postgresql12-contrib
databases/postgresql12-server
databases/timescaledb
ftp/curl
mail/postfix
net/dual-dhclient
net/rsync
security/py-certbot-dns-route53
sysutils/daemontools
sysutils/munin-contrib
sysutils/munin-node
sysutils/pv
sysutils/tmux
```
