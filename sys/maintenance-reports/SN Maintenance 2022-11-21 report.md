# SN DB Maintenance 2022-11-21

This maintenance is to add additional storage to the SN Postgres cluster, specifically the
`dat` storage pool.

# SolarDB A (replica)

The zpool information before starting:

```
$ zpool list

NAME   SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP  HEALTH  ALTROOT
dat   99.5G  85.5G  14.0G        -         -    78%    85%  1.00x  ONLINE  -
idx   99.5G  36.5G  63.0G        -         -    59%    36%  1.00x  ONLINE  -
wal   49.5G   278M  49.2G        -         -    36%     0%  1.00x  ONLINE  -
```

## Attach new volume

A new 100 GiB gp3 volume `vol-00404bdeef0ed6da0` named `SolarDB_A dat2` has been created and
attached to the SolarDB A instance. The device name is `/dev/sdi`. To view the new device and
identify it:

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
    
$ nvmecontrol identify nvme4 |head -13

Controller Capabilities/Features
================================
Vendor ID:                   1d0f
Subsystem Vendor ID:         1d0f
Serial Number:               vol00404bdeef0ed6da0
Model Number:                Amazon Elastic Block Store
Firmware Version:            1.0
Recommended Arb Burst:       32
IEEE OUI Identifier:         dc 02 a0
Multi-Path I/O Capabilities: Not Supported
Max Data Transfer Size:      262144 bytes
Controller ID:               0x0000
Version:                     1.0.0
```

This confirms that `nvme4` is the new device, as the **Serial Number** matches the EBS volume
identifier, `00404bdeef0ed6da0`.

## Add new volume to `dat` zpool

The name of the NVMe device will be `/dev/diskid/DISK-X` where `X` is the volume identifier from
above, i.e. `/dev/diskid/DISK-vol00404bdeef0ed6da0`. To preview adding this to the pool:

```
$ zpool add -n dat /dev/diskid/DISK-vol00404bdeef0ed6da0

would update 'dat' to the following configuration:
        dat
          diskid/DISK-vol0e66e82462fb547d3
          diskid/DISK-vol00404bdeef0ed6da0
```

To execute, **repeat the `zpool add` command without the `-n` argument**.

## Review updated state

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP  HEALTH  ALTROOT
dat                                  199G  85.5G   113G        -         -    39%    42%  1.00x  ONLINE  -
  diskid/DISK-vol0e66e82462fb547d3  99.5G  85.5G  14.0G        -         -    78%  85.9%
  diskid/DISK-vol00404bdeef0ed6da0  99.5G  3.29M  99.5G        -         -     0%  0.00%
idx                                 99.5G  36.5G  63.0G        -         -    59%    36%  1.00x  ONLINE  -
  diskid/DISK-vol049efbf7b0e47b440  99.5G  36.5G  63.0G        -         -    59%  36.7%
wal                                 49.5G   218M  49.3G        -         -    36%     0%  1.00x  ONLINE  -
  diskid/DISK-vol02e9ec7f6cf8ba9a8  49.5G   218M  49.3G        -         -    36%  0.43%
```

# SolarDB 0 (main)

Repeat the same steps as above. Information before starting:

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP  HEALTH  ALTROOT
dat                                 99.5G  73.6G  25.9G        -         -    78%    73%  1.00x  ONLINE  -
  diskid/DISK-vol05a875893ee5351dd  99.5G  73.6G  25.9G        -         -    78%  73.9%
idx                                 99.5G  30.2G  69.3G        -         -    60%    30%  1.00x  ONLINE  -
  diskid/DISK-vol0a03b9af141825b01  99.5G  30.2G  69.3G        -         -    60%  30.4%
wal                                 49.5G  96.6M  49.4G        -         -    30%     0%  1.00x  ONLINE  -
  diskid/DISK-vol0744c9816478f9253  49.5G  96.6M  49.4G        -         -    30%  0.19%
```

## Attach new volume

A new 100 GiB gp3 volume `vol-02a30be6baa06ff7a` named `SolarDB_0 dat2` has been created and
attached to the SolarDB 0 instance. The device name is `/dev/sdi`. To view the new device and
identify it:

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
    
$ nvmecontrol identify nvme4 |head -13

Controller Capabilities/Features
================================
Vendor ID:                   1d0f
Subsystem Vendor ID:         1d0f
Serial Number:               vol02a30be6baa06ff7a
Model Number:                Amazon Elastic Block Store
Firmware Version:            1.0
Recommended Arb Burst:       32
IEEE OUI Identifier:         dc 02 a0
Multi-Path I/O Capabilities: Not Supported
Max Data Transfer Size:      262144 bytes
Controller ID:               0x0000
Version:                     1.0.0
```

This confirms that `nvme4` is the new device, as the **Serial Number** matches the EBS volume
identifier, `02a30be6baa06ff7a`.

## Add new volume to `dat` zpool

The name of the NVMe device will be `/dev/diskid/DISK-X` where `X` is the volume identifier from
above, i.e. `/dev/diskid/DISK-vol02a30be6baa06ff7a`. To preview adding this to the pool:

```
$ zpool add -n dat /dev/diskid/DISK-vol02a30be6baa06ff7a

would update 'dat' to the following configuration:
        dat
          diskid/DISK-vol05a875893ee5351dd
          diskid/DISK-vol02a30be6baa06ff7a
```

To execute, **repeat the `zpool add` command without the `-n` argument**.

## Review updated state

```
$ zpool list -v

NAME                                 SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP  HEALTH  ALTROOT
dat                                  199G  73.6G   125G        -         -    39%    36%  1.00x  ONLINE  -
  diskid/DISK-vol05a875893ee5351dd  99.5G  73.6G  25.9G        -         -    78%  73.9%
  diskid/DISK-vol02a30be6baa06ff7a  99.5G  4.39M  99.5G        -         -     0%  0.00%
idx                                 99.5G  30.2G  69.3G        -         -    60%    30%  1.00x  ONLINE  -
  diskid/DISK-vol0a03b9af141825b01  99.5G  30.2G  69.3G        -         -    60%  30.4%
wal                                 49.5G  92.3M  49.4G        -         -    30%     0%  1.00x  ONLINE  -
  diskid/DISK-vol0744c9816478f9253  49.5G  92.3M  49.4G        -         -    30%  0.18%
```

