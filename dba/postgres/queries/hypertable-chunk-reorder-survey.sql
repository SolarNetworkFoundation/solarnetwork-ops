/* ============================================================================
 * OPS-51: survey the datum, aggregate and audit hypertable chunks for reorder
 * maintenance. Read-only: it reads only the catalogs and the statistics, never
 * a chunk, so it is cheap to run on production:
 *
 *   psql -X -P pager=off -d solarnetwork -f hypertable-chunk-reorder-survey.sql
 *
 * lead_corr is pg_stats.correlation of the first column of the chunk's unique
 * index (stream_id), as of the last ANALYZE. A chunk in index order shows 1; a
 * chunk in ingest order shows about 0. If a fraction f of the rows is out of
 * index order (appended by backfill or moved by updates), lead_corr is about
 * (1 - f)^2: 0.9 means about 5% of the rows are out of order.
 * ============================================================================
 */

SELECT ch.hypertable_name AS ht
	, ch.chunk_name
	, ch.range_end::date AS range_end
	, COALESCE(ch.chunk_tablespace, 'default') AS heap_tblspc
	, COALESCE(ti.spcname, 'default') AS idx_tblspc
	, pg_size_pretty(pg_relation_size(c.oid)) AS heap
	, pg_size_pretty(pg_indexes_size(c.oid)) AS idx
	, round(s.correlation::numeric, 3) AS lead_corr
	, GREATEST(st.last_analyze, st.last_autoanalyze)::date AS analyzed
	, st.n_mod_since_analyze AS mod_since_analyze
FROM timescaledb_information.chunks ch
JOIN pg_class c ON c.oid = format('%I.%I', ch.chunk_schema, ch.chunk_name)::regclass
JOIN pg_stat_user_tables st ON st.relid = c.oid
JOIN pg_index i ON i.indrelid = c.oid
JOIN pg_class ic ON ic.oid = i.indexrelid
LEFT JOIN pg_tablespace ti ON ti.oid = ic.reltablespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = i.indkey[0]
LEFT JOIN pg_stats s ON s.schemaname = ch.chunk_schema AND s.tablename = ch.chunk_name AND s.attname = a.attname AND NOT s.inherited
WHERE ch.hypertable_schema = 'solardatm'
	AND ch.hypertable_name IN ('da_datm', 'agg_datm_hourly', 'agg_datm_daily', 'agg_datm_monthly',
		'aud_datm_io', 'aud_datm_daily', 'aud_datm_monthly', 'aud_acc_datm_daily')
ORDER BY ch.hypertable_name, ch.range_end;

-- the reorder and chunk-moving jobs, with their schedules
SELECT j.job_id, j.proc_name, j.hypertable_name, j.schedule_interval, j.scheduled, j.fixed_schedule
	, s.last_run_started_at, s.last_successful_finish, s.next_start, s.total_runs, s.total_failures
	, j.config
FROM timescaledb_information.jobs j
LEFT JOIN timescaledb_information.job_stats s USING (job_id)
WHERE j.proc_name ILIKE '%reorder%' OR j.proc_name = 'move_chunks'
ORDER BY j.job_id;

-- whether pgstattuple (for pgstattuple_approx) is available
SELECT name, default_version, installed_version FROM pg_available_extensions WHERE name = 'pgstattuple';

-- the database's default tablespace, and where temporary files go
SELECT d.datname, t.spcname AS default_tablespace, current_setting('temp_tablespaces') AS temp_tablespaces
	, current_setting('data_directory') AS data_directory
FROM pg_database d JOIN pg_tablespace t ON t.oid = d.dattablespace
WHERE d.datname = current_database();
SELECT spcname, pg_tablespace_location(oid) AS location FROM pg_tablespace ORDER BY 1;
