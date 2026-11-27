# SN DB Maintenance 2025-08-25

This maintenance is to add additional storage to the SN Postgres cluster, specifically the
`idx` storage pool.

# SolarDB A (replica)

The zpool information before starting:

```
$ zpool list

NAME   SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat    796G   367G   429G        -         -    53%    46%  1.00x    ONLINE  -
idx    199G   140G  59.3G        -         -    82%    70%  1.00x    ONLINE  -
wal   49.5G   728M  48.8G        -         -    29%     1%  1.00x    ONLINE  -
wrm    248G  48.5G   199G        -         -     2%    19%  1.00x    ONLINE  -
```

## Attach new volume

A new 100 GiB gp3 volume `vol-0fc4d0ebe99da9642` named `SolarDB_A idx3` has been created.

Monitored `/var/log/messages` and then attached the volume to the SolarDB A instance as device
name is `/dev/sdl`. The log showed:

```
Nov 22 22:31:53 solardb-a kernel: nvme9: <Generic NVMe Device> irq 11 at device 23.0 on pci0
Nov 22 22:31:53 solardb-a kernel: nda9 at nvme9 bus 0 scbus9 target 0 lun 1
Nov 22 22:31:53 solardb-a kernel: nda9: <Amazon Elastic Block Store 1.0 vol0fc4d0ebe99da9642>
Nov 22 22:31:53 solardb-a kernel: nda9: Serial Number vol0fc4d0ebe99da9642
Nov 22 22:31:53 solardb-a kernel: nda9: nvme version 1.0
Nov 22 22:31:53 solardb-a kernel: nda9: 204800MB (419430400 512 byte sectors)
```

To view the new device and review the identity:

```
$ devctl rescan pci0

root@solardb-a:~ # nvmecontrol devlist
 nvme0: Amazon Elastic Block Store
    nvme0ns1 (10240MB)
 nvme1: Amazon Elastic Block Store
    nvme1ns1 (204800MB)
 nvme2: Amazon Elastic Block Store
    nvme2ns1 (256000MB)
 nvme3: Amazon Elastic Block Store
    nvme3ns1 (51200MB)
 nvme4: Amazon Elastic Block Store
    nvme4ns1 (102400MB)
 nvme5: Amazon Elastic Block Store
    nvme5ns1 (102400MB)
 nvme6: Amazon Elastic Block Store
    nvme6ns1 (102400MB)
 nvme7: Amazon Elastic Block Store
    nvme7ns1 (102400MB)
 nvme8: Amazon Elastic Block Store
    nvme8ns1 (409600MB)
 nvme9: Amazon Elastic Block Store
    nvme9ns1 (204800MB)
    
$ nvmecontrol identify nvme9 |head -13

Controller Capabilities/Features
================================
Vendor ID:                   1d0f
Subsystem Vendor ID:         1d0f
Serial Number:               vol0fc4d0ebe99da9642
Model Number:                Amazon Elastic Block Store
Firmware Version:            1.0
Recommended Arb Burst:       32
IEEE OUI Identifier:         a0 02 dc
Multi-Path I/O Capabilities: Not Supported
Max Data Transfer Size:      262144 bytes
Sanitize Crypto Erase:       Not Supported
Sanitize Block Erase:        Not Supported
```

This confirms that `nvme9` is the new device, as the **Serial Number** matches the EBS volume
identifier, `0fc4d0ebe99da9642`.

## Add new volume to `idx` zpool

The name of the NVMe device will be `/dev/diskid/DISK-X` where `X` is the volume identifier from
above, i.e. `/dev/diskid/DISK-vol0fc4d0ebe99da9642`. To preview adding this to the pool:

```
$ zpool add -n idx /dev/diskid/DISK-vol0fc4d0ebe99da9642

would update 'idx' to the following configuration:

        idx
          nda4
          diskid/DISK-vol0b7bc50a32358f89c
          diskid/DISK-vol0fc4d0ebe99da9642
```

To execute, **repeat the `zpool add` command without the `-n` argument**.

## Review updated state

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat                                  796G   367G   429G        -         -    53%    46%  1.00x    ONLINE  -
  diskid/DISK-vol0e66e82462fb547d3   100G  79.4G  20.1G        -         -    80%  79.8%      -    ONLINE
  diskid/DISK-vol00404bdeef0ed6da0   100G  83.3G  16.2G        -         -    81%  83.7%      -    ONLINE
  diskid/DISK-vol03c88fd4c622fd1c7   200G   138G  60.8G        -         -    75%  69.4%      -    ONLINE
  diskid/DISK-vol0a863dc4ccb9a62df   400G  66.0G   332G        -         -    30%  16.6%      -    ONLINE
idx                                  398G   140G   258G        -         -    41%    35%  1.00x    ONLINE  -
  nda4                               100G  87.1G  12.4G        -         -    88%  87.6%      -    ONLINE
  diskid/DISK-vol0b7bc50a32358f89c   100G  52.6G  46.9G        -         -    76%  52.8%      -    ONLINE
  diskid/DISK-vol0fc4d0ebe99da9642   200G      0   199G        -         -     0%  0.00%      -    ONLINE
wal                                 49.5G   592M  48.9G        -         -    29%     1%  1.00x    ONLINE  -
  diskid/DISK-vol02e9ec7f6cf8ba9a8    50G   592M  48.9G        -         -    29%  1.16%      -    ONLINE
wrm                                  248G  48.5G   199G        -         -     2%    19%  1.00x    ONLINE  -
  diskid/DISK-vol087510e9581e77d46   250G  48.5G   199G        -         -     2%  19.6%      -    ONLINE
