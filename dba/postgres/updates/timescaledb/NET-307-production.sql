SELECT public.create_hypertable('solaruser.user_event_log', 'event_id',
	chunk_time_interval => interval '1 months',
	create_default_indexes => FALSE,
	time_partitioning_func => 'solarcommon.uuid_to_timestamp_v7');

ALTER INDEX solaruser.user_event_log_pk 		SET TABLESPACE solarindex;
ALTER INDEX solaruser.user_event_log_tags_idx 	SET TABLESPACE solarindex;

GRANT INSERT ON TABLE solaruser.user_event_log TO solar;

SELECT add_retention_policy('solaruser.user_event_log', INTERVAL '1 year', if_not_exists => TRUE);
