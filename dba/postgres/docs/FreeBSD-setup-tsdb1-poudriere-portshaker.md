Set up some ZFS datasets:

```
sudo zfs create -o mountpoint=/usr/local/poudriere/ports/tsdb1 zpoud/poudriere/ports/tsdb1
zfs create -o mountpoint=none zpoud/portshaker
zfs set compression=lz4 zpoud/portshaker
zfs create -o mountpoint=/var/cache/portshaker zpoud/portshaker/cache
```

Create self-managed ports tree for poudriere:
```
sudo poudriere ports -c -m null -M /usr/local/poudriere/ports/tsdb1 -p tsdb1
```

Configured `/usr/local/etc/portshaker.conf` with:

```
# vim:set syntax=sh:

#---[ Base directory for mirrored Ports Trees ]---
mirror_base_dir="/var/cache/portshaker"

#---[ Directories where to merge ports ]---
ports_trees="tsdb1"

tsdb1_ports_tree="/usr/local/poudriere/ports/tsdb1"
tsdb1_merge_from="freebsd sn-custom"
```

Configured `/usr/local/etc/portshaker.d/freebsd` with:

```sh
#!/bin/sh
. /usr/local/share/portshaker/portshaker.subr
if [ "$1" != '--' ]; then
  err 1 "Extra arguments"
fi
shift
method="portsnap"
run_portshaker_command $*
```

Configured `/usr/local/etc/portshaker.d/sn-custom` with:

```sh
#!/bin/sh
. /usr/local/share/portshaker/portshaker.subr
if [ "$1" != '--' ]; then
  err 1 "Extra arguments"
fi
shift
method="git"
git_clone_uri="https://github.com/SolarNetwork/freebsd-custom-ports.git"
git_branch=main
run_portshaker_command $*
```

Ran

```sh
sudo portshaker -U
sudo portshaker -M
```
