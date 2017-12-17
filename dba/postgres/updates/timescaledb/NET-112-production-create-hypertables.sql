\echo `date` Renaming old datum tables to make way for hypertables...

ALTER TABLE solardatum.da_datum RENAME CONSTRAINT da_datum_pkey TO da_datum_pkey_old;
ALTER TABLE solardatum.da_datum RENAME TO da_datum_old;

ALTER TABLE solardatum.da_loc_datum RENAME CONSTRAINT da_loc_datum_pkey TO da_loc_datum_pkey_old;
ALTER TABLE solardatum.da_loc_datum RENAME TO da_loc_datum_old;

\echo `date` Creating datum hypertables...

CREATE TABLE solardatum.da_datum (
    ts timestamp with time zone NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    posted timestamp with time zone NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[]
);

CREATE TABLE solardatum.da_loc_datum (
    ts timestamp with time zone NOT NULL,
    loc_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    posted timestamp with time zone NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[]
);

\echo `date` Renaming old aggregate datum tables to make way for hypertables...

ALTER TABLE solaragg.agg_datum_hourly RENAME CONSTRAINT agg_datum_hourly_pkey TO agg_datum_hourly_pkey_old;
ALTER TABLE solaragg.agg_datum_hourly RENAME TO agg_datum_hourly_old;

ALTER TABLE solaragg.agg_datum_daily RENAME CONSTRAINT agg_datum_daily_pkey TO agg_datum_daily_pkey_old;
ALTER TABLE solaragg.agg_datum_daily RENAME TO agg_datum_daily_old;

ALTER TABLE solaragg.agg_datum_monthly RENAME CONSTRAINT agg_datum_monthly_pkey TO agg_datum_monthly_pkey_old;
ALTER TABLE solaragg.agg_datum_monthly RENAME TO agg_datum_monthly_old;

ALTER TABLE solaragg.agg_loc_datum_hourly RENAME CONSTRAINT agg_loc_datum_hourly_pkey TO agg_loc_datum_hourly_pkey_old;
ALTER TABLE solaragg.agg_loc_datum_hourly RENAME TO agg_loc_datum_hourly_old;

ALTER TABLE solaragg.agg_loc_datum_daily RENAME CONSTRAINT agg_loc_datum_daily_pkey TO agg_loc_datum_daily_pkey_old;
ALTER TABLE solaragg.agg_loc_datum_daily RENAME TO agg_loc_datum_daily_old;

ALTER TABLE solaragg.agg_loc_datum_monthly RENAME CONSTRAINT agg_loc_datum_monthly_pkey TO agg_loc_datum_monthly_pkey_old;
ALTER TABLE solaragg.agg_loc_datum_monthly RENAME TO agg_loc_datum_monthly_old;

\echo `date` Renaming old aggregate datum audit tables to make way for hypertables...

ALTER TABLE solaragg.aud_datum_hourly RENAME CONSTRAINT aud_datum_hourly_pkey TO aud_datum_hourly_pkey_old;
ALTER TABLE solaragg.aud_datum_hourly RENAME TO aud_datum_hourly_old;

ALTER TABLE solaragg.aud_loc_datum_hourly RENAME CONSTRAINT aud_loc_datum_hourly_pkey TO aud_loc_datum_hourly_pkey_old;
ALTER TABLE solaragg.aud_loc_datum_hourly RENAME TO aud_loc_datum_hourly_old;

\echo `date` Creating aggregate datum hypertables...

CREATE TABLE solaragg.agg_datum_hourly (
    ts_start timestamp with time zone NOT NULL,
    local_date timestamp without time zone NOT NULL,
    node_id bigint NOT NULL,
    source_id  character varying(64) NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[]
);

CREATE TABLE solaragg.agg_datum_daily (
    ts_start timestamp with time zone NOT NULL,
    local_date date NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[]
);

CREATE TABLE solaragg.agg_datum_monthly (
    ts_start timestamp with time zone NOT NULL,
    local_date date NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[]
);

CREATE TABLE solaragg.agg_loc_datum_hourly (
    ts_start timestamp with time zone NOT NULL,
    local_date timestamp without time zone NOT NULL,
    loc_id bigint NOT NULL,
    source_id  character varying(64) NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[]
);

CREATE TABLE solaragg.agg_loc_datum_daily (
    ts_start timestamp with time zone NOT NULL,
    local_date date NOT NULL,
    loc_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[]
);

CREATE TABLE solaragg.agg_loc_datum_monthly (
    ts_start timestamp with time zone NOT NULL,
    local_date date NOT NULL,
    loc_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[]
);

\echo `date` Creating aggregate datum audit hypertables...

CREATE TABLE solaragg.aud_datum_hourly (
  ts_start timestamp with time zone NOT NULL,
  node_id bigint NOT NULL,
  source_id character varying(64) NOT NULL,
  prop_count integer NOT NULL
);

CREATE TABLE solaragg.aud_loc_datum_hourly (
  ts_start timestamp with time zone NOT NULL,
  loc_id bigint NOT NULL,
  source_id character varying(64) NOT NULL,
  prop_count integer NOT NULL
);

\echo `date` Creating temporary indexes on old datum ts columns to speed up copy...

DO $$
DECLARE
	curr_year integer := 2008;
	max_year integer := 2018;
	ddl text;
	idx_count integer := 0;
	idx_created boolean := FALSE;
BEGIN
	LOOP
		SELECT count(*) FROM pg_indexes
		WHERE schemaname = 'solardatum'
			AND tablename = 'da_datum_p'||curr_year
			AND indexname = 'da_datum_p'||curr_year||'_ts_idx'
		INTO idx_count;

		IF idx_count < 1 THEN
			RAISE NOTICE 'Creating ts index on da_datum_p%', curr_year;
			ddl := 'CREATE INDEX IF NOT EXISTS da_datum_p' || curr_year || '_ts_idx ON solardatum.da_datum_p'
				|| curr_year || ' (ts) TABLESPACE solarindex';
			EXECUTE ddl;
			--EXECUTE 'ANALYZE VERBOSE solardatum.da_datum_p' || curr_year;
			idx_created := TRUE;
		ELSE
			RAISE NOTICE 'Index da_datum_p%_ts_idx already exists', curr_year;
		END IF;
		curr_year := curr_year + 1;
		EXIT WHEN curr_year > max_year;
	END LOOP;
	IF idx_created THEN
		RAISE NOTICE 'Analyzing da_datum table';
		ANALYZE VERBOSE solardatum.da_datum;
	END IF;
END;$$;
