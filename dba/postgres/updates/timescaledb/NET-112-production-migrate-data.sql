\echo `date` Creating  datum hypertables...

SELECT public.create_hypertable('solardatum.da_datum'::regclass, 'ts'::name,
	NULL::name,
	NULL::integer,
	NULL::name,
	NULL::name,
	interval '6 months',
	FALSE,
	TRUE,
	NULL::regproc);
SELECT public.create_hypertable('solardatum.da_loc_datum'::regclass, 'ts'::name,
	NULL::name,
	NULL::integer,
	NULL::name,
	NULL::name,
	interval '1 year',
	FALSE,
	TRUE,
	NULL::regproc);

\echo `date` Creating aggregate datum hypertables...

SELECT public.create_hypertable('solaragg.agg_datum_hourly'::regclass, 'ts_start'::name,
	NULL::name,
	NULL::integer,
	NULL::name,
	NULL::name,
	interval '6 months',
	FALSE,
	TRUE,
	NULL::regproc);

SELECT public.create_hypertable('solaragg.agg_datum_daily'::regclass, 'ts_start'::name,
	NULL::name,
	NULL::integer,
	NULL::name,
	NULL::name,
	interval '1 years',
	FALSE,
	TRUE,
	NULL::regproc);

SELECT public.create_hypertable('solaragg.agg_datum_monthly'::regclass, 'ts_start'::name,
	NULL::name,
	NULL::integer,
	NULL::name,
	NULL::name,
	interval '5 years',
	FALSE,
	TRUE,
	NULL::regproc);

SELECT public.create_hypertable('solaragg.agg_loc_datum_hourly'::regclass, 'ts_start'::name,
	NULL::name,
	NULL::integer,
	NULL::name,
	NULL::name,
	interval '1 year',
	FALSE,
	TRUE,
	NULL::regproc);

SELECT public.create_hypertable('solaragg.agg_loc_datum_daily'::regclass, 'ts_start'::name,
	NULL::name,
	NULL::integer,
	NULL::name,
	NULL::name,
	interval '5 years',
	FALSE,
	TRUE,
	NULL::regproc);

SELECT public.create_hypertable('solaragg.agg_loc_datum_monthly'::regclass, 'ts_start'::name,
	NULL::name,
	NULL::integer,
	NULL::name,
	NULL::name,
	interval '10 years',
	FALSE,
	TRUE,
	NULL::regproc);

\echo `date` Creating aggregate datum audit hypertables...

SELECT public.create_hypertable('solaragg.aud_datum_hourly'::regclass, 'ts_start'::name,
	NULL::name,
	NULL::integer,
	NULL::name,
	NULL::name,
	interval '6 months',
	FALSE,
	TRUE,
	NULL::regproc);

SELECT public.create_hypertable('solaragg.aud_loc_datum_hourly'::regclass, 'ts_start'::name,
	NULL::name,
	NULL::integer,
	NULL::name,
	NULL::name,
	interval '1 year',
	FALSE,
	TRUE,
	NULL::regproc);

\echo `date` Migrating datum data < 2015...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts < '2015-01-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2015 H1...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2015-01-01 00:00:00+13'::timestamptz AND ts < '2015-06-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2015 H2...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2015-06-01 00:00:00+13'::timestamptz AND ts < '2016-01-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2016 Q1...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2016-01-01 00:00:00+13'::timestamptz AND ts < '2016-04-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2016 Q2...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2016-04-01 00:00:00+13'::timestamptz AND ts < '2016-07-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2016 Q3...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2016-07-01 00:00:00+13'::timestamptz AND ts < '2016-10-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2016 M10...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2016-10-01 00:00:00+13'::timestamptz AND ts < '2016-11-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2016 M11...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2016-11-01 00:00:00+13'::timestamptz AND ts < '2016-12-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2016 M12...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2016-12-01 00:00:00+13'::timestamptz AND ts < '2017-01-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2017 M01...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2017-01-01 00:00:00+13'::timestamptz AND ts < '2017-02-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2017 M02...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2017-02-01 00:00:00+13'::timestamptz AND ts < '2017-03-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2017 M03...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2017-03-01 00:00:00+13'::timestamptz AND ts < '2017-04-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2017 M04...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2017-04-01 00:00:00+13'::timestamptz AND ts < '2017-05-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2017 M05...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2017-05-01 00:00:00+13'::timestamptz AND ts < '2017-06-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2017 M06...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2017-06-01 00:00:00+13'::timestamptz AND ts < '2017-07-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2017 M07...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2017-07-01 00:00:00+13'::timestamptz AND ts < '2017-08-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2017 M08...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2017-08-01 00:00:00+13'::timestamptz AND ts < '2017-09-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2017 M09...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2017-09-01 00:00:00+13'::timestamptz AND ts < '2017-10-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2017 M10...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2017-10-01 00:00:00+13'::timestamptz AND ts < '2017-11-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2017 M11...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2017-11-01 00:00:00+13'::timestamptz AND ts < '2017-12-01 00:00:00+13'::timestamptz;

