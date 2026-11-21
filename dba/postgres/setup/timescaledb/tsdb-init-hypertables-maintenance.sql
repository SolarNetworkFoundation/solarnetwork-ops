/* ============================================================================
 * OPS-51: hypertable chunk maintenance support, for the chunk-maintenance.sh
 * script in dba/postgres/scripts.
 *
 * The script keeps the chunks of the datum, aggregate and audit hypertables in
 * the order of their unique index, compacts chunks with a lot of free space or
 * index bloat, and keeps each chunk's statistics current. It replaces the
 * TimescaleDB reorder policies, which reorder each chunk only once, and the
 * weekly vacuumdb --analyze-only (turned off for OPS-45). The objects here decide
 * what each chunk needs; the script checks the server and the free space, then
 * acts on a few chunks a run, within a byte budget.
 *
 * This file is not part of tsdb-init.sql. Run it by hand, as a superuser, in each
 * database to be maintained:
 *
 *   psql -X -U postgres -d solarnetwork -f tsdb-init-hypertables-maintenance.sql
 *
 * It replaces the NET-112 and NET-124 chunk_index_maint support, which it drops.
 * It can be run again to update the objects; the chunk_maint_hypertable and
 * chunk_maint_log tables keep their rows.
 *
 * Objects, all in the _timescaledb_solarnetwork schema:
 *
 *   chunk_maint_hypertable   the hypertables to maintain, with the index to keep
 *                            each one's chunks in the order of
 *   chunk_maint_log          one row for each task the script performs
 *   chunk_maint_chunk        facts about every chunk of those hypertables
 *   chunk_maint_status       what each chunk needs, and why, or why it is left
 *                            alone
 *   chunk_maint_candidates   the chunks that need something, in the order the
 *                            script takes them
 *   chunk_maint_preflight    the server checks the script makes before it starts
 *   chunk_maint_storage      the directory of each tablespace and of pg_wal
 *
 *   SELECT chunk, range_end, corr, mod_pct, skip_reason, action, reason
 *   FROM _timescaledb_solarnetwork.chunk_maint_status
 *   ORDER BY hypertable_name, range_end;
 *
 *   SELECT priority, chunk, action, reason, analyze_first, pg_size_pretty(cost)
 *   FROM _timescaledb_solarnetwork.chunk_maint_candidates
 *   ORDER BY priority;
 *
 * What each chunk gets, in chunk_maint_status.action:
 *
 *   reorder   rewrite the chunk in index order with reorder_chunk(), when it is
 *             out of order or has a lot of free space. reorder_chunk() writes
 *             the new copy where the chunk is: the heap in its tablespace, and
 *             each index in the index's own tablespace. (An index in the
 *             database's default tablespace may be put elsewhere, such as in one
 *             of the hypertable's attached tablespaces, which the free space
 *             check does not allow for.)
 *   cluster   the same with CLUSTER, for testing on a server without the
 *             TimescaleDB licence (chunk_maint.use_cluster)
 *   reindex   REINDEX INDEX CONCURRENTLY, when only the index is bloated
 *   analyze   ANALYZE, when enough rows have changed since the chunk's last
 *             ANALYZE
 *
 * After a rewrite the script always analyzes the chunk, as reorder_chunk() does
 * not.
 *
 * How it decides:
 *
 *  - Order is judged by pg_stats.correlation of the first column of the reorder
 *    index (stream_id). If a fraction f of a chunk's rows is out of index order,
 *    the correlation is about (1 - f)^2: 1 for a chunk in order, about 0 for one
 *    in ingest order, and 0.9 for one with about 5% of its rows out of order.
 *  - The correlation is only as current as the chunk's last ANALYZE, so every
 *    row changed since then is counted as out of order (corr_est). When that is
 *    what makes a chunk need a rewrite, or when the statistics may predate the
 *    chunk's last rewrite (stats_current), analyze_first is true: the script
 *    analyzes the chunk and looks again before rewriting it.
 *  - A chunk whose relfilenode is still its OID has never been rewritten. One
 *    rewritten by something other than this script (move_chunks, the old reorder
 *    policies) may have been rewritten after its last ANALYZE.
 *  - Heap free space is measured with pgstattuple_approx() when the pgstattuple
 *    extension is installed, for the chunks the statistics show as free enough;
 *    otherwise it is estimated from the statistics, which runs a few points high.
 *  - Index bloat is estimated from the statistics, as in the index_health view
 *    (queries/index-health-view.sql).
 *
 * A chunk is left alone (skip_reason) when it is compressed, has no reorder
 * index, ended less than chunk_maint.min_age ago, is due to be moved by a
 * move_chunks job within chunk_maint.move_margin (that move reorders it), or is
 * smaller than chunk_maint.min_chunk_mb.
 *
 * A chunk that a move_chunks job (OPS-38) has moved out of its hypertable's
 * tablespace (moved), to solarwarm or, where there is one, solarcold, is
 * maintained where it is, after the chunks on main storage. Nothing here names
 * those tablespaces: the jobs' configurations say where chunks go and when,
 * lag_max included. With a solarwarm job for chunks 5 to 8 years old and a
 * solarcold job for older ones, a chunk on main storage is left alone once it is
 * about 4.5 years old, and one in solarwarm once it is about 7.5, as each is then
 * due to move within the default move_margin; one in solarcold is never due to
 * move again.
 *
 * The thresholds can be changed for a session, without recreating the views (the
 * script does this with -s NAME=VALUE):
 *
 *   SET chunk_maint.min_age = '7 days';         -- age of a chunk's end before it is touched
 *   SET chunk_maint.move_margin = '6 months';   -- skip chunks moving within this
 *   SET chunk_maint.min_chunk_mb = 100;         -- skip smaller chunks (heap and indexes)
 *   SET chunk_maint.max_corr = 0.9;             -- reorder when corr_est is below this
 *   SET chunk_maint.min_free_pct = 20;          -- rewrite when this much of the heap is free
 *   SET chunk_maint.min_free_mb = 1024;         --   and at least this much
 *   SET chunk_maint.min_bloat_pct = 30;         -- reindex when this much of the index is bloat
 *   SET chunk_maint.min_bloat_mb = 1024;        --   and at least this much
 *   SET chunk_maint.analyze_pct = 2;            -- analyze when this many rows changed (percent)
 *   SET chunk_maint.rewrite_interval = '30 days'; -- don't rewrite a chunk again within this
 *   SET chunk_maint.temp_tablespace = 'solar';  -- where the sort spills; default the database's
 *   SET chunk_maint.use_pgstattuple = on;       -- measure heap free space if possible
 *   SET chunk_maint.use_cluster = off;          -- CLUSTER in place of reorder_chunk(): testing only
 *   SET chunk_maint.max_archive_ready = 64;     -- preflight: WAL segments waiting to be archived
 *   SET chunk_maint.max_replica_lag_mb = 1024;  -- preflight: replica and slot lag
 *
 * The space and IO each task needs, in bytes, as the script counts them:
 *
 *   heap_need, index_need   a new copy of the heap, or of the indexes, in the
 *                           chunk's tablespaces
 *   temp_need               sort spill in temp_tablespace: 1.25 x the heap for a
 *                           rewrite, the index for a reindex
 *   wal_need                WAL written: the heap and indexes for a rewrite
 *   analyze_bytes           the pages one ANALYZE of the chunk reads: up to 300 x
 *                           the statistics target
 *   cost                    what the task counts against the script's budget:
 *                           the heap and indexes rewritten, plus each ANALYZE
 * ============================================================================
 */

