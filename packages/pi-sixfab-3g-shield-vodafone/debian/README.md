# SolarNode Sixfab 3G Shield Debian package

This directory contains packaging scripts used to create the `sn-pi-sixfab-3g-shield-vodafone`
Debian package, which provides configuration and support for the Sixfab 3G Shield. The goal of this
package is to configure, start, and maintain a mobile network connection on the 3G shield's modem.

# Services

The `sn-sixfab-3g-pppd` service manages the `pppd` daemon, but is not installed. The
`sn-sixfab-3c-reconnect` service is managed by a timer, that runs the
`/usr/share/solarnode/bin/sixfab-3g-reconnect.sh` script to verify if the `1.1.1.1` DNS service can
be reached via `ping`. If not, the `sn-sixfab-3g-pppd` service is restarted.

# Packaging

This section describes how the `sn-sixfab-3g-shield` package is created.

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
