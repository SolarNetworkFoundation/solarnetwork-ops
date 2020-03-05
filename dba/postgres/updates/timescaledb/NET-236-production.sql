ALTER SEQUENCE solarev.ocpp_system_user_seq OWNER TO solarnet;
ALTER SEQUENCE solarev.ocpp_charge_point_seq OWNER TO solarnet;
ALTER SEQUENCE solarev.ocpp_charge_tx_seq OWNER TO solarnet;
ALTER SEQUENCE solarev.ocpp_system_user_seq OWNER TO solarnet;
GRANT ALL ON SEQUENCE solarev.ocpp_authorization_seq TO solaruser;
GRANT ALL ON SEQUENCE solarev.ocpp_charge_point_seq TO solaruser;
GRANT ALL ON SEQUENCE solarev.ocpp_charge_tx_seq TO solaruser;
GRANT ALL ON SEQUENCE solarev.ocpp_charge_tx_seq TO solarinput;
GRANT ALL ON SEQUENCE solarev.ocpp_system_user_seq TO solaruser;

ALTER TABLE solarev.ocpp_authorization OWNER TO solarnet;
GRANT SELECT ON TABLE solarev.ocpp_authorization TO solar;

ALTER TABLE solarev.ocpp_charge_point OWNER TO solarnet;
GRANT SELECT ON TABLE solarev.ocpp_charge_point TO solar;
GRANT SELECT, UPDATE, REFERENCES, TRIGGER ON TABLE solarev.ocpp_charge_point TO solarinput;

ALTER TABLE solarev.ocpp_charge_point_conn OWNER TO solarnet;
GRANT SELECT ON TABLE solarev.ocpp_charge_point_conn TO solar;
GRANT ALL ON TABLE solarev.ocpp_charge_point_conn TO solarinput;

ALTER TABLE solarev.ocpp_charge_point_settings OWNER TO solarnet;
GRANT SELECT ON TABLE solarev.ocpp_charge_point_settings TO solar;

ALTER TABLE solarev.ocpp_charge_sess OWNER TO solarnet;
GRANT SELECT ON TABLE solarev.ocpp_charge_sess TO solar;
GRANT ALL ON TABLE solarev.ocpp_charge_sess TO solarinput;

ALTER TABLE solarev.ocpp_charge_sess_reading OWNER TO solarnet;
GRANT SELECT ON TABLE solarev.ocpp_charge_sess_reading TO solar;
GRANT ALL ON TABLE solarev.ocpp_charge_sess_reading TO solarinput;

ALTER TABLE solarev.ocpp_system_user OWNER TO solarnet;
GRANT SELECT ON TABLE solarev.ocpp_system_user TO solar;

ALTER TABLE solarev.ocpp_user_settings OWNER TO solarnet;
GRANT SELECT ON TABLE solarev.ocpp_user_settings TO solar;
