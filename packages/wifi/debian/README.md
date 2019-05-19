# WiFi Debian package

This directory contains packaging scripts used to create a WiFi service `sn-wifi.deb`.

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

[fpm]: https://github.com/jordansissel/fpm
[dropBrute]: https://github.com/robzr/dropBrute