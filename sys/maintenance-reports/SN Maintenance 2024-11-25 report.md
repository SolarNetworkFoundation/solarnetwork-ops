# SN DB Maintenance 2024-11-25

This maintenance is to add additional storage to the SN Postgres cluster, specifically the
`dat` storage pool.

# SolarDB A (replica)

The zpool information before starting:

```
$ zpool list

NAME   SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP  HEALTH  ALTROOT
dat    199G   159G  39.6G        -         -    80%    80%  1.00x  ONLINE  -
idx   99.5G  64.5G  35.0G        -         -    77%    64%  1.00x  ONLINE  -
wal   49.5G   331M  49.2G        -         -    29%     0%  1.00x  ONLINE  -
```

## Attach new volume

A new 200 GiB gp3 volume `vol-03c88fd4c622fd1c7` named `SolarDB_A dat3` has been created.

Monitored `/var/log/messages` and then attached the volume to the SolarDB A instance as device
name is `/dev/sdj`. The log showed:

```
Nov 24 20:34:35 solardb-a kernel: nvme5: <Generic NVMe Device> irq 11 at device 27.0 on pci0
Nov 24 20:34:36 solardb-a kernel: nvd5: <Amazon Elastic Block Store> NVMe namespace
Nov 24 20:34:36 solardb-a kernel: nvd5: 204800MB (419430400 512 byte sectors)
```

To view the new device and review the identity:

```
$ devctl rescan pci0

$ nvmecontrol devlist

 nvme0: Amazon Elastic Block Store
    nvme0ns1 (10240MB)
 nvme1: Amazon Elastic Block Store
    nvme1ns1 (51200MB)
 nvme2: Amazon Elastic Block Store
    nvme2ns1 (102400MB)
 nvme3: Amazon Elastic Block Store
    nvme3ns1 (102400MB)
 nvme4: Amazon Elastic Block Store
    nvme4ns1 (102400MB)
 nvme5: Amazon Elastic Block Store
    nvme5ns1 (204800MB)
    
$ nvmecontrol identify nvme5 |head -13

Controller Capabilities/Features
================================
Vendor ID:                   1d0f
Subsystem Vendor ID:         1d0f
Serial Number:               vol03c88fd4c622fd1c7
Model Number:                Amazon Elastic Block Store
Firmware Version:            1.0
Recommended Arb Burst:       32
IEEE OUI Identifier:         dc 02 a0
Multi-Path I/O Capabilities: Not Supported
Max Data Transfer Size:      262144 bytes
Controller ID:               0x0000
Version:                     1.0.0
```

This confirms that `nvme5` is the new device, as the **Serial Number** matches the EBS volume
identifier, `03c88fd4c622fd1c7`.

## Add new volume to `dat` zpool

The name of the NVMe device will be `/dev/diskid/DISK-X` where `X` is the volume identifier from
above, i.e. `/dev/diskid/DISK-vol03c88fd4c622fd1c7`. To preview adding this to the pool:

```
$ zpool add -n dat /dev/diskid/DISK-vol03c88fd4c622fd1c7

would update 'dat' to the following configuration:
	dat
	  diskid/DISK-vol0e66e82462fb547d3
	  diskid/DISK-vol00404bdeef0ed6da0
	  diskid/DISK-vol03c88fd4c622fd1c7
```

To execute, **repeat the `zpool add` command without the `-n` argument**.

## Review updated state

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP  HEALTH  ALTROOT
dat                                  398G   159G   239G        -         -    40%    40%  1.00x  ONLINE  -
  diskid/DISK-vol0e66e82462fb547d3  99.5G  95.7G  3.79G        -         -    85%  96.2%
  diskid/DISK-vol00404bdeef0ed6da0  99.5G  63.7G  35.8G        -         -    75%  64.0%
  diskid/DISK-vol03c88fd4c622fd1c7   199G  1.70M   199G        -         -     0%  0.00%
idx                                 99.5G  64.5G  35.0G        -         -    77%    64%  1.00x  ONLINE  -
  diskid/DISK-vol049efbf7b0e47b440  99.5G  64.5G  35.0G        -         -    77%  64.8%
wal                                 49.5G   338M  49.2G        -         -    29%     0%  1.00x  ONLINE  -
  diskid/DISK-vol02e9ec7f6cf8ba9a8  49.5G   338M  49.2G        -         -    29%  0.66%
