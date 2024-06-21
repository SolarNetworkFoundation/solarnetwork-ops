\i init/updates/NET-382-http-sessions.sql

ALTER INDEX solaruser.http_session_pk 				SET TABLESPACE solarindex;
ALTER INDEX solaruser.http_session_session_unq 		SET TABLESPACE solarindex;
ALTER INDEX solaruser.http_session_exp_idx 			SET TABLESPACE solarindex;
ALTER INDEX solaruser.http_session_principal_idx 	SET TABLESPACE solarindex;
ALTER INDEX solaruser.http_session_attributes_pk 	SET TABLESPACE solarindex;

REVOKE ALL ON TABLE solaruser.http_session FROM solar;
GRANT ALL ON TABLE solaruser.http_session TO solaruser;

REVOKE ALL ON TABLE solaruser.http_session_attributes FROM solar;
GRANT ALL ON TABLE solaruser.http_session_attributes TO solaruser;
