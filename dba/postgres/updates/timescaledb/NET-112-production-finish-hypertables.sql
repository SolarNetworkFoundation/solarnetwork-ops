\echo `date` Creating datum hypertable index...

CREATE UNIQUE INDEX da_datum_pkey
	ON solardatum.da_datum (node_id, ts, source_id)
	TABLESPACE solarindex;

\echo `date` Creating loc datum hypertable index...

CREATE UNIQUE INDEX da_loc_datum_pkey
	ON solardatum.da_loc_datum (loc_id, ts, source_id)
	TABLESPACE solarindex;

\echo `date` Creating agg datum hypertable indexes...

CREATE UNIQUE INDEX agg_datum_hourly_pkey
	ON solaragg.agg_datum_hourly (node_id, ts_start, source_id)
	TABLESPACE solarindex;
CREATE UNIQUE INDEX agg_datum_daily_pkey
	ON solaragg.agg_datum_daily (node_id, ts_start, source_id)
	TABLESPACE solarindex;
CREATE UNIQUE INDEX agg_datum_monthly_pkey
	ON solaragg.agg_datum_monthly (node_id, ts_start, source_id)
	TABLESPACE solarindex;

\echo `date` Creating agg loc datum hypertable indexes...

CREATE UNIQUE INDEX agg_loc_datum_hourly_pkey
	ON solaragg.agg_loc_datum_hourly (loc_id, ts_start, source_id)
	TABLESPACE solarindex;
CREATE UNIQUE INDEX agg_loc_datum_daily_pkey
	ON solaragg.agg_loc_datum_daily (loc_id, ts_start, source_id)
	TABLESPACE solarindex;
CREATE UNIQUE INDEX agg_loc_datum_monthly_pkey
	ON solaragg.agg_loc_datum_monthly (loc_id, ts_start, source_id)
	TABLESPACE solarindex;

\echo `date` Creating agg datum audit hypertable indexes...

CREATE UNIQUE INDEX aud_datum_hourly_pkey
	ON solaragg.aud_datum_hourly (node_id, ts_start, source_id)
	TABLESPACE solarindex;

CREATE UNIQUE INDEX aud_loc_datum_hourly_pkey
	ON solaragg.aud_loc_datum_hourly (loc_id, ts_start, source_id)
	TABLESPACE solarindex;

\echo `date` Running CLUSTER on datum hypertable...

CLUSTER solardatum.da_datum USING da_datum_pkey;

\echo `date` Running CLUSTER on loc_datum hypertable...

CLUSTER solardatum.da_loc_datum USING da_loc_datum_pkey;

\echo `date` Running ANALYZE on datum hypertable...

ANALYZE solardatum.da_datum;

\echo `date` Running ANALYZE on loc datum hypertable...

ANALYZE solardatum.da_loc_datum;

\echo `date` Running CLUSTER on agg datum hypertables...

CLUSTER solaragg.agg_datum_hourly USING agg_datum_hourly_pkey;
CLUSTER solaragg.agg_datum_daily USING agg_datum_daily_pkey;
CLUSTER solaragg.agg_datum_monthly USING agg_datum_monthly_pkey;

CLUSTER solaragg.aud_datum_hourly USING aud_datum_hourly_pkey;

\echo `date` Running CLUSTER on agg loc_datum hypertables...

CLUSTER solaragg.agg_loc_datum_hourly USING agg_loc_datum_hourly_pkey;
CLUSTER solaragg.agg_loc_datum_daily USING agg_loc_datum_daily_pkey;
CLUSTER solaragg.agg_loc_datum_monthly USING agg_loc_datum_monthly_pkey;

CLUSTER solaragg.aud_loc_datum_hourly USING aud_loc_datum_hourly_pkey;

\echo `date` Running ANALYZE on agg datum hypertables...

ANALYZE solaragg.agg_datum_hourly;
ANALYZE solaragg.agg_datum_daily;
ANALYZE solaragg.agg_datum_monthly;

ANALYZE solaragg.aud_datum_hourly;

\echo `date`  Running ANALYZE on agg loc datum hypertables...

ANALYZE solaragg.agg_loc_datum_hourly;
ANALYZE solaragg.agg_loc_datum_daily;
ANALYZE solaragg.agg_loc_datum_monthly;

ANALYZE solaragg.aud_loc_datum_hourly;

\echo `date` Creating datum hypertable stale datum triggers...

CREATE TRIGGER aa_agg_stale_datum
    BEFORE INSERT OR DELETE OR UPDATE
    ON solardatum.da_datum
    FOR EACH ROW
    EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();

CREATE TRIGGER aa_agg_stale_loc_datum
    BEFORE INSERT OR DELETE OR UPDATE
    ON solardatum.da_loc_datum
    FOR EACH ROW
    EXECUTE PROCEDURE solardatum.trigger_agg_stale_loc_datum();
