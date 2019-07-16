# libmodbus for SolarNode

## Building

Make sure `autoconf`, `automake`, and `libtool` are installed, e.g.

```sh
apt-get install autoconf automake libtool
```

Clone the git repository, check out the release tag, and build like this:

```sh
$ git clone https://github.com/stephane/libmodbus.git
$ cd libmodbus
$ git checkout v3.1.4
$ ./autogen.sh
$ ./configure --prefix="$PWD/local/usr"
$ make && make install
$ cd ..
$ make
```
