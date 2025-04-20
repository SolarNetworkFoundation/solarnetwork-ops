# Dev SNDB Setup Warm/Cold Storage tiers

The goal is to add two new zpools to hold "warm" and "cold" Postgres tablespaces. The "warm" pool
is for "old but not super old" data, designed to be hosted on low-cost storage like AWS `st1`. The
"cold" pool is for "super old data", designed to be hosted on lower-cost storage like AWS `sc1`.

This guide follows on from the [Dev SNDB Setup](Dev-Database-Mirror-Setup.md) and guide. This also
assumes the database has been [updated](Postgres-12-to-17-upgrade.md) to Postgres 17, on FreeBSD 14.


## Setup zfs

Create `wrm` and `cld`. Using the `dmesg` output as a guide to
the drive names:

```
da4: <VMware, VMware Virtual S 1.0> Fixed Direct Access SCSI-2 device
da4: 320.000MB/s transfers (160.000MHz, offset 127, 16bit)
da4: Command Queueing enabled
da4: 51200MB (104857600 512 byte sectors)
da4: quirks=0x140<RETRY_BUSY,STRICT_UNMAP>
da5 at mpt0 bus 0 scbus2 target 5 lun 0
da5: <VMware, VMware Virtual S 1.0> Fixed Direct Access SCSI-2 device
da5: 320.000MB/s transfers (160.000MHz, offset 127, 16bit)
da5: Command Queueing enabled
da5: 51200MB (104857600 512 byte sectors)
da5: quirks=0x140<RETRY_BUSY,STRICT_UNMAP>```

Here `da4` will be used for `dat-warm`, `da5` for `dat-cold`.

```sh
zpool create -O canmount=off -m none wrm /dev/da4
zpool create -O canmount=off -m none cld /dev/da5
```

Setup dataset properties and create Postgres 17 filesystems:

```sh 
#!/bin/sh -e

POOLS="wrm cld"

for p in $POOLS; do
   	zfs set atime=off $p
	zfs set exec=off $p
	zfs set setuid=off $p
	if [ "$p" = "wrm" ]; then
		zfs set recordsize=64k $p
		zfs set compression=lz4 $p
	else
		zfs set recordsize=128k $p
		zfs set compression=zstd-9 $p
	fi
	zfs create -o mountpoint=/sndb/$p $p/$p
	chown -R postgres:postgres /sndb/$p
	chmod 700 /sndb/$p
done
```

A this point, we have:

```sh
# zfs list
NAME       USED  AVAIL  REFER  MOUNTPOINT
cld        684K  48.0G    96K  none
cld/cld     96K  48.0G    96K  /sndb/cld
dat        181G  11.8G    96K  none
dat/dat    179G  11.8G   179G  /sndb/dat
dat/home  1.59G  11.8G  1.07G  /sndb/home
dat/log    312K  11.8G   176K  /sndb/log
idx       72.9G  23.5G    96K  none
idx/idx   72.9G  23.5G  72.7G  /sndb/idx
wal       20.2M  47.9G    96K  none
wal/wal   18.5M  47.9G  18.1M  /sndb/wal
wrm        708K  48.0G    96K  none
wrm/wrm     96K  48.0G    96K  /sndb/wrm

# zfs get compression,recordsize /sndb/wrm
NAME     PROPERTY     VALUE           SOURCE
wrm/wrm  compression  lz4             inherited from wrm
wrm/wrm  recordsize   64K             inherited from wrm

# zfs get compression,recordsize /sndb/cld
NAME     PROPERTY     VALUE           SOURCE
cld/cld  compression  zstd-9          inherited from cld
cld/cld  recordsize   128K            inherited from cld
```

## Setup Postgres tablespaces

Setup new tablespaces `solarwarm` and `solarcold`:

```sh
su -l postgres -c 'psql -xd solarnetwork -c "CREATE TABLESPACE solarwarm OWNER solarnet LOCATION '"'"'/sndb/wrm'"'"'"'
su -l postgres -c 'psql -xd solarnetwork -c "CREATE TABLESPACE solarcold OWNER solarnet LOCATION '"'"'/sndb/cld'"'"'"'
```

## Setup move_chunks procedure

