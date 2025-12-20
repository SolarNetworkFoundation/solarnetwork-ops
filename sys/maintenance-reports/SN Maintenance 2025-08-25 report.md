# SN DB Maintenance 2024-11-25

This maintenance is to add additional storage to the SN Postgres cluster, specifically the
`idx` storage pool.

# SolarDB A (replica)

The zpool information before starting:

```
$ zpool list

NAME   SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat    398G   198G   200G        -         -    61%    49%  1.00x    ONLINE  -
idx   99.5G  79.4G  20.1G        -         -    83%    79%  1.00x    ONLINE  -
wal   49.5G   359M  49.1G        -         -    28%     0%  1.00x    ONLINE  -
wrm    248G  33.3G   215G        -         -     1%    13%  1.00x    ONLINE  -
```

## Attach new volume

A new 100 GiB gp3 volume `vol-0b7bc50a32358f89c` named `SolarDB_A idx2` has been created.

Monitored `/var/log/messages` and then attached the volume to the SolarDB A instance as device
name is `/dev/sdl`. The log showed:

```
Aug 24 22:37:32 solardb-a kernel: nvme7: <Generic NVMe Device> irq 10 at device 25.0 on pci0
Aug 24 22:37:32 solardb-a kernel: nda7 at nvme7 bus 0 scbus7 target 0 lun 1
Aug 24 22:37:32 solardb-a kernel: nda7: <Amazon Elastic Block Store 1.0 vol0b7bc50a32358f89c>
Aug 24 22:37:32 solardb-a kernel: nda7: Serial Number vol0b7bc50a32358f89c
Aug 24 22:37:32 solardb-a kernel: nda7: nvme version 1.0
Aug 24 22:37:32 solardb-a kernel: nda7: 102400MB (209715200 512 byte sectors)
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
    
$ nvmecontrol identify nvme7 |head -13

Controller Capabilities/Features
================================
Vendor ID:                   1d0f
Subsystem Vendor ID:         1d0f
Serial Number:               vol0b7bc50a32358f89c
Model Number:                Amazon Elastic Block Store
Firmware Version:            1.0
Recommended Arb Burst:       32
IEEE OUI Identifier:         a0 02 dc
Multi-Path I/O Capabilities: Not Supported
Max Data Transfer Size:      262144 bytes
Sanitize Crypto Erase:       Not Supported
Sanitize Block Erase:        Not Supported
```

This confirms that `nvme7` is the new device, as the **Serial Number** matches the EBS volume
identifier, `0b7bc50a32358f89c`.

## Add new volume to `idx` zpool

The name of the NVMe device will be `/dev/diskid/DISK-X` where `X` is the volume identifier from
above, i.e. `/dev/diskid/DISK-vol0b7bc50a32358f89c`. To preview adding this to the pool:

```
$ zpool add -n idx /dev/diskid/DISK-vol0b7bc50a32358f89c

would update 'idx' to the following configuration:

        idx
          nda4
          diskid/DISK-vol0b7bc50a32358f89c
```

To execute, **repeat the `zpool add` command without the `-n` argument**.

## Review updated state

```
$ zpool list -v

NAMENAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat                                  398G   198G   200G        -         -    61%    49%  1.00x    ONLINE  -
  diskid/DISK-vol0e66e82462fb547d3   100G  45.0G  54.5G        -         -    59%  45.2%      -    ONLINE
  diskid/DISK-vol00404bdeef0ed6da0   100G  59.3G  40.2G        -         -    68%  59.6%      -    ONLINE
  diskid/DISK-vol03c88fd4c622fd1c7   200G  93.9G   105G        -         -    59%  47.2%      -    ONLINE
idx                                  199G  79.4G   120G        -         -    41%    39%  1.00x    ONLINE  -
  nda4                               100G  79.4G  20.1G        -         -    83%  79.8%      -    ONLINE
  diskid/DISK-vol0b7bc50a32358f89c   100G      0  99.5G        -         -     0%  0.00%      -    ONLINE
wal                                 49.5G   423M  49.1G        -         -    28%     0%  1.00x    ONLINE  -
  diskid/DISK-vol02e9ec7f6cf8ba9a8    50G   423M  49.1G        -         -    28%  0.83%      -    ONLINE
wrm                                  248G  33.3G   215G        -         -     1%    13%  1.00x    ONLINE  -
  diskid/DISK-vol087510e9581e77d46   250G  33.3G   215G        -         -     1%  13.4%      -    ONLINE
```

# SolarDB 0 (main)

Repeat the same steps as above. Information before starting:

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat                                  398G   186G   212G        -         -    64%    46%  1.00x    ONLINE  -
  diskid/DISK-vol05a875893ee5351dd   100G  77.5G  22.0G        -         -    79%  77.9%      -    ONLINE
  diskid/DISK-vol020b1ba008d5b21c2   100G  68.1G  31.4G        -         -    76%  68.5%      -    ONLINE
  diskid/DISK-vol020b1ba008d5b21c2   200G  40.3G   159G        -         -    52%  20.3%      -    ONLINE
