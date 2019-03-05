CREATE EXTENSION IF NOT EXISTS timescaledb WITH SCHEMA public;

-- HYPERTABLE solardatum.da_datum

ALTER TABLE solardatum.da_datum DROP CONSTRAINT da_datum_pkey;

CREATE UNIQUE INDEX da_datum_pkey
	ON solardatum.da_datum (node_id, ts, source_id)
	TABLESPACE solarindex;

SELECT public.create_hypertable('solardatum.da_datum'::regclass, 'ts'::name,
	chunk_time_interval => interval '6 months',
	create_default_indexes => FALSE);
	
-- HYPERTABLE solardatum.da_loc_datum

ALTER TABLE solardatum.da_loc_datum DROP CONSTRAINT da_loc_datum_pkey;

CREATE UNIQUE INDEX da_loc_datum_pkey
	ON solardatum.da_loc_datum (loc_id, ts, source_id)
	TABLESPACE solarindex;

SELECT public.create_hypertable('solardatum.da_loc_datum'::regclass, 'ts'::name,
	chunk_time_interval => interval '1 year',
	create_default_indexes => FALSE);

-- HYPERTABLE solaragg.agg_datum_hourly

ALTER TABLE solaragg.agg_datum_hourly DROP CONSTRAINT agg_datum_hourly_pkey;

CREATE UNIQUE INDEX agg_datum_hourly_pkey
	ON solaragg.agg_datum_hourly (node_id, ts_start, source_id)
	TABLESPACE solarindex;

SELECT public.create_hypertable('solaragg.agg_datum_hourly'::regclass, 'ts_start'::name,
	chunk_time_interval => interval '6 months',
	create_default_indexes => FALSE);

-- HYPERTABLE solaragg.agg_datum_daily

ALTER TABLE solaragg.agg_datum_daily DROP CONSTRAINT agg_datum_daily_pkey;

CREATE UNIQUE INDEX agg_datum_daily_pkey
	ON solaragg.agg_datum_daily (node_id, ts_start, source_id)
	TABLESPACE solarindex;

SELECT public.create_hypertable('solaragg.agg_datum_daily'::regclass, 'ts_start'::name,
	chunk_time_interval => interval '1 years',
	create_default_indexes => FALSE);

-- HYPERTABLE solaragg.agg_datum_monthly

ALTER TABLE solaragg.agg_datum_monthly DROP CONSTRAINT agg_datum_monthly_pkey;

CREATE UNIQUE INDEX agg_datum_monthly_pkey
	ON solaragg.agg_datum_monthly (node_id, ts_start, source_id)
	TABLESPACE solarindex;

SELECT public.create_hypertable('solaragg.agg_datum_monthly'::regclass, 'ts_start'::name,
	chunk_time_interval => interval '5 years',
	create_default_indexes => FALSE);

-- HYPERTABLE solaragg.agg_loc_datum_hourly

ALTER TABLE solaragg.agg_loc_datum_hourly DROP CONSTRAINT agg_loc_datum_hourly_pkey;

CREATE UNIQUE INDEX agg_loc_datum_hourly_pkey
	ON solaragg.agg_loc_datum_hourly (loc_id, ts_start, source_id)
	TABLESPACE solarindex;

SELECT public.create_hypertable('solaragg.agg_loc_datum_hourly'::regclass, 'ts_start'::name,
	chunk_time_interval => interval '1 year',
	create_default_indexes => FALSE);

-- HYPERTABLE solaragg.agg_loc_datum_daily

ALTER TABLE solaragg.agg_loc_datum_daily DROP CONSTRAINT agg_loc_datum_daily_pkey;

CREATE UNIQUE INDEX agg_loc_datum_daily_pkey
	ON solaragg.agg_loc_datum_daily (loc_id, ts_start, source_id)
	TABLESPACE solarindex;

SELECT public.create_hypertable('solaragg.agg_loc_datum_daily'::regclass, 'ts_start'::name,
	chunk_time_interval => interval '5 years',
	create_default_indexes => FALSE);

-- HYPERTABLE solaragg.agg_loc_datum_monthly

ALTER TABLE solaragg.agg_loc_datum_monthly DROP CONSTRAINT agg_loc_datum_monthly_pkey;

CREATE UNIQUE INDEX agg_loc_datum_monthly_pkey
	ON solaragg.agg_loc_datum_monthly (loc_id, ts_start, source_id)
	TABLESPACE solarindex;

SELECT public.create_hypertable('solaragg.agg_loc_datum_monthly'::regclass, 'ts_start'::name,
	chunk_time_interval => interval '10 years',
	create_default_indexes => FALSE);

-- HYPERTABLE solaragg.aud_datum_hourly

ALTER TABLE solaragg.aud_datum_hourly DROP CONSTRAINT aud_datum_hourly_pkey;

CREATE UNIQUE INDEX aud_datum_hourly_pkey
	ON solaragg.aud_datum_hourly (node_id, ts_start, source_id)
	TABLESPACE solarindex;

SELECT public.create_hypertable('solaragg.aud_datum_hourly'::regclass, 'ts_start'::name,
	chunk_time_interval => interval '6 months',
	create_default_indexes => FALSE);

-- HYPERTABLE solaragg.aud_datum_daily

ALTER TABLE solaragg.aud_datum_daily DROP CONSTRAINT aud_datum_daily_pkey;

CREATE UNIQUE INDEX aud_datum_daily_pkey
	ON solaragg.aud_datum_daily (node_id, ts_start, source_id)
	TABLESPACE solarindex;

SELECT public.create_hypertable('solaragg.aud_datum_daily'::regclass, 'ts_start'::name,
	chunk_time_interval => interval '1 years',
	create_default_indexes => FALSE);

-- HYPERTABLE solaragg.aud_datum_monthly

ALTER TABLE solaragg.aud_datum_monthly DROP CONSTRAINT aud_datum_monthly_pkey;

CREATE UNIQUE INDEX aud_datum_monthly_pkey
	ON solaragg.aud_datum_monthly (node_id, ts_start, source_id)
	TABLESPACE solarindex;

SELECT public.create_hypertable('solaragg.aud_datum_monthly'::regclass, 'ts_start'::name,
	chunk_time_interval => interval '5 years',
	create_default_indexes => FALSE);

-- HYPERTABLE solaragg.aud_loc_datum_hourly

ALTER TABLE solaragg.aud_loc_datum_hourly DROP CONSTRAINT aud_loc_datum_hourly_pkey;

CREATE UNIQUE INDEX aud_loc_datum_hourly_pkey
	ON solaragg.aud_loc_datum_hourly (loc_id, ts_start, source_id)
	TABLESPACE solarindex;

SELECT public.create_hypertable('solaragg.aud_loc_datum_hourly'::regclass, 'ts_start'::name,
	chunk_time_interval => interval '1 year',
	create_default_indexes => FALSE);

-- HYPERTABLE solaragg.aud_acc_datum_daily

ALTER TABLE solaragg.aud_acc_datum_daily DROP CONSTRAINT aud_acc_datum_daily_pkey;

CREATE UNIQUE INDEX aud_acc_datum_daily_pkey
	ON solaragg.aud_acc_datum_daily (node_id, ts_start, source_id)
	TABLESPACE solarindex;

SELECT public.create_hypertable('solaragg.aud_acc_datum_daily'::regclass, 'ts_start'::name,
	chunk_time_interval => interval '1 years',
	create_default_indexes => FALSE);
