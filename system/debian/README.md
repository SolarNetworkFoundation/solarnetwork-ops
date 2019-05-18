# SolarNode system support Debian package

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
	-n sn-system -v 1.0.0-1 \
	-a all \
	--description 'SolarNode system support' \
	--license 'Apache License 2.0' \
	-f \
	-d 'bash (>= 4.4)' \
	-d 'systemd (>= 230)' \
	--after-install sn-system.postinst \
	etc
```