idx                                 99.5G  58.3G  41.2G        -         -    84%    58%  1.00x    ONLINE  -
  nda4                               100G  58.3G  41.2G        -         -    84%  58.6%      -    ONLINE
wal                                 49.5G  74.1M  49.4G        -         -    26%     0%  1.00x    ONLINE  -
  nda2                                50G  74.1M  49.4G        -         -    26%  0.14%      -    ONLINE
wrm                                  248G  33.3G   215G        -         -     0%    13%  1.00x    ONLINE  -
  diskid/DISK-vol0d9657c9b274608c6   250G  33.3G   215G        -         -     0%  13.4%      -    ONLINE
```

## Attach new volume

A new 200 GiB gp3 volume `vol-020b1ba008d5b21c2` named `SolarDB_0 idx2` has been created.

Monitored `/var/log/messages` and then attached the volume to the SolarDB A instance as device
name is `/dev/sdl`. The log showed:


```
Aug 24 22:43:45 solardb-0 kernel: nvme7: <Generic NVMe Device> irq 10 at device 25.0 on pci0
Aug 24 22:43:45 solardb-0 kernel: nda7 at nvme7 bus 0 scbus7 target 0 lun 1
Aug 24 22:43:45 solardb-0 kernel: nda7: <Amazon Elastic Block Store 1.0 vol020b1ba008d5b21c2>
Aug 24 22:43:45 solardb-0 kernel: nda7: Serial Number vol020b1ba008d5b21c2
Aug 24 22:43:45 solardb-0 kernel: nda7: nvme version 1.0
Aug 24 22:43:45 solardb-0 kernel: nda7: 102400MB (209715200 512 byte sectors)
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
    
$ nvmecontrol identify nvme7 |head -13

Controller Capabilities/Features
================================
Vendor ID:                   1d0f
Subsystem Vendor ID:         1d0f
Serial Number:               vol020b1ba008d5b21c2
Model Number:                Amazon Elastic Block Store
Firmware Version:            1.0
Recommended Arb Burst:       32
IEEE OUI Identifier:         a0 02 dc
Multi-Path I/O Capabilities: Not Supported
Max Data Transfer Size:      262144 bytes
Sanitize Crypto Erase:       Not Supported
Sanitize Block Erase:        Not Supported
```

This confirms that `nvme7` is the new device, as the **Serial Number** matches the EBS volume
identifier, `020b1ba008d5b21c2`.

## Add new volume to `idx` zpool

The name of the NVMe device will be `/dev/diskid/DISK-X` where `X` is the volume identifier from
above, i.e. `/dev/diskid/DISK-vol020b1ba008d5b21c2`. To preview adding this to the pool:

```
$ zpool add -n idx /dev/diskid/DISK-vol020b1ba008d5b21c2

would update 'idx' to the following configuration:

        idx
          nda4
          diskid/DISK-vol020b1ba008d5b21c2
```

To execute, **repeat the `zpool add` command without the `-n` argument**.

### ashift error

The previous command did not work, reporting this error:

```
cannot add to 'idx': adding devices with different physical sector sizes is not allowed
```

Adding `--allow-ashift-mismatch` allowed the operation to succeed, e.g.

```sh
zpool add --allow-ashift-mismatch idx /dev/diskid/DISK-vol020b1ba008d5b21c2
```

## Review updated state

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat                                  398G   186G   212G        -         -    64%    46%  1.00x    ONLINE  -
  diskid/DISK-vol05a875893ee5351dd   100G  77.5G  22.0G        -         -    79%  77.9%      -    ONLINE
  diskid/DISK-vol02a30be6baa06ff7a   100G  68.1G  31.4G        -         -    76%  68.5%      -    ONLINE
  diskid/DISK-vol0e62feb5f32cc7c91   200G  40.3G   159G        -         -    52%  20.3%      -    ONLINE
idx                                  199G  58.3G   141G        -         -    42%    29%  1.00x    ONLINE  -
  nda4                               100G  58.3G  41.2G        -         -    84%  58.6%      -    ONLINE
  diskid/DISK-vol020b1ba008d5b21c2   100G  7.95M  99.5G        -         -     0%  0.00%      -    ONLINE
wal                                 49.5G   114M  49.4G        -         -    26%     0%  1.00x    ONLINE  -
  nda2                                50G   114M  49.4G        -         -    26%  0.22%      -    ONLINE
wrm                                  248G  33.3G   215G        -         -     0%    13%  1.00x    ONLINE  -
  diskid/DISK-vol0d9657c9b274608c6   250G  33.3G   215G        -         -     0%  13.4%      -    ONLINE
```

