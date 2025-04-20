ALTER INDEX solaruser.user_secret_pk SET TABLESPACE solarindex;
ALTER INDEX solaruser.user_keypair_pk SET TABLESPACE solarindex;

GRANT SELECT ON TABLE solaruser.user_keypair TO solarjobs;
GRANT ALL ON TABLE solaruser.user_keypair TO solaruser;

GRANT SELECT ON TABLE solaruser.user_secret TO solarjobs;
GRANT ALL ON TABLE solaruser.user_secret TO solaruser;
