GRANT USAGE ON SCHEMA public TO solardnp3;
GRANT USAGE ON SCHEMA solardnp3 TO solardnp3;
GRANT USAGE ON SCHEMA solardnp3 TO solarjobs;
GRANT USAGE ON SCHEMA solardnp3 TO solaruser;

GRANT SELECT(user_id, node_id, archived) ON solaruser.user_node TO solardnp3;
