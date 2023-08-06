GRANT USAGE ON SCHEMA public TO solardnp3;
GRANT USAGE ON SCHEMA solardnp3 TO solaruser;
GRANT USAGE ON SCHEMA solardnp3 TO solarjobs;

GRANT SELECT(user_id, node_id, archived) ON solaruser.user_node TO solardnp3;
