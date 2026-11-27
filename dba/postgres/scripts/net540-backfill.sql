/*
 * NET-540: install the net540_backfill schema, which net540-backfill.sh uses to fill
 * solardatm.agg_datm_15m for the hours before step 1's boundary (plan section 12).
 *
 * Run by `net540-backfill.sh install`, never by hand, with these psql variables:
 *
 *   script_version  the script's version
 *   range_start     the first hour to fill, normally '2002-07-12 00:00:00+00' (the first seeded
 *                   15 minute chunk)
 *   range_end       step 1's boundary before the backfill moves it: the hours from here on were
 *                   computed with their 15 minute rows
 *   clock_error     true to fill also, last, the hours before range_start and from range_end on
 *                   that have an hourly row and no 15 minute row (nodes with a wrong clock), as
 *                   chunks 1001 and 1002
 *
 * Everything the backfill keeps is in this schema, and nothing else is created: dropping the
 * schema (`net540-backfill.sh drop`) removes it all. It does not change any table or function
 * of the product. What the backfill writes to product tables, it writes through the procedures
 * here: 15 minute rows into solardatm.agg_datm_15m (insert only, ON CONFLICT DO NOTHING), step
 * 1's boundary in solardatm.agg_datm_15m_setting (once, to -infinity), and, in the slice rewrite
 * mode only, the property arrays of raw datum stored as array slices in solardatm.da_datm.
 *
 * Every read of a hypertable goes stream by stream through its primary key, with the stream and
 * the time bounds as literals, so that chunks are excluded when the statement is planned.
 */

\set ON_ERROR_STOP on
SET timezone = 'UTC';

CREATE SCHEMA net540_backfill;
COMMENT ON SCHEMA net540_backfill IS
	'NET-540 backfill of solardatm.agg_datm_15m: settings, progress and lists. Drop it when done.';

-- ---------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------

/* What the backfill was installed for, in one row. */
CREATE TABLE net540_backfill.setting (
	id					BOOLEAN NOT NULL DEFAULT TRUE PRIMARY KEY CHECK (id),
	installed			TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
	script_version		INTEGER NOT NULL,
	-- the hours to fill: [range_start, range_end)
	range_start			TIMESTAMP WITH TIME ZONE NOT NULL,
	range_end			TIMESTAMP WITH TIME ZONE NOT NULL,
	clock_error			BOOLEAN NOT NULL,
	-- the boundary phase
	boundary_moved		TIMESTAMP WITH TIME ZONE,
	boundary_waited		TIMESTAMP WITH TIME ZONE
);

/*
 * stop asks running workers to stop after the unit they are on. dry_plan is what the dry run
 * units were planned for (chunk/streams/seed), to tell whether a dry run carries on. fail_run
 * counts the units in a row that failed in every hour (work() stops at a limit); fill resets it.
 */
CREATE TABLE net540_backfill.control (
	id					BOOLEAN NOT NULL DEFAULT TRUE PRIMARY KEY CHECK (id),
	stop				BOOLEAN NOT NULL DEFAULT FALSE,
	changed				TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
	dry_plan			TEXT,
	fail_run			INTEGER NOT NULL DEFAULT 0
);
INSERT INTO net540_backfill.control DEFAULT VALUES;

/*
 * The time ranges to fill, one for each 15 minute chunk (or gap between chunks) within the
 * range, worked through in chunk_no order. The status goes
 *   pending -> planning -> filling -> filled -> checked -> done
 * or to failed when the check finds an hour left without its 15 minute rows.
 */
CREATE TABLE net540_backfill.chunk (
	chunk_no			INTEGER NOT NULL PRIMARY KEY,
	range_start			TIMESTAMP WITH TIME ZONE NOT NULL,
	range_end			TIMESTAMP WITH TIME ZONE NOT NULL,
	chunk_table			TEXT,
	index_name			TEXT,
	status				TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
							'pending', 'planning', 'filling', 'filled', 'checked', 'done', 'failed')),
	plan_pos			UUID,
	planned				TIMESTAMP WITH TIME ZONE,
	filled				TIMESTAMP WITH TIME ZONE,
	vacuumed			TIMESTAMP WITH TIME ZONE,
	checked				TIMESTAMP WITH TIME ZONE,
	reindexed			TIMESTAMP WITH TIME ZONE,
	units				INTEGER,
	unfilled			JSONB,
	index_bytes_filled	BIGINT,
	index_bytes_packed	BIGINT,
	rows_15m			BIGINT,
	CHECK (range_start < range_end)
);

/*
 * Work to do: one stream for one UTC day (clipped to its chunk), the hours with an hourly row
 * and no 15 minute row when planned. A unit is deleted in the transaction that fills it, so a
 * unit is either done, with everything it wrote, or still here.
 */
CREATE TABLE net540_backfill.unit (
	dry					BOOLEAN NOT NULL,
	chunk_no			INTEGER NOT NULL,
	day					TIMESTAMP WITH TIME ZONE NOT NULL,
	stream_id			UUID NOT NULL,
	day_end				TIMESTAMP WITH TIME ZONE NOT NULL,
	hours				INTEGER NOT NULL,
	PRIMARY KEY (dry, chunk_no, day, stream_id)
);

/*
 * What each unit did, written in the transaction that did it. pass counts the times the same
 * unit was done: a chunk done again (retry), or a day planned again because hours were left
 * out (stale, slice) or failed. exact: done as a dry run or a trial does it (see fill_unit()).
 */
CREATE TABLE net540_backfill.unit_log (
	dry					BOOLEAN NOT NULL,
	chunk_no			INTEGER NOT NULL,
	day					TIMESTAMP WITH TIME ZONE NOT NULL,
	stream_id			UUID NOT NULL,
	pass				SMALLINT NOT NULL,
	worker				SMALLINT NOT NULL,
	exact				BOOLEAN NOT NULL,
	done				TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT clock_timestamp(),
	-- hours computed, 15 minute rows the rollup gave, and rows inserted
	hours				INTEGER NOT NULL,
	slots				INTEGER NOT NULL,
	rows_15m			INTEGER NOT NULL,
	-- the stored hour against today's: counted only
	n_same				INTEGER NOT NULL,
	n_text_only			INTEGER NOT NULL,
	n_pad				INTEGER NOT NULL,
	n_round9			INTEGER NOT NULL,
	n_noise				INTEGER NOT NULL,
	n_no_raw			INTEGER NOT NULL,
	-- listed in diff
	n_read_end			INTEGER NOT NULL,
	n_compact			INTEGER NOT NULL,
	n_other				INTEGER NOT NULL,
	n_stored_only		INTEGER NOT NULL,
	-- hours left out: a pending stale row, or (count mode) a slice the rollup would read
	n_stale				INTEGER NOT NULL,
	n_slice				INTEGER NOT NULL,
	-- hours computed whose rollup gives an hour row but no 15 minute row (nothing to insert)
	n_no_slots			INTEGER NOT NULL,
	-- hours that raised an error (listed in failed), when the unit was done hour by hour
	n_error				INTEGER NOT NULL,
	-- exact (dry run or trial): hours whose datum before the window were asked for
	n_prefix			INTEGER NOT NULL,
	slices_found		INTEGER NOT NULL,
	slices_rewritten	INTEGER NOT NULL,
	ms_probe			REAL NOT NULL,
	ms_compute			REAL NOT NULL,
	PRIMARY KEY (dry, chunk_no, day, stream_id, pass)
);
-- for status: the units done in the last hour
CREATE INDEX unit_log_done_idx ON net540_backfill.unit_log (done);

/*
 * The raw datum of each stream already looked at for slices by the full fill: [probed_from,
 * probed_to]. A unit of the full fill reads the datum its hours' rollups may read, back to a
 * year before the day, and skips the part already looked at. A dry run or a trial reads only
 * what its own hours read, and leaves the range alone (NULL for a stream only they did). The row
 * also keeps two units of one stream apart.
 */
CREATE TABLE net540_backfill.probe (
	stream_id			UUID NOT NULL PRIMARY KEY,
	probed_from			TIMESTAMP WITH TIME ZONE,
	probed_to			TIMESTAMP WITH TIME ZONE
);

/*
 * Raw datum found stored as array slices (a lower bound above 1). state: found (still stored
 * so), rewritten (filled from position 1, old_* as stored before), gone (no longer a slice when
 * it was to be rewritten).
 */
CREATE TABLE net540_backfill.slice (
	stream_id			UUID NOT NULL,
	ts					TIMESTAMP WITH TIME ZONE NOT NULL,
	lower_i				INTEGER,
	lower_a				INTEGER,
	lower_s				INTEGER,
	state				TEXT NOT NULL DEFAULT 'found' CHECK (state IN ('found', 'rewritten', 'gone')),
	found				TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
	rewritten			TIMESTAMP WITH TIME ZONE,
	old_i				NUMERIC[],
	old_a				NUMERIC[],
	old_s				TEXT[],
	PRIMARY KEY (stream_id, ts)
);

/* Hours left out, and why: slice (count mode) or stale (live processing will compute them). */
CREATE TABLE net540_backfill.skipped (
	dry					BOOLEAN NOT NULL,
	stream_id			UUID NOT NULL,
	ts_start			TIMESTAMP WITH TIME ZONE NOT NULL,
	reason				TEXT NOT NULL CHECK (reason IN ('slice', 'stale')),
	chunk_no			INTEGER NOT NULL,
	at					TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
	PRIMARY KEY (dry, stream_id, ts_start)
);

/*
 * The hours whose stored row really differs from today's rollup (D18): verdict read_end,
 * compact or other as net540-history-analyze.py classifies them, with its column codes in
 * cols, or stored_only (a stored row, raw datum in the hour, and no row today). Reprocessing
 * one means marking (stream_id, ts_start, 'h') stale. stored_md5 is md5 of the stored row's
 * text when compared, to tell whether it has changed since.
 */
CREATE TABLE net540_backfill.diff (
	dry					BOOLEAN NOT NULL,
	stream_id			UUID NOT NULL,
	ts_start			TIMESTAMP WITH TIME ZONE NOT NULL,
	verdict				TEXT NOT NULL,
	cols				TEXT,
	kind				CHARACTER(1),
	stored_md5			TEXT NOT NULL,
	chunk_no			INTEGER NOT NULL,
	compared			TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
	PRIMARY KEY (dry, stream_id, ts_start)
);

/*
 * Hours left unfilled by an error of their own: a unit that raised an error its data can cause
 * (see error_kind()) is done again hour by hour, and each hour that raises one is listed here,
 * with its unit's chunk and day. The other hours are filled, and the unit is done. A row is
 * deleted when its hour is done without an error (a later unit of the same hours, after retry or
 * in the full fill after a trial), and by check_chunk() once the hour has a 15 minute row or no
 * hourly row.
 */
CREATE TABLE net540_backfill.failed (
	dry					BOOLEAN NOT NULL,
	stream_id			UUID NOT NULL,
	ts_start			TIMESTAMP WITH TIME ZONE NOT NULL,
	chunk_no			INTEGER NOT NULL,
	day					TIMESTAMP WITH TIME ZONE NOT NULL,
	at					TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT clock_timestamp(),
	sqlstate			TEXT NOT NULL,
	message				TEXT,
	PRIMARY KEY (dry, stream_id, ts_start)
);

