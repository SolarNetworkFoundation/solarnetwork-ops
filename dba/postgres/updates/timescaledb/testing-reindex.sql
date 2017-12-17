CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS agg_datum_hourly_pkey_new
	ON solaragg.agg_datum_hourly (node_id, ts_start, source_id)
	TABLESPACE solarindex;
ALTER INDEX da_datum_pkey RENAME TO da_datum_pkey_old;
ALTER INDEX da_datum_pkey_new RENAME TO da_datum_pkey;
DROP INDEX da_datum_pkey_old;

/* List chunks with the upper time limit:

select chunk_table,to_timestamp(upper(ranges[1])::double precision / 1000000) from chunk_relation_size('solardatum.da_loc_datum_hyper');
                 chunk_table                 |      to_timestamp
---------------------------------------------+------------------------
 "_timescaledb_internal"."_hyper_2_10_chunk" | 2018-01-01 13:00:00+13
 "_timescaledb_internal"."_hyper_2_11_chunk" | 2015-01-01 19:00:00+13
 "_timescaledb_internal"."_hyper_2_12_chunk" | 2009-01-01 07:00:00+13
 "_timescaledb_internal"."_hyper_2_13_chunk" | 2013-01-01 07:00:00+13
 "_timescaledb_internal"."_hyper_2_14_chunk" | 2010-01-01 13:00:00+13
 "_timescaledb_internal"."_hyper_2_15_chunk" | 2011-01-01 19:00:00+13
 "_timescaledb_internal"."_hyper_2_16_chunk" | 2012-01-02 01:00:00+13
 "_timescaledb_internal"."_hyper_2_17_chunk" | 2014-01-01 13:00:00+13
 "_timescaledb_internal"."_hyper_2_18_chunk" | 2017-01-01 07:00:00+13
(9 rows)
*/