```sql
CREATE OR REPLACE PROCEDURE solarcommon.move_chunks(job_id int, config jsonb)
LANGUAGE PLPGSQL
AS $$
DECLARE
   ht REGCLASS;
   lag interval;
   lag_max interval;
   destination_tablespace name;
   index_destination_tablespace name;
   reorder_index REGCLASS;
   max_move INTEGER;
   chunk REGCLASS;
   chunk_table_size BIGINT;
   chunk_index_size BIGINT;
   tmp_name name;
BEGIN
   SELECT jsonb_object_field_text(config, 'hypertable')::regclass INTO STRICT ht;
   SELECT jsonb_object_field_text(config, 'lag')::INTERVAL INTO STRICT lag;
   SELECT jsonb_object_field_text(config, 'lag_max')::INTERVAL INTO STRICT lag_max;
   SELECT jsonb_object_field_text(config, 'destination_tablespace') INTO STRICT destination_tablespace;
   SELECT jsonb_object_field_text(config, 'index_destination_tablespace') INTO STRICT index_destination_tablespace;
   SELECT jsonb_object_field_text(config, 'reorder_index')::regclass INTO STRICT reorder_index;
   SELECT COALESCE(jsonb_object_field_text(config, 'max_move')::INTEGER, 100) INTO STRICT max_move;

 IF ht IS NULL OR lag IS NULL OR destination_tablespace IS NULL THEN
   RAISE EXCEPTION 'Config must have hypertable, lag and destination_tablespace';
 END IF;

 IF index_destination_tablespace IS NULL THEN
   index_destination_tablespace := destination_tablespace;
 END IF;

 FOR chunk, chunk_table_size, chunk_index_size IN
    SELECT c.oid, s.table_bytes, s.index_bytes
    FROM pg_class AS c
    LEFT JOIN pg_tablespace AS t ON (c.reltablespace = t.oid)
    JOIN pg_namespace AS n ON (c.relnamespace = n.oid)
    JOIN (SELECT * FROM show_chunks(ht, older_than => lag, newer_than => lag_max) SHOW (oid)) AS chunks ON (chunks.oid::text = n.nspname || '.' || c.relname)
    JOIN chunks_detailed_size(ht) s ON s.chunk_schema || '.' || s.chunk_name = chunks.oid::text
    WHERE t.spcname != destination_tablespace OR t.spcname IS NULL
    LIMIT max_move
 LOOP
   RAISE NOTICE 'Moving chunk % data -> % (%), index -> % (%); ordered by %', chunk::TEXT,
       destination_tablespace::TEXT, pg_size_pretty(chunk_table_size),
       index_destination_tablespace::TEXT, pg_size_pretty(chunk_index_size),
       reorder_index::TEXT;
   PERFORM move_chunk(
       chunk => chunk,
       destination_tablespace => destination_tablespace,
       index_destination_tablespace => index_destination_tablespace,
       reorder_index => reorder_index
   );
 END LOOP;
END
$$;
```

## Create tier jobs

```sql
-- add daily job to move to cold storage; start tomorrow night at 10pm
SELECT add_job(
  'solarcommon.move_chunks',
  '1d',
  config => $${
    "hypertable": "solardatm.da_datm",
    "lag": "10 years",
    "destination_tablespace": "solarcold",
    "index_destination_tablespace": "solarcold",
    "reorder_index": "solardatm.da_datm_pkey",
    "max_move": 1
  }$$,
  initial_start => CURRENT_DATE AT TIME ZONE 'UTC' AT TIME ZONE 'UTC' + INTERVAL 'P1DT22H'
);

-- add daily job to move to warm storage; start tomorrow morning at 3am
SELECT add_job(
  'solarcommon.move_chunks',
  '1d',
  config => $${
  	"hypertable": "solardatm.da_datm",
  	"lag": "5 years",
  	"lag_max": "10 years",
  	"destination_tablespace": "solarwarm",
  	"index_destination_tablespace": "solarindex",
  	"reorder_index": "solardatm.da_datm_pkey",
  	"max_move": 1
  }$$,
  initial_start => CURRENT_DATE AT TIME ZONE 'UTC' AT TIME ZONE 'UTC' + INTERVAL 'P1DT3H' 
);
```

## Manually run jobs

```sh
su -l postgres -c 'psql -d solarnetwork -c "CALL run_job(1031)"'

su -l postgres -c 'psql -d solarnetwork -c "CALL run_job(1032)"'
```

## Before/after comparison

Before:

```
NAME   SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
cld   49.5G   704K  49.5G        -         -     0%     0%  1.00x    ONLINE  -
dat    199G   181G  18.0G        -         -     5%    90%  1.00x    ONLINE  -
idx   99.5G  72.9G  26.6G        -         -     1%    73%  1.00x    ONLINE  -
wal   49.5G  20.5M  49.5G        -         -     0%     0%  1.00x    ONLINE  -
wrm   49.5G   708K  49.5G        -         -     0%     0%  1.00x    ONLINE  -

# zfs get recordsize,compression,compressratio dat idx wrm cld
NAME  PROPERTY       VALUE           SOURCE
cld   recordsize     128K            local
cld   compression    zstd-9          local
cld   compressratio  1.00x           -
dat   recordsize     32K             local
dat   compression    lz4             local
dat   compressratio  2.62x           -
idx   recordsize     8K              local
idx   compression    lz4             local
idx   compressratio  1.98x           -
wrm   recordsize     64K             local
wrm   compression    lz4             local
wrm   compressratio  1.00x           -
```

After:

```
NAME   SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
cld   49.5G  4.04G  45.5G        -         -     0%     8%  1.00x    ONLINE  -
dat    199G   146G  52.6G        -         -     4%    73%  1.00x    ONLINE  -
idx   99.5G  57.6G  41.9G        -         -     1%    57%  1.00x    ONLINE  -
wal   49.5G  6.98G  42.5G        -         -     4%    14%  1.00x    ONLINE  -
wrm   49.5G  31.8G  17.7G        -         -     0%    64%  1.00x    ONLINE  -

# zfs get recordsize,compression,compressratio dat idx wrm cld
NAME  PROPERTY       VALUE           SOURCE
cld   recordsize     128K            local
cld   compression    zstd-9          local
cld   compressratio  5.76x           -
dat   recordsize     32K             local
dat   compression    lz4             local
dat   compressratio  2.58x           -
idx   recordsize     8K              local
idx   compression    lz4             local
idx   compressratio  1.98x           -
wrm   recordsize     64K             local
wrm   compression    lz4             local
wrm   compressratio  3.12x           -
```
