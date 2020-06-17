GRANT ALL    ON TABLE    solaruser.user_node_event_task        TO solarjobs;
GRANT ALL    ON TABLE    solaruser.user_node_event_task_result TO solarjobs;
GRANT SELECT ON TABLE    solaruser.user_node_event_hook        TO solarjobs;

GRANT ALL    ON TABLE    solaruser.user_node_event_hook        TO solaruser;
GRANT ALL    ON SEQUENCE solaruser.user_node_event_hook_seq    TO solaruser;
