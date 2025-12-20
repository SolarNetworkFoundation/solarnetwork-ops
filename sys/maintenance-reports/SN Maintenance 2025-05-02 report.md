# SN DB Maintenance 2025-05-02

This maintenance is to add additional storage to the SN Postgres cluster, specifically a new
`wrm` storage pool for "warm" data that is old and can be offloaded to a slower storage tier.

# SolarDB A (replica)

The zpool information before starting:

```
$ zpool list

NAME   SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat    398G   197G   201G        -         -    47%    49%  1.00x    ONLINE  -
idx   99.5G  79.9G  19.6G        -         -    77%    80%  1.00x    ONLINE  -
wal   49.5G   400M  49.1G        -         -    27%     0%  1.00x    ONLINE  -
```

## Attach new volume

A new 250 GiB st1 volume `vol-087510e9581e77d46` named `SolarDB_A wrm1` has been created.

Monitored `/var/log/messages` and then attached the volume to the SolarDB A instance as device
name is `/dev/sdk`. The log showed:

```
May  1 22:12:30 solardb-a kernel: nvme6: <Generic NVMe Device> irq 10 at device 26.0 on pci0
May  1 22:12:30 solardb-a kernel: nda6: <Amazon Elastic Block Store 1.0 vol087510e9581e77d46>
May  1 22:12:30 solardb-a kernel: nda6: 256000MB (524288000 512 byte sectors)
```

To view the new device and review the identity:

```
$ devctl rescan pci0

$ nvmecontrol devlist

 nvme0: Amazon Elastic Block Store
    nvme0ns1 (10240MB)
 nvme1: Amazon Elastic Block Store
    nvme1ns1 (204800MB)
 nvme2: Amazon Elastic Block Store
    nvme2ns1 (51200MB)
 nvme3: Amazon Elastic Block Store
    nvme3ns1 (102400MB)
 nvme4: Amazon Elastic Block Store
    nvme4ns1 (102400MB)
 nvme5: Amazon Elastic Block Store
    nvme5ns1 (102400MB)
 nvme6: Amazon Elastic Block Store
    nvme6ns1 (256000MB)
    
$ nvmecontrol identify nvme6 |head -13

Controller Capabilities/Features
================================
Vendor ID:                   1d0f
Subsystem Vendor ID:         1d0f
Serial Number:               vol087510e9581e77d46
Model Number:                Amazon Elastic Block Store
Firmware Version:            1.0
Recommended Arb Burst:       32
IEEE OUI Identifier:         a0 02 dc
Multi-Path I/O Capabilities: Not Supported
Max Data Transfer Size:      262144 bytes
Sanitize Crypto Erase:       Not Supported
Sanitize Block Erase:        Not Supported
```

This confirms that `nvme6` is the new device, as the **Serial Number** matches the EBS volume
identifier, `087510e9581e77d46`.

## Create new `wrm` zpool

The name of the NVMe device will be `/dev/diskid/DISK-X` where `X` is the volume identifier from
above, i.e. `/dev/diskid/DISK-vol087510e9581e77d46`. To preview adding this to the pool:

```sh
# zpool create -n -O canmount=off -m none wrm /dev/diskid/DISK-vol087510e9581e77d46

would create 'wrm' with the following layout:

	wrm
	  diskid/DISK-vol087510e9581e77d46
```

To execute, **repeat the `zpool create` command without the `-n` argument**.

## Review updated state

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat                                  398G   197G   201G        -         -    47%    49%  1.00x    ONLINE  -
  diskid/DISK-vol0e66e82462fb547d3   100G  41.2G  58.3G        -         -    37%  41.4%      -    ONLINE
  diskid/DISK-vol00404bdeef0ed6da0   100G  62.5G  37.0G        -         -    63%  62.8%      -    ONLINE
  diskid/DISK-vol03c88fd4c622fd1c7   200G  93.4G   106G        -         -    44%  46.9%      -    ONLINE
idx                                 99.5G  79.9G  19.6G        -         -    77%    80%  1.00x    ONLINE  -
  nda4                               100G  79.9G  19.6G        -         -    77%  80.3%      -    ONLINE
wal                                 49.5G   428M  49.1G        -         -    27%     0%  1.00x    ONLINE  -
  nda2                                50G   428M  49.1G        -         -    27%  0.84%      -    ONLINE
wrm                                  248G   552K   248G        -         -     0%     0%  1.00x    ONLINE  -
  diskid/DISK-vol087510e9581e77d46   250G   552K   248G        -         -     0%  0.00%      -    ONLINE
