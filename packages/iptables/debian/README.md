# iptables Debian package

```sh
$ fpm -s dir -t deb -m 'packaging@solarnetwork.org.nz' \
	--vendor 'SolarNetwork Foundation' \
	-n sn-iptables -v 1.0.0-1 \
	-a all \
	--description 'iptables firewall management service' \
	--license 'Apache License 2.0' \
	-f \
	-d 'cron (>= 3.0)' \
	-d 'iptables (>= 1.6.0)' \
	-d 'systemd (>= 232)' \
	--deb-systemd sn-iptables.service \
	etc usr
```
