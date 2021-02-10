-- solardatm
ALTER DEFAULT PRIVILEGES IN SCHEMA solardatm REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA solardatm REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA solardatm REVOKE ALL ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA solardatm REVOKE ALL ON TYPES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES IN SCHEMA solardatm GRANT SELECT ON TABLES TO solar;
ALTER DEFAULT PRIVILEGES IN SCHEMA solardatm GRANT USAGE,SELECT ON SEQUENCES TO solar;
ALTER DEFAULT PRIVILEGES IN SCHEMA solardatm GRANT EXECUTE ON FUNCTIONS TO solar;
ALTER DEFAULT PRIVILEGES IN SCHEMA solardatm GRANT USAGE ON TYPES TO solar;

ALTER DEFAULT PRIVILEGES IN SCHEMA solardatm GRANT ALL ON TABLES TO solarinput;
ALTER DEFAULT PRIVILEGES IN SCHEMA solardatm GRANT ALL ON TABLES TO solarjobs;