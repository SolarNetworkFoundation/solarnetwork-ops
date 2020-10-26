--DROP SCHEMA IF EXISTS solardatm CASCADE;
CREATE SCHEMA IF NOT EXISTS solardatm;

-- datum stream indirection table
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

-- location datum stream indirection table
CREATE TABLE solardatm.da_loc_datm_meta (
	stream_id	UUID NOT NULL DEFAULT uuid_generate_v4(),
	loc_id		BIGINT NOT NULL,
	source_id	CHARACTER VARYING(64) NOT NULL,
	created		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	updated		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	names_i		TEXT[],
	names_a		TEXT[],
	names_s		TEXT[],
	jdata		JSONB,
	CONSTRAINT da_loc_datm_meta_pkey PRIMARY KEY (stream_id),
	CONSTRAINT da_loc_datm_meta_unq UNIQUE (loc_id, source_id)
);

-- datum table
CREATE TABLE solardatm.da_datm (
	stream_id	UUID NOT NULL,
	ts			TIMESTAMP WITH TIME ZONE NOT NULL,
	received	TIMESTAMP WITH TIME ZONE NOT NULL,
	data_i		NUMERIC[],
	data_a		NUMERIC[],
	data_s		TEXT[],
	data_t		TEXT[],
	CONSTRAINT da_datm_pkey PRIMARY KEY (stream_id, ts)
);

CREATE UNIQUE INDEX IF NOT EXISTS da_datm_unq_reverse ON solardatm.da_datm (stream_id, ts DESC);

/**
 * Migrate a JSON datum into the `solardatm.da_datm` table.
 *
 * This function accepts the "current" property name arrays as an optimisation when migrating
 * multiple rows of data. If the given datum has properties that are not found in any of the
 * given name arrays, the name will be added and then the associated `solardatm.da_datm_meta`
 * column updated to match. The name arrays are declared as `INOUT` so that the updated values
 * can be saved and used again, helping reduce the amount of updates needed to the
 * `solardatm.da_datm_meta` table.
 *
 * @param sid 		the stream ID to use
 * @param ddate 	datum timestamp
 * @param src		datum source ID
 * @param rdate		datum received date
 * @param jdata_i	instantaneous JSON properties
 * @param jdata_a	accumulating JSON properties
 * @param jdata_s	status JSON properties
 * @param jdata_t	tag properties
 * @param p_i		the stream instantaneous property names; possibly appeneded to
 * @param p_a 		the stream accumulating property names; possible appended to
 * @param p_s		the stream status property names; possible appended to
 */
CREATE OR REPLACE FUNCTION solardatm.migrate_datum_json(
		sid 			UUID,
		ddate			TIMESTAMP WITH TIME ZONE,
		src				TEXT,
		rdate			TIMESTAMP WITH TIME ZONE,
		jdata_i			JSONB,
		jdata_a			JSONB,
		jdata_s			JSONB,
		jdata_t			TEXT[],
		INOUT p_i 		TEXT[],
		INOUT p_a 		TEXT[],
		INOUT p_s 		TEXT[],
		OUT   is_ins 	BOOLEAN
	) LANGUAGE plpgsql VOLATILE AS
$$
DECLARE
	-- property name arrays
	p		RECORD;

	-- property value arrays
	v_i 	NUMERIC[];
	v_a		NUMERIC[];
	v_s		TEXT[];

	idx		INTEGER;
