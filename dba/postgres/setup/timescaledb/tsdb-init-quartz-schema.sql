ALTER DEFAULT PRIVILEGES IN SCHEMA quartz REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA quartz REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA quartz REVOKE ALL ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA quartz REVOKE ALL ON TYPES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES IN SCHEMA quartz GRANT ALL ON TABLES TO solarjobs;
ALTER DEFAULT PRIVILEGES IN SCHEMA quartz GRANT ALL ON SEQUENCES TO solarjobs;
ALTER DEFAULT PRIVILEGES IN SCHEMA quartz GRANT ALL ON FUNCTIONS TO solarjobs;
ALTER DEFAULT PRIVILEGES IN SCHEMA quartz GRANT ALL ON TYPES TO solarjobs;
