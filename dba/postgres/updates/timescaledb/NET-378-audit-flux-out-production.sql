\i init/updates/NET-378-audit-flux-out.sql

SELECT public.create_hypertable('solardatm.aud_user_io', 'ts_start',
	chunk_time_interval => INTERVAL '1 years',
	create_default_indexes => FALSE);

SELECT public.create_hypertable('solardatm.aud_user_daily', 'ts_start',
	chunk_time_interval => INTERVAL '5 years',
	create_default_indexes => FALSE);

SELECT public.create_hypertable('solardatm.aud_user_monthly', 'ts_start',
	chunk_time_interval => INTERVAL '10 years',
	create_default_indexes => FALSE);

ALTER INDEX solardatm.aud_user_io_pkey 		SET TABLESPACE solarindex;
ALTER INDEX solardatm.aud_user_daily_pkey 	SET TABLESPACE solarindex;
ALTER INDEX solardatm.aud_user_monthly_pkey SET TABLESPACE solarindex;

GRANT ALL ON TABLE solardatm.aud_user_io TO solaruser;
GRANT ALL ON TABLE solardatm.aud_stale_user TO solaruser;

GRANT SELECT, INSERT, UPDATE ON TABLE solardatm.aud_user_io TO solarquery;
GRANT INSERT, UPDATE ON TABLE solardatm.aud_stale_user TO solarquery;