```

## Add Munin monitoring for `wrm`

```sh
ln -sfh /usr/local/share/munin/plugins/zfs-filesystem-graph /usr/local/etc/munin/plugins/zfs_fs_wrm

service munin-node onerestart
```

# SolarDB 0 (main)

Repeat the same steps as above. Information before starting:

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat                                  398G   181G   217G        -         -    61%    45%  1.00x    ONLINE  -
  diskid/DISK-vol05a875893ee5351dd   100G  90.8G  8.75G        -         -    86%  91.2%      -    ONLINE
  diskid/DISK-vol02a30be6baa06ff7a   100G  67.7G  31.8G        -         -    75%  68.0%      -    ONLINE
  diskid/DISK-vol0e62feb5f32cc7c91   200G  22.8G   176G        -         -    42%  11.5%      -    ONLINE
idx                                 99.5G  61.5G  38.0G        -         -    79%    61%  1.00x    ONLINE  -
  nda4                               100G  61.5G  38.0G        -         -    79%  61.9%      -    ONLINE
wal                                 49.5G   180M  49.3G        -         -    25%     0%  1.00x    ONLINE  -
  nda2                                50G   180M  49.3G        -         -    25%  0.35%      -    ONLINE
```

## Attach new volume

A new 250 GiB st1 volume `vol-0d9657c9b274608c6` named `SolarDB_0 wrm1` has been created.

Monitored `/var/log/messages` and then attached the volume to the SolarDB A instance as device
name is `/dev/sdk`. The log showed:


```
May  1 22:09:09 solardb-0 kernel: nvme6: <Generic NVMe Device> irq 10 at device 26.0 on pci0
May  1 22:09:09 solardb-0 kernel: nda6: <Amazon Elastic Block Store 1.0 vol0d9657c9b274608c6>
May  1 22:09:09 solardb-0 kernel: nda6: 256000MB (524288000 512 byte sectors)
```

```
$ devctl rescan pci0

$ nvmecontrol devlist

 nvme0: Amazon Elastic Block Store
    nvme0ns1 (10240MB)
 nvme1: Amazon Elastic Block Store
    nvme1ns1 (204800MB)
 nvme2: Amazon Elastic Block Store
    nvme2ns1 (51200MB)
 nvme3: Amazon Elastic Block Store
    nvme3ns1 (102400MB)
 nvme4: Amazon Elastic Block Store
    nvme4ns1 (102400MB)
 nvme5: Amazon Elastic Block Store
    nvme5ns1 (102400MB)
 nvme6: Amazon Elastic Block Store
    nvme6ns1 (256000MB)
    
$ nvmecontrol identify nvme6 |head -13

Controller Capabilities/Features
================================
Vendor ID:                   1d0f
Subsystem Vendor ID:         1d0f
Serial Number:               vol0d9657c9b274608c6
Model Number:                Amazon Elastic Block Store
Firmware Version:            1.0
Recommended Arb Burst:       32
IEEE OUI Identifier:         a0 02 dc
Multi-Path I/O Capabilities: Not Supported
Max Data Transfer Size:      262144 bytes
Sanitize Crypto Erase:       Not Supported
Sanitize Block Erase:        Not Supported
```

This confirms that `nvme6` is the new device, as the **Serial Number** matches the EBS volume
identifier, `0d9657c9b274608c6`.

## Create new `wrm` zpool

The name of the NVMe device will be `/dev/diskid/DISK-X` where `X` is the volume identifier from
above, i.e. `/dev/diskid/DISK-vol0d9657c9b274608c6`. To preview adding this to the pool:

```sh
# zpool create -n -O canmount=off -m none wrm /dev/diskid/DISK-vol0d9657c9b274608c6

would create 'wrm' with the following layout:

	wrm
	  diskid/DISK-vol0d9657c9b274608c6
```

To execute, **repeat the `zpool create` command without the `-n` argument**.

## Review updated state

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat                                  398G   181G   217G        -         -    61%    45%  1.00x    ONLINE  -
  diskid/DISK-vol05a875893ee5351dd   100G  90.7G  8.75G        -         -    86%  91.2%      -    ONLINE
  diskid/DISK-vol02a30be6baa06ff7a   100G  67.7G  31.8G        -         -    75%  68.0%      -    ONLINE
  diskid/DISK-vol0e62feb5f32cc7c91   200G  22.8G   176G        -         -    42%  11.5%      -    ONLINE
