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
	-n sn-rxtx -v 1.0.0-1 \
	-a all \
	--description 'SolarNode RXTX support' \
	--license 'Apache License 2.0' \
	-f \
	-d 'librxtx-java (>= 2.2pre2)' \
	--after-install sn-rxtx.postinst \
	--after-remove sn-rxtx.postrm \
	usr
```

