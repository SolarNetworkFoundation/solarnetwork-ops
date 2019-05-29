# libmodbus for SolarNode

## Building

```sh
$ ./autogen.sh
$ ./configure --prefix="$PWD/local/usr"
$ make && make install
```
Now copy the `Makefile` from this directory into `local/` and then:

```sh
$ cd local
$ make
```
