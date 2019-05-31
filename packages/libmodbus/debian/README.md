# libmodbus for SolarNode

## Building

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
