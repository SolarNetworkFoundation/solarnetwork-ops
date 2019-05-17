# iptables Debian package

This directory contains packaging scripts used to create an iptables based firewall service 
`sn-iptables.deb`. It integrates a SSH [brute force][dropBrute] response script.


## Packaging requirements

Packaging done via [fpm][fpm]. To install `fpm`:

```sh
$ sudo apt-get install ruby ruby-dev build-essential
$ sudo gem install --no-ri --no-rdoc fpm
```

## Create package

Use `fpm` to package the service. This package is architecture independent:

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

[fpm]: https://github.com/jordansissel/fpm
[dropBrute]: https://github.com/robzr/dropBrute