idx                                 99.5G  61.5G  38.0G        -         -    79%    61%  1.00x    ONLINE  -
  nda4                               100G  61.5G  38.0G        -         -    79%  61.9%      -    ONLINE
wal                                 49.5G   195M  49.3G        -         -    25%     0%  1.00x    ONLINE  -
  nda2                                50G   195M  49.3G        -         -    25%  0.38%      -    ONLINE
wrm                                  248G   552K   248G        -         -     0%     0%  1.00x    ONLINE  -
  diskid/DISK-vol0d9657c9b274608c6   250G   552K   248G        -         -     0%  0.00%      -    ONLINE
```

## Add Munin monitoring for `wrm`

```sh
ln -sfh /usr/local/share/munin/plugins/zfs-filesystem-graph /usr/local/etc/munin/plugins/zfs_fs_wrm

service munin-node onerestart
```

# Setup for Postgres

Now configure a Postgres tablespace that resides on the new `wrm` storage pool.

## Configure filesystem for Postgres tablespace

Configure a `/sndb/wrm` filesystem for Postgres to use:

```sh
zfs set atime=off wrm
zfs set exec=off wrm
zfs set setuid=off wrm
zfs set recordsize=64k wrm
zfs set compression=lz4 wrm
zfs create -o mountpoint=/sndb/wrm wrm/wrm
chown postgres:postgres /sndb/wrm
chmod 755 /sndb/wrm
```

**Repeat on the replica server.**

A this point, we have:

```sh
# zfs list -o name,used,avail,refer,mountpoint,compression,recordsize
NAME       USED  AVAIL  REFER  MOUNTPOINT  COMPRESS        RECSIZE
dat        181G   204G    23K  none        lz4                 32K
dat/dat    180G   204G   180G  /sndb/dat   lz4                 32K
dat/home  1.01G   204G  1.01G  /sndb/home  lz4                 32K
dat/log   34.6M   204G  34.6M  /sndb/log   gzip               128K
idx       61.6G  34.8G    23K  none        lz4                  8K
idx/idx   61.4G  34.8G  61.4G  /sndb/idx   lz4                  8K
wal        144M  47.8G    23K  none        lz4                  8K
wal/wal    134M  47.8G   134M  /sndb/wal   lz4                  8K
wrm        696K   240G    96K  none        lz4                 64K
wrm/wrm     96K   240G    96K  /sndb/wrm   lz4                 64K
```

## Setup Postgres tablespace

Setup new tablespace `solarwarm`:

```sh
su -l postgres -c 'psql -xd solarnetwork -c "CREATE TABLESPACE solarwarm OWNER solarnet LOCATION '"'"'/sndb/wrm'"'"' WITH (seq_page_cost=1, random_page_cost=4, effective_io_concurrency=1, maintenance_io_concurrency=10)"'
```

# Setup move procedure

Executed the [OPS-38-solarwarm-tablespace.sql](../../dba/postgres/updates/timescaledb/OPS-38-solarwarm-tablespace.sql)
update. The created job ID was `1031`.

Then manually ran once to confirm:

```sh
su -l postgres -c 'psql -d solarnetwork -c "CALL run_job(1031)"'

NOTICE:  Moving chunk _timescaledb_internal._hyper_14_1952_chunk data -> solarwarm (86 MB), index -> solarwarm (31 MB); ordered by solardatm.da_datm_pkey
CALL
```

Afterwards the filesystems looked like this:

```
$ zfs list -o name,used,avail,refer,mountpoint,compression,recordsize,compressratio
NAME       USED  AVAIL  REFER  MOUNTPOINT  COMPRESS        RECSIZE  RATIO
dat        181G   204G    23K  none        lz4                 32K  2.98x
dat/dat    180G   204G   180G  /sndb/dat   lz4                 32K  2.99x
dat/home  1.01G   204G  1.01G  /sndb/home  lz4                 32K  1.48x
dat/log   34.7M   204G  34.7M  /sndb/log   gzip               128K  11.33x
idx       61.5G  34.9G    23K  none        lz4                  8K  2.59x
idx/idx   61.4G  34.9G  61.4G  /sndb/idx   lz4                  8K  2.59x
wal        333M  47.6G    23K  none        lz4                  8K  1.84x
wal/wal    323M  47.6G   323M  /sndb/wal   lz4                  8K  1.84x
wrm       37.3M   240G    96K  none        lz4                 64K  3.18x
wrm/wrm   36.7M   240G  36.7M  /sndb/wrm   lz4                 64K  3.19x
```