```

# SolarDB 0 (main)

Repeat the same steps as above. Information before starting:

```
# zpool list -v
NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat                                  796G   361G   435G        -         -    57%    45%  1.00x    ONLINE  -
  diskid/DISK-vol05a875893ee5351dd   100G  94.1G  5.45G        -         -    93%  94.5%      -    ONLINE
  diskid/DISK-vol02a30be6baa06ff7a   100G  94.8G  4.73G        -         -    91%  95.2%      -    ONLINE
  diskid/DISK-vol0e62feb5f32cc7c91   200G   121G  78.2G        -         -    75%  60.7%      -    ONLINE
  diskid/DISK-vol0f1f87a9c2135b3cf   400G  51.3G   347G        -         -    31%  12.9%      -    ONLINE
idx                                  199G   114G  84.9G        -         -    84%    57%  1.00x    ONLINE  -
  nda4                               100G  59.6G  39.9G        -         -    87%  59.9%      -    ONLINE
  diskid/DISK-vol020b1ba008d5b21c2   100G  54.5G  45.0G        -         -    81%  54.8%      -    ONLINE
wal                                 49.5G   243M  49.3G        -         -    26%     0%  1.00x    ONLINE  -
  nda2                                50G   243M  49.3G        -         -    26%  0.47%      -    ONLINE
wrm                                  248G  48.7G   199G        -         -     1%    19%  1.00x    ONLINE  -
  diskid/DISK-vol0d9657c9b274608c6   250G  48.7G   199G        -         -     1%  19.6%      -    ONLINE
```

## Attach new volume

A new 100 GiB gp3 volume `vol-05f456c23b4856360` named `SolarDB_0 idx3` has been created.

Monitored `/var/log/messages` and then attached the volume to the SolarDB A instance as device
name is `/dev/sdl`. The log showed:


```
Nov 22 22:36:21 solardb-0 kernel: nvme9: <Generic NVMe Device> irq 11 at device 23.0 on pci0
Nov 22 22:36:21 solardb-0 kernel: nda9 at nvme9 bus 0 scbus9 target 0 lun 1
Nov 22 22:36:21 solardb-0 kernel: nda9: <Amazon Elastic Block Store 1.0 vol05f456c23b4856360>
Nov 22 22:36:21 solardb-0 kernel: nda9: Serial Number vol05
Nov 22 22:36:21 solardb-0 kernel: f456c23b4856360
Nov 22 22:36:21 solardb-0 kernel: nda9: nvme version 1.0
Nov 22 22:36:21 solardb-0 kernel: nda9: 204800MB (419430400 512 byte sectors)
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
 nvme7: Amazon Elastic Block Store
    nvme7ns1 (102400MB)
 nvme8: Amazon Elastic Block Store
    nvme8ns1 (409600MB)
 nvme9: Amazon Elastic Block Store
    nvme9ns1 (204800MB)
    
$ nvmecontrol identify nvme9 |head -13

Controller Capabilities/Features
================================
Vendor ID:                   1d0f
Subsystem Vendor ID:         1d0f
Serial Number:               vol05f456c23b4856360
Model Number:                Amazon Elastic Block Store
Firmware Version:            1.0
Recommended Arb Burst:       32
IEEE OUI Identifier:         a0 02 dc
Multi-Path I/O Capabilities: Not Supported
Max Data Transfer Size:      262144 bytes
Sanitize Crypto Erase:       Not Supported
Sanitize Block Erase:        Not Supported
```

This confirms that `nvme9` is the new device, as the **Serial Number** matches the EBS volume
identifier, `05f456c23b4856360`.

## Add new volume to `idx` zpool

The name of the NVMe device will be `/dev/diskid/DISK-X` where `X` is the volume identifier from
above, i.e. `/dev/diskid/DISK-vol05f456c23b4856360`. To preview adding this to the pool:

```
$ zpool add -n idx /dev/diskid/DISK-vol05f456c23b4856360

would update 'idx' to the following configuration:

        idx
          nda4
          diskid/DISK-vol020b1ba008d5b21c2
          diskid/DISK-vol05f456c23b4856360
```

To execute, **repeat the `zpool add` command without the `-n` argument**.

## Review updated state

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat                                  796G   361G   435G        -         -    57%    45%  1.00x    ONLINE  -
  diskid/DISK-vol05a875893ee5351dd   100G  94.1G  5.43G        -         -    93%  94.5%      -    ONLINE
  diskid/DISK-vol02a30be6baa06ff7a   100G  94.8G  4.73G        -         -    91%  95.2%      -    ONLINE
  diskid/DISK-vol0e62feb5f32cc7c91   200G   121G  78.3G        -         -    75%  60.6%      -    ONLINE
  diskid/DISK-vol0f1f87a9c2135b3cf   400G  51.4G   347G        -         -    31%  12.9%      -    ONLINE
idx                                  398G   114G   284G        -         -    42%    28%  1.00x    ONLINE  -
  nda4                               100G  59.6G  39.9G        -         -    87%  59.9%      -    ONLINE
  diskid/DISK-vol020b1ba008d5b21c2   100G  54.5G  45.0G        -         -    81%  54.8%      -    ONLINE
  diskid/DISK-vol05f456c23b4856360   200G  1.68M   199G        -         -     0%  0.00%      -    ONLINE
wal                                 49.5G   278M  49.2G        -         -    26%     0%  1.00x    ONLINE  -
  nda2                                50G   278M  49.2G        -         -    26%  0.54%      -    ONLINE
wrm                                  248G  48.7G   199G        -         -     1%    19%  1.00x    ONLINE  -
  diskid/DISK-vol0d9657c9b274608c6   250G  48.7G   199G        -         -     1%  19.6%      -    ONLINE
```

