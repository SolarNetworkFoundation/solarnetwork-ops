# mbpoll for SolarNode

## Building

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