BEGIN
	-- copy instantaneous props
	FOR p IN SELECT * FROM jsonb_each_text(jdata_i) LOOP
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
		-- catch cast exceptions: saw example of 'Infinity' string
		BEGIN
			v_i[idx] := p.value::numeric;
		EXCEPTION WHEN others THEN
			RAISE WARNING 'JSON value not numeric: stream %, source %, ts %, i.key %, i.value %',
				sid, src, ddate, p.key, p.value;
			v_i[idx] := NULL;
		END;
	END LOOP;

	-- copy accumulating props
	FOR p IN SELECT * FROM jsonb_each_text(jdata_a) LOOP
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
		BEGIN
			v_a[idx] := p.value::numeric;
		EXCEPTION WHEN others THEN
			RAISE WARNING 'JSON value not numeric: stream %, source %, ts %, i.key %, i.value %',
				sid, src, ddate, p.key, p.value;
			v_i[idx] := NULL;
		END;
	END LOOP;

	-- copy status props
	FOR p IN SELECT * FROM jsonb_each_text(jdata_s) LOOP
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

	INSERT INTO solardatm.da_datm (stream_id, ts, received, data_i, data_a, data_s, data_t)
	VALUES (
		sid
		, ddate
		, rdate
		, CASE WHEN COALESCE(array_length(v_i, 1), 0) < 1 THEN NULL ELSE v_i END
		, CASE WHEN COALESCE(array_length(v_a, 1), 0) < 1 THEN NULL ELSE v_a END
		, CASE WHEN COALESCE(array_length(v_s, 1), 0) < 1 THEN NULL ELSE v_s END
		, jdata_t
	)
	ON CONFLICT (stream_id, ts) DO UPDATE
	SET received = EXCLUDED.received,
		data_i = EXCLUDED.data_i,
		data_a = EXCLUDED.data_a,
		data_s = EXCLUDED.data_s,
		data_t = EXCLUDED.data_t
	RETURNING (xmax = 0)
	INTO is_ins;
END;
$$;


/**
 * Migrate a JSON location datum into the `solardatm.da_datm` table.
 *
 * This function accepts the "current" property name arrays as an optimisation when migrating
 * multiple rows of data. If the given datum has properties that are not found in any of the
 * given name arrays, the name will be added and then the associated `solardatm.da_datm_meta`
 * column updated to match. The name arrays are declared as `INOUT` so that the updated values
 * can be saved and used again, helping reduce the amount of updates needed to the
 * `solardatm.da_datm_meta` table.
 *
 * @param sid 		the stream ID to use
 * @param ddate 	datum timestamp
 * @param src		datum source ID
 * @param rdate		datum received date
 * @param jdata_i	instantaneous JSON properties
 * @param jdata_a	accumulating JSON properties
 * @param jdata_s	status JSON properties
 * @param jdata_t	tag properties
 * @param p_i		the stream instantaneous property names; possibly appeneded to
 * @param p_a 		the stream accumulating property names; possible appended to
 * @param p_s		the stream status property names; possible appended to
 */
CREATE OR REPLACE FUNCTION solardatm.migrate_loc_datum_json(
		sid 			UUID,
		ddate			TIMESTAMP WITH TIME ZONE,
		src				TEXT,
		rdate			TIMESTAMP WITH TIME ZONE,
		jdata_i			JSONB,
		jdata_a			JSONB,
		jdata_s			JSONB,
		jdata_t			TEXT[],
		INOUT p_i 		TEXT[],
		INOUT p_a 		TEXT[],
		INOUT p_s 		TEXT[],
		OUT   is_ins 	BOOLEAN
	) LANGUAGE plpgsql VOLATILE AS
$$
DECLARE
	-- property name arrays
	p		RECORD;

	-- property value arrays
	v_i 	NUMERIC[];
	v_a		NUMERIC[];
	v_s		TEXT[];

	idx		INTEGER;
