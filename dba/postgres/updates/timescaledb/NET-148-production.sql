-- create new tables / functions / triggers

-- \i init/updates/NET-148-user-datum-expire.sql

-- apply production permissions

GRANT USAGE, SELECT ON SEQUENCE solaruser.user_expire_seq TO solar;
GRANT ALL ON SEQUENCE solaruser.user_expire_seq TO solarinput;

GRANT ALL ON TABLE solaruser.user_expire_data_conf TO solar;

GRANT EXECUTE ON FUNCTION solaruser.preview_expire_datum_for_policy(bigint,jsonb,interval) TO solar;
GRANT EXECUTE ON FUNCTION solaruser.expire_datum_for_policy(bigint,jsonb,interval) TO solar;
