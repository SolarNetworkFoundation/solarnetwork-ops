/**
 * Function to move hypertable chunks as part of a Timescale scheduled job.
 *
 * The JSON configuration expects the following properties:
 *
 * hypertable                   - the name of the hypertable, e.g. 'solardatm.da_datm'
 * lag                          - an interval literal for the minimum lag, e.g. '5 years'
 * lag_max                      - an optional interval literal for the maximum lag, e.g. '10 years'
 * destination_tablespace       - the destination tablespace to move chunks to, e.g. 'solarwarm'
 * index_destination_tablespace - an optional destination tablespace to move chunk indexes to; if
 *                                not specified then `destination_tablespace` will be assumed
 * reorder_index                - the name of the index to reorder the chunk data on, e.g.
 *                                solardatm.da_datm_pkey
 * max_move                     - an optional maximum number of chunks to move per invocation;
 *                                defaults to 100
 *
 * Example configuration:
 *
 * {
 *   "hypertable": "solardatm.da_datm",
 *   "lag": "5 years",
 *   "destination_tablespace": "solarwarm",
 *   "index_destination_tablespace": "solarwarm",
 *   "reorder_index": "solardatm.da_datm_pkey",
 *   "max_move": 1
 * }
 *
 * @param job_id the Timescale job ID
 * @param config the Timescale job configuration
 */
CREATE OR REPLACE PROCEDURE solarcommon.move_chunks(job_id int, config jsonb)
LANGUAGE PLPGSQL AS $$
DECLARE
	ht REGCLASS;
	lag interval;
	lag_max interval;
	destination_tablespace name;
	index_destination_tablespace name;
	reorder_index REGCLASS;
	max_move INTEGER;
	chunk REGCLASS;
	chunk_table_size BIGINT;
	chunk_index_size BIGINT;
	tmp_name name;
BEGIN
	SELECT jsonb_object_field_text(config, 'hypertable')::regclass INTO STRICT ht;
	SELECT jsonb_object_field_text(config, 'lag')::INTERVAL INTO STRICT lag;
	SELECT jsonb_object_field_text(config, 'lag_max')::INTERVAL INTO STRICT lag_max;
	SELECT jsonb_object_field_text(config, 'destination_tablespace') INTO STRICT destination_tablespace;
	SELECT jsonb_object_field_text(config, 'index_destination_tablespace') INTO STRICT index_destination_tablespace;
	SELECT jsonb_object_field_text(config, 'reorder_index')::regclass INTO STRICT reorder_index;
	SELECT COALESCE(jsonb_object_field_text(config, 'max_move')::INTEGER, 100) INTO STRICT max_move;

	IF ht IS NULL OR lag IS NULL OR destination_tablespace IS NULL THEN
		RAISE EXCEPTION 'Config must have hypertable, lag, and destination_tablespace';
	END IF;

	IF index_destination_tablespace IS NULL THEN
		index_destination_tablespace := destination_tablespace;
	END IF;

	FOR chunk, chunk_table_size, chunk_index_size IN
		SELECT c.oid, s.table_bytes, s.index_bytes
		FROM pg_class AS c
		LEFT JOIN pg_tablespace AS t ON (c.reltablespace = t.oid)
		JOIN pg_namespace AS n ON (c.relnamespace = n.oid)
		JOIN (SELECT * FROM show_chunks(ht, older_than => lag, newer_than => lag_max) SHOW (oid)) AS chunks
			ON (chunks.oid::text = n.nspname || '.' || c.relname)
		JOIN chunks_detailed_size(ht) s ON s.chunk_schema || '.' || s.chunk_name = chunks.oid::text
		WHERE t.spcname != destination_tablespace OR t.spcname IS NULL
		LIMIT max_move
	LOOP
		RAISE NOTICE 'Moving chunk % data -> % (%), index -> % (%); ordered by %', chunk::TEXT,
			destination_tablespace::TEXT, pg_size_pretty(chunk_table_size),
			index_destination_tablespace::TEXT, pg_size_pretty(chunk_index_size),
			reorder_index::TEXT;
		PERFORM move_chunk(
			chunk => chunk,
			destination_tablespace => destination_tablespace,
			index_destination_tablespace => index_destination_tablespace,
			reorder_index => reorder_index
		);
	END LOOP;
END
$$;

-- add daily job to move to warm storage; start in 3 days at 3am
SELECT add_job(
	'solarcommon.move_chunks',
	'1d',
	config => $${
		"hypertable": "solardatm.da_datm",
		"lag": "6 years",
		"destination_tablespace": "solarwarm",
		"index_destination_tablespace": "solarwarm",
		"reorder_index": "solardatm.da_datm_pkey",
		"max_move": 1
	}$$,
	initial_start => CURRENT_DATE AT TIME ZONE 'UTC' AT TIME ZONE 'UTC' + INTERVAL 'P3DT3H'
);
