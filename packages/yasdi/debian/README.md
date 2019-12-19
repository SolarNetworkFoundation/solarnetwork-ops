# yasdi for SolarNode

## Building

Make sure `cmake`, `make`, and `pkg-config` are installed, e.g.

```sh
apt-get install cmake make
```

```sh
$ git clone https://github.com/SolarNetwork/yasdi.git
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
