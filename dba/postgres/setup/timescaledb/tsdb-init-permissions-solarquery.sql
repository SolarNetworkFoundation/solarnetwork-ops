-- SELECT on user tables for security enforcement
GRANT SELECT ON solaruser.user_user TO solarquery;
GRANT SELECT ON solaruser.user_node TO solarquery;
