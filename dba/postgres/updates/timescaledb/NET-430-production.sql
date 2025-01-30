\i init/updates/NET-430-cloud-datum-stream-claim-update.sql

SELECT stmt || ';' FROM (SELECT * FROM public.set_index_tablespace('solardin', 'solarindex')) AS res;
