# OpenDNP3 Debian packaging

This directory contains packaging scripts used to create the OpenDNP3 `.deb`.
See [the wiki][wiki-docs] for more info on building OpenDNP3.

## Building

Follow the [wiki guide][wiki-docs] on building OpenDNP3. You can check out the git 
repository directly into this directory, or create a symlink to it. Either way, you
should have a `dnp3` directory (or link to one) in this directory. The `Makefile`
used below defaults to a `cmake` build directory `dnp3/build/native/local`. You
can change that by passing a `DNP3_INSTALL_DIR` variable to `make`, as shown here:


```sh
make DNP3_INSTALL_DIR=dnp3/build/native/local
```

If building with OpenSSL 1.1, call like this:

```sh
$ make SSL_DEP=libssl1.1 SSL_DEV_DEP=libssl-dev
```

To specify a specific distribution target, add the `DIST` parameter, like

```sh
$ make DIST=buster SSL_DEP=libssl1.1 SSL_DEV_DEP=libssl-dev
```

[wiki-docs]: https://github.com/SolarNetworkFoundation/solarnetwork-ops/wiki/OpenDNP3-Debian-Packaging
