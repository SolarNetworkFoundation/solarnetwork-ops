ALTER INDEX solarnet.oauth2_authorized_client_pk 	SET TABLESPACE solarindex;

GRANT ALL ON TABLE solarnet.oauth2_authorized_client TO solaruser;
GRANT ALL ON TABLE solarnet.oauth2_authorized_client TO solarjobs;
