-- create new tables / functions / triggers

-- \i init/updates/NET-165-datum-import.sql

-- apply production permissions

ALTER TABLE solarnet.sn_datum_import_job OWNER TO solarnet;
GRANT SELECT ON TABLE solarnet.sn_datum_import_job TO solar;
GRANT ALL ON TABLE solarnet.sn_datum_import_job TO solarinput;

ALTER FUNCTION solarnet.claim_datum_import_job() OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solarnet.claim_datum_import_job() TO solar;

ALTER FUNCTION solarnet.purge_completed_datum_import_jobs(older_date timestamp with time zone) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solarnet.purge_completed_datum_import_jobs(older_date timestamp with time zone) TO solar;
