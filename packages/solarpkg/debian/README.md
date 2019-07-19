# SolarNode solarpkg support Debian package

This directory contains packaging scripts used to create the `sn-solarpkg` Debian package, which
provides functionality required to support the _solarpkg_ package management API.

# Packaging

This section describes how the `sn-solarpkg` package is created.

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