BEGIN;

CREATE SCHEMA IF NOT EXISTS _timescaledb_solarnetwork;

-- ----------------------------------------------------------------------------
-- Remove the NET-112 and NET-124 chunk index maintenance support.
-- ----------------------------------------------------------------------------

DO $$
DECLARE
	f regprocedure;
BEGIN
	FOR f IN
		SELECT p.oid::regprocedure
		FROM pg_catalog.pg_proc p
		INNER JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
		WHERE n.nspname = '_timescaledb_solarnetwork'
			AND p.proname IN (
				'find_chunk_index_need_maint'
				, 'find_chunk_index_need_reindex_maint'
				, 'find_chunk_index_need_cluster_maint'
				, 'perform_one_chunk_reindex_maintenance'
				, 'perform_one_chunk_cluster_maintenance'
				, 'perform_chunk_reindex_maintenance'
			)
	LOOP
		EXECUTE format('DROP FUNCTION %s', f);
	END LOOP;
END
$$;

DROP VIEW IF EXISTS _timescaledb_solarnetwork.chunk_time_index_maint;
DROP TABLE IF EXISTS _timescaledb_solarnetwork.chunk_index_maint;

-- only the chunk_index_maint foreign key into the TimescaleDB catalog needed this
REVOKE REFERENCES ON TABLE _timescaledb_catalog.chunk FROM PUBLIC;


-- ----------------------------------------------------------------------------
-- pgstattuple: pgstattuple_approx() measures a chunk's free space cheaply. It is
-- optional: without it, free space is estimated from the statistics.
-- ----------------------------------------------------------------------------

DO $$
BEGIN
	IF EXISTS (SELECT 1 FROM pg_catalog.pg_available_extensions WHERE name = 'pgstattuple') THEN
		CREATE EXTENSION IF NOT EXISTS pgstattuple WITH SCHEMA public;
	ELSE
		RAISE NOTICE 'The pgstattuple extension is not available, so chunk free space will be estimated from the statistics.';
	END IF;
END
$$;


-- ----------------------------------------------------------------------------
-- Tables
-- ----------------------------------------------------------------------------

/**
 * The hypertables whose chunks are maintained, and for each the index to keep its chunks in the
 * order of.
 *
 * reorder_index is the name of an index on the hypertable, in the hypertable's schema. Set enabled
 * to FALSE to leave a hypertable alone.
 */
CREATE TABLE IF NOT EXISTS _timescaledb_solarnetwork.chunk_maint_hypertable (
	hypertable_schema	TEXT NOT NULL,
	hypertable_name		TEXT NOT NULL,
	reorder_index		TEXT NOT NULL,
	enabled				BOOLEAN NOT NULL DEFAULT TRUE,
	CONSTRAINT chunk_maint_hypertable_pkey PRIMARY KEY (hypertable_schema, hypertable_name)
);

-- the hypertables NET-266 gave reorder policies
INSERT INTO _timescaledb_solarnetwork.chunk_maint_hypertable (hypertable_schema, hypertable_name, reorder_index)
VALUES
	('solardatm', 'da_datm', 				'da_datm_pkey'),
	('solardatm', 'agg_datm_hourly', 		'agg_datm_hourly_pkey'),
	('solardatm', 'agg_datm_daily', 		'agg_datm_daily_pkey'),
	('solardatm', 'agg_datm_monthly', 		'agg_datm_monthly_pkey'),
	('solardatm', 'aud_datm_io', 			'aud_datm_io_pkey'),
	('solardatm', 'aud_datm_daily', 		'aud_datm_daily_pkey'),
	('solardatm', 'aud_datm_monthly', 		'aud_datm_monthly_pkey'),
	('solardatm', 'aud_acc_datm_daily', 	'aud_acc_datm_daily_pkey')
ON CONFLICT DO NOTHING;

/**
 * One row for each task performed on a chunk. A row with no finished time is a task still running,
 * or one that was interrupted. A row with an error is a task that failed; a rewrite that failed was
 * rolled back.
 *
 * relfilenode_after is the chunk's relfilenode once the task finished. Every task but reindex ends
 * with an ANALYZE, so a chunk whose relfilenode matches one of these rows has statistics newer than
 * its last rewrite.
 */
