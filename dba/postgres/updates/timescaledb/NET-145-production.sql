-- create new tables / functions / triggers

-- \i init/updates/NET-145-storage-accumulation-auditing.sql

-- apply production permissions

GRANT EXECUTE ON FUNCTION solaragg.find_audit_acc_datum_daily(bigint,text) TO solar;

GRANT SELECT ON TABLE solaragg.aud_acc_datum_daily TO solar;
GRANT ALL ON TABLE solaragg.aud_acc_datum_daily TO solarinput;

GRANT EXECUTE ON FUNCTION solaragg.populate_audit_acc_datum_daily(bigint,text) TO solarinput;

-- move indexes to right tablespace and convert from PRIMARY KEY to UNIQUE INDEX
-- so hypertable remembers tablespace in chunk tables

ALTER TABLE solaragg.aud_acc_datum_daily DROP CONSTRAINT aud_acc_datum_daily_pkey;

CREATE UNIQUE INDEX aud_acc_datum_daily_pkey
	ON solaragg.aud_acc_datum_daily (node_id, ts_start, source_id)
	TABLESPACE solarindex;

-- create hypertables

SELECT public.create_hypertable('solaragg.aud_acc_datum_daily'::regclass, 'ts_start'::name,
	chunk_time_interval => interval '1 years',
	create_default_indexes => FALSE);
