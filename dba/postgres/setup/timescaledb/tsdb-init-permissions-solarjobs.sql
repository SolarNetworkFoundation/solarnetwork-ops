GRANT USAGE   ON SCHEMA quartz TO solarjobs;

GRANT ALL     ON SEQUENCE solaruser.user_alert_seq TO solarjobs;

GRANT ALL     ON TABLE solardatum.da_datum TO solarjobs;
GRANT ALL     ON TABLE solardatum.da_datum_range TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_adhoc_export_task TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_alert TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_alert_sit TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_datum_delete_job TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_export_task TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_export_datum_conf TO solarjobs;
GRANT SELECT  ON TABLE solaruser.user_node_event_hook TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_node_event_task TO solarjobs;
GRANT ALL     ON TABLE solaruser.user_node_event_task_result TO solarjobs;

GRANT EXECUTE ON FUNCTION solardatum.store_datum(timestamp with time zone, bigint, text, timestamp with time zone, text, boolean) TO solarjobs;
