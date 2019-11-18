# SolarNode Raspberry Pi Seeed Studio CAN HAT Debian package

This directory contains packaging scripts used to create the `sn-pi-seeed-can-hat` Debian package,
which provides configuration and support for the Seeed Studio CAN HAT. The goal of this package is
to configure the CAN HAT for use by SolarNode on a Raspberry Pi.

The kernel modules included here are compiled from the Seeed Studio [pi-hats][pi-hats] project.

# Packaging

This section describes how the `sn-pi-seeed-can-hat` package is created.

## Packaging requirements

Packaging done via [fpm][fpm] and `make`. To install `fpm`:

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
[pi-hats]: https://github.com/Seeed-Studio/pi-hats