-- DROP SCHEMA IF EXISTS solardatm CASCADE;
CREATE SCHEMA IF NOT EXISTS solardatm;

-- stream indirection table
CREATE TABLE solardatm.da_datm_meta (
	stream_id	UUID NOT NULL DEFAULT uuid_generate_v4(),
	node_id		BIGINT NOT NULL,
	source_id	CHARACTER VARYING(64) NOT NULL,
	created		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	updated		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	names_i		TEXT[],
	names_a		TEXT[],
	names_s		TEXT[],
	jdata		JSONB,
	CONSTRAINT da_datm_meta_pkey PRIMARY KEY (stream_id),
	CONSTRAINT da_datm_meta_unq UNIQUE (node_id, source_id)
);

CREATE TABLE solardatm.da_datm (
	stream_id	UUID NOT NULL,
	ts			TIMESTAMP WITH TIME ZONE NOT NULL,
	posted		TIMESTAMP WITH TIME ZONE NOT NULL,
	data_i		NUMERIC[],
	data_a		NUMERIC[],
	data_s		TEXT[],
	data_t		TEXT[],
	CONSTRAINT da_datm_pkey PRIMARY KEY (stream_id, ts)
);

CREATE OR REPLACE FUNCTION solardatm.migrate_datum(
	node 			BIGINT,
	src 			TEXT,
	start_date		TIMESTAMP WITH TIME ZONE,
	end_date		TIMESTAMP WITH TIME ZONE
	) RETURNS BIGINT LANGUAGE plpgsql VOLATILE AS
$$
DECLARE
	sid 	UUID;

	-- property name arrays
	p		RECORD;
	p_i		TEXT[];
	p_a		TEXT[];
	p_s		TEXT[];

	-- property value arrays
	v_i 	NUMERIC[];
	v_a		NUMERIC[];
	v_s		TEXT[];

	idx		INTEGER;
	d		solardatum.da_datum;
	rcount 	BIGINT := 0;
	curs 	NO SCROLL CURSOR FOR
				SELECT * FROM solardatum.da_datum
				WHERE node_id = node
					AND source_id = src
					AND ts >= start_date
					AND ts < end_date;
BEGIN
	-- get, or create, stream ID
	INSERT INTO solardatm.da_datm_meta (node_id, source_id)
	VALUES (node, src)
	ON CONFLICT (node_id, source_id) DO NOTHING
	RETURNING stream_id, names_i, names_a, names_s
	INTO sid, p_i, p_a, p_s;

	IF NOT FOUND THEN
		SELECT stream_id, names_i, names_a, names_s
		FROM solardatm.da_datm_meta
		WHERE node_id = node AND source_id = src
		INTO sid, p_i, p_a, p_s;
	END IF;

	FOR d IN curs LOOP
		v_i := ARRAY[]::NUMERIC[];
		v_a := ARRAY[]::NUMERIC[];
		v_s := ARRAY[]::TEXT[];

		-- copy instantaneous props
		FOR p IN SELECT * FROM jsonb_each_text(d.jdata_i) LOOP
			idx := COALESCE(array_position(p_i, p.key), 0);
			IF idx < 1 THEN
				UPDATE solardatm.da_datm_meta SET names_i = CASE
						WHEN COALESCE(array_position(names_i, p.key), 0) < 1 THEN array_append(names_i, p.key)
						ELSE names_i
						END
				WHERE stream_id = sid
				RETURNING names_i INTO p_i;
				idx := array_position(p_i, p.key);
			END IF;
			v_i[idx] := p.value::numeric;
		END LOOP;

		-- copy accumulating props
		FOR p IN SELECT * FROM jsonb_each_text(d.jdata_a) LOOP
			idx := COALESCE(array_position(p_a, p.key), 0);
			IF idx < 1 THEN
				UPDATE solardatm.da_datm_meta SET names_a = CASE
						WHEN COALESCE(array_position(names_a, p.key), 0) < 1 THEN array_append(names_a, p.key)
						ELSE names_a
						END
				WHERE stream_id = sid
				RETURNING names_a INTO p_a;
				idx := array_position(p_a, p.key);
			END IF;
			v_a[idx] := p.value::numeric;
		END LOOP;

		-- copy status props
		FOR p IN SELECT * FROM jsonb_each_text(d.jdata_s) LOOP
			idx := COALESCE(array_position(p_s, p.key), 0);
			IF idx < 1 THEN
				UPDATE solardatm.da_datm_meta SET names_s = CASE
						WHEN COALESCE(array_position(names_s, p.key), 0) < 1 THEN array_append(names_s, p.key)
						ELSE names_i
						END
				WHERE stream_id = sid
				RETURNING names_s INTO p_s;
				idx := array_position(p_s, p.key);
			END IF;
			v_s[idx] := p.value;
		END LOOP;

		INSERT INTO solardatm.da_datm (stream_id, ts, posted, data_i, data_a, data_s, data_t)
		VALUES (
			sid
			, d.ts
			, d.posted
			, CASE WHEN COALESCE(array_length(v_i, 1), 0) < 1 THEN NULL ELSE v_i END
			, CASE WHEN COALESCE(array_length(v_a, 1), 0) < 1 THEN NULL ELSE v_a END
			, CASE WHEN COALESCE(array_length(v_s, 1), 0) < 1 THEN NULL ELSE v_s END
			, d.jdata_t
		)
		ON CONFLICT DO NOTHING;

		rcount := rcount + 1;
	END LOOP;

	RETURN rcount;
END;
$$;
