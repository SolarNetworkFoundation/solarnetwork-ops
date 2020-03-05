GRANT SELECT ON TABLE solaruser.network_association TO solarinput;
GRANT SELECT ON TABLE solaruser.user_node TO solarinput;
GRANT SELECT ON TABLE solaruser.user_user TO solarinput;

GRANT INSERT,UPDATE ON TABLE solaragg.agg_stale_datum TO solarinput;
GRANT INSERT,UPDATE ON TABLE solaragg.aud_datum_hourly TO solarinput;

GRANT ALL ON SEQUENCE solarev.ocpp_charge_tx_seq TO solarinput;
GRANT SELECT, UPDATE, REFERENCES, TRIGGER ON TABLE solarev.ocpp_charge_point TO solarinput;
GRANT ALL ON TABLE solarev.ocpp_charge_point_conn TO solarinput;
GRANT ALL ON TABLE solarev.ocpp_charge_sess TO solarinput;
GRANT ALL ON TABLE solarev.ocpp_charge_sess_reading TO solarinput;
