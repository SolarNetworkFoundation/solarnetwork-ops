SELECT public.create_hypertable('solardatm.aud_node_io', 'ts_start',
	chunk_time_interval => INTERVAL '4 months',
	create_default_indexes => FALSE);

SELECT public.create_hypertable('solardatm.aud_node_daily', 'ts_start',
	chunk_time_interval => INTERVAL '1 years',
	create_default_indexes => FALSE);

SELECT public.create_hypertable('solardatm.aud_node_monthly', 'ts_start',
	chunk_time_interval => INTERVAL '5 years',
	create_default_indexes => FALSE);

ALTER INDEX solardatm.aud_node_io_pkey 		SET TABLESPACE solarindex;
ALTER INDEX solardatm.aud_node_daily_pkey 	SET TABLESPACE solarindex;
ALTER INDEX solardatm.aud_node_monthly_pkey SET TABLESPACE solarindex;

GRANT INSERT ON TABLE solardatm.aud_node_io TO solaruser;
