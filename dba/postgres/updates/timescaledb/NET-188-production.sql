-- create new tables / functions / triggers

-- \i init/updates/NET-188-datum-aux-metas.sql

-- apply production permissions

ALTER FUNCTION solardatum.store_datum_aux(timestamp with time zone, bigint, character varying, solardatum.da_datum_aux_type, text, text, text, text)OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.store_datum_aux(timestamp with time zone, bigint, character varying, solardatum.da_datum_aux_type, text, text, text, text) TO solarin;
REVOKE ALL ON FUNCTION solardatum.store_datum_aux(timestamp with time zone, bigint, character varying, solardatum.da_datum_aux_type, text, text, text, text) FROM PUBLIC;

ALTER FUNCTION solardatum.move_datum_aux(timestamp with time zone,bigint,character varying,solardatum.da_datum_aux_type,timestamp with time zone,bigint,character varying,solardatum.da_datum_aux_type,text,text,text,text) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.move_datum_aux(timestamp with time zone,bigint,character varying,solardatum.da_datum_aux_type,timestamp with time zone,bigint,character varying,solardatum.da_datum_aux_type,text,text,text,text) TO solarin;
REVOKE ALL ON FUNCTION solardatum.move_datum_aux(timestamp with time zone,bigint,character varying,solardatum.da_datum_aux_type,timestamp with time zone,bigint,character varying,solardatum.da_datum_aux_type,text,text,text,text) FROM public;
