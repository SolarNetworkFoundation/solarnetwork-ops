-- copy from solardatum.da_datum_aux -> solardatm.da_datm_aux
INSERT INTO solardatm.da_datm_aux (stream_id, ts, atype, updated, notes, jdata_af, jdata_as, jmeta)
SELECT m.stream_id, aux.ts, aux.atype, aux.updated, aux.notes, aux.jdata_af, aux.jdata_as, aux.jmeta
FROM solardatum.da_datum_aux aux
INNER JOIN solardatm.da_datm_meta m ON m.node_id = aux.node_id AND m.source_id = aux.source_id
ON CONFLICT (stream_id, ts, atype) DO NOTHING
;
