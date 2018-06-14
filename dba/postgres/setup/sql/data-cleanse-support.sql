/**
 * Delete ALL data for a set of node IDs and source IDs.
 *
 * The node IDs and source IDs are ANDed together, but keep in mind ANY source
 * will match ANY node.
 */
CREATE OR REPLACE FUNCTION solardatum.cleanse_datum(nodes bigint[], sources text[])
	RETURNS BIGINT LANGUAGE plpgsql VOLATILE AS
$$
DECLARE
	nodes_str TEXT := array_to_string(nodes, ',');
	sources_str TEXT := array_to_string(sources, ',');
    num_rows BIGINT := 0;
BEGIN
	-- delete from raw data table
	DELETE FROM solardatum.da_datum
	WHERE node_id = ANY(nodes)
		AND source_id = ANY(sources);
	GET DIAGNOSTICS num_rows = ROW_COUNT;
	RAISE NOTICE 'Deleted % raw datum rows matching nodes %, sources %', num_rows, nodes_str, sources_str;
	RETURN num_rows;
END
$$;

/* Example call:

SELECT * FROM solardatum.cleanse_datum(ARRAY[1::bigint], ARRAY['foo']);