\echo `date` Migrating datum data 2017 M12...

INSERT INTO solardatum.da_datum
		(ts,node_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,node_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_datum_old
	 WHERE ts >= '2017-12-01 00:00:00+13'::timestamptz AND ts < '2018-01-01 00:00:00+13'::timestamptz;


/* slower, but less memory
DO $$
DECLARE
	curr_time timestamptz := '2008-08-01 00:00:00+13'::timestamptz;
	end_time timestamptz := CURRENT_TIMESTAMP;
	span interval := interval '1 months';
	conn_str text := 'dbname=solarnetwork';
	query text;
BEGIN
	LOOP
		RAISE NOTICE 'Copying da_datum from % @ %', curr_time, timeofday();
		query := 'INSERT INTO solardatum.da_datum '
			|| 'SELECT ts,node_id,source_id,posted,'
			||	'jdata->''i'' as jdata_i,jdata->''a'' as jdata_a,jdata->''s'' as jdata_s,jdata->''t'' as jdata_t '
			|| 'FROM solardatum.da_datum_old WHERE ts >= '
				|| quote_nullable(curr_time) || '::timestamptz AND ts < (' || quote_nullable(curr_time)
					|| '::timestamptz + interval '''||to_char(span, 'MM')||' months'')';

		PERFORM dblink.dblink_connect('dblink_tx', conn_str);
		PERFORM dblink.dblink('dblink_tx', query);
		PERFORM dblink.dblink_disconnect('dblink_tx');

		curr_time = curr_time + span;
		EXIT WHEN curr_time > end_time;
	END LOOP;
END;$$;
*/

\echo `date` Migrating loc datum data...

INSERT INTO solardatum.da_loc_datum
		(ts,loc_id,source_id,posted,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts,loc_id,source_id,posted,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solardatum.da_loc_datum_old;

/* ========================
 * Aggregate data migration
 * ======================== */

\echo `date` Migrating agg datum hourly data...

INSERT INTO solaragg.agg_datum_hourly
		(ts_start,local_date,node_id,source_id,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts_start,local_date,node_id,source_id,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solaragg.agg_datum_hourly_old;

\echo `date` Migrating agg datum daily data...

INSERT INTO solaragg.agg_datum_daily
		(ts_start,local_date,node_id,source_id,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts_start,local_date,node_id,source_id,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solaragg.agg_datum_daily_old;

\echo `date` Migrating agg datum monthly data...

INSERT INTO solaragg.agg_datum_monthly
		(ts_start,local_date,node_id,source_id,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts_start,local_date,node_id,source_id,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solaragg.agg_datum_monthly_old;

\echo `date` Migrating agg loc datum hourly data...

INSERT INTO solaragg.agg_loc_datum_hourly
		(ts_start,local_date,loc_id,source_id,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts_start,local_date,loc_id,source_id,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solaragg.agg_loc_datum_hourly_old;

\echo `date` Migrating agg loc datum daily data...

INSERT INTO solaragg.agg_loc_datum_daily
		(ts_start,local_date,loc_id,source_id,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts_start,local_date,loc_id,source_id,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solaragg.agg_loc_datum_daily_old;

\echo `date` Migrating agg loc datum monthly data...

INSERT INTO solaragg.agg_loc_datum_monthly
		(ts_start,local_date,loc_id,source_id,jdata_i,jdata_a,jdata_s,jdata_t)
	SELECT ts_start,local_date,loc_id,source_id,
		jdata->'i' as jdata_i,jdata->'a' as jdata_a,jdata->'s' as jdata_s,
		solarcommon.json_array_to_text_array(jdata->'t') as jdata_t
	 FROM solaragg.agg_loc_datum_monthly_old;

\echo `date` Migrating aggregate datum audit data...

INSERT INTO solaragg.aud_datum_hourly
		(ts_start,node_id,source_id,prop_count)
	SELECT ts_start,node_id,source_id,prop_count
	FROM solaragg.aud_datum_hourly_old;

INSERT INTO solaragg.aud_loc_datum_hourly
		(ts_start,loc_id,source_id,prop_count)
	SELECT ts_start,loc_id,source_id,prop_count
	FROM solaragg.aud_loc_datum_hourly_old;

