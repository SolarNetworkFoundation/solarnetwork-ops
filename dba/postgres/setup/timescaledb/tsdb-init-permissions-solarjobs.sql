GRANT USAGE ON SCHEMA quartz TO solarjobs;

GRANT ALL ON SEQUENCE solaruser.user_alert_seq TO solarjobs;

GRANT ALL ON TABLE solaruser.user_adhoc_export_task TO solarjobs;
GRANT ALL ON TABLE solaruser.user_alert_sit TO solarjobs;
GRANT ALL ON TABLE solaruser.user_datum_delete_job TO solarjobs;
GRANT ALL ON TABLE solaruser.user_export_task TO solarjobs;
