# Compile TimescaleDB for Postgres.app on OS X

Requirements:

 * Postgres.app
 * cmake (`brew install cmake`)

Then checkout TimescaleDB source from git, e.g.

```shell
# clone source
git clone https://github.com/timescale/timescaledb.git

# checkout version tag
cd timescaledb
git checkout 2.5.1     # or some other release

# perform build
export PATH=/Applications/Postgres.app/Contents/Versions/12/bin:$PATH
OPENSSL_ROOT_DIR=/usr/local/opt/openssl ./bootstrap -DREGRESS_CHECKS=OFF
cd build && make
make install
```
