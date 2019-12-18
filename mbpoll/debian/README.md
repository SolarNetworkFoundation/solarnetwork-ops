# mbpoll for SolarNode

## Building

Make sure `cmake`, `make`, and `pkg-config` are installed, e.g.

```sh
apt-get install cmake make
```

Clone the git repository, check out the release tag, and build like this:

```sh
$ git clone https://github.com/epsilonrt/mbpoll
$ cd mbpoll
$ git checkout v1.4.11
$ mkdir -p build/native
$ cd build/native
$ cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr ../..
$ make && make install DESTDIR=$PWD/local
$ cd ../../..
$ make
```

To specify a specific distribution target, add the `DIST` parameter, like

```sh
$ make DIST=buster
```
