# mbpoll for SolarNode

## Building

```sh
$ mkdir build
$ cd build
$ cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr ..
```

Now copy the `Makefile` from this directory into the `local/` directory, and then:

```sh
$ cd local
$ make
```
