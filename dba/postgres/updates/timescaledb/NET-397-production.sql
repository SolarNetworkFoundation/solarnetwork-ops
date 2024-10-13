ALTER INDEX solardin.cin_integration_pk 					SET TABLESPACE solarindex;
ALTER INDEX solardin.cin_datum_stream_pk 					SET TABLESPACE solarindex;
ALTER INDEX solardin.cin_datum_stream_prop_pk 				SET TABLESPACE solarindex;
ALTER INDEX solardin.cin_datum_stream_poll_task_pk 			SET TABLESPACE solarindex;

GRANT EXECUTE ON FUNCTION solardin.change_integration_enabled() TO solaruser;
GRANT EXECUTE ON FUNCTION solardin.change_integration_enabled() TO solarjobs;

GRANT EXECUTE ON FUNCTION solardin.change_datum_stream_enabled() TO solaruser;
GRANT EXECUTE ON FUNCTION solardin.change_datum_stream_enabled() TO solarjobs;

GRANT EXECUTE ON FUNCTION solardin.claim_datum_stream_poll_task() TO solarjobs;
