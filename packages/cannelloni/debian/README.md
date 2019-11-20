# cannelloni for SolarNode

## Building

Clone the git repository, check out the release tag, and build like this:

```sh
$ git clone https://github.com/mguentner/cannelloni.git
$ cd cannelloni

# switch to specific release, if needed:
# git checkout 20160414

$ mkdir -p build/native
$ cd build/native
$ cmake -DCMAKE_BUILD_TYPE=Release -DSCTP_SUPPORT=false -DCMAKE_INSTALL_PREFIX:PATH=/usr ../..
$ make && make install DESTDIR=$PWD/local
$ cd ../../..
$ make
```

To specify a specific distribution target, add the `DIST` parameter, like

```sh
$ make DIST=buster
```
