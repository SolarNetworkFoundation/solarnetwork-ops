-- create new tables / functions / triggers

-- \i init/updates/NET-174-disjoint-readings.sql

-- apply production permissions

ALTER TABLE solardatum.da_datum_aux OWNER TO solarnet;
GRANT SELECT ON TABLE solardatum.da_datum_aux TO solar;
GRANT ALL ON TABLE solardatum.da_datum_aux TO solarinput;

ALTER FUNCTION solardatum.store_datum_aux(timestamp with time zone, bigint, character varying(64), solardatum.da_datum_aux_type, text, text, text) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.store_datum_aux(timestamp with time zone, bigint, character varying(64), solardatum.da_datum_aux_type, text, text, text) TO solar;

ALTER FUNCTION solardatum.jdata_from_datum_aux_final(solardatum.da_datum_aux) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.jdata_from_datum_aux_final(solardatum.da_datum_aux) TO solar;

ALTER FUNCTION solardatum.jdata_from_datum_aux_start(solardatum.da_datum_aux) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.jdata_from_datum_aux_start(solardatum.da_datum_aux) TO solar;

ALTER FUNCTION solarcommon.jsonb_diffsum_object_sfunc(jsonb, jsonb) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solarcommon.jsonb_diffsum_object_sfunc(jsonb, jsonb) TO solar;

ALTER FUNCTION solarcommon.jsonb_diffsum_object_finalfunc(jsonb) OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solarcommon.jsonb_diffsum_object_finalfunc(jsonb) TO solar;