/*
 * The check: every hour of a chunk with an hourly row and no 15 minute row, with the reason
 * (written by check_chunk(), replacing the chunk's earlier rows):
 *   off_hour  the row does not start on the UTC hour: stale processing never computes it
 *   no_raw    no raw datum in the hour (expired or deleted): nothing to compute
 *   no_today  raw datum, but today's rollup gives no row (listed in diff as stored_only, unless
 *             the stored row holds only zeros and NULLs, which counts as pad)
 *   no_slots  raw datum, and today's rollup gives an hour row but no 15 minute row: stale
 *             processing would store none either (a datum holding nothing in the hour, say, and
 *             a next one whose accumulating array holds only NULL)
 *   stale     a stale row is pending: live processing will compute it
 *   slice     left out in count mode: the rollup would read a slice
 *   error     the hour raised an error when filled (see failed); not a failure of the chunk
 *   missing   none of these: the backfill should have filled it; the chunk fails
 */
CREATE TABLE net540_backfill.unfilled (
	chunk_no			INTEGER NOT NULL,
	stream_id			UUID NOT NULL,
	ts_start			TIMESTAMP WITH TIME ZONE NOT NULL,
	reason				TEXT NOT NULL,
	PRIMARY KEY (chunk_no, stream_id, ts_start)
);

-- ---------------------------------------------------------------------------------------------
-- Comparison: net540-history-analyze.py's classify(), in SQL
-- ---------------------------------------------------------------------------------------------

CREATE TYPE net540_backfill.verdict AS (verdict TEXT, cols TEXT);

/* same_or_r9(): 'eq', 'round9', 'near9', 'noise', or NULL, for two numbers. */
CREATE FUNCTION net540_backfill.same_or_r9(s NUMERIC, t NUMERIC) RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
	d NUMERIC;
BEGIN
	IF s IS NULL AND t IS NULL THEN
		RETURN 'eq';
	ELSIF s IS NULL OR t IS NULL THEN
		RETURN NULL;
	ELSIF s = t THEN
		RETURN 'eq';
	ELSIF s = round(t, 9) THEN
		RETURN 'round9';
	END IF;
	d := abs(s - t);
	-- Decimal's exponent of the stored value's text is minus its scale
	IF scale(s) <= 9 AND d <= 0.000000001 THEN
		RETURN 'near9';
	ELSIF d / GREATEST(abs(s), abs(t)) <= 0.000000000001 THEN
		RETURN 'noise';
	END IF;
	RETURN NULL;
END
$$;

