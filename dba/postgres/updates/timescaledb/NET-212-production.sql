CREATE UNIQUE INDEX da_datum_x_acc_idx ON solardatum.da_datum (node_id, source_id, ts DESC, jdata_a)
	TABLESPACE solarindex
    WHERE jdata_a IS NOT NULL;
