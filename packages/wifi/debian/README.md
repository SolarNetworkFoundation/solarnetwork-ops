# WiFi Debian package

This directory contains packaging scripts used to create the `sn-wifi` Debian package, which
provides a way to manage a WiFi network connection.

## WiFi configuration

This package will ask for the following WiFi settings when configured:

 1. Country code, e.g. `NZ`
 2. WiFi network name (SSID)
 3. WiFi network password
 
You can run 

```
$ dpkg-reconfigure sn-wifi
```

to manage these settings. The configuration for the connection is located in
`/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`. A `sn-wifi-conf@wlan0.service` uses that
configuration to connect to the WiFi network using the first-available WiFi device, `wlan0`.

## Startup WiFi bootstrap

This package provides a `sn-wifi-bootconf.service` that will look for a `/boot/wpa_supplicant.conf`
file when the system boots. If found, it will move that file as-is to
`/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`. In the case of a Raspberry Pi, the `/boot`
partition of its OS SD card can be easily mounted on most computers, where you can easily create the
file. Then, when the Pi boots up the WiFi credentials will be applied and the Pi will be able to
connect to the network.

# Packaging

This section describes how the `sn-wifi` package is created.

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
[dropBrute]: https://github.com/robzr/dropBrute