BEGIN
	-- copy instantaneous props
	FOR p IN SELECT * FROM jsonb_each_text(jdata_i) LOOP
		idx := COALESCE(array_position(p_i, p.key), 0);
		IF idx < 1 THEN
			UPDATE solardatm.da_loc_datm_meta SET names_i = CASE
					WHEN COALESCE(array_position(names_i, p.key), 0) < 1 THEN array_append(names_i, p.key)
					ELSE names_i
					END
			WHERE stream_id = sid
			RETURNING names_i INTO p_i;
			idx := array_position(p_i, p.key);
		END IF;
		-- catch cast exceptions: saw example of 'Infinity' string
		BEGIN
			v_i[idx] := p.value::numeric;
		EXCEPTION WHEN others THEN
			RAISE WARNING 'JSON value not numeric: stream %, source %, ts %, i.key %, i.value %',
				sid, src, ddate, p.key, p.value;
			v_i[idx] := NULL;
		END;
	END LOOP;

	-- copy accumulating props
	FOR p IN SELECT * FROM jsonb_each_text(jdata_a) LOOP
		idx := COALESCE(array_position(p_a, p.key), 0);
		IF idx < 1 THEN
			UPDATE solardatm.da_loc_datm_meta SET names_a = CASE
					WHEN COALESCE(array_position(names_a, p.key), 0) < 1 THEN array_append(names_a, p.key)
					ELSE names_a
					END
			WHERE stream_id = sid
			RETURNING names_a INTO p_a;
			idx := array_position(p_a, p.key);
		END IF;
		BEGIN
			v_a[idx] := p.value::numeric;
		EXCEPTION WHEN others THEN
			RAISE WARNING 'JSON value not numeric: stream %, source %, ts %, i.key %, i.value %',
				sid, src, ddate, p.key, p.value;
			v_i[idx] := NULL;
		END;
	END LOOP;

	-- copy status props
	FOR p IN SELECT * FROM jsonb_each_text(jdata_s) LOOP
		idx := COALESCE(array_position(p_s, p.key), 0);
		IF idx < 1 THEN
			UPDATE solardatm.da_loc_datm_meta SET names_s = CASE
					WHEN COALESCE(array_position(names_s, p.key), 0) < 1 THEN array_append(names_s, p.key)
					ELSE names_i
					END
			WHERE stream_id = sid
			RETURNING names_s INTO p_s;
			idx := array_position(p_s, p.key);
		END IF;
		v_s[idx] := p.value;
	END LOOP;

	INSERT INTO solardatm.da_datm (stream_id, ts, received, data_i, data_a, data_s, data_t)
	VALUES (
		sid
		, ddate
		, rdate
		, CASE WHEN COALESCE(array_length(v_i, 1), 0) < 1 THEN NULL ELSE v_i END
		, CASE WHEN COALESCE(array_length(v_a, 1), 0) < 1 THEN NULL ELSE v_a END
		, CASE WHEN COALESCE(array_length(v_s, 1), 0) < 1 THEN NULL ELSE v_s END
		, jdata_t
	)
	ON CONFLICT (stream_id, ts) DO UPDATE
	SET received = EXCLUDED.received,
		data_i = EXCLUDED.data_i,
		data_a = EXCLUDED.data_a,
		data_s = EXCLUDED.data_s,
		data_t = EXCLUDED.data_t
	RETURNING (xmax = 0)
	INTO is_ins;
END;
$$;


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
	p_i		TEXT[];
	p_a		TEXT[];
	p_s		TEXT[];

	d		solardatum.da_datum;
	rcount 	BIGINT := 0;
	is_ins	BOOLEAN;
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

	OPEN curs;
	LOOP
		FETCH curs INTO d;
		EXIT WHEN NOT FOUND;
		SELECT * FROM solardatm.migrate_datum_json(sid, d.ts, d.source_id, d.posted,
						d.jdata_i, d.jdata_a, d.jdata_s, d.jdata_t, p_i, p_a, p_s)
		INTO p_i, p_a, p_s, is_ins;
		IF is_ins THEN
			rcount := rcount + 1;
		END IF;
	END LOOP;
	CLOSE curs;

	RETURN rcount;
END;
$$;


CREATE OR REPLACE FUNCTION solardatm.migrate_loc_datum(
	loc 			BIGINT,
	src 			TEXT,
	start_date		TIMESTAMP WITH TIME ZONE,
	end_date		TIMESTAMP WITH TIME ZONE
	) RETURNS BIGINT LANGUAGE plpgsql VOLATILE AS
$$
DECLARE
	sid 	UUID;

	-- property name arrays
	p_i		TEXT[];
	p_a		TEXT[];
	p_s		TEXT[];

	d		solardatum.da_loc_datum;
	rcount 	BIGINT := 0;
	is_ins  BOOLEAN;
	curs 	NO SCROLL CURSOR FOR
				SELECT * FROM solardatum.da_loc_datum
				WHERE loc_id = loc
					AND source_id = src
					AND ts >= start_date
					AND ts < end_date;
