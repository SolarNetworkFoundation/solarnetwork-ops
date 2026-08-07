# SN DB Maintenance 2026-08-08

This maintenance is to add additional storage to the SN Postgres cluster, specifically the
`dat` storage pool.

# SolarDB A (replica)

The zpool information before starting:

```
$ zpool list -v
NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat                                  398G   323G  75.4G        -         -    79%    81%  1.00x    ONLINE  -
  diskid/DISK-vol0e66e82462fb547d3   100G  87.7G  11.8G        -         -    83%  88.2%      -    ONLINE
  diskid/DISK-vol00404bdeef0ed6da0   100G  90.6G  8.93G        -         -    85%  91.0%      -    ONLINE
  diskid/DISK-vol03c88fd4c622fd1c7   200G   144G  54.7G        -         -    75%  72.5%      -    ONLINE
idx                                  199G   125G  74.0G        -         -    75%    62%  1.00x    ONLINE  -
  nda4                               100G  83.9G  15.6G        -         -    85%  84.3%      -    ONLINE
  diskid/DISK-vol0b7bc50a32358f89c   100G  41.1G  58.4G        -         -    65%  41.3%      -    ONLINE
wal                                 49.5G   692M  48.8G        -         -    29%     1%  1.00x    ONLINE  -
  diskid/DISK-vol02e9ec7f6cf8ba9a8    50G   692M  48.8G        -         -    29%  1.36%      -    ONLINE
wrm                                  248G  46.4G   202G        -         -     2%    18%  1.00x    ONLINE  -
  diskid/DISK-vol087510e9581e77d46   250G  46.4G   202G        -         -     2%  18.7%      -    ONLINE
```

## Attach new volume

A new 400 GiB gp3 volume `vol-0a863dc4ccb9a62df` named `SolarDB_A dat4` has been created.

Monitored `/var/log/messages` and then attached the volume to the SolarDB A instance as device
name is `/dev/sdm`. The log showed:

```
Aug  7 19:04:43 solardb-a kernel: nvme8: <Generic NVMe Device> irq 11 at device 24.0 on pci0
Aug  7 19:04:43 solardb-a kernel: nda8 at nvme8 bus 0 scbus8 target 0 lun 1
Aug  7 19:04:43 solardb-a kernel: nda8: <Amazon Elastic Block Store 1.0 vol0a863dc4ccb9a62df>
Aug  7 19:04:43 solardb-a kernel: nda8: Serial Number vol0a863dc4ccb9a62df
Aug  7 19:04:43 solardb-a kernel: nda8: nvme version 1.0
Aug  7 19:04:43 solardb-a kernel: nda8: 409600MB (838860800 512 byte sectors)
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
 nvme8: Amazon Elastic Block Store
    nvme8ns1 (409600MB)
    
$ nvmecontrol identify nvme8 |head -13

Controller Capabilities/Features
================================
Vendor ID:                   1d0f
Subsystem Vendor ID:         1d0f
Serial Number:               vol0a863dc4ccb9a62df
Model Number:                Amazon Elastic Block Store
Firmware Version:            1.0
Recommended Arb Burst:       32
IEEE OUI Identifier:         a0 02 dc
Multi-Path I/O Capabilities: Not Supported
Max Data Transfer Size:      262144 bytes
Sanitize Crypto Erase:       Not Supported
Sanitize Block Erase:        Not Supported
```

This confirms that `nvme8` is the new device, as the **Serial Number** matches the EBS volume
identifier, `0a863dc4ccb9a62df`.

## Add new volume to `dat` zpool

The name of the NVMe device will be `/dev/diskid/DISK-X` where `X` is the volume identifier from
above, i.e. `/dev/diskid/DISK-vol0a863dc4ccb9a62df`. To preview adding this to the pool:

```
$ zpool add -n dat /dev/diskid/DISK-vol0a863dc4ccb9a62df

would update 'dat' to the following configuration:

	dat
	  diskid/DISK-vol0e66e82462fb547d3
	  diskid/DISK-vol00404bdeef0ed6da0
	  diskid/DISK-vol03c88fd4c622fd1c7
	  diskid/DISK-vol0a863dc4ccb9a62df
```

To execute, **repeat the `zpool add` command without the `-n` argument**.

## Review updated state

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat                                  796G   323G   473G        -         -    39%    40%  1.00x    ONLINE  -
  diskid/DISK-vol0e66e82462fb547d3   100G  87.7G  11.8G        -         -    83%  88.2%      -    ONLINE
  diskid/DISK-vol00404bdeef0ed6da0   100G  90.6G  8.93G        -         -    85%  91.0%      -    ONLINE
  diskid/DISK-vol03c88fd4c622fd1c7   200G   144G  54.7G        -         -    75%  72.5%      -    ONLINE
  diskid/DISK-vol0a863dc4ccb9a62df   400G   392K   398G        -         -     0%  0.00%      -    ONLINE
idx                                  199G   125G  74.0G        -         -    75%    62%  1.00x    ONLINE  -
  nda4                               100G  83.9G  15.6G        -         -    85%  84.3%      -    ONLINE
  diskid/DISK-vol0b7bc50a32358f89c   100G  41.1G  58.4G        -         -    65%  41.3%      -    ONLINE
wal                                 49.5G   551M  49.0G        -         -    29%     1%  1.00x    ONLINE  -
  diskid/DISK-vol02e9ec7f6cf8ba9a8    50G   551M  49.0G        -         -    29%  1.08%      -    ONLINE
