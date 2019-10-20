# SolarNode Motion Support Debian packaging

This directory contains packaging scripts used to create the `sn-motion` Debian package, which
provides support functionality for integrating SolarNode with `motion`.

# sn-motion-cleaner timer

This package installs a `sn-motion-cleaner` timer service that runs daily to clean out old media
files captured by `motion`. The `/etc/default/sn-motion` file contains the configurable setting
for how many days of media are retained.

# Packaging

This section describes how the `sn-motion` package is created.

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
