\i init/updates/NET-464-rate-limiting.sql

ALTER TABLE solarcommon.bucket SET TABLESPACE solarindex;
ALTER TABLE solarcommon.bucket_1 SET TABLESPACE solarindex;
ALTER TABLE solarcommon.bucket_2 SET TABLESPACE solarindex;
ALTER TABLE solarcommon.bucket_3 SET TABLESPACE solarindex;
ALTER INDEX solarcommon.bucket_pk SET TABLESPACE solarindex;
ALTER INDEX solarcommon.bucket_1_pkey SET TABLESPACE solarindex;
ALTER INDEX solarcommon.bucket_2_pkey SET TABLESPACE solarindex;
ALTER INDEX solarcommon.bucket_3_pkey SET TABLESPACE solarindex;

GRANT ALL ON TABLE solarcommon.bucket TO solar;