```

# SolarDB 0 (main)

Repeat the same steps as above. Information before starting:

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP  HEALTH  ALTROOT
dat                                  199G   145G  53.9G        -         -    78%    72%  1.00x  ONLINE  -
  diskid/DISK-vol05a875893ee5351dd  99.5G  87.3G  12.2G        -         -    83%  87.7%
  diskid/DISK-vol02a30be6baa06ff7a  99.5G  57.8G  41.7G        -         -    73%  58.1%
idx                                 99.5G  52.4G  47.1G        -         -    75%    52%  1.00x  ONLINE  -
  diskid/DISK-vol0a03b9af141825b01  99.5G  52.4G  47.1G        -         -    75%  52.6%
wal                                 49.5G   148M  49.4G        -         -    27%     0%  1.00x  ONLINE  -
  diskid/DISK-vol0744c9816478f9253  49.5G   148M  49.4G        -         -    27%  0.29%
```

## Attach new volume

A new 200 GiB gp3 volume `vol-02a30be6baa06ff7a` named `SolarDB_0 dat3` has been created.

Monitored `/var/log/messages` and then attached the volume to the SolarDB A instance as device
name is `/dev/sdj`. The log showed:


```
Nov 24 20:42:23 solardb-0 kernel: nvme5: <Generic NVMe Device> irq 11 at device 27.0 on pci0
Nov 24 20:42:24 solardb-0 kernel: nvd5: <Amazon Elastic Block Store> NVMe namespace
Nov 24 20:42:24 solardb-0 kernel: nvd5: 204800MB (419430400 512 byte sectors)
```

```
$ devctl rescan pci0

$ nvmecontrol devlist

 nvme0: Amazon Elastic Block Store
    nvme0ns1 (10240MB)
 nvme1: Amazon Elastic Block Store
    nvme1ns1 (51200MB)
 nvme2: Amazon Elastic Block Store
    nvme2ns1 (102400MB)
 nvme3: Amazon Elastic Block Store
    nvme3ns1 (102400MB)
 nvme4: Amazon Elastic Block Store
    nvme4ns1 (102400MB)
 nvme5: Amazon Elastic Block Store
    nvme5ns1 (204800MB)
    
$ nvmecontrol identify nvme5 |head -13

Controller Capabilities/Features
================================
Vendor ID:                   1d0f
Subsystem Vendor ID:         1d0f
Serial Number:               vol0e62feb5f32cc7c91
Model Number:                Amazon Elastic Block Store
Firmware Version:            1.0
Recommended Arb Burst:       32
IEEE OUI Identifier:         dc 02 a0
Multi-Path I/O Capabilities: Not Supported
Max Data Transfer Size:      262144 bytes
Controller ID:               0x0000
Version:                     1.0.0
```

This confirms that `nvme5` is the new device, as the **Serial Number** matches the EBS volume
identifier, `0e62feb5f32cc7c91`.

## Add new volume to `dat` zpool

The name of the NVMe device will be `/dev/diskid/DISK-X` where `X` is the volume identifier from
above, i.e. `/dev/diskid/DISK-vol0e62feb5f32cc7c91`. To preview adding this to the pool:

```
$ zpool add -n dat /dev/diskid/DISK-vol0e62feb5f32cc7c91

would update 'dat' to the following configuration:
	dat
	  diskid/DISK-vol05a875893ee5351dd
	  diskid/DISK-vol02a30be6baa06ff7a
	  diskid/DISK-vol0e62feb5f32cc7c91
```

To execute, **repeat the `zpool add` command without the `-n` argument**.

## Review updated state

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP  HEALTH  ALTROOT
dat                                  398G   145G   253G        -         -    39%    36%  1.00x  ONLINE  -
  diskid/DISK-vol05a875893ee5351dd  99.5G  87.3G  12.2G        -         -    83%  87.7%
  diskid/DISK-vol02a30be6baa06ff7a  99.5G  57.8G  41.7G        -         -    73%  58.1%
  diskid/DISK-vol0e62feb5f32cc7c91   199G  1.60M   199G        -         -     0%  0.00%
idx                                 99.5G  52.4G  47.1G        -         -    75%    52%  1.00x  ONLINE  -
  diskid/DISK-vol0a03b9af141825b01  99.5G  52.4G  47.1G        -         -    75%  52.6%
wal                                 49.5G   156M  49.3G        -         -    27%     0%  1.00x  ONLINE  -
  diskid/DISK-vol0744c9816478f9253  49.5G   156M  49.3G        -         -    27%  0.30%
```

