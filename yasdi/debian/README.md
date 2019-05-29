# yasdi for SolarNode

## Building

```sh
$ cd projects/generic-cmake
$ mkdir build
$ cd build
$ cmake .. -DCMAKE_INSTALL_PREFIX:PATH=/usr
$ make && make DESTDIR=$PWD/local install
```

Now copy the `Makefile` from this directory into the `local/` directory, and then:

```sh
$ cd local
$ make
```
