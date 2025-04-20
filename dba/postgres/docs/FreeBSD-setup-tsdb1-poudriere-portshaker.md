# SolarNetwork FreeBSD DB server package build environment

The packages for the FreeBSD based "SolarDB" servers are currently based on FreeBSD 12.3
and Postgres 12. In order to continue supporting this environment after FreeBSD has moved
on to newer releases, we set up Portshaker for use with Poudriere to build the packages
we need.

## Portshaker setup

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
tsdb1_merge_from="freebsd-12 sn-custom"
```

> **Note** the referenced `freebsd-12 sn-custom` trees, which are configured below.

## FreeBSD 12 tree

Need to use a snapshot of the ports tree from the time of FreeBSD 12.
Decided that the `2024Q1` branch works for this purpose.

Configured `/usr/local/etc/portshaker.d/freebsd-12` with:

```sh
#!/bin/sh
. /usr/local/share/portshaker/portshaker.subr
if [ "$1" != '--' ]; then
  err 1 "Extra arguments"
fi
shift
method="git"
git_clone_uri="https://github.com/freebsd/freebsd-ports.git"
git_branch=2024Q1
run_portshaker_command $*
```

## SN Custom tree

Need to merge in the `SolarNetwork/freebsd-custom-ports` tree to pull in
the specific version of Timescale and the `aggs_for_vecs` extension.

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

## Portshaker update

```sh
sudo portshaker -U
sudo portshaker -M
```