CREATE TABLE IF NOT EXISTS _timescaledb_solarnetwork.chunk_maint_log (
	id					BIGINT GENERATED BY DEFAULT AS IDENTITY,
	started				TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT clock_timestamp(),
	finished			TIMESTAMP WITH TIME ZONE,
	hypertable_schema	TEXT NOT NULL,
	hypertable_name		TEXT NOT NULL,
	chunk_schema		TEXT NOT NULL,
	chunk_name			TEXT NOT NULL,
	range_end			TIMESTAMP WITH TIME ZONE,
	action				TEXT NOT NULL,
	reason				TEXT,
	stmt				TEXT,
	heap_tablespace		TEXT,
	index_tablespace	TEXT,
	heap_bytes_before	BIGINT,
	index_bytes_before	BIGINT,
	corr_before			REAL,
	heap_bytes_after	BIGINT,
	index_bytes_after	BIGINT,
	corr_after			REAL,
	relfilenode_after	OID,
	error				TEXT,
	CONSTRAINT chunk_maint_log_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS chunk_maint_log_chunk_idx
	ON _timescaledb_solarnetwork.chunk_maint_log (chunk_schema, chunk_name);


-- ----------------------------------------------------------------------------
-- Functions used by the views
-- ----------------------------------------------------------------------------

/**
 * The percentage of a chunk's heap that is free or holds dead rows, measured with
 * pgstattuple_approx(); NULL when the pgstattuple extension is not installed or the current role
 * may not use it (it needs superuser or pg_stat_scan_tables).
 *
 * pgstattuple_approx() reads only the pages that the visibility map does not show as all-visible,
 * and takes the free space of the rest from the free space map, so it is cheap on a chunk that is no
 * longer written to.
 *
 * @param chunk the chunk to measure
 */
CREATE OR REPLACE FUNCTION _timescaledb_solarnetwork.chunk_maint_heap_free_pct(chunk regclass)
	RETURNS DOUBLE PRECISION LANGUAGE plpgsql VOLATILE STRICT AS
$$
DECLARE
	ext_schema name;
	result DOUBLE PRECISION;
BEGIN
	SELECT n.nspname INTO ext_schema
	FROM pg_catalog.pg_extension e
	INNER JOIN pg_catalog.pg_namespace n ON n.oid = e.extnamespace
	WHERE e.extname = 'pgstattuple';

	IF ext_schema IS NULL THEN
		RETURN NULL;
	END IF;

	EXECUTE format('SELECT approx_free_percent + dead_tuple_percent FROM %I.pgstattuple_approx($1)', ext_schema)
	INTO result
	USING chunk;

	RETURN result;
EXCEPTION WHEN insufficient_privilege THEN
	RETURN NULL;
END
$$;


-- ----------------------------------------------------------------------------
-- Views
-- ----------------------------------------------------------------------------

DROP VIEW IF EXISTS _timescaledb_solarnetwork.chunk_maint_candidates;
DROP VIEW IF EXISTS _timescaledb_solarnetwork.chunk_maint_status;
DROP VIEW IF EXISTS _timescaledb_solarnetwork.chunk_maint_chunk;
DROP VIEW IF EXISTS _timescaledb_solarnetwork.chunk_maint_preflight;
DROP VIEW IF EXISTS _timescaledb_solarnetwork.chunk_maint_storage;

/**
 * Facts about every chunk of the enabled chunk_maint_hypertable hypertables: no thresholds, no
 * decisions. It reads only the catalogs, the statistics and the size of each file.
 *
 * moved is true for a chunk whose heap is not in its hypertable's tablespace, as a move_chunks job
 * leaves one (in solarwarm or solarcold). move_due is when a move_chunks job will move the chunk to
 * another tablespace, reordering it as it does. analyzed_here is true when this script analyzed the
 * chunk since it was last rewritten.
 */
CREATE VIEW _timescaledb_solarnetwork.chunk_maint_chunk AS
WITH mv AS (
	-- the move_chunks jobs (OPS-38): each moves the chunks older than lag (and, if it has a lag_max,
	-- starting less than lag_max ago, as show_chunks(newer_than) does) to its destination tablespace
	SELECT to_regclass(j.config->>'hypertable') AS ht
		, (j.config->>'lag')::INTERVAL AS lag
		, (j.config->>'lag_max')::INTERVAL AS lag_max
		, j.config->>'destination_tablespace' AS destination
	FROM timescaledb_information.jobs j
	WHERE j.proc_name = 'move_chunks'
		AND j.scheduled
		AND j.config ? 'hypertable'
		AND j.config ? 'lag'
)
SELECT m.hypertable_schema
	, m.hypertable_name
	, ch.chunk_schema::TEXT AS chunk_schema
	, ch.chunk_name::TEXT AS chunk_name
	, c.oid::regclass AS chunk
	, ch.range_start
	, ch.range_end
	, ch.is_compressed
	, c.relfilenode
	, c.reltablespace <> htc.reltablespace AS moved
	, COALESCE(ct.spcname, dbt.spcname)::TEXT AS heap_tablespace
	, format('%I.%I', m.hypertable_schema, m.reorder_index) AS reorder_index
	, ix.oid::regclass AS chunk_index
	, ix.relname::TEXT AS chunk_index_name
	, COALESCE(it.spcname, dbt.spcname)::TEXT AS index_tablespace
	, pg_table_size(c.oid) AS heap_bytes
	, pg_relation_size(c.oid) AS heap_main_bytes
	, pg_indexes_size(c.oid) AS index_bytes
	, pg_relation_size(ix.oid) AS reorder_index_bytes
	, c.relpages
	, c.reltuples
	, c.relnatts
	, COALESCE((
		SELECT o.option_value::NUMERIC FROM pg_options_to_table(c.reloptions) o WHERE o.option_name = 'fillfactor'
		), 100) AS heap_fillfactor
	, ix.reltuples AS index_reltuples
	, COALESCE((
		SELECT o.option_value::NUMERIC FROM pg_options_to_table(ix.reloptions) o WHERE o.option_name = 'fillfactor'
		), 90) AS index_fillfactor
	, s.correlation AS corr
	, hw.data_width AS heap_data_width
	, iw.data_width AS index_data_width
	, iw.null_frac AS index_null_frac
	, iw.has_stats AS index_has_stats
	, st.n_mod_since_analyze AS mod_since_analyze
	, st.n_tup_ins + st.n_tup_upd + st.n_tup_del AS writes
	, GREATEST(st.last_analyze, st.last_autoanalyze) AS analyzed
	-- ANALYZE samples 300 rows for each unit of the largest statistics target of any column
	, GREATEST(current_setting('default_statistics_target')::INTEGER, (
		SELECT max(a.attstattarget)
		FROM pg_catalog.pg_attribute a
		WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
		)) AS stats_target
	, (
		SELECT min(ch.range_end + mv.lag)
		FROM mv
		WHERE mv.ht = htc.oid
			AND mv.destination IS DISTINCT FROM COALESCE(ct.spcname, dbt.spcname)
			AND (mv.lag_max IS NULL OR ch.range_start >= CURRENT_TIMESTAMP - mv.lag_max)
	) AS move_due
	, lg.last_rewrite
	, lg.last_reindex
	, COALESCE(lg.analyzed_here, FALSE) AS analyzed_here
FROM _timescaledb_solarnetwork.chunk_maint_hypertable m
INNER JOIN pg_catalog.pg_namespace htn ON htn.nspname = m.hypertable_schema
INNER JOIN pg_catalog.pg_class htc ON htc.relnamespace = htn.oid AND htc.relname = m.hypertable_name
INNER JOIN timescaledb_information.chunks ch
	ON ch.hypertable_schema = m.hypertable_schema AND ch.hypertable_name = m.hypertable_name
INNER JOIN _timescaledb_catalog.chunk cat ON cat.schema_name = ch.chunk_schema AND cat.table_name = ch.chunk_name
INNER JOIN pg_catalog.pg_namespace cn ON cn.nspname = ch.chunk_schema
INNER JOIN pg_catalog.pg_class c ON c.relnamespace = cn.oid AND c.relname = ch.chunk_name
CROSS JOIN (
	SELECT t.spcname
	FROM pg_catalog.pg_database d
	INNER JOIN pg_catalog.pg_tablespace t ON t.oid = d.dattablespace
	WHERE d.datname = current_database()
) dbt
LEFT JOIN pg_catalog.pg_tablespace ct ON ct.oid = c.reltablespace
LEFT JOIN _timescaledb_catalog.chunk_index ci ON ci.chunk_id = cat.id AND ci.hypertable_index_name = m.reorder_index
LEFT JOIN pg_catalog.pg_class ix ON ix.relnamespace = cn.oid AND ix.relname = ci.index_name
LEFT JOIN pg_catalog.pg_index i ON i.indexrelid = ix.oid
LEFT JOIN pg_catalog.pg_tablespace it ON it.oid = ix.reltablespace
LEFT JOIN pg_catalog.pg_attribute la ON la.attrelid = c.oid AND la.attnum = i.indkey[0]
LEFT JOIN pg_catalog.pg_stats s ON s.schemaname = ch.chunk_schema
	AND s.tablename = ch.chunk_name
	AND s.attname = la.attname
	AND NOT s.inherited
LEFT JOIN pg_catalog.pg_stat_user_tables st ON st.relid = c.oid
-- the average width of a row's columns
LEFT JOIN LATERAL (
	SELECT sum((1 - hs.null_frac) * hs.avg_width) AS data_width
	FROM pg_catalog.pg_stats hs
	WHERE hs.schemaname = ch.chunk_schema AND hs.tablename = ch.chunk_name AND NOT hs.inherited
) hw ON TRUE
-- the average width of a reorder index entry's columns
LEFT JOIN LATERAL (
	SELECT sum((1 - COALESCE(xs.null_frac, 0)) * xs.avg_width) AS data_width
		, max(COALESCE(xs.null_frac, 0)) AS null_frac
		, count(*) = count(xs.avg_width) AS has_stats
	FROM generate_series(0, i.indnatts - 1) AS k(pos)
	INNER JOIN pg_catalog.pg_attribute xa ON xa.attrelid = c.oid AND xa.attnum = i.indkey[k.pos]
	LEFT JOIN pg_catalog.pg_stats xs ON xs.schemaname = ch.chunk_schema
		AND xs.tablename = ch.chunk_name
		AND xs.attname = xa.attname
		AND NOT xs.inherited
) iw ON TRUE
LEFT JOIN LATERAL (
	SELECT max(l.finished) FILTER (WHERE l.action IN ('reorder', 'cluster')) AS last_rewrite
		, max(l.finished) FILTER (WHERE l.action = 'reindex') AS last_reindex
		, bool_or(l.action <> 'reindex' AND l.relfilenode_after = c.relfilenode) AS analyzed_here
	FROM _timescaledb_solarnetwork.chunk_maint_log l
	WHERE l.chunk_schema = ch.chunk_schema
		AND l.chunk_name = ch.chunk_name
		AND l.finished IS NOT NULL
		AND l.error IS NULL
) lg ON TRUE
WHERE m.enabled;

/**
 * What each chunk of the enabled chunk_maint_hypertable hypertables needs, and why; see the notes
 * at the top of this file. action is NULL for a chunk that needs nothing, or one that is left alone
 * (skip_reason). stmt is the statement that performs action, and analyze_stmt the ANALYZE that
 * follows a rewrite, or comes first when analyze_first is true.
 */
CREATE VIEW _timescaledb_solarnetwork.chunk_maint_status AS
SELECT d.hypertable_schema
	, d.hypertable_name
	, d.chunk_schema
	, d.chunk_name
	, d.chunk
	, d.range_start
	, d.range_end
	, d.moved
	, d.heap_tablespace
	, d.index_tablespace
	, d.heap_bytes
	, d.index_bytes
	, d.reltuples::BIGINT AS reltuples
	, round(d.corr::NUMERIC, 3) AS corr
	, round(d.corr_est::NUMERIC, 3) AS corr_est
	, d.mod_since_analyze
	, round((100 * d.mod_frac)::NUMERIC, 2) AS mod_pct
	, d.analyzed
	, d.stats_current
	, round(d.heap_free_pct::NUMERIC, 1) AS heap_free_pct
	, d.heap_free_measured IS NOT NULL AS heap_free_measured
	, round(d.index_bloat_pct::NUMERIC, 1) AS index_bloat_pct
	, d.move_due
	, d.last_rewrite
	, d.skip_reason
	, d.action
	, CASE
		WHEN d.action IN ('reorder', 'cluster') THEN concat_ws('; '
			, CASE WHEN d.order_needed THEN
				format('correlation %s', COALESCE(round(d.corr::NUMERIC, 3)::TEXT, 'unknown'))
				|| CASE WHEN round((100 * d.mod_frac)::NUMERIC, 1) > 0
					THEN format(', with %s%% of rows changed since analyzed', round((100 * d.mod_frac)::NUMERIC, 1))
					ELSE '' END
				END
			, CASE WHEN d.heap_needed THEN
				format('heap %s%% free (%s)', round(d.heap_free_pct::NUMERIC, 1), pg_size_pretty(d.heap_free_bytes::BIGINT))
				END)
		WHEN d.action = 'reindex' THEN
			format('index %s%% bloat (%s)', round(d.index_bloat_pct::NUMERIC, 1), pg_size_pretty(d.index_bloat_bytes::BIGINT))
		WHEN d.action = 'analyze' THEN
			format('%s%% of rows changed since analyzed', round((100 * d.mod_frac)::NUMERIC, 1))
		END AS reason
	, d.analyze_first
	, CASE d.action
		WHEN 'reorder' THEN format('SELECT %I.reorder_chunk(%L, %L)'
			, d.tsdb_schema, format('%I.%I', d.chunk_schema, d.chunk_name), d.reorder_index)
		WHEN 'cluster' THEN format('CLUSTER %I.%I USING %I', d.chunk_schema, d.chunk_name, d.chunk_index_name)
		WHEN 'reindex' THEN format('REINDEX INDEX CONCURRENTLY %I.%I', d.chunk_schema, d.chunk_index_name)
		WHEN 'analyze' THEN format('ANALYZE %I.%I', d.chunk_schema, d.chunk_name)
		END AS stmt
	, format('ANALYZE %I.%I', d.chunk_schema, d.chunk_name) AS analyze_stmt
	, d.temp_tablespace
	, CASE WHEN d.action IN ('reorder', 'cluster') THEN d.heap_bytes ELSE 0 END AS heap_need
	, CASE
		WHEN d.action IN ('reorder', 'cluster') THEN d.index_bytes
		WHEN d.action = 'reindex' THEN d.reorder_index_bytes
		ELSE 0 END AS index_need
	, CASE
		WHEN d.action IN ('reorder', 'cluster') THEN ceil(1.25 * d.heap_bytes)::BIGINT
		WHEN d.action = 'reindex' THEN d.reorder_index_bytes
		ELSE 0 END AS temp_need
	, CASE
		WHEN d.action IN ('reorder', 'cluster') THEN d.heap_bytes + d.index_bytes
		WHEN d.action = 'reindex' THEN d.reorder_index_bytes
		ELSE 0 END AS wal_need
	, d.analyze_bytes
	, CASE
		WHEN d.action IN ('reorder', 'cluster') THEN d.heap_bytes + d.index_bytes + d.analyze_bytes
		WHEN d.action = 'reindex' THEN d.reorder_index_bytes
		WHEN d.action = 'analyze' THEN d.analyze_bytes
		ELSE 0 END
		+ CASE WHEN d.analyze_first THEN d.analyze_bytes ELSE 0 END AS cost
	, d.writes
	, d.mod_frac
FROM (
	SELECT a.*
		-- analyze first when the statistics may predate the chunk's last rewrite, or when only the
		-- rows changed since the last ANALYZE make the chunk look out of order
		, CASE
			WHEN a.action IN ('reorder', 'cluster') THEN NOT a.stats_current OR NOT (a.order_raw OR a.heap_needed)
			WHEN a.action = 'reindex' THEN NOT a.stats_current
			ELSE FALSE
			END AS analyze_first
	FROM (
		SELECT m.*
			, CASE
				WHEN m.skip_reason IS NOT NULL THEN NULL
				WHEN (m.order_needed OR m.heap_needed) AND NOT m.recently_rewritten THEN
					CASE WHEN m.use_cluster THEN 'cluster' ELSE 'reorder' END
				WHEN m.bloat_needed AND NOT m.recently_rewritten AND NOT m.recently_reindexed THEN 'reindex'
				WHEN m.mod_frac >= m.analyze_frac THEN 'analyze'
				END AS action
		FROM (
			SELECT e.*
				, COALESCE(e.heap_free_measured, e.heap_free_pct_stats) AS heap_free_pct
				, e.heap_main_bytes * COALESCE(e.heap_free_measured, e.heap_free_pct_stats) / 100 AS heap_free_bytes
				, 100 * e.index_bloat_bytes / NULLIF(e.reorder_index_bytes, 0) AS index_bloat_pct
				, (1 - LEAST(1, COALESCE(e.f_raw, 1) + e.mod_frac)) ^ 2 AS corr_est
				, e.corr IS NOT NULL AND e.corr < e.max_corr AS order_raw
				, (1 - LEAST(1, COALESCE(e.f_raw, 1) + e.mod_frac)) ^ 2 < e.max_corr AS order_needed
				, COALESCE(COALESCE(e.heap_free_measured, e.heap_free_pct_stats) >= e.min_free_pct
					AND e.heap_main_bytes * COALESCE(e.heap_free_measured, e.heap_free_pct_stats) / 100 >= e.min_free_bytes
					, FALSE) AS heap_needed
				, COALESCE(100 * e.index_bloat_bytes / NULLIF(e.reorder_index_bytes, 0) >= e.min_bloat_pct
					AND e.index_bloat_bytes >= e.min_bloat_bytes
					, FALSE) AS bloat_needed
				, e.analyzed IS NOT NULL AND (e.relfilenode = e.chunk::OID OR e.analyzed_here) AS stats_current
				, COALESCE(e.last_rewrite > CURRENT_TIMESTAMP - e.rewrite_interval, FALSE) AS recently_rewritten
				, COALESCE(e.last_reindex > CURRENT_TIMESTAMP - e.rewrite_interval, FALSE) AS recently_reindexed
			FROM (
				SELECT k.*
					-- measure the free space of a chunk the statistics show as free enough to rewrite
					, CASE
						WHEN k.use_pgstattuple
							AND k.skip_reason IS NULL
							AND k.heap_free_pct_stats >= k.min_free_pct
							AND k.heap_main_bytes * k.heap_free_pct_stats / 100 >= k.min_free_bytes
						THEN _timescaledb_solarnetwork.chunk_maint_heap_free_pct(k.chunk)
						END AS heap_free_measured
					, CASE WHEN k.index_est_bytes IS NOT NULL
						THEN GREATEST(k.reorder_index_bytes - k.index_est_bytes, 0)
						END AS index_bloat_bytes
				FROM (
					SELECT c.*
						, cfg.*
						-- the fraction of the rows out of index order, from corr = (1 - f)^2
						, CASE WHEN c.corr IS NOT NULL THEN 1 - sqrt(GREATEST(c.corr, 0)) END AS f_raw
						, COALESCE(c.mod_since_analyze, 0) / GREATEST(c.reltuples, 1)::DOUBLE PRECISION AS mod_frac
						-- a page holds its size less a 24 byte header, filled to the fillfactor; a row is a
						-- 23 byte header and its null bitmap, padded to 8 bytes, then its columns, padded to
						-- 8 bytes, plus a 4 byte pointer
						, CASE WHEN c.relpages > 0 AND c.reltuples >= 0 AND c.heap_data_width IS NOT NULL THEN
							GREATEST(0, 100 * (1 - ceil(
								c.reltuples
								* (ceil((23 + ceil(c.relnatts / 8.0)) / 8) * 8 + ceil(c.heap_data_width / 8) * 8 + 4)
								/ ((cfg.bs - 24) * c.heap_fillfactor / 100)
							) / c.relpages))
							END AS heap_free_pct_stats
						-- as in the index_health view: a page holds its size less a 24 byte header and 16
						-- bytes of btree data, filled to the fillfactor; an entry is an 8 byte header, 8 more
						-- when it holds a NULL, and its columns, padded to 8 bytes, plus a 4 byte pointer; one
						-- more page for the metapage
						, CASE WHEN c.index_has_stats AND c.index_data_width IS NOT NULL AND c.index_reltuples >= 0 THEN
							(1 + ceil(
								c.index_reltuples
								* (ceil((8 + 8 * c.index_null_frac + c.index_data_width) / 8) * 8 + 4)
								/ ((cfg.bs - 40) * c.index_fillfactor / 100)
							)) * cfg.bs
							END AS index_est_bytes
						, LEAST(c.heap_main_bytes / cfg.bs, 300 * c.stats_target)::BIGINT * cfg.bs::BIGINT AS analyze_bytes
						, CASE
							WHEN c.is_compressed THEN 'compressed'
							WHEN c.chunk_index IS NULL THEN 'no reorder index'
							WHEN c.range_end IS NULL OR c.range_end > CURRENT_TIMESTAMP - cfg.min_age THEN 'current'
							WHEN c.move_due < CURRENT_TIMESTAMP + cfg.move_margin THEN 'moving soon'
							WHEN c.heap_bytes + c.index_bytes < cfg.min_chunk_bytes THEN 'small'
							END AS skip_reason
					FROM _timescaledb_solarnetwork.chunk_maint_chunk c
					CROSS JOIN (
						SELECT current_setting('block_size')::NUMERIC AS bs
							, (SELECT n.nspname
								FROM pg_catalog.pg_extension x
								INNER JOIN pg_catalog.pg_namespace n ON n.oid = x.extnamespace
								WHERE x.extname = 'timescaledb') AS tsdb_schema
							, COALESCE(NULLIF(current_setting('chunk_maint.min_age', TRUE), '')::INTERVAL
								, INTERVAL '7 days') AS min_age
							, COALESCE(NULLIF(current_setting('chunk_maint.move_margin', TRUE), '')::INTERVAL
								, INTERVAL '6 months') AS move_margin
							, COALESCE(NULLIF(current_setting('chunk_maint.min_chunk_mb', TRUE), '')::NUMERIC
								, 100) * 1048576 AS min_chunk_bytes
							, COALESCE(NULLIF(current_setting('chunk_maint.max_corr', TRUE), '')::DOUBLE PRECISION
								, 0.9) AS max_corr
							, COALESCE(NULLIF(current_setting('chunk_maint.min_free_pct', TRUE), '')::DOUBLE PRECISION
								, 20) AS min_free_pct
							, COALESCE(NULLIF(current_setting('chunk_maint.min_free_mb', TRUE), '')::NUMERIC
								, 1024) * 1048576 AS min_free_bytes
							, COALESCE(NULLIF(current_setting('chunk_maint.min_bloat_pct', TRUE), '')::DOUBLE PRECISION
								, 30) AS min_bloat_pct
							, COALESCE(NULLIF(current_setting('chunk_maint.min_bloat_mb', TRUE), '')::NUMERIC
								, 1024) * 1048576 AS min_bloat_bytes
							, COALESCE(NULLIF(current_setting('chunk_maint.analyze_pct', TRUE), '')::DOUBLE PRECISION
								, 2) / 100 AS analyze_frac
							, COALESCE(NULLIF(current_setting('chunk_maint.rewrite_interval', TRUE), '')::INTERVAL
								, INTERVAL '30 days') AS rewrite_interval
							, COALESCE(NULLIF(current_setting('chunk_maint.temp_tablespace', TRUE), ''), (
								SELECT t.spcname
								FROM pg_catalog.pg_database d
								INNER JOIN pg_catalog.pg_tablespace t ON t.oid = d.dattablespace
								WHERE d.datname = current_database()
								)) AS temp_tablespace
							, COALESCE(NULLIF(current_setting('chunk_maint.use_pgstattuple', TRUE), '')::BOOLEAN
								, TRUE) AS use_pgstattuple
							, COALESCE(NULLIF(current_setting('chunk_maint.use_cluster', TRUE), '')::BOOLEAN
								, FALSE) AS use_cluster
					) cfg
				) k
			) e
		) m
	) a
) d;

/**
 * The chunks that need something, in the order chunk-maintenance.sh takes them (priority): rewrites
 * and reindexes before analyzes; chunks on main storage before moved ones; then the newest chunks
 * first, as they are queried the most, and for analyzes the chunks whose statistics are furthest
 * behind first.
 */
CREATE VIEW _timescaledb_solarnetwork.chunk_maint_candidates AS
SELECT row_number() OVER (ORDER BY
		s.action = 'analyze'
		, s.moved
		, CASE WHEN s.action = 'analyze' THEN s.mod_frac END DESC NULLS LAST
		, s.range_end DESC
		, s.chunk_name
	) AS priority
	, s.*
FROM _timescaledb_solarnetwork.chunk_maint_status s
WHERE s.action IS NOT NULL;

/**
 * The checks chunk-maintenance.sh makes before it starts; it stops if any is not ok. It needs a
 * superuser, or a role with pg_monitor, to list the WAL archive status directory.
 */
CREATE VIEW _timescaledb_solarnetwork.chunk_maint_preflight AS
WITH cfg AS (
	SELECT pg_is_in_recovery() AS in_recovery
		, COALESCE(NULLIF(current_setting('chunk_maint.max_archive_ready', TRUE), '')::INTEGER, 64) AS max_ready
		, COALESCE(NULLIF(current_setting('chunk_maint.max_replica_lag_mb', TRUE), '')::NUMERIC, 1024)
			* 1048576 AS max_lag
		, COALESCE(NULLIF(current_setting('chunk_maint.use_cluster', TRUE), '')::BOOLEAN, FALSE) AS use_cluster
		, current_setting('archive_mode') <> 'off' AS archiving
)
SELECT 1 AS seq
	, 'primary' AS check_name
	, NOT cfg.in_recovery AS ok
	, CASE WHEN cfg.in_recovery THEN 'this server is a replica' ELSE 'not a replica' END AS detail
FROM cfg
UNION ALL
SELECT 2
	, 'licence'
	, cfg.use_cluster OR COALESCE(current_setting('timescaledb.license', TRUE), '') = 'timescale'
	, format('timescaledb.license is %s', COALESCE(current_setting('timescaledb.license', TRUE), 'not set'))
		|| CASE WHEN cfg.use_cluster THEN ', but CLUSTER is used instead (chunk_maint.use_cluster)' ELSE '' END
FROM cfg
UNION ALL
SELECT 3
	, 'jobs'
	, count(j.job_id) = 0
	, COALESCE('running: ' || string_agg(format('%s.%s [%s]', j.proc_schema, j.proc_name, j.job_id), ', ')
		, 'no reorder or move_chunks job is running')
FROM timescaledb_information.jobs j
-- as timescaledb_information.job_stats finds a running job
INNER JOIN pg_catalog.pg_stat_activity a ON a.datname = current_database()
	AND a.application_name = j.application_name
	AND a.state = 'active'
WHERE j.proc_name IN ('policy_reorder', 'move_chunks')
UNION ALL
SELECT 4
	, 'archiver'
	, NOT cfg.archiving OR COALESCE(a.last_failed_time <= a.last_archived_time, a.last_failed_time IS NULL)
	, CASE
		WHEN NOT cfg.archiving THEN 'archive_mode is off'
		WHEN COALESCE(a.last_failed_time <= a.last_archived_time, a.last_failed_time IS NULL)
			THEN format('last archived %s at %s', COALESCE(a.last_archived_wal, 'nothing')
				, COALESCE(date_trunc('second', a.last_archived_time)::TEXT, 'never'))
		ELSE format('archiving %s failed at %s', a.last_failed_wal, date_trunc('second', a.last_failed_time))
		END
FROM cfg
CROSS JOIN pg_catalog.pg_stat_archiver a
UNION ALL
SELECT 5
	, 'archive backlog'
	, NOT cfg.archiving OR r.ready <= cfg.max_ready
	, format('%s WAL segments waiting to be archived (at most %s)', r.ready, cfg.max_ready)
FROM cfg
CROSS JOIN LATERAL (
	SELECT count(*) AS ready
	FROM pg_ls_archive_statusdir() f
	WHERE cfg.archiving AND f.name LIKE '%.ready'
) r
UNION ALL
SELECT 6
	, 'replica lag'
	, cfg.in_recovery OR COALESCE(max(x.lag) <= cfg.max_lag, TRUE)
	, CASE
		WHEN cfg.in_recovery THEN 'not checked on a replica'
		WHEN count(x.lag) = 0 THEN 'no replica is streaming'
		ELSE format('%s replica(s), the furthest %s behind (at most %s)'
			, count(x.lag), pg_size_pretty(max(x.lag)), pg_size_pretty(cfg.max_lag))
		END
FROM cfg
LEFT JOIN LATERAL (
	SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), r.replay_lsn) AS lag
	FROM pg_catalog.pg_stat_replication r
	WHERE NOT cfg.in_recovery AND r.replay_lsn IS NOT NULL
) x ON TRUE
GROUP BY cfg.in_recovery, cfg.max_lag
UNION ALL
SELECT 7
	, 'replication slots'
	, cfg.in_recovery OR COALESCE(max(x.retained) <= cfg.max_lag, TRUE)
	, CASE
		WHEN cfg.in_recovery THEN 'not checked on a replica'
		WHEN count(x.retained) = 0 THEN 'no replication slot holds WAL'
		ELSE format('%s slot(s), holding at most %s of WAL (at most %s)'
			, count(x.retained), pg_size_pretty(max(x.retained)), pg_size_pretty(cfg.max_lag))
		END
