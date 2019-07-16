# yasdi for SolarNode

## Building

Unarchive the `yasdi` source into a `yasdi` directory. Then,

```sh
$ cd yasdi/projects/generic-cmake
$ mkdir -p build/native
$ cd build/native
$ cmake ../.. -DCMAKE_INSTALL_PREFIX:PATH=/usr
$ make && make DESTDIR=$PWD/local install

$ cd ../../../../..
$ make
```

To specify a specific distribution target, add the `DIST` parameter, like

```sh
$ make DIST=buster
```
