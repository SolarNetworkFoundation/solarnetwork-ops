# SolarNode Raspberry Pi Seeed Studio CAN HAT Debian package

This directory contains packaging scripts used to create the `sn-pi-seeed-can-hat` Debian package,
which provides configuration and support for the Seeed Studio CAN HAT. The goal of this package is
to configure the CAN HAT for use by SolarNode on a Raspberry Pi.

The kernel modules included here are compiled from the Seeed Studio [pi-hats][pi-hats] project,
which are released under the MIT licence.

# Services

This package installs a `sn-pi-seeed-socketcan@.service` systemd service template for configuring
the CAN bus interface. Two instances of this template will be automatically started by the presence
of the `/dev/can0` and `/dev/can1` devices, which are both provided by the CAN HAT and made
available by this package. By default the interfaces are configured with the following settings,
which can be customised via systemd environment configurations.

| Environment | Default | Description |
|:------------|:--------|:------------|
| `SOCKETCAN_BAUD` | 1000000 | The bitrate to use. Defaults to 1MB. |
| `SOCKETCAN_RESTART_MS` | 1000 | Automatic restart delay time. If set to a non-zero value, a restart of the CAN controller will be triggered automatically in case of a bus-off condition after the specified delay time in milliseconds. |
| `SOCKETCAN_OPTS` | `berr-reporting on` | Additional CAN interface options. |

You can use systemd drop-in units to customise these settings. For example, to enable CAN FD on the
`can0` interface with an 8MB dynamic bitrate, create a
`/etc/systemd/system/sn-pi-seeed-socketcan@can0.service.d/fd.conf` file with the following content:

```
[Service]
Environment="SOCKETCAN_OPTS=berr-reporting on dbitrate 8000000 fd on"
```

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