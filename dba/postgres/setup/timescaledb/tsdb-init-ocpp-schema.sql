-- solarev
ALTER DEFAULT PRIVILEGES IN SCHEMA solarev REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarev REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarev REVOKE ALL ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarev REVOKE ALL ON TYPES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES IN SCHEMA solarev GRANT SELECT ON TABLES TO solar;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarev GRANT USAGE,SELECT ON SEQUENCES TO solar;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarev GRANT EXECUTE ON FUNCTIONS TO solar;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarev GRANT USAGE ON TYPES TO solar;

ALTER DEFAULT PRIVILEGES IN SCHEMA solarev GRANT ALL ON TABLES TO solarjobs;
ALTER DEFAULT PRIVILEGES IN SCHEMA solarev GRANT ALL ON TABLES TO solaruser;
