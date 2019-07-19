# SolarNode OS Stat support Debian package

This directory contains packaging scripts used to create the necessary configuration
to support the SolarNode [OS Statistics Datum Source][osstat] plugin.

## Packaging requirements

Packaging done via [fpm][fpm]. To install `fpm`:

```sh
$ sudo apt-get install ruby ruby-dev build-essential
$ sudo gem install --no-ri --no-rdoc fpm
```

## Create package

Use `fpm` to package the service via `make`. This package is architecture independent:

```sh
$ make
```

To specify a specific distribution target, add the `DIST` parameter, like

```sh
$ make DIST=buster
```

[fpm]: https://github.com/jordansissel/fpm
[osstat]: https://github.com/SolarNetwork/solarnetwork-node/tree/master/net.solarnetwork.node.datum.os.stat