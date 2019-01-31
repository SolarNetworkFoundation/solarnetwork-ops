-- create new tables / functions / triggers

-- \i init/updates/NET-178-ad-hoc-export.sql

-- apply production permissions

ALTER TABLE solaruser.user_adhoc_export_task OWNER TO solarnet;
GRANT SELECT ON TABLE solaruser.user_adhoc_export_task TO solar;
GRANT ALL ON TABLE solaruser.user_adhoc_export_task TO solarinput;

ALTER FUNCTION solaruser.store_adhoc_export_task(BIGINT, CHARACTER(1), TIMESTAMP WITH TIME ZONE, text) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaruser.store_adhoc_export_task(BIGINT, CHARACTER(1), TIMESTAMP WITH TIME ZONE, text) TO solar;

ALTER FUNCTION solaruser.purge_completed_user_adhoc_export_tasks(timestamp with time zone) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaruser.purge_completed_user_adhoc_export_tasks(timestamp with time zone) TO solar;
