\i init/updates/NET-435-user-api-billing.sql

INSERT INTO solarcommon.messages ("vers","bundle","locale","msg_key","msg_val") VALUES
('2008-01-01 00:00:00+13'::timestamptz,'snf.billing','en','api-data.item','API Data'),
('2008-01-01 00:00:00+13'::timestamptz,'snf.billing','en','api-data.unit','Bytes');
