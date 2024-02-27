GRANT USAGE ON SCHEMA public TO solardin;
GRANT USAGE ON SCHEMA solardin TO solardin;
GRANT USAGE ON SCHEMA solardin TO solarjobs;
GRANT USAGE ON SCHEMA solardin TO solaruser;

GRANT SELECT(user_id, node_id, archived) ON solaruser.user_node TO solardin;
