GRANT SELECT ON TABLE solaruser.network_association TO solarinput;
GRANT SELECT ON TABLE solaruser.user_node TO solarinput;
GRANT SELECT ON TABLE solaruser.user_user TO solarinput;

GRANT ALL ON SEQUENCE solarev.ocpp_charge_tx_seq TO solarinput;
GRANT SELECT, UPDATE, REFERENCES, TRIGGER ON TABLE solarev.ocpp_charge_point TO solarinput;
GRANT ALL ON TABLE solarev.ocpp_charge_point_action_status TO solarinput;
GRANT ALL ON TABLE solarev.ocpp_charge_point_conn TO solarinput;
GRANT ALL ON TABLE solarev.ocpp_charge_point_status TO solarinput;
GRANT ALL ON TABLE solarev.ocpp_charge_sess TO solarinput;
GRANT ALL ON TABLE solarev.ocpp_charge_sess_reading TO solarinput;
