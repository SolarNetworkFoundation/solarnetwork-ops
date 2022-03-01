GRANT USAGE   ON SCHEMA quartz TO solarjobs;

GRANT ALL     ON SEQUENCE solaruser.user_alert_seq TO solarjobs;

GRANT ALL     ON TABLE solarcommon.app_setting TO solarjobs;
GRANT ALL     ON TABLE solardatm.da_datm TO solarjobs;
GRANT ALL     ON TABLE solardatm.da_datm_meta TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_adhoc_export_task TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_alert TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_alert_sit TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_datum_delete_job TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_export_task TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_export_datum_conf TO solarjobs;
GRANT SELECT  ON TABLE solaruser.user_node_event_hook TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_node_event_task TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_node_event_task_result TO solarjobs;

GRANT EXECUTE ON FUNCTION solardatm.store_datum(timestamp with time zone, bigint, text, timestamp with time zone, text, boolean) TO solarjobs;

-- Allow long exports to run without timeout: NOTE this must be set on users granted this role,
-- it is shown here as a reminder.
ALTER ROLE solarjobs SET idle_in_transaction_session_timeout TO 0;