BEGIN
	-- get, or create, stream ID
	INSERT INTO solardatm.da_loc_datm_meta (loc_id, source_id)
	VALUES (loc, src)
	ON CONFLICT (loc_id, source_id) DO NOTHING
	RETURNING stream_id, names_i, names_a, names_s
	INTO sid, p_i, p_a, p_s;

	IF NOT FOUND THEN
		SELECT stream_id, names_i, names_a, names_s
		FROM solardatm.da_loc_datm_meta
		WHERE loc_id = loc AND source_id = src
		INTO sid, p_i, p_a, p_s;
	END IF;

	OPEN curs;
	LOOP
		FETCH curs INTO d;
		EXIT WHEN NOT FOUND;
		SELECT * FROM solardatm.migrate_loc_datum_json(sid, d.ts, d.source_id, d.posted,
						d.jdata_i, d.jdata_a, d.jdata_s, d.jdata_t, p_i, p_a, p_s)
		INTO p_i, p_a, p_s, is_ins;
		IF is_ins THEN
			rcount := rcount + 1;
		END IF;
	END LOOP;
	CLOSE curs;

	RETURN rcount;
END;
$$;


/**
 * Add or update a datum record. The data is stored in the `solardatm.da_datm` table.
 *
 * @param node 	the node ID
 * @param src 	the source ID
 * @param ts 	the datum timestamp
 * @param rdate the date the datum was received by SolarNetwork
 * @param jdata the datum JSON object (with jdata_i, jdata_a, jdata_s, and jdata_t properties)
 * @param track if `TRUE` then also insert results of `solardatum.calculate_stale_datum()`
 *                     into the `solaragg.agg_stale_datum` table and call
 *                     `solardatum.update_datum_range_dates()` to keep the
 *                     `solardatum.da_datum_range` table up-to-date
 */
CREATE OR REPLACE FUNCTION solardatm.store_datum(
	node 			BIGINT,
	src 			TEXT,
	ddate 			TIMESTAMP WITH TIME ZONE,
	rdate 			TIMESTAMP WITH TIME ZONE,
	jdata 			TEXT,
	track 			BOOLEAN DEFAULT TRUE)
  RETURNS void LANGUAGE plpgsql VOLATILE AS
$$
DECLARE
	ts_crea 			TIMESTAMP WITH TIME ZONE 	:= COALESCE(ddate, now());
	ts_recv 			TIMESTAMP WITH TIME ZONE	:= COALESCE(rdate, now());
	jdata_json 			JSONB 						:= jdata::jsonb;
	jdata_prop_count 	INTEGER 					:= solardatum.datum_prop_count(jdata_json);
	ts_recv_hour 		TIMESTAMP WITH TIME ZONE 	:= date_trunc('hour', ts_recv);
	is_insert 			BOOLEAN 					:= false;

	sid 	UUID;

	-- property name arrays
	p_i		TEXT[];
	p_a		TEXT[];
	p_s		TEXT[];
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

	SELECT * FROM solardatm.migrate_datum_json(sid, ts_crea, src, ts_recv,
					jdata_json->jdata_i,
					jdata_json->jdata_a,
					jdata_json->jdata_s,
					solarcommon.json_array_to_text_array(jdata_json->jdata_t),
					p_i, p_a, p_s)
	INTO p_i, p_a, p_s, is_insert;

	/*
	INSERT INTO solaragg.aud_datum_hourly (
		ts_start, node_id, source_id, datum_count, prop_count)
	VALUES (ts_post_hour, node, src, 1, jdata_prop_count)
	ON CONFLICT (node_id, ts_start, source_id) DO UPDATE
	SET datum_count = aud_datum_hourly.datum_count + (CASE is_insert WHEN TRUE THEN 1 ELSE 0 END),
		prop_count = aud_datum_hourly.prop_count + EXCLUDED.prop_count;

	IF track THEN
		INSERT INTO solaragg.agg_stale_datum (agg_kind, node_id, ts_start, source_id)
		SELECT 'h' AS agg_kind, node_id, ts_start, source_id
		FROM solardatum.calculate_stale_datum(node, src, cdate)
		ON CONFLICT (agg_kind, node_id, ts_start, source_id) DO NOTHING;

		IF is_insert THEN
			PERFORM solardatum.update_datum_range_dates(node, src, cdate);
		END IF;
	END IF;
	*/
