# VerneMQ FreeBSD Port Setup Guide

```sh
# install build deps
pkg install git gmake erlang-runtime22 snappy

# clone repo
git clone https://github.com/vernemq/vernemq
cd vernemq
git checkout 1.12.1

# patch for FreeBSD support
# edit rebar.lock and change eleveldb git link to
# d9393e1dec448b415736cfffc21d6896da9b174e

# build
export PATH=$PATH:/usr/local/lib/erlang22/bin
gmake rel
```
