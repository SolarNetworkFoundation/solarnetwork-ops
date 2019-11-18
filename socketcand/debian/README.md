# socketcand for SolarNode

## Building

Make sure `autoconf`, `automake`, `libtool`, and `libconfig-dev` are installed, e.g.

```sh
apt-get install autoconf automake libtool libconfig-dev
```

You also need the kernel headers installed. For example on a Raspberry Pi:

```
apt-get intall raspbian-kernel-headers
```

Clone the git repository, check out the release tag, and build like this:

```sh
$ git clone git clone https://github.com/linux-can/socketcand.git
$ cd socketcand
$ ./autogen.sh
$ ./configure
$ make && make install DESTDIR=local init_script=no
$ cd ..
```

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
