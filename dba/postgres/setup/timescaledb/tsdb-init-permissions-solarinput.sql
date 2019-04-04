GRANT SELECT ON TABLE solaruser.network_association TO solarinput;
GRANT SELECT ON TABLE solaruser.user_node TO solarinput;
GRANT SELECT ON TABLE solaruser.user_user TO solarinput;

GRANT INSERT,UPDATE ON TABLE solaragg.agg_stale_datum TO solarinput;
GRANT INSERT,UPDATE ON TABLE solaragg.aud_datum_hourly TO solarinput;