wrm                                  248G  46.4G   202G        -         -     2%    18%  1.00x    ONLINE  -
  diskid/DISK-vol087510e9581e77d46   250G  46.4G   202G        -         -     2%  18.7%      -    ONLINE
```

# SolarDB 0 (main)

Repeat the same steps as above. Information before starting:

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat                                  398G   318G  80.1G        -         -    83%    79%  1.00x    ONLINE  -
  diskid/DISK-vol05a875893ee5351dd   100G  94.8G  4.68G        -         -    93%  95.3%      -    ONLINE
  diskid/DISK-vol02a30be6baa06ff7a   100G  96.5G  3.02G        -         -    91%  97.0%      -    ONLINE
  diskid/DISK-vol0e62feb5f32cc7c91   200G   127G  72.4G        -         -    74%  63.6%      -    ONLINE
idx                                  199G   101G  97.6G        -         -    80%    50%  1.00x    ONLINE  -
  nda4                               100G  58.0G  41.5G        -         -    85%  58.3%      -    ONLINE
  diskid/DISK-vol020b1ba008d5b21c2   100G  43.3G  56.2G        -         -    75%  43.5%      -    ONLINE
wal                                 49.5G   206M  49.3G        -         -    26%     0%  1.00x    ONLINE  -
  nda2                                50G   206M  49.3G        -         -    26%  0.40%      -    ONLINE
wrm                                  248G  46.4G   202G        -         -     0%    18%  1.00x    ONLINE  -
  diskid/DISK-vol0d9657c9b274608c6   250G  46.4G   202G        -         -     0%  18.7%      -    ONLINE
```

## Attach new volume

A new 400 GiB gp3 volume `vol-0f1f87a9c2135b3cf` named `SolarDB_0 dat4` has been created.

Monitored `/var/log/messages` and then attached the volume to the SolarDB A instance as device
name is `/dev/sdm`. The log showed:


```
Aug  7 19:09:30 solardb-0 kernel: nvme8: <Generic NVMe Device> irq 11 at device 24.0 on pci0
Aug  7 19:09:30 solardb-0 kernel: nda8 at nvme8 bus 0 scbus8 target 0 lun 1
Aug  7 19:09:30 solardb-0 kernel: nda8: <Amazon Elastic Block Store 1.0 vol0f1f87a9c2135b3cf>
Aug  7 19:09:30 solardb-0 kernel: nda8: Serial Number vol0f1f87a9c2135b3cf
Aug  7 19:09:30 solardb-0 kernel: nda8: nvme version 1.0
Aug  7 19:09:30 solardb-0 kernel: nda8: 409600MB (838860800 512 byte sectors)
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
    
$ nvmecontrol identify nvme8 |head -13

Controller Capabilities/Features
================================
Vendor ID:                   1d0f
Subsystem Vendor ID:         1d0f
Serial Number:               vol0f1f87a9c2135b3cf
Model Number:                Amazon Elastic Block Store
Firmware Version:            1.0
Recommended Arb Burst:       32
IEEE OUI Identifier:         a0 02 dc
Multi-Path I/O Capabilities: Not Supported
Max Data Transfer Size:      262144 bytes
Sanitize Crypto Erase:       Not Supported
Sanitize Block Erase:        Not Supported
```

This confirms that `nvme8` is the new device, as the **Serial Number** matches the EBS volume
identifier, `0f1f87a9c2135b3cf`.

## Add new volume to `dat` zpool

The name of the NVMe device will be `/dev/diskid/DISK-X` where `X` is the volume identifier from
above, i.e. `/dev/diskid/DISK-vol0f1f87a9c2135b3cf`. To preview adding this to the pool:

```
$ zpool add -n dat /dev/diskid/DISK-vol0f1f87a9c2135b3cf

would update 'dat' to the following configuration:

	dat
	  diskid/DISK-vol05a875893ee5351dd
	  diskid/DISK-vol02a30be6baa06ff7a
	  diskid/DISK-vol0e62feb5f32cc7c91
	  diskid/DISK-vol0f1f87a9c2135b3cf
```

To execute, **repeat the `zpool add` command without the `-n` argument**.

## Review updated state

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
dat                                  796G   318G   478G        -         -    41%    39%  1.00x    ONLINE  -
  diskid/DISK-vol05a875893ee5351dd   100G  94.8G  4.69G        -         -    93%  95.3%      -    ONLINE
  diskid/DISK-vol02a30be6baa06ff7a   100G  96.5G  3.02G        -         -    91%  97.0%      -    ONLINE
  diskid/DISK-vol0e62feb5f32cc7c91   200G   127G  72.4G        -         -    74%  63.6%      -    ONLINE
  diskid/DISK-vol0f1f87a9c2135b3cf   400G  10.7M   398G        -         -     0%  0.00%      -    ONLINE
idx                                  199G   101G  97.6G        -         -    80%    50%  1.00x    ONLINE  -
  nda4                               100G  58.0G  41.5G        -         -    85%  58.3%      -    ONLINE
  diskid/DISK-vol020b1ba008d5b21c2   100G  43.3G  56.2G        -         -    75%  43.5%      -    ONLINE
wal                                 49.5G   231M  49.3G        -         -    26%     0%  1.00x    ONLINE  -
  nda2                                50G   231M  49.3G        -         -    26%  0.45%      -    ONLINE
wrm                                  248G  46.4G   202G        -         -     0%    18%  1.00x    ONLINE  -
  diskid/DISK-vol0d9657c9b274608c6   250G  46.4G   202G        -         -     0%  18.7%      -    ONLINE
```