END;
$$;


/**
 * Add or update a location datum record. The data is stored in the `solardatm.da_datm` table.
 *
 * @param loc 	the location ID
 * @param src 	the source ID
 * @param ts 	the datum timestamp
 * @param rdate the date the datum was received by SolarNetwork
 * @param jdata the datum JSON object (with jdata_i, jdata_a, jdata_s, and jdata_t properties)
 * @param track if `TRUE` then also insert results of `solardatum.calculate_stale_datum()`
 *                     into the `solaragg.agg_stale_datum` table and call
 *                     `solardatum.update_datum_range_dates()` to keep the
 *                     `solardatum.da_datum_range` table up-to-date
 */
CREATE OR REPLACE FUNCTION solardatm.store_loc_datum(
	loc 			BIGINT,
	src 			TEXT,
	ddate 			TIMESTAMP WITH TIME ZONE,
	rdate 			TIMESTAMP WITH TIME ZONE,
	jdata 			TEXT,
	track 			BOOLEAN DEFAULT TRUE)
  RETURNS void LANGUAGE plpgsql VOLATILE AS
$$
DECLARE
	ts_crea 			TIMESTAMP WITH TIME ZONE 	:= COALESCE(ddate, now());
	ts_recv 			TIMESTAMP WITH TIME ZONE	:= COALESCE(rdate, now());
	jdata_json 			JSONB 						:= jdata::jsonb;
	jdata_prop_count 	INTEGER 					:= solardatum.datum_prop_count(jdata_json);
	ts_recv_hour 		TIMESTAMP WITH TIME ZONE 	:= date_trunc('hour', ts_recv);
	is_insert 			BOOLEAN 					:= false;

	sid 	UUID;

	-- property name arrays
	p_i		TEXT[];
	p_a		TEXT[];
	p_s		TEXT[];
BEGIN
	-- get, or create, stream ID
	INSERT INTO solardatm.da_loc_datm_meta (loc_id, source_id)
	VALUES (loc, src)
	ON CONFLICT (loc_id, source_id) DO NOTHING
	RETURNING stream_id, names_i, names_a, names_s
	INTO sid, p_i, p_a, p_s;

	IF NOT FOUND THEN
		SELECT stream_id, names_i, names_a, names_s
		FROM solardatm.da_loc_datm_meta
		WHERE loc_id = loc AND source_id = src
		INTO sid, p_i, p_a, p_s;
	END IF;

	SELECT * FROM solardatm.migrate_loc_datum_json(sid, ts_crea, src, ts_recv,
					jdata_json->jdata_i,
					jdata_json->jdata_a,
					jdata_json->jdata_s,
					solarcommon.json_array_to_text_array(jdata_json->jdata_t),
					p_i, p_a, p_s)
	INTO p_i, p_a, p_s, is_insert;

	/*
	INSERT INTO solaragg.aud_datum_hourly (
		ts_start, loc_id, source_id, datum_count, prop_count)
	VALUES (ts_post_hour, loc, src, 1, jdata_prop_count)
	ON CONFLICT (loc_id, ts_start, source_id) DO UPDATE
	SET datum_count = aud_datum_hourly.datum_count + (CASE is_insert WHEN TRUE THEN 1 ELSE 0 END),
		prop_count = aud_datum_hourly.prop_count + EXCLUDED.prop_count;

	IF track THEN
		INSERT INTO solaragg.agg_stale_datum (agg_kind, loc_id, ts_start, source_id)
		SELECT 'h' AS agg_kind, loc_id, ts_start, source_id
		FROM solardatum.calculate_stale_datum(loc, src, cdate)
		ON CONFLICT (agg_kind, loc_id, ts_start, source_id) DO NOTHING;

		IF is_insert THEN
			PERFORM solardatum.update_datum_range_dates(loc, src, cdate);
		END IF;
	END IF;
	*/
END;
$$;
