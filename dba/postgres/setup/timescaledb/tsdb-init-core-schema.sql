ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet REVOKE ALL ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet REVOKE ALL ON TYPES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet GRANT SELECT ON TABLES TO solar;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet GRANT USAGE,SELECT ON SEQUENCES TO solar;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet GRANT EXECUTE ON FUNCTIONS TO solar;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet GRANT USAGE ON TYPES TO solar;

ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet GRANT ALL ON TABLES TO solarjobs;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet GRANT ALL ON SEQUENCES TO solarjobs;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet GRANT ALL ON FUNCTIONS TO solarjobs;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet GRANT ALL ON TYPES TO solarjobs;

ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet GRANT ALL ON TABLES TO solaruser;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet GRANT ALL ON SEQUENCES TO solaruser;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet GRANT ALL ON FUNCTIONS TO solaruser;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarnet GRANT ALL ON TYPES TO solaruser;