FROM cfg
LEFT JOIN LATERAL (
	SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), s.restart_lsn) AS retained
	FROM pg_catalog.pg_replication_slots s
	WHERE NOT cfg.in_recovery AND s.restart_lsn IS NOT NULL
) x ON TRUE
GROUP BY cfg.in_recovery, cfg.max_lag;

/**
 * The directory of each tablespace, and of pg_wal, for the script's free space check. Reading it
 * needs a superuser, or a role with pg_read_all_settings, for the data directory.
 */
CREATE VIEW _timescaledb_solarnetwork.chunk_maint_storage AS
SELECT t.spcname::TEXT AS name
	, CASE
		WHEN t.spcname = 'pg_default' THEN current_setting('data_directory') || '/base'
		WHEN t.spcname = 'pg_global' THEN current_setting('data_directory') || '/global'
		-- an in-place tablespace (the allow_in_place_tablespaces developer option) is given relative to
		-- the data directory
		WHEN pg_tablespace_location(t.oid) NOT LIKE '/%'
			THEN current_setting('data_directory') || '/' || pg_tablespace_location(t.oid)
		ELSE pg_tablespace_location(t.oid)
		END AS path
FROM pg_catalog.pg_tablespace t
UNION ALL
-- tablespace names may not start with pg_, so this cannot clash with one
SELECT 'pg_wal', current_setting('data_directory') || '/pg_wal';


