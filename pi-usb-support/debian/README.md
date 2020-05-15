# SolarNode Raspberry Pi USB support Debian package

This package provides support for USB devices on Raspberry Pi devices.

# USB TTY physical port names

This package installs some udev rules that create consistently named symlinks to USB TTY (serial)
devices based on the physical USB ports on the Pi. This is to help with configuring services that
depend on serial devices being plugged into specific ports for deployment reasons.

Links are named `/dev/ttyUSB_X` where `X` is a number staring a `1`. See the following sections for
the specific hardware layouts and how they are mapped.

## Pi 3B and 3B+

Looking at the side of the Pi with the ethernet port (labeled `Eth`) to the left of the 4 USB ports
labeled as `ttyUSB_1` through `ttyUSB_4`:

```
        +-----+ +-----+
        |  1  | |  3  |
+-----+ +-----+ +-----+
| Eth | |  2  | |  4  |
+-----+ +-----+ +-----+
```

# Building

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