/* same_or_r9() for two JSON elements: numbers as above, anything else equal or not. */
CREATE FUNCTION net540_backfill.same_or_r9_j(s JSONB, t JSONB) RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
	IF s IS NULL OR jsonb_typeof(s) = 'null' THEN
		RETURN CASE WHEN t IS NULL OR jsonb_typeof(t) = 'null' THEN 'eq' END;
	ELSIF t IS NULL OR jsonb_typeof(t) = 'null' THEN
		RETURN NULL;
	ELSIF jsonb_typeof(s) = 'number' AND jsonb_typeof(t) = 'number' THEN
		RETURN net540_backfill.same_or_r9((s #>> '{}')::NUMERIC, (t #>> '{}')::NUMERIC);
	ELSIF s = t THEN
		RETURN 'eq';
	END IF;
	RETURN NULL;
END
$$;

/* worse(): the worse of two codes, eq < noise < round9 < near9. */
CREATE FUNCTION net540_backfill.worse(a TEXT, b TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
	SELECT CASE
		WHEN array_position(ARRAY['eq', 'noise', 'round9', 'near9'], a)
			>= array_position(ARRAY['eq', 'noise', 'round9', 'near9'], b) THEN a
		ELSE b
		END
$$;

/* cmp_lists(): element by element, recursing into nested arrays; NULL if they differ. */
CREATE FUNCTION net540_backfill.cmp_lists(s JSONB, t JSONB) RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
	n		INTEGER;
	r		TEXT;
	w		TEXT := 'eq';
BEGIN
	IF jsonb_typeof(s) = 'array' OR jsonb_typeof(t) = 'array' THEN
		IF jsonb_typeof(s) IS DISTINCT FROM 'array' OR jsonb_typeof(t) IS DISTINCT FROM 'array' THEN
			RETURN NULL;
		END IF;
		n := jsonb_array_length(s);
		IF n <> jsonb_array_length(t) THEN
			RETURN NULL;
		END IF;
		FOR i IN 0 .. n - 1 LOOP
			r := net540_backfill.cmp_lists(s -> i, t -> i);
			IF r IS NULL THEN
				RETURN NULL;
			ELSIF r <> 'eq' THEN
				w := net540_backfill.worse(w, r);
			END IF;
		END LOOP;
		RETURN w;
	END IF;
	RETURN net540_backfill.same_or_r9_j(s, t);
END
$$;

/* absent(): an element today's rollup writes for a property with no value in the hour. */
CREATE FUNCTION net540_backfill.absent(x JSONB, zero_ok BOOLEAN) RETURNS BOOLEAN
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
	f		JSONB;
BEGIN
	IF jsonb_typeof(x) = 'array' THEN
		IF jsonb_array_length(x) = 0 THEN
			RETURN FALSE;
		END IF;
		f := x -> 0;
		IF NOT (jsonb_typeof(f) = 'null' OR (jsonb_typeof(f) = 'number' AND (f #>> '{}')::NUMERIC = 0)) THEN
			RETURN FALSE;
		END IF;
		FOR i IN 1 .. jsonb_array_length(x) - 1 LOOP
			IF jsonb_typeof(x -> i) <> 'null' THEN
				RETURN FALSE;
			END IF;
		END LOOP;
		RETURN TRUE;
	END IF;
	RETURN x IS NULL OR jsonb_typeof(x) = 'null'
		OR (zero_ok AND jsonb_typeof(x) = 'number' AND (x #>> '{}')::NUMERIC = 0);
END
$$;

/* column(): how one array column of the stored row relates to today's. */
CREATE FUNCTION net540_backfill.column_code(s JSONB, t JSONB, zero_ok BOOLEAN) RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
	s2		JSONB := COALESCE(s, '[]'::JSONB);
	t2		JSONB := COALESCE(t, '[]'::JSONB);
	ns		INTEGER;
	nt		INTEGER;
	r		TEXT;
	ok		BOOLEAN;
	tc		JSONB;
BEGIN
	IF s IS NULL AND t IS NULL THEN
		RETURN 'eq';
	END IF;
	r := net540_backfill.cmp_lists(s2, t2);
	IF r IS NOT NULL THEN
		RETURN r;
	END IF;
	ns := jsonb_array_length(s2);
	nt := jsonb_array_length(t2);
	-- padding: today longer by absent elements only
	IF nt > ns THEN
		ok := TRUE;
		FOR i IN ns .. nt - 1 LOOP
			IF NOT net540_backfill.absent(t2 -> i, zero_ok) THEN
				ok := FALSE;
				EXIT;
			END IF;
		END LOOP;
		IF ok THEN
			SELECT COALESCE(jsonb_agg(e ORDER BY o), '[]'::JSONB) INTO tc
			FROM jsonb_array_elements(t2) WITH ORDINALITY AS a(e, o)
			WHERE o <= ns;
			r := net540_backfill.cmp_lists(s2, tc);
			IF r IS NOT NULL THEN
				RETURN CASE WHEN r = 'eq' THEN 'pad' ELSE 'pad+' || r END;
			END IF;
		END IF;
	END IF;
	-- compaction: stored is today without its absent elements
	SELECT COALESCE(jsonb_agg(e ORDER BY o), '[]'::JSONB) INTO tc
	FROM jsonb_array_elements(t2) WITH ORDINALITY AS a(e, o)
	WHERE NOT net540_backfill.absent(e, FALSE);
	IF jsonb_array_length(tc) < nt THEN
		r := net540_backfill.cmp_lists(s2, tc);
		IF r IS NOT NULL THEN
			RETURN CASE WHEN r = 'eq' THEN 'compact' ELSE 'compact+' || r END;
		END IF;
	END IF;
	RETURN 'other';
END
$$;

/*
 * read_end(): readings [diff, start, end] that all compare, or have the same start and another
 * end, each side's difference its own end less its own start. 'short', 'long', 'mixed' (the
 * stored difference against today's) or NULL.
 */
CREATE FUNCTION net540_backfill.read_end(s JSONB, t JSONB) RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
	ns		INTEGER;
	nt		INTEGER;
	a		JSONB;
	b		JSONB;
	a0 NUMERIC; a1 NUMERIC; a2 NUMERIC;
	b0 NUMERIC; b1 NUMERIC; b2 NUMERIC;
	short	BOOLEAN := FALSE;
	long	BOOLEAN := FALSE;
BEGIN
	IF s IS NULL OR t IS NULL THEN
		RETURN NULL;
	END IF;
	ns := jsonb_array_length(s);
	nt := jsonb_array_length(t);
	IF nt < ns THEN
		RETURN NULL;
	END IF;
	FOR i IN ns .. nt - 1 LOOP
		IF NOT net540_backfill.absent(t -> i, TRUE) THEN
			RETURN NULL;
		END IF;
	END LOOP;
	FOR i IN 0 .. ns - 1 LOOP
		a := s -> i;
		b := t -> i;
		IF jsonb_typeof(a) IS DISTINCT FROM 'array' OR jsonb_typeof(b) IS DISTINCT FROM 'array'
				OR jsonb_array_length(a) <> 3 OR jsonb_array_length(b) <> 3 THEN
			RETURN NULL;
		END IF;
		CONTINUE WHEN net540_backfill.cmp_lists(a, b) IS NOT NULL;
		IF jsonb_typeof(a -> 0) <> 'number' OR jsonb_typeof(a -> 1) <> 'number' OR jsonb_typeof(a -> 2) <> 'number'
				OR jsonb_typeof(b -> 0) <> 'number' OR jsonb_typeof(b -> 1) <> 'number' OR jsonb_typeof(b -> 2) <> 'number' THEN
			RETURN NULL;
		END IF;
		a0 := (a ->> 0)::NUMERIC; a1 := (a ->> 1)::NUMERIC; a2 := (a ->> 2)::NUMERIC;
		b0 := (b ->> 0)::NUMERIC; b1 := (b ->> 1)::NUMERIC; b2 := (b ->> 2)::NUMERIC;
		IF net540_backfill.same_or_r9(a1, b1) IS NULL OR net540_backfill.same_or_r9(a2, b2) IS NOT NULL THEN
			RETURN NULL;
		ELSIF net540_backfill.same_or_r9(a0, a2 - a1) IS NULL OR net540_backfill.same_or_r9(b0, b2 - b1) IS NULL THEN
			RETURN NULL;
		END IF;
		IF abs(a0) < abs(b0) THEN
			short := TRUE;
		ELSE
			long := TRUE;
		END IF;
	END LOOP;
	IF NOT (short OR long) THEN
		RETURN NULL;
	END IF;
	RETURN CASE WHEN short AND long THEN 'mixed' WHEN short THEN 'short' ELSE 'long' END;
END
$$;

/*
 * classify(): the verdict for a stored hour and today's, both present and not the same as text:
 * text_only, pad, round9, noise, read_end, compact or other, and the column codes as
 * 'name=code' joined by spaces in the analyzer's column order (i a si r s t). An array column
 * equal to today's as an array (equal values in each place, NULLs alike) is 'eq' there, so it
 * is skipped without converting it.
 */
CREATE FUNCTION net540_backfill.classify(s solardatm.agg_datm, t solardatm.agg_datm)
RETURNS net540_backfill.verdict LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
	cols	TEXT[] := '{}';
	flat	TEXT[] := '{}';
	v		TEXT;
	w		TEXT;
	res		net540_backfill.verdict;
BEGIN
	IF s.data_i IS DISTINCT FROM t.data_i THEN
		v := net540_backfill.column_code(to_jsonb(s.data_i), to_jsonb(t.data_i), FALSE);
		IF v <> 'eq' THEN cols := cols || ('i=' || v); END IF;
	END IF;
	IF s.data_a IS DISTINCT FROM t.data_a THEN
		v := net540_backfill.column_code(to_jsonb(s.data_a), to_jsonb(t.data_a), TRUE);
		IF v <> 'eq' THEN cols := cols || ('a=' || v); END IF;
	END IF;
	IF s.stat_i IS DISTINCT FROM t.stat_i THEN
		v := net540_backfill.column_code(to_jsonb(s.stat_i), to_jsonb(t.stat_i), FALSE);
		IF v <> 'eq' THEN cols := cols || ('si=' || v); END IF;
	END IF;
	IF s.read_a IS DISTINCT FROM t.read_a THEN
		v := net540_backfill.column_code(to_jsonb(s.read_a), to_jsonb(t.read_a), TRUE);
		IF v = 'other' THEN
			w := net540_backfill.read_end(to_jsonb(s.read_a), to_jsonb(t.read_a));
			IF w IS NOT NULL THEN
				v := 'read_end:' || w;
			END IF;
		END IF;
		IF v <> 'eq' THEN cols := cols || ('r=' || v); END IF;
	END IF;
	-- status and tags: whenever the lists differ, even if the code is eq
	IF s.data_s IS DISTINCT FROM t.data_s THEN
		cols := cols || ('s=' || net540_backfill.column_code(to_jsonb(s.data_s), to_jsonb(t.data_s), FALSE));
	END IF;
	IF s.data_t IS DISTINCT FROM t.data_t THEN
		IF s.data_t IS NOT NULL AND t.data_t IS NOT NULL
				AND ARRAY(SELECT DISTINCT x COLLATE "C" FROM unnest(s.data_t) AS x ORDER BY 1)
					= ARRAY(SELECT DISTINCT x COLLATE "C" FROM unnest(t.data_t) AS x ORDER BY 1) THEN
			-- the same tags in another order: no difference
			v := 'pad';
		ELSE
			v := net540_backfill.column_code(to_jsonb(s.data_t), to_jsonb(t.data_t), FALSE);
		END IF;
		cols := cols || ('t=' || v);
	END IF;
	-- the codes, without column names and ways
	SELECT COALESCE(array_agg(DISTINCT f), '{}') INTO flat
	FROM unnest(cols) AS c(c)
	CROSS JOIN LATERAL unnest(string_to_array(split_part(split_part(c.c, '=', 2), ':', 1), '+')) AS f;
	res.verdict := CASE
		WHEN 'other' = ANY (flat) THEN 'other'
		WHEN 'compact' = ANY (flat) THEN 'compact'
		WHEN 'read_end' = ANY (flat) THEN 'read_end'
		WHEN 'round9' = ANY (flat) OR 'near9' = ANY (flat) THEN 'round9'
		WHEN 'noise' = ANY (flat) THEN 'noise'
		WHEN cardinality(flat) > 0 THEN 'pad'
		ELSE 'text_only'
		END;
	res.cols := array_to_string(cols, ' ');
	RETURN res;
END
$$;

/*
 * all_absent(): true when a row holds no value at all, by absent()'s rules: no status or tags,
 * and every element of the other columns absent (NULL, or 0 where zero counts as nothing).
 */
CREATE FUNCTION net540_backfill.all_absent(s solardatm.agg_datm) RETURNS BOOLEAN
LANGUAGE SQL IMMUTABLE AS $$
	SELECT s.data_s IS NULL AND s.data_t IS NULL
		AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(to_jsonb(s.data_i), '[]')) e
			WHERE NOT net540_backfill.absent(e, FALSE))
		AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(to_jsonb(s.data_a), '[]')) e
			WHERE NOT net540_backfill.absent(e, TRUE))
		AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(to_jsonb(s.stat_i), '[]')) e
			WHERE NOT net540_backfill.absent(e, FALSE))
		AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(COALESCE(to_jsonb(s.read_a), '[]')) e
			WHERE NOT net540_backfill.absent(e, TRUE))
$$;

-- ---------------------------------------------------------------------------------------------
-- Filling
-- ---------------------------------------------------------------------------------------------

/* What fill_unit() did: the counts unit_log keeps, for a unit or for one hour of it. */
CREATE TYPE net540_backfill.unit_result AS (
	hours				INTEGER,
	slots				INTEGER,
	rows_15m			INTEGER,
	n_same				INTEGER,
	n_text_only			INTEGER,
	n_pad				INTEGER,
	n_round9			INTEGER,
	n_noise				INTEGER,
	n_no_raw			INTEGER,
	n_read_end			INTEGER,
	n_compact			INTEGER,
	n_other				INTEGER,
	n_stored_only		INTEGER,
	n_stale				INTEGER,
	n_slice				INTEGER,
	n_no_slots			INTEGER,
	n_prefix			INTEGER,
	slices_found		INTEGER,
	slices_rewritten	INTEGER,
	ms_probe			REAL,
	ms_compute			REAL
);

/*
 * Fill one unit: one stream for one day window [p_w0, p_w1), or one hour of it, in the caller's
 * transaction.
 *
 * 1. Look for slices in the raw datum the hours' rollups may read.
 *    The full fill (p_exact false) reads from a year and 2 days before the window (the furthest
 *    back find_datm_for_time_slot() looks with the P1Y tolerance the rollup passes) to an hour
 *    after it (the furthest forward), skipping what this stream's earlier units already looked
 *    at. Each stream's datum are so read once, in time order, but the first unit of a stream
 *    reads the year before it.
 *    A dry run or a trial (p_exact true) reads only what its own hours' rollups read, and leaves
 *    the stream's probed range alone. An hour's rollup reads datum from its prior datum to an
 *    hour after it, and its prior datum is the last one before it with an accumulating array (a
 *    stream without accumulating properties has none). So every hour after the window's first
 *    datum with an accumulating array reads only datum of the window and the hour after it,
 *    which are looked at with one range scan; for the hours up to that datum,
 *    find_datm_for_time_slot() itself gives what they read before the window.
 * 2. Count mode: if a slice of data_i or data_a is recorded in what the hours may read, find with
 *    find_datm_for_time_slot() itself the hours whose rollup reads one, and leave them out.
 *    Rewrite mode: lock and log the slices in that range, and store their arrays from position
 *    1, NULL first, before computing.
 * 3. One statement computes every hour of the window that has an hourly row, no 15 minute row
 *    and no pending stale row, inserts the 15 minute rows (not in a dry run), compares each
 *    stored hour with today's and lists the real differences.
 */
CREATE FUNCTION net540_backfill.fill_unit(
		p_sid		UUID,
		p_w0		TIMESTAMP WITH TIME ZONE,
		p_w1		TIMESTAMP WITH TIME ZONE,
		p_chunk		INTEGER,
		p_dry		BOOLEAN,
		p_slice		TEXT,
		p_exact		BOOLEAN DEFAULT FALSE
	) RETURNS net540_backfill.unit_result LANGUAGE plpgsql VOLATILE AS $$
DECLARE
	-- the raw datum the hours' rollups may read: [need0, need1]
	need0		TIMESTAMP WITH TIME ZONE := p_w0 - INTERVAL 'P1Y' - INTERVAL 'P2D';
	need1		CONSTANT TIMESTAMP WITH TIME ZONE := p_w1 + INTERVAL 'PT1H';
	res			net540_backfill.unit_result;
	pf			TIMESTAMP WITH TIME ZONE;
	pt			TIMESTAMP WITH TIME ZONE;
	lo_op		TEXT;
	lo			TIMESTAMP WITH TIME ZONE;
	t0			TIMESTAMP WITH TIME ZONE := clock_timestamp();
	skip_hours	TIMESTAMP WITH TIME ZONE[] := '{}';
	rw_ts		TIMESTAMP WITH TIME ZONE[];
	rw_done		TIMESTAMP WITH TIME ZONE[];
	obj_kind	CHARACTER;
	has_a		BOOLEAN;
	first_a		TIMESTAMP WITH TIME ZONE;
	read_from	TIMESTAMP WITH TIME ZONE;
	n			INTEGER;
	-- record the slices among rows d(ts, data_i, data_a, data_s) of stream %1$L
	slice_ins	CONSTANT TEXT := $q$
		INSERT INTO net540_backfill.slice (stream_id, ts, lower_i, lower_a, lower_s, old_i, old_a, old_s)
		SELECT %1$L::uuid, d.ts
			, CASE WHEN array_lower(d.data_i, 1) > 1 THEN array_lower(d.data_i, 1) END
			, CASE WHEN array_lower(d.data_a, 1) > 1 THEN array_lower(d.data_a, 1) END
			, CASE WHEN array_lower(d.data_s, 1) > 1 THEN array_lower(d.data_s, 1) END
			, d.data_i, d.data_a, d.data_s
		FROM d
		WHERE array_lower(d.data_i, 1) > 1 OR array_lower(d.data_a, 1) > 1 OR array_lower(d.data_s, 1) > 1
		ON CONFLICT (stream_id, ts) DO NOTHING
		RETURNING 1
		$q$;
BEGIN
	res.slices_found := 0;
	res.slices_rewritten := 0;
	res.n_prefix := 0;
	SELECT m.kind, COALESCE(cardinality(m.names_a), 0) > 0 INTO obj_kind, has_a
	FROM solardatm.find_metadata_for_stream(p_sid) m;

	-- the probe row keeps two units of one stream apart
	INSERT INTO net540_backfill.probe (stream_id) VALUES (p_sid) ON CONFLICT DO NOTHING;
	SELECT probed_from, probed_to INTO pf, pt
	FROM net540_backfill.probe WHERE stream_id = p_sid FOR UPDATE;

	IF p_exact THEN
		-- 1, a dry run or a trial: the window's datum, and an hour after it
		EXECUTE format($q$
			WITH d AS (
				SELECT d.ts, d.data_i, d.data_a, d.data_s
				FROM solardatm.da_datm d
				WHERE d.stream_id = %1$L::uuid
					AND d.ts >= %2$L::timestamptz AND d.ts <= %3$L::timestamptz
					AND (array_lower(d.data_i, 1) > 1 OR array_lower(d.data_a, 1) > 1
						OR array_lower(d.data_s, 1) > 1)
			)
			, f AS ($q$ || slice_ins || $q$)
			SELECT count(*)::integer FROM f
			$q$, p_sid, p_w0, need1) INTO n;
		res.slices_found := n;
		need0 := p_w0;
		IF has_a THEN
			-- the window's first datum with an accumulating array: no hour after it reads a datum
			-- before the window
			EXECUTE format($q$
				SELECT d.ts FROM solardatm.da_datm d
				WHERE d.stream_id = %1$L::uuid
					AND d.ts >= %2$L::timestamptz AND d.ts < %3$L::timestamptz
					AND d.data_a IS NOT NULL
				ORDER BY d.ts
				LIMIT 1
				$q$, p_sid, p_w0, p_w1) INTO first_a;
			-- what the rollups of the hours to it read before the window, as they read it
			EXECUTE format($q$
				WITH h AS (
					SELECT h.ts_start
					FROM solardatm.agg_datm_hourly h
					WHERE h.stream_id = %1$L::uuid
						AND h.ts_start >= %2$L::timestamptz AND h.ts_start < %3$L::timestamptz
						AND h.ts_start <= %4$L::timestamptz
						AND h.ts_start = date_trunc('hour', h.ts_start, 'UTC')
						AND NOT EXISTS (
							SELECT 1 FROM solardatm.agg_stale_datm s
							WHERE s.agg_kind = 'h' AND s.ts_start = h.ts_start AND s.stream_id = %1$L::uuid
						)
						AND NOT EXISTS (
							SELECT 1 FROM solardatm.agg_datm_15m q
							WHERE q.stream_id = %1$L::uuid
								AND q.ts_start >= %2$L::timestamptz AND q.ts_start < %3$L::timestamptz
								AND q.ts_start >= h.ts_start AND q.ts_start < h.ts_start + INTERVAL 'PT1H'
						)
				)
				, d AS MATERIALIZED (
					SELECT DISTINCT ON (d.ts) d.ts, d.data_i, d.data_a, d.data_s
					FROM h
					CROSS JOIN LATERAL solardatm.find_datm_for_time_slot(%1$L::uuid, h.ts_start
						, h.ts_start + INTERVAL 'PT1H', INTERVAL 'P1Y') d
					WHERE d.rtype = 0 AND d.ts < %2$L::timestamptz
					ORDER BY d.ts
				)
				, f AS ($q$ || slice_ins || $q$)
				SELECT (SELECT count(*) FROM h)::integer, (SELECT count(*) FROM f)::integer
					, (SELECT min(d.ts) FROM d)
				$q$, p_sid, p_w0, p_w1, COALESCE(first_a, p_w1)) INTO res.n_prefix, n, read_from;
			res.slices_found := res.slices_found + n;
			need0 := LEAST(p_w0, read_from);
		END IF;
	ELSE
		-- 1, the full fill: the slice probe, from where this stream's units have looked to
		IF pf IS NOT NULL AND pf <= need0 AND pt >= need0 THEN
			lo_op := '>';
			lo := pt;
		ELSE
			lo_op := '>=';
			lo := need0;
			pf := need0;
			pt := NULL;
		END IF;
		IF pt IS NULL OR pt < need1 THEN
			EXECUTE format($q$
				WITH d AS (
					SELECT d.ts, d.data_i, d.data_a, d.data_s
					FROM solardatm.da_datm d
					WHERE d.stream_id = %1$L::uuid
						AND d.ts %2$s %3$L::timestamptz AND d.ts <= %4$L::timestamptz
						AND (array_lower(d.data_i, 1) > 1 OR array_lower(d.data_a, 1) > 1
							OR array_lower(d.data_s, 1) > 1)
				)
				, f AS ($q$ || slice_ins || $q$)
				SELECT count(*)::integer FROM f
				$q$, p_sid, lo_op, lo, need1) INTO n;
			res.slices_found := n;
			UPDATE net540_backfill.probe
			SET probed_from = pf, probed_to = GREATEST(COALESCE(pt, need1), need1)
			WHERE stream_id = p_sid;
		END IF;
	END IF;

	-- 2. slices the hours' rollups may read
	IF EXISTS (
		SELECT 1 FROM net540_backfill.slice s
		WHERE s.stream_id = p_sid AND s.ts >= need0 AND s.ts <= need1 AND s.state = 'found'
			AND (p_slice = 'rewrite' OR s.lower_i IS NOT NULL OR s.lower_a IS NOT NULL)
	) THEN
		IF p_slice = 'count' OR p_dry THEN
			-- the hours whose rollup reads a slice, exactly as the rollup reads them
			EXECUTE format($q$
				SELECT COALESCE(array_agg(h.ts_start ORDER BY h.ts_start), '{}')
				FROM solardatm.agg_datm_hourly h
				WHERE h.stream_id = %1$L::uuid
					AND h.ts_start >= %2$L::timestamptz AND h.ts_start < %3$L::timestamptz
					AND EXISTS (
						SELECT 1
						FROM solardatm.find_datm_for_time_slot(%1$L::uuid, h.ts_start
							, h.ts_start + INTERVAL 'PT1H', INTERVAL 'P1Y') d
						WHERE d.rtype = 0
							AND (array_lower(d.data_i, 1) > 1 OR array_lower(d.data_a, 1) > 1)
					)
				$q$, p_sid, p_w0, p_w1) INTO skip_hours;
		ELSE
			-- rewrite: lock the datum and log the arrays they hold now, then rewrite them
			SELECT array_agg(s.ts ORDER BY s.ts) INTO rw_ts
			FROM net540_backfill.slice s
			WHERE s.stream_id = p_sid AND s.ts >= need0 AND s.ts <= need1 AND s.state = 'found';
			EXECUTE format($q$
				UPDATE net540_backfill.slice s
				SET old_i = d.data_i, old_a = d.data_a, old_s = d.data_s
				FROM (
					SELECT d.ts, d.data_i, d.data_a, d.data_s
					FROM solardatm.da_datm d
					WHERE d.stream_id = %1$L::uuid
						AND d.ts >= %2$L::timestamptz AND d.ts <= %3$L::timestamptz
						AND d.ts = ANY (%4$L::timestamptz[])
					FOR UPDATE
				) d
				WHERE s.stream_id = %1$L::uuid AND s.ts = d.ts
				$q$, p_sid, rw_ts[1], rw_ts[cardinality(rw_ts)], rw_ts);
			EXECUTE format($q$
				WITH u AS (
					UPDATE solardatm.da_datm d SET
						  data_i = CASE WHEN array_lower(d.data_i, 1) > 1
							THEN array_fill(NULL::NUMERIC, ARRAY[array_lower(d.data_i, 1) - 1]) || d.data_i
							ELSE d.data_i END
						, data_a = CASE WHEN array_lower(d.data_a, 1) > 1
							THEN array_fill(NULL::NUMERIC, ARRAY[array_lower(d.data_a, 1) - 1]) || d.data_a
							ELSE d.data_a END
						, data_s = CASE WHEN array_lower(d.data_s, 1) > 1
							THEN array_fill(NULL::TEXT, ARRAY[array_lower(d.data_s, 1) - 1]) || d.data_s
							ELSE d.data_s END
					WHERE d.stream_id = %1$L::uuid
						AND d.ts >= %2$L::timestamptz AND d.ts <= %3$L::timestamptz
						AND d.ts = ANY (%4$L::timestamptz[])
						AND (array_lower(d.data_i, 1) > 1 OR array_lower(d.data_a, 1) > 1
							OR array_lower(d.data_s, 1) > 1)
					RETURNING d.ts
				)
				SELECT COALESCE(array_agg(u.ts), '{}') FROM u
				$q$, p_sid, rw_ts[1], rw_ts[cardinality(rw_ts)], rw_ts) INTO rw_done;
			UPDATE net540_backfill.slice s
			SET state = CASE WHEN s.ts = ANY (rw_done) THEN 'rewritten' ELSE 'gone' END
				, rewritten = now()
			WHERE s.stream_id = p_sid AND s.ts = ANY (rw_ts);
			res.slices_rewritten := cardinality(rw_done);
		END IF;
	END IF;
	res.ms_probe := extract(epoch FROM clock_timestamp() - t0) * 1000;

	-- 3. compute, insert, compare
	t0 := clock_timestamp();
	EXECUTE format($q$
		WITH h0 AS MATERIALIZED (
			SELECT h.stream_id, h.ts_start, h.data_i, h.data_a, h.data_s, h.data_t, h.stat_i, h.read_a
				, EXISTS (
					SELECT 1 FROM solardatm.agg_stale_datm s
					WHERE s.agg_kind = 'h' AND s.ts_start = h.ts_start AND s.stream_id = h.stream_id
				) AS stale
				, h.ts_start = ANY (%4$L::timestamptz[]) AS slice
			FROM solardatm.agg_datm_hourly h
			WHERE h.stream_id = %1$L::uuid
				AND h.ts_start >= %2$L::timestamptz AND h.ts_start < %3$L::timestamptz
				-- stale processing computes hours on the UTC hour only, in every zone
				AND h.ts_start = date_trunc('hour', h.ts_start, 'UTC')
				AND NOT EXISTS (
					SELECT 1 FROM solardatm.agg_datm_15m q
					WHERE q.stream_id = %1$L::uuid
						AND q.ts_start >= %2$L::timestamptz AND q.ts_start < %3$L::timestamptz
						AND q.ts_start >= h.ts_start AND q.ts_start < h.ts_start + INTERVAL 'PT1H'
				)
		)
		, h AS MATERIALIZED (
			SELECT * FROM h0 WHERE NOT h0.stale AND NOT h0.slice
		)
		, r AS MATERIALIZED (
			SELECT h.ts_start AS hour, r.stream_id, r.ts_start, r.data_i, r.data_a, r.data_s, r.data_t
				, r.stat_i, r.read_a, r.slots
			FROM h
			CROSS JOIN LATERAL solardatm.rollup_datm_15m_for_hour(%1$L::uuid, h.ts_start
				, h.ts_start + INTERVAL 'PT1H') r
		)
		, ins AS (
			INSERT INTO solardatm.agg_datm_15m (stream_id, ts_start, data_i, data_a, data_s, data_t, stat_i, read_a)
			SELECT x.stream_id, x.ts_start, x.data_i, x.data_a, x.data_s, x.data_t, x.stat_i, x.read_a
			FROM r CROSS JOIN LATERAL unnest(r.slots) AS x
			WHERE NOT %5$L::boolean
			ORDER BY x.ts_start DESC
			ON CONFLICT (stream_id, ts_start) DO NOTHING
			RETURNING 1
		)
		, v AS MATERIALIZED (
			SELECT h.ts_start
				, ROW(h.stream_id, h.ts_start, h.data_i, h.data_a, h.data_s, h.data_t, h.stat_i, h.read_a)::solardatm.agg_datm AS s
				, CASE WHEN r.hour IS NOT NULL THEN
					ROW(r.stream_id, r.ts_start, r.data_i, r.data_a, r.data_s, r.data_t, r.stat_i, r.read_a)::solardatm.agg_datm
				  END AS t
				, CASE WHEN r.hour IS NULL THEN EXISTS (
					SELECT 1 FROM solardatm.da_datm d
					WHERE d.stream_id = %1$L::uuid
						AND d.ts >= %2$L::timestamptz AND d.ts < %3$L::timestamptz
						AND d.ts >= h.ts_start AND d.ts < h.ts_start + INTERVAL 'PT1H'
				  ) END AS raw
			FROM h LEFT OUTER JOIN r ON r.hour = h.ts_start
		)
		, k AS MATERIALIZED (
			SELECT v.ts_start, v.s
				, CASE
					-- zeros and NULLs only where today has nothing: the analyzer's pad
					WHEN v.t IS NULL AND v.raw AND net540_backfill.all_absent(v.s)
						THEN ROW('pad', NULL)::net540_backfill.verdict
					WHEN v.t IS NULL AND v.raw THEN ROW('stored_only', NULL)::net540_backfill.verdict
					WHEN v.t IS NULL THEN ROW('no_raw', NULL)::net540_backfill.verdict
					WHEN (v.s)::text = (v.t)::text THEN ROW('same', NULL)::net540_backfill.verdict
					ELSE net540_backfill.classify(v.s, v.t)
				  END AS c
			FROM v
		)
		, d AS (
			INSERT INTO net540_backfill.diff (dry, stream_id, ts_start, verdict, cols, kind, stored_md5, chunk_no)
			SELECT %5$L::boolean, %1$L::uuid, k.ts_start, (k.c).verdict, (k.c).cols, %7$L, md5((k.s)::text), %6$s
			FROM k
			WHERE (k.c).verdict IN ('stored_only', 'read_end', 'compact', 'other')
			ON CONFLICT (dry, stream_id, ts_start) DO UPDATE
			SET verdict = EXCLUDED.verdict, cols = EXCLUDED.cols, kind = EXCLUDED.kind
				, stored_md5 = EXCLUDED.stored_md5, chunk_no = EXCLUDED.chunk_no, compared = now()
			RETURNING 1
		)
		, sk AS (
			INSERT INTO net540_backfill.skipped (dry, stream_id, ts_start, reason, chunk_no)
			SELECT %5$L::boolean, %1$L::uuid, h0.ts_start, CASE WHEN h0.slice THEN 'slice' ELSE 'stale' END, %6$s
			FROM h0
			WHERE h0.stale OR h0.slice
			ON CONFLICT (dry, stream_id, ts_start) DO UPDATE
			SET reason = EXCLUDED.reason, chunk_no = EXCLUDED.chunk_no, at = now()
			RETURNING 1
		)
		, uk AS (
			DELETE FROM net540_backfill.skipped x
			USING h
			WHERE x.dry = %5$L::boolean AND x.stream_id = %1$L::uuid AND x.ts_start = h.ts_start
			RETURNING 1
		)
		SELECT
			  (SELECT count(*) FROM h)::integer
			, (SELECT COALESCE(sum(cardinality(r.slots)), 0) FROM r)::integer
			, (SELECT count(*) FROM ins)::integer
			, count(*) FILTER (WHERE (k.c).verdict = 'same')::integer
			, count(*) FILTER (WHERE (k.c).verdict = 'text_only')::integer
			, count(*) FILTER (WHERE (k.c).verdict = 'pad')::integer
			, count(*) FILTER (WHERE (k.c).verdict = 'round9')::integer
			, count(*) FILTER (WHERE (k.c).verdict = 'noise')::integer
			, count(*) FILTER (WHERE (k.c).verdict = 'no_raw')::integer
			, count(*) FILTER (WHERE (k.c).verdict = 'read_end')::integer
			, count(*) FILTER (WHERE (k.c).verdict = 'compact')::integer
			, count(*) FILTER (WHERE (k.c).verdict = 'other')::integer
			, count(*) FILTER (WHERE (k.c).verdict = 'stored_only')::integer
			, (SELECT count(*) FROM h0 WHERE h0.stale)::integer
			, (SELECT count(*) FROM h0 WHERE h0.slice)::integer
			, (SELECT count(*) FROM r WHERE COALESCE(cardinality(r.slots), 0) = 0)::integer
		FROM k
		$q$, p_sid, p_w0, p_w1, skip_hours, p_dry, p_chunk, obj_kind)
	INTO res.hours, res.slots, res.rows_15m, res.n_same, res.n_text_only, res.n_pad, res.n_round9,
		res.n_noise, res.n_no_raw, res.n_read_end, res.n_compact, res.n_other, res.n_stored_only,
		res.n_stale, res.n_slice, res.n_no_slots;
	res.ms_compute := extract(epoch FROM clock_timestamp() - t0) * 1000;
	RETURN res;
END
$$;

/*
 * The streams to fill, node and location, as stale processing finds them.
 */
CREATE VIEW net540_backfill.stream AS
	SELECT stream_id FROM solardatm.da_datm_meta
	UNION ALL
	SELECT stream_id FROM solardatm.da_loc_datm_meta;

/*
 * Plan the units of a chunk: for each stream, each UTC day of the chunk with an hourly row and
 * no 15 minute row. For the fill (p_dry false, p_streams 0), every stream, in batches of p_batch
 * with a commit after each, resuming at the last stream planned, the chunk row locked for each
 * batch; it returns early, the chunk still planning, when the other worker has the chunk row
 * or a stop is asked for, and the chunk is filling once every stream is planned. p_streams N > 0
 * plans only the first N streams with work in the chunk, in md5 order of the stream and p_seed
 * (a trial, or a dry run), and leaves the chunk's status alone. A dry run (p_dry true) is planned
 * in one transaction, and replaces any earlier dry run's units, and its own logs and lists; with
 * p_day (the start of a UTC day of the chunk) it plans only that day, for every stream or for
 * p_streams of them.
 */
CREATE PROCEDURE net540_backfill.plan_chunk(
		p_chunk		INTEGER,
		p_dry		BOOLEAN,
		p_streams	INTEGER,
		p_seed		TEXT,
		p_batch		INTEGER DEFAULT 1000,
		p_day		TIMESTAMP WITH TIME ZONE DEFAULT NULL
	) LANGUAGE plpgsql AS $$
DECLARE
	c			net540_backfill.chunk;
	batch		UUID[];
	n			INTEGER;
	taken		INTEGER := 0;
	s			UUID;
	has_work	BOOLEAN;
	ins_sql		CONSTANT TEXT := $q$
		INSERT INTO net540_backfill.unit (dry, chunk_no, day, stream_id, day_end, hours)
		SELECT %1$L::boolean, %2$s, GREATEST(x.day, %3$L::timestamptz), s.stream_id
			, LEAST(x.day + INTERVAL 'P1D', %4$L::timestamptz), x.hours
		FROM unnest(%5$L::uuid[]) AS s(stream_id)
		CROSS JOIN LATERAL (
			SELECT date_trunc('day', h.ts_start, 'UTC') AS day, count(*)::integer AS hours
			FROM solardatm.agg_datm_hourly h
			WHERE h.stream_id = s.stream_id
				AND h.ts_start >= %3$L::timestamptz AND h.ts_start < %4$L::timestamptz
				AND h.ts_start = date_trunc('hour', h.ts_start, 'UTC')
				AND NOT EXISTS (
					SELECT 1 FROM solardatm.agg_datm_15m q
					WHERE q.stream_id = s.stream_id
						AND q.ts_start >= %3$L::timestamptz AND q.ts_start < %4$L::timestamptz
						AND q.ts_start >= h.ts_start AND q.ts_start < h.ts_start + INTERVAL 'PT1H'
				)
			GROUP BY 1
			OFFSET 0
		) x
		ON CONFLICT DO NOTHING
		$q$;
	pos			UUID;
BEGIN
	IF p_dry THEN
		DELETE FROM net540_backfill.unit WHERE dry;
		DELETE FROM net540_backfill.unit_log WHERE dry AND chunk_no = p_chunk;
		DELETE FROM net540_backfill.diff WHERE dry AND chunk_no = p_chunk;
		DELETE FROM net540_backfill.skipped WHERE dry AND chunk_no = p_chunk;
		DELETE FROM net540_backfill.failed WHERE dry AND chunk_no = p_chunk;
		UPDATE net540_backfill.control SET dry_plan = p_chunk || '/' || p_streams || '/' || p_seed
			|| COALESCE('/' || to_char(p_day AT TIME ZONE 'UTC', 'YYYY-MM-DD'), '');
	ELSIF p_day IS NOT NULL THEN
		RAISE EXCEPTION 'A day is for a dry run only';
	END IF;
	IF p_dry OR p_streams > 0 THEN
		SELECT * INTO c FROM net540_backfill.chunk WHERE chunk_no = p_chunk;
		IF c.chunk_no IS NULL THEN
			RAISE EXCEPTION 'No chunk %', p_chunk;
		END IF;
		IF p_day IS NOT NULL THEN
			IF p_day <> date_trunc('day', p_day, 'UTC') OR p_day + INTERVAL 'P1D' <= c.range_start
					OR p_day >= c.range_end THEN
				RAISE EXCEPTION 'Not a UTC day of chunk % (% to %): %', p_chunk, c.range_start, c.range_end, p_day;
			END IF;
			-- the day's part of the chunk, planned as the chunk would be
			c.range_start := GREATEST(p_day, c.range_start);
			c.range_end := LEAST(p_day + INTERVAL 'P1D', c.range_end);
		END IF;
	END IF;
	IF p_dry AND p_streams < 1 THEN
		-- a dry run of every stream of the chunk (or of its day), in this one transaction
		LOOP
			SELECT array_agg(x.stream_id ORDER BY x.stream_id) INTO batch
			FROM (
				SELECT x.stream_id FROM net540_backfill.stream x
				WHERE pos IS NULL OR x.stream_id > pos
				ORDER BY x.stream_id
				LIMIT p_batch
			) x;
			EXIT WHEN batch IS NULL;
			EXECUTE format(ins_sql, TRUE, p_chunk, c.range_start, c.range_end, batch);
			pos := batch[cardinality(batch)];
		END LOOP;
		RETURN;
	ELSIF p_streams > 0 THEN
		FOR s IN SELECT x.stream_id FROM net540_backfill.stream x ORDER BY md5(x.stream_id::text || p_seed) LOOP
			EXECUTE format($q$
				SELECT EXISTS (
					SELECT 1 FROM solardatm.agg_datm_hourly h
					WHERE h.stream_id = %1$L::uuid
						AND h.ts_start >= %2$L::timestamptz AND h.ts_start < %3$L::timestamptz
						AND h.ts_start = date_trunc('hour', h.ts_start, 'UTC')
						AND NOT EXISTS (
							SELECT 1 FROM solardatm.agg_datm_15m q
							WHERE q.stream_id = %1$L::uuid
								AND q.ts_start >= %2$L::timestamptz AND q.ts_start < %3$L::timestamptz
								AND q.ts_start >= h.ts_start AND q.ts_start < h.ts_start + INTERVAL 'PT1H'
						)
				)
				$q$, s, c.range_start, c.range_end) INTO has_work;
			CONTINUE WHEN NOT has_work;
			EXECUTE format(ins_sql, p_dry, p_chunk, c.range_start, c.range_end, ARRAY[s]);
			taken := taken + 1;
			EXIT WHEN taken >= p_streams;
		END LOOP;
		RAISE NOTICE 'planned % streams of chunk %', taken, p_chunk;
		RETURN;
	END IF;

	LOOP
		-- the chunk row is locked while each batch is planned, so two workers take turns
		SELECT * INTO c FROM net540_backfill.chunk WHERE chunk_no = p_chunk FOR UPDATE SKIP LOCKED;
		IF c.chunk_no IS NULL OR (SELECT stop FROM net540_backfill.control) THEN
			COMMIT;
			RETURN;
		ELSIF c.status NOT IN ('pending', 'planning') THEN
			COMMIT;
			RETURN;
		END IF;
		SELECT array_agg(x.stream_id ORDER BY x.stream_id) INTO batch
		FROM (
			SELECT x.stream_id FROM net540_backfill.stream x
			WHERE c.plan_pos IS NULL OR x.stream_id > c.plan_pos
			ORDER BY x.stream_id
			LIMIT p_batch
		) x;
		IF batch IS NULL THEN
			SELECT count(*) INTO n FROM net540_backfill.unit WHERE NOT dry AND chunk_no = p_chunk;
			UPDATE net540_backfill.chunk SET status = 'filling', planned = now(), units = n
			WHERE chunk_no = p_chunk;
			COMMIT;
			RETURN;
		END IF;
		EXECUTE format(ins_sql, FALSE, p_chunk, c.range_start, c.range_end, batch);
		UPDATE net540_backfill.chunk SET status = 'planning', plan_pos = batch[cardinality(batch)]
		WHERE chunk_no = p_chunk;
		COMMIT;
	END LOOP;
END
$$;

/*
 * Why to hold back, or NULL:
 *   - the hourly stale queue is longer than p_max_stale;
 *   - fewer than p_replicas replicas are streaming, or one replays more than p_max_lag bytes
 *     behind;
 *   - a replication slot holds more than p_max_lag bytes of WAL;
 *   - WAL archiving is failing, or more than p_max_ready segments wait to be archived.
 * A limit of 0 is not checked. The last two are the checks of chunk-maintenance.sh (OPS-51):
 * they find WAL piling up in pg_wal, which the lag of the streaming replicas does not show. The
 * reasons hold no figure that changes while the cause lasts, other than a replica's lag, so the
 * fill logs each once.
 */
CREATE FUNCTION net540_backfill.hold_reason(
		p_max_stale	INTEGER,
		p_max_lag	BIGINT,
		p_replicas	INTEGER,
		p_max_ready	INTEGER DEFAULT 0
	) RETURNS TEXT LANGUAGE plpgsql STABLE AS $$
DECLARE
	n			INTEGER;
	lag			NUMERIC;
	slot		TEXT;
	arch		RECORD;
BEGIN
	IF p_max_stale > 0 THEN
		SELECT count(*) INTO n
		FROM (SELECT 1 FROM solardatm.agg_stale_datm WHERE agg_kind = 'h' LIMIT p_max_stale + 1) x;
		IF n > p_max_stale THEN
			RETURN 'stale queue over ' || p_max_stale;
		END IF;
	END IF;
	IF p_replicas > 0 OR p_max_lag > 0 THEN
		SELECT count(*) FILTER (WHERE r.state = 'streaming')
			, max(pg_wal_lsn_diff(pg_current_wal_lsn(), r.replay_lsn))
		INTO n, lag
		FROM pg_catalog.pg_stat_replication r;
		IF p_replicas > 0 AND n < p_replicas THEN
			RETURN n || ' of ' || p_replicas || ' replicas streaming';
		ELSIF p_max_lag > 0 AND lag > p_max_lag THEN
			RETURN 'replica ' || pg_size_pretty(lag) || ' behind';
		END IF;
	END IF;
	IF p_max_lag > 0 THEN
		-- a slot nothing reads from keeps WAL in pg_wal, and no streaming replica shows it
		SELECT s.slot_name, pg_wal_lsn_diff(pg_current_wal_lsn(), s.restart_lsn)
		INTO slot, lag
		FROM pg_catalog.pg_replication_slots s
		WHERE s.restart_lsn IS NOT NULL
		ORDER BY 2 DESC
		LIMIT 1;
		IF lag > p_max_lag THEN
			RETURN 'replication slot ' || slot || ' holds over ' || pg_size_pretty(p_max_lag) || ' of WAL';
		END IF;
	END IF;
	IF p_max_ready > 0 AND current_setting('archive_mode') <> 'off' THEN
		SELECT a.last_failed_wal, a.last_failed_time, a.last_archived_time
		INTO arch
		FROM pg_catalog.pg_stat_archiver a;
		IF arch.last_failed_time IS NOT NULL
				AND (arch.last_archived_time IS NULL OR arch.last_failed_time > arch.last_archived_time) THEN
			RETURN 'WAL archiving is failing (' || COALESCE(arch.last_failed_wal, 'no segment named') || ')';
		END IF;
		-- needs a superuser, or pg_monitor; the fill runs as a superuser
		SELECT count(*) INTO n
		FROM pg_catalog.pg_ls_archive_statusdir() f
		WHERE f.name LIKE '%.ready';
		IF n > p_max_ready THEN
			RETURN 'over ' || p_max_ready || ' WAL segments waiting to be archived';
		END IF;
	END IF;
	RETURN NULL;
END
$$;

/*
 * What work() does about an error, by its SQLSTATE:
 *   cancel     a cancel or a shutdown: raised again; the unit's transaction is rolled back and
 *              the unit stays listed
 *   transient  a lock wait, a deadlock or a serialization failure: the unit stays listed, and
 *              work() returns, to be called again after a wait
 *   data       what a unit's own data can cause (data exceptions, integrity and cardinality
 *              violations, errors a function raises, CASE not found, a program limit such as an
 *              array too big), and XX000: the C functions the rollup calls (pad_vec(), the
 *              vec_agg_*() aggregates, vec_to_*()) raise their errors with no code, so a datum
 *              whose array is longer than its stream's names fails its hour with XX000. The
 *              unit is done again hour by hour, and only the hours that fail are listed in
 *              failed. An internal error the data does not cause fails every hour of every
 *              unit, so work()'s p_max_fail_run stops the fill after a few units
 *   fatal      anything else (out of disk or memory, I/O errors, data or index corruption,
 *              XX001 and XX002, a missing object or privilege, a feature not supported, ...):
 *              the fill stops, the unit still listed
 */
CREATE FUNCTION net540_backfill.error_kind(p_state TEXT) RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
	SELECT CASE
		WHEN p_state IN ('57014', '57P01', '57P02', '57P03') THEN 'cancel'
		WHEN p_state IN ('55P03', '40P01', '40001') THEN 'transient'
		WHEN left(p_state, 2) IN ('21', '22', '23', '2F', 'P0') OR p_state IN ('20000', '54000', 'XX000') THEN 'data'
		ELSE 'fatal'
		END
$$;

/* one_line(): a message on one line, without the | psql separates fields with. */
CREATE FUNCTION net540_backfill.one_line(p_text TEXT) RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
	SELECT translate(regexp_replace(COALESCE(p_text, ''), '\s+', ' ', 'g'), '|', '/')
$$;

/*
 * A worker: fill units, one transaction each, until p_units are done or p_seconds have passed,
 * then return, with p_status:
 *   ok        more to do: call again (after a pause)
 *   hold: ..  held back by the stale queue, replication or WAL archiving (hold_reason()): call
 *             again later
 *   wait      the other worker is finishing the chunk's last unit: call again soon
 *   retry: .. a unit met a lock wait, a deadlock or a serialization failure, and is still
 *             listed: call again after a wait
 *   filled:N  chunk N has just been filled: vacuum, check and reindex it, then call again
 *   done      nothing left (with p_planned_only, nothing left of what was planned)
 *   stop      net540_backfill.control.stop is set
 *   failed:N  the check of chunk N found hours missing: stop and look
 *   error: .. a unit met an error its data cannot cause (see error_kind()), and is still listed;
 *             or p_max_fail_run units in a row failed in every hour (0: no limit): stop and look
 * p_done is the units done, p_failed the hours of them that failed (listed in failed), and
 * p_failure the last such error. A unit that raises an error its data can cause is done again
 * hour by hour in the same transaction: the hours that succeed are filled, those that fail are
 * listed, and the unit is done. p_planned_only works only through units already planned (a
 * trial or a dry run), plans no chunk, and does them as fill_unit() does with p_exact.
 */
CREATE PROCEDURE net540_backfill.work(
		p_worker		INTEGER,
		p_dry			BOOLEAN,
		p_slice			TEXT,
		p_units			INTEGER,
		p_seconds		NUMERIC,
		p_max_stale		INTEGER,
		p_max_lag		BIGINT,
		p_replicas		INTEGER,
		p_planned_only	BOOLEAN,
		p_max_fail_run	INTEGER DEFAULT 3,
		p_max_ready		INTEGER DEFAULT 0,
		INOUT p_done	INTEGER DEFAULT NULL,
		INOUT p_failed	INTEGER DEFAULT NULL,
		INOUT p_failure	TEXT DEFAULT NULL,
		INOUT p_status	TEXT DEFAULT NULL
	) LANGUAGE plpgsql AS $$
DECLARE
	t_end		CONSTANT TIMESTAMP WITH TIME ZONE := clock_timestamp() + p_seconds * INTERVAL '1 second';
	next_hold	TIMESTAMP WITH TIME ZONE := clock_timestamp();
	reason		TEXT;
	c			net540_backfill.chunk;
	u			net540_backfill.unit;
	pos_day		TIMESTAMP WITH TIME ZONE := '-infinity';
	pos_sid		UUID := '00000000-0000-0000-0000-000000000000';
	pos_chunk	INTEGER := -1;
	r			net540_backfill.unit_result;
	results		net540_backfill.unit_result[];
	hrs			TIMESTAMP WITH TIME ZONE[];
	hr			TIMESTAMP WITH TIME ZONE;
	outcome		TEXT;
	whole		BOOLEAN;
	n_err		INTEGER;
	n_run		INTEGER;
	e_state		TEXT;
	e_msg		TEXT;
BEGIN
	p_done := 0;
	p_failed := 0;
	IF p_slice NOT IN ('count', 'rewrite') THEN
		RAISE EXCEPTION 'Unknown slice mode %', p_slice;
	END IF;
	LOOP
		IF (SELECT stop FROM net540_backfill.control) THEN
			p_status := 'stop';
			RETURN;
		END IF;
		IF clock_timestamp() >= next_hold THEN
			reason := net540_backfill.hold_reason(p_max_stale, p_max_lag, p_replicas, p_max_ready);
			IF reason IS NOT NULL THEN
				p_status := 'hold: ' || reason;
				RETURN;
			END IF;
			next_hold := clock_timestamp() + INTERVAL 'PT10S';
		END IF;

		u := NULL;
		IF p_planned_only THEN
			SELECT x.* INTO u FROM net540_backfill.unit x
			WHERE x.dry = p_dry
			ORDER BY x.chunk_no, x.day, x.stream_id
			LIMIT 1
			FOR UPDATE SKIP LOCKED;
			IF u.stream_id IS NULL THEN
				p_status := CASE WHEN EXISTS (SELECT 1 FROM net540_backfill.unit x WHERE x.dry = p_dry)
					THEN 'wait' ELSE 'done' END;
				COMMIT;
				RETURN;
			END IF;
		ELSE
			IF EXISTS (SELECT 1 FROM net540_backfill.chunk WHERE status = 'failed') THEN
				SELECT 'failed:' || min(chunk_no) INTO p_status FROM net540_backfill.chunk WHERE status = 'failed';
				RETURN;
			END IF;
			SELECT x.* INTO c FROM net540_backfill.chunk x
			WHERE x.status IN ('pending', 'planning', 'filling')
			ORDER BY x.chunk_no
			LIMIT 1;
			IF c.chunk_no IS NULL THEN
				p_status := 'done';
				RETURN;
			ELSIF c.status IN ('pending', 'planning') THEN
				CALL net540_backfill.plan_chunk(c.chunk_no, FALSE, 0, '');
				IF (SELECT x.status FROM net540_backfill.chunk x WHERE x.chunk_no = c.chunk_no)
						IN ('pending', 'planning') THEN
					-- the other worker is planning a batch of it, or a stop was asked for
					p_status := 'wait';
					COMMIT;
					RETURN;
				END IF;
				CONTINUE;
			END IF;
			IF c.chunk_no <> pos_chunk THEN
				pos_chunk := c.chunk_no;
				pos_day := '-infinity';
				pos_sid := '00000000-0000-0000-0000-000000000000';
			END IF;
			SELECT x.* INTO u FROM net540_backfill.unit x
			WHERE NOT x.dry AND x.chunk_no = c.chunk_no AND (x.day, x.stream_id) > (pos_day, pos_sid)
			ORDER BY x.day, x.stream_id
			LIMIT 1
			FOR UPDATE SKIP LOCKED;
			IF u.stream_id IS NULL AND pos_day > '-infinity' THEN
				-- from the start again, for a unit passed over while the other worker had it
				pos_day := '-infinity';
				pos_sid := '00000000-0000-0000-0000-000000000000';
				CONTINUE;
			ELSIF u.stream_id IS NULL THEN
				IF EXISTS (SELECT 1 FROM net540_backfill.unit x WHERE NOT x.dry AND x.chunk_no = c.chunk_no) THEN
					p_status := 'wait';
					COMMIT;
					RETURN;
				END IF;
				UPDATE net540_backfill.chunk SET status = 'filled', filled = now()
				WHERE chunk_no = c.chunk_no AND status = 'filling';
				p_status := CASE WHEN FOUND THEN 'filled:' || c.chunk_no ELSE 'wait' END;
				COMMIT;
				RETURN;
			END IF;
			pos_day := u.day;
			pos_sid := u.stream_id;
		END IF;

		-- the unit in one go
		results := '{}';
		n_err := 0;
		whole := TRUE;
		outcome := 'ok';
		BEGIN
			r := net540_backfill.fill_unit(u.stream_id, u.day, u.day_end, u.chunk_no, u.dry, p_slice, p_planned_only);
			results := ARRAY[r];
		EXCEPTION WHEN OTHERS THEN
			GET STACKED DIAGNOSTICS e_state = RETURNED_SQLSTATE, e_msg = MESSAGE_TEXT;
			outcome := net540_backfill.error_kind(e_state);
			IF outcome = 'cancel' THEN
				RAISE;
			END IF;
		END;
		IF outcome = 'data' THEN
			-- again hour by hour, so that only the hours that really fail are left unfilled
			whole := FALSE;
			outcome := 'ok';
			RAISE WARNING 'Unit failed: stream %, day %: % %; doing it hour by hour', u.stream_id, u.day, e_state, e_msg;
			EXECUTE format($q$
				SELECT COALESCE(array_agg(h.ts_start ORDER BY h.ts_start), '{}')
				FROM solardatm.agg_datm_hourly h
				WHERE h.stream_id = %1$L::uuid
					AND h.ts_start >= %2$L::timestamptz AND h.ts_start < %3$L::timestamptz
					AND h.ts_start = date_trunc('hour', h.ts_start, 'UTC')
					AND NOT EXISTS (
						SELECT 1 FROM solardatm.agg_datm_15m q
						WHERE q.stream_id = %1$L::uuid
							AND q.ts_start >= %2$L::timestamptz AND q.ts_start < %3$L::timestamptz
							AND q.ts_start >= h.ts_start AND q.ts_start < h.ts_start + INTERVAL 'PT1H'
					)
				$q$, u.stream_id, u.day, u.day_end) INTO hrs;
			BEGIN
				FOREACH hr IN ARRAY hrs LOOP
					BEGIN
						r := net540_backfill.fill_unit(u.stream_id, hr, hr + INTERVAL 'PT1H', u.chunk_no, u.dry
							, p_slice, p_planned_only);
						results := results || r;
						DELETE FROM net540_backfill.failed f
						WHERE f.dry = u.dry AND f.stream_id = u.stream_id AND f.ts_start = hr;
					EXCEPTION WHEN OTHERS THEN
						GET STACKED DIAGNOSTICS e_state = RETURNED_SQLSTATE, e_msg = MESSAGE_TEXT;
						IF net540_backfill.error_kind(e_state) <> 'data' THEN
							RAISE;
						END IF;
						INSERT INTO net540_backfill.failed (dry, stream_id, ts_start, chunk_no, day, sqlstate, message)
						VALUES (u.dry, u.stream_id, hr, u.chunk_no, u.day, e_state, e_msg)
						ON CONFLICT (dry, stream_id, ts_start) DO UPDATE
						SET chunk_no = EXCLUDED.chunk_no, day = EXCLUDED.day, at = EXCLUDED.at
							, sqlstate = EXCLUDED.sqlstate, message = EXCLUDED.message;
						n_err := n_err + 1;
						RAISE WARNING 'Hour failed: stream %, hour %: % %', u.stream_id, hr, e_state, e_msg;
					END;
				END LOOP;
			EXCEPTION WHEN OTHERS THEN
				-- a lock wait part way, say: nothing of the hours is kept
				GET STACKED DIAGNOSTICS e_state = RETURNED_SQLSTATE, e_msg = MESSAGE_TEXT;
				outcome := net540_backfill.error_kind(e_state);
				IF outcome = 'cancel' THEN
					RAISE;
				ELSIF outcome = 'data' THEN
					outcome := 'fatal';
				END IF;
				results := '{}';
				n_err := 0;
			END;
		END IF;
		IF outcome <> 'ok' THEN
			-- transient or fatal: the unit stays listed
			ROLLBACK;
			p_status := CASE WHEN outcome = 'transient' THEN 'retry: ' ELSE 'error: ' END
				|| e_state || ' ' || net540_backfill.one_line(e_msg);
			RETURN;
		END IF;
		IF whole THEN
			-- hours of it that failed before are done now
			DELETE FROM net540_backfill.failed f
			WHERE f.dry = u.dry AND f.stream_id = u.stream_id AND f.ts_start >= u.day AND f.ts_start < u.day_end;
		END IF;
		INSERT INTO net540_backfill.unit_log (dry, chunk_no, day, stream_id, pass, worker, exact
			, hours, slots, rows_15m, n_same, n_text_only, n_pad, n_round9, n_noise, n_no_raw
			, n_read_end, n_compact, n_other, n_stored_only, n_stale, n_slice, n_no_slots, n_error, n_prefix
			, slices_found, slices_rewritten, ms_probe, ms_compute)
		SELECT u.dry, u.chunk_no, u.day, u.stream_id
			, COALESCE((SELECT max(l.pass) FROM net540_backfill.unit_log l WHERE l.dry = u.dry
				AND l.chunk_no = u.chunk_no AND l.day = u.day AND l.stream_id = u.stream_id), 0) + 1
			, p_worker, p_planned_only
			, COALESCE(sum(x.hours), 0), COALESCE(sum(x.slots), 0), COALESCE(sum(x.rows_15m), 0)
			, COALESCE(sum(x.n_same), 0), COALESCE(sum(x.n_text_only), 0), COALESCE(sum(x.n_pad), 0)
			, COALESCE(sum(x.n_round9), 0), COALESCE(sum(x.n_noise), 0), COALESCE(sum(x.n_no_raw), 0)
			, COALESCE(sum(x.n_read_end), 0), COALESCE(sum(x.n_compact), 0), COALESCE(sum(x.n_other), 0)
			, COALESCE(sum(x.n_stored_only), 0), COALESCE(sum(x.n_stale), 0), COALESCE(sum(x.n_slice), 0)
			, COALESCE(sum(x.n_no_slots), 0), n_err, COALESCE(sum(x.n_prefix), 0)
			, COALESCE(sum(x.slices_found), 0), COALESCE(sum(x.slices_rewritten), 0)
			, COALESCE(sum(x.ms_probe), 0), COALESCE(sum(x.ms_compute), 0)
		FROM unnest(results) x;
		-- units in a row that failed in every hour: something is wrong for all of them
		IF n_err > 0 AND cardinality(results) = 0 THEN
			UPDATE net540_backfill.control SET fail_run = fail_run + 1 RETURNING fail_run INTO n_run;
		ELSE
			UPDATE net540_backfill.control SET fail_run = 0 WHERE fail_run > 0;
			n_run := 0;
		END IF;
		DELETE FROM net540_backfill.unit
		WHERE dry = u.dry AND chunk_no = u.chunk_no AND day = u.day AND stream_id = u.stream_id;
		COMMIT;
		p_done := p_done + 1;
		IF n_err > 0 THEN
			p_failed := p_failed + n_err;
			p_failure := e_state || ' ' || net540_backfill.one_line(e_msg);
		END IF;
		IF p_max_fail_run > 0 AND n_run >= p_max_fail_run THEN
			p_status := 'error: ' || n_run || ' units in a row failed in every hour, the last with ' || p_failure;
			RETURN;
		END IF;
		IF p_done >= p_units OR clock_timestamp() >= t_end THEN
			p_status := 'ok';
			RETURN;
		END IF;
	END LOOP;
END
$$;

/*
 * Check a chunk: list every hour of it with an hourly row and no 15 minute row, with its
 * reason (see unfilled), stream by stream through the primary keys, p_batch streams to a
 * transaction. A filled chunk becomes checked, or failed if any hour is missing (an hour listed
 * in failed is not a failure of the chunk); p_set_status false leaves the status alone (the
 * final check of every chunk), as does the check of a chunk that is not filled. An hour the
 * fill has not done yet is pending, and costs only a lookup in unit and unit_log, so a check of
 * a chunk not yet filled (after a trial, say) reads its hourly rows but computes nothing:
 * today's rollup is computed only for an hour whose unit is done and that has raw datum and no
 * 15 minute row. One check of a chunk runs at a time (a session advisory lock, 540540 and the
 * chunk number): another waits for it. It first drops from failed the chunk's hours that have a
 * 15 minute row now, or no hourly row.
 */
CREATE PROCEDURE net540_backfill.check_chunk(
		p_chunk			INTEGER,
		p_set_status	BOOLEAN DEFAULT TRUE,
		p_batch			INTEGER DEFAULT 500
	) LANGUAGE plpgsql AS $$
DECLARE
	c			net540_backfill.chunk;
	batch		UUID[];
	pos			UUID;
	counts		JSONB;
	n_batch		BIGINT;
	pending		BIGINT := 0;
	not_filled	BOOLEAN;
BEGIN
	IF NOT EXISTS (SELECT 1 FROM net540_backfill.chunk WHERE chunk_no = p_chunk) THEN
		RAISE EXCEPTION 'No chunk %', p_chunk;
	END IF;
	-- the fill's post-processing and the check command would both rewrite the chunk's list
	IF NOT pg_try_advisory_lock(540540, p_chunk) THEN
		RAISE NOTICE 'Waiting for another check of chunk % to finish', p_chunk;
		PERFORM set_config('lock_timeout', '0', TRUE);
		PERFORM pg_advisory_lock(540540, p_chunk);
	END IF;
	SELECT * INTO c FROM net540_backfill.chunk WHERE chunk_no = p_chunk;
	-- until the chunk is filled, a stream's day the fill has not been to is pending
	not_filled := c.status IN ('pending', 'planning', 'filling');
	-- failed hours filled since, or gone: no longer failed
	EXECUTE format($q$
		DELETE FROM net540_backfill.failed f
		WHERE NOT f.dry AND f.chunk_no = %1$s AND (
			EXISTS (
				SELECT 1 FROM solardatm.agg_datm_15m q
				WHERE q.stream_id = f.stream_id
					AND q.ts_start >= %2$L::timestamptz AND q.ts_start < %3$L::timestamptz
					AND q.ts_start >= f.ts_start AND q.ts_start < f.ts_start + INTERVAL 'PT1H'
			) OR NOT EXISTS (
				SELECT 1 FROM solardatm.agg_datm_hourly h
				WHERE h.stream_id = f.stream_id
					AND h.ts_start >= %2$L::timestamptz AND h.ts_start < %3$L::timestamptz
					AND h.ts_start = f.ts_start
			))
		$q$, p_chunk, c.range_start, c.range_end);
	DELETE FROM net540_backfill.unfilled WHERE chunk_no = p_chunk;
	COMMIT;
	LOOP
		SELECT array_agg(x.stream_id ORDER BY x.stream_id) INTO batch
		FROM (
			SELECT x.stream_id FROM net540_backfill.stream x
			WHERE pos IS NULL OR x.stream_id > pos
			ORDER BY x.stream_id
			LIMIT p_batch
		) x;
		EXIT WHEN batch IS NULL;
		pos := batch[cardinality(batch)];
		EXECUTE format($q$
			WITH y AS (
			SELECT s.stream_id, x.ts_start
				, CASE
					WHEN x.ts_start <> date_trunc('hour', x.ts_start, 'UTC') THEN 'off_hour'
					WHEN EXISTS (
						SELECT 1 FROM solardatm.agg_stale_datm st
						WHERE st.agg_kind = 'h' AND st.ts_start = x.ts_start AND st.stream_id = s.stream_id
					) THEN 'stale'
					WHEN EXISTS (
						SELECT 1 FROM net540_backfill.failed f
						WHERE NOT f.dry AND f.stream_id = s.stream_id AND f.ts_start = x.ts_start
					) THEN 'error'
					WHEN EXISTS (
						SELECT 1 FROM net540_backfill.unit u
						WHERE NOT u.dry AND u.chunk_no = %1$s
							AND u.day = GREATEST(date_trunc('day', x.ts_start, 'UTC'), %2$L::timestamptz)
							AND u.stream_id = s.stream_id
					) OR (%5$L::boolean AND NOT EXISTS (
						SELECT 1 FROM net540_backfill.unit_log l
						WHERE NOT l.dry AND l.chunk_no = %1$s
							AND l.day = GREATEST(date_trunc('day', x.ts_start, 'UTC'), %2$L::timestamptz)
							AND l.stream_id = s.stream_id
					)) THEN 'pending'
					WHEN EXISTS (
						SELECT 1 FROM net540_backfill.skipped k
						WHERE NOT k.dry AND k.stream_id = s.stream_id AND k.ts_start = x.ts_start AND k.reason = 'slice'
					) THEN 'slice'
					WHEN NOT EXISTS (
						SELECT 1 FROM solardatm.da_datm d
						WHERE d.stream_id = s.stream_id
							AND d.ts >= %2$L::timestamptz AND d.ts < %3$L::timestamptz
							AND d.ts >= x.ts_start AND d.ts < x.ts_start + INTERVAL 'PT1H'
					) THEN 'no_raw'
					-- rare: computed only for an hour done, with raw datum and no 15 minute row
					ELSE (
						SELECT CASE
							WHEN count(*) = 0 THEN 'no_today'
							WHEN COALESCE(sum(cardinality(r.slots)), 0) = 0 THEN 'no_slots'
							ELSE 'missing'
							END
						FROM solardatm.rollup_datm_15m_for_hour(s.stream_id, x.ts_start
							, x.ts_start + INTERVAL 'PT1H') r
					)
				  END AS reason
			FROM unnest(%4$L::uuid[]) AS s(stream_id)
			CROSS JOIN LATERAL (
				SELECT h.ts_start
				FROM solardatm.agg_datm_hourly h
				WHERE h.stream_id = s.stream_id
					AND h.ts_start >= %2$L::timestamptz AND h.ts_start < %3$L::timestamptz
					AND NOT EXISTS (
						SELECT 1 FROM solardatm.agg_datm_15m q
						WHERE q.stream_id = s.stream_id
							AND q.ts_start >= %2$L::timestamptz AND q.ts_start < %3$L::timestamptz
							AND q.ts_start >= h.ts_start AND q.ts_start < h.ts_start + INTERVAL 'PT1H'
					)
				OFFSET 0
			) x
			)
			, ins AS (
				INSERT INTO net540_backfill.unfilled (chunk_no, stream_id, ts_start, reason)
				SELECT %1$s, y.stream_id, y.ts_start, y.reason FROM y WHERE y.reason <> 'pending'
			)
			SELECT count(*) FILTER (WHERE y.reason = 'pending') FROM y
			$q$, p_chunk, c.range_start, c.range_end, batch, not_filled) INTO n_batch;
		pending := pending + n_batch;
		COMMIT;
	END LOOP;
	SELECT COALESCE(jsonb_object_agg(reason, n), '{}') INTO counts
	FROM (
		SELECT reason, count(*) AS n FROM net540_backfill.unfilled WHERE chunk_no = p_chunk GROUP BY reason
		UNION ALL
		SELECT 'pending', pending WHERE pending > 0
	) x;
	UPDATE net540_backfill.chunk
	SET unfilled = counts, checked = now()
		, status = CASE
			WHEN NOT p_set_status OR status NOT IN ('filled', 'checked', 'failed') THEN status
			WHEN COALESCE((counts ->> 'missing')::integer, 0) > 0 THEN 'failed'
			ELSE 'checked'
			END
	WHERE chunk_no = p_chunk;
	COMMIT;
	PERFORM pg_advisory_unlock(540540, p_chunk);
END
$$;

/*
 * The boundary phase: move step 1's boundary from p_expected (the backfill's range end) to
 * -infinity, so that from then on stale processing computes the 15 minute rows of every hour
 * it processes, and then wait, as NET-540-production-stale.sql does, until no session that
 * began before the move still holds a lock on agg_stale_datm: such a session may have read the
 * old boundary for an hour it is processing. Run again after a timeout, it only waits.
 */
CREATE PROCEDURE net540_backfill.move_boundary(p_expected TIMESTAMP WITH TIME ZONE) LANGUAGE plpgsql AS $$
DECLARE
	b			TIMESTAMP WITH TIME ZONE := solardatm.agg_datm_15m_complete_from();
	st			net540_backfill.setting;
	started		TIMESTAMP WITH TIME ZONE;
	deadline	TIMESTAMP WITH TIME ZONE;
	pids		INTEGER[];
BEGIN
	SELECT * INTO st FROM net540_backfill.setting;
	IF b IS NULL THEN
		RAISE EXCEPTION 'Step 1''s boundary is not set';
	ELSIF b = '-infinity' THEN
		IF st.boundary_moved IS NULL THEN
			RAISE EXCEPTION 'The boundary is already -infinity, but not moved by this backfill';
		END IF;
		started := st.boundary_moved;
	ELSIF b <> p_expected OR b <> st.range_end THEN
		RAISE EXCEPTION 'The boundary is %, not the expected % (range end %)', b, p_expected, st.range_end;
	ELSE
		UPDATE solardatm.agg_datm_15m_setting SET complete_from = '-infinity', modified = now();
		IF NOT FOUND THEN
			RAISE EXCEPTION 'No row in solardatm.agg_datm_15m_setting';
		END IF;
		UPDATE net540_backfill.setting SET boundary_moved = now(), boundary_waited = NULL;
		COMMIT;
		started := clock_timestamp();
		UPDATE net540_backfill.setting SET boundary_moved = started;
		COMMIT;
		RAISE NOTICE 'Moved the boundary from % to -infinity', b;
	END IF;

	deadline := clock_timestamp() + INTERVAL 'PT10M';
	LOOP
		PERFORM pg_stat_clear_snapshot();
		SELECT array_agg(DISTINCT a.pid ORDER BY a.pid) INTO pids
		FROM pg_catalog.pg_locks l
		INNER JOIN pg_catalog.pg_stat_activity a ON a.pid = l.pid
		WHERE l.locktype = 'relation'
			AND l.database = (SELECT oid FROM pg_catalog.pg_database WHERE datname = current_database())
			AND l.relation = 'solardatm.agg_stale_datm'::regclass
			AND a.pid <> pg_backend_pid()
			AND a.backend_type = 'client backend'
			AND a.xact_start < started;
		EXIT WHEN pids IS NULL;
		IF clock_timestamp() > deadline THEN
			RAISE EXCEPTION 'Gave up after 10 minutes waiting for sessions %', pids
			USING HINT = 'The boundary is moved. Run the boundary phase again to wait again.';
		END IF;
		PERFORM pg_sleep(0.5);
		COMMIT;
	END LOOP;
	UPDATE net540_backfill.setting SET boundary_waited = now();
	COMMIT;
	RAISE NOTICE 'No session that began before the move holds a lock on agg_stale_datm';
END
$$;

/*
 * Do a chunk again: after a failed check (and whatever caused it put right), or to fill the
 * hours of a chunk that are still without 15 minute rows, those that failed among them. It is
 * planned afresh: only the hours still without 15 minute rows get units. What the earlier passes
 * logged stays in unit_log, and its failed hours stay listed until they are done.
 */
CREATE PROCEDURE net540_backfill.retry_chunk(p_chunk INTEGER) LANGUAGE plpgsql AS $$
BEGIN
	DELETE FROM net540_backfill.unit WHERE NOT dry AND chunk_no = p_chunk;
	UPDATE net540_backfill.chunk
	SET status = 'pending', plan_pos = NULL, planned = NULL, filled = NULL, vacuumed = NULL
		, checked = NULL, reindexed = NULL, units = NULL, unfilled = NULL
	WHERE chunk_no = p_chunk;
	IF NOT FOUND THEN
		RAISE EXCEPTION 'No chunk %', p_chunk;
	END IF;
	COMMIT;
END
$$;

-- ---------------------------------------------------------------------------------------------
-- Settings and chunks
-- ---------------------------------------------------------------------------------------------

INSERT INTO net540_backfill.setting (script_version, range_start, range_end, clock_error)
VALUES (:'script_version'::integer, :'range_start'::timestamptz, :'range_end'::timestamptz, :'clock_error'::boolean);

-- the 15 minute chunks within the range, and any gap between them, in time order; with the
-- clock error switch, the times before and after the range as two more, filled last
WITH s AS (
	SELECT range_start AS rs, range_end AS re, clock_error FROM net540_backfill.setting
)
, c AS (
	SELECT GREATEST(c.range_start, s.rs) AS r0, LEAST(c.range_end, s.re) AS r1
		, format('%I.%I', c.chunk_schema, c.chunk_name) AS tbl
	FROM timescaledb_information.chunks c, s
	WHERE c.hypertable_schema = 'solardatm' AND c.hypertable_name = 'agg_datm_15m'
		AND c.range_end > s.rs AND c.range_start < s.re
)
, g AS (
	SELECT c.r1 AS g0, lead(c.r0, 1, s.re) OVER (ORDER BY c.r0) AS g1 FROM c, s
	UNION ALL
	SELECT s.rs, COALESCE((SELECT min(c.r0) FROM c), s.re) FROM s
)
, r AS (
	SELECT r0, r1, tbl, 0 AS grp FROM c
	UNION ALL
	SELECT g0, g1, NULL, 0 FROM g WHERE g1 > g0
	UNION ALL
	SELECT '-infinity', s.rs, NULL, 1 FROM s WHERE s.clock_error AND s.rs > '-infinity'
	UNION ALL
	SELECT s.re, 'infinity', NULL, 2 FROM s WHERE s.clock_error
)
INSERT INTO net540_backfill.chunk (chunk_no, range_start, range_end, chunk_table, index_name)
SELECT CASE WHEN r.grp = 0 THEN row_number() OVER (PARTITION BY r.grp = 0 ORDER BY r.r0) ELSE 1000 + r.grp END
	, r.r0, r.r1, r.tbl
	, (SELECT i.indexrelid::regclass::text FROM pg_catalog.pg_index i
		WHERE i.indrelid = r.tbl::regclass AND i.indisunique LIMIT 1)
FROM r;

SELECT 'installed net540_backfill: ' || count(*) || ' chunks from ' || min(range_start)
	|| ' to ' || max(range_end) AS installed
FROM net540_backfill.chunk;
