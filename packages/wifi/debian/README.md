# WiFi Debian package

This directory contains packaging scripts used to create a WiFi service `sn-wifi.deb`.

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
	-n sn-wifi -v 1.0.0-1 \
	-a all \
	--description 'WiFi management service' \
	--license 'Apache License 2.0' \
	-f \
	-d 'wpasupplicant (>= 2:2.4)' \
	-d 'systemd (>= 232)' \
	--after-install sn-wifi.postinst \
	--after-remove sn-wifi.postrm \
	--deb-config sn-wifi.config \
	--deb-templates sn-wifi.templates \
	--deb-systemd sn-wifi-bootconf.service \
	etc lib usr
```

[fpm]: https://github.com/jordansissel/fpm
[dropBrute]: https://github.com/robzr/dropBrute