-- ----------------------------------------------------------------------------
-- Logging functions, used by the script around each task
-- ----------------------------------------------------------------------------

/**
 * Log the start of a task on a chunk, with the chunk's sizes and correlation before it.
 *
 * @param chunk 	the chunk
 * @param action 	the action: reorder, cluster, reindex or analyze
 * @param reason 	why
 * @param stmt 		the statements run
 * @return the ID of the new chunk_maint_log row, or NULL if the chunk is not one of an enabled
 *         chunk_maint_hypertable hypertable
 */
CREATE OR REPLACE FUNCTION _timescaledb_solarnetwork.chunk_maint_log_start(
		chunk regclass,
		action TEXT,
		reason TEXT,
		stmt TEXT
	)
	RETURNS BIGINT LANGUAGE SQL VOLATILE AS
$$
	INSERT INTO _timescaledb_solarnetwork.chunk_maint_log (hypertable_schema, hypertable_name
		, chunk_schema, chunk_name, range_end, action, reason, stmt, heap_tablespace, index_tablespace
		, heap_bytes_before, index_bytes_before, corr_before)
	SELECT k.hypertable_schema, k.hypertable_name
		, k.chunk_schema, k.chunk_name, k.range_end, $2, $3, $4, k.heap_tablespace, k.index_tablespace
		, k.heap_bytes, k.index_bytes, k.corr
	FROM _timescaledb_solarnetwork.chunk_maint_chunk k
	WHERE k.chunk = $1
	RETURNING id
