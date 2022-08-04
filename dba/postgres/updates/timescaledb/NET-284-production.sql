-- allow updating node datum stream metadata
GRANT EXECUTE ON FUNCTION solardatm.store_stream_datum(uuid, timestamp with time zone, timestamp with time zone, numeric[], numeric[], text[], text[], boolean) TO solarjobs;