$$;

/**
 * Log the end of a task, with the chunk's sizes, correlation and relfilenode after it.
 *
 * @param log_id 	the ID returned by chunk_maint_log_start()
 * @param err 		the error the task failed with, or NULL if it succeeded
 */
CREATE OR REPLACE FUNCTION _timescaledb_solarnetwork.chunk_maint_log_finish(
		log_id BIGINT,
		err TEXT DEFAULT NULL
	)
	RETURNS VOID LANGUAGE SQL VOLATILE AS
$$
	UPDATE _timescaledb_solarnetwork.chunk_maint_log l
	SET finished = clock_timestamp()
		, error = $2
		, (heap_bytes_after, index_bytes_after, corr_after, relfilenode_after) = (
			SELECT k.heap_bytes, k.index_bytes, k.corr, k.relfilenode
			FROM _timescaledb_solarnetwork.chunk_maint_chunk k
			WHERE k.chunk_schema = l.chunk_schema AND k.chunk_name = l.chunk_name
		)
	WHERE l.id = $1
$$;


-- ----------------------------------------------------------------------------
-- Comments and access
-- ----------------------------------------------------------------------------

COMMENT ON TABLE _timescaledb_solarnetwork.chunk_maint_hypertable IS
	'The hypertables whose chunks chunk-maintenance.sh maintains (OPS-51), with the index to keep each one''s chunks in the order of.';
COMMENT ON TABLE _timescaledb_solarnetwork.chunk_maint_log IS
	'One row for each task chunk-maintenance.sh performs on a chunk (OPS-51).';
COMMENT ON VIEW _timescaledb_solarnetwork.chunk_maint_chunk IS
	'Facts about every chunk of the hypertables in chunk_maint_hypertable (OPS-51).';
COMMENT ON VIEW _timescaledb_solarnetwork.chunk_maint_status IS
	'What each chunk of the hypertables in chunk_maint_hypertable needs, and why (OPS-51). Thresholds are chunk_maint.* settings; see tsdb-init-hypertables-maintenance.sql.';
COMMENT ON VIEW _timescaledb_solarnetwork.chunk_maint_candidates IS
	'The chunks that need maintenance, in the order chunk-maintenance.sh takes them (OPS-51).';
COMMENT ON VIEW _timescaledb_solarnetwork.chunk_maint_preflight IS
	'The server checks chunk-maintenance.sh makes before it starts (OPS-51).';
COMMENT ON VIEW _timescaledb_solarnetwork.chunk_maint_storage IS
	'The directory of each tablespace and of pg_wal, for chunk-maintenance.sh''s free space check (OPS-51).';

-- as tsdb-init-permissions.sql does for the rest of the schema
REVOKE ALL ON FUNCTION _timescaledb_solarnetwork.chunk_maint_heap_free_pct(regclass) FROM PUBLIC;
REVOKE ALL ON FUNCTION _timescaledb_solarnetwork.chunk_maint_log_start(regclass, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION _timescaledb_solarnetwork.chunk_maint_log_finish(BIGINT, TEXT) FROM PUBLIC;

COMMIT;
