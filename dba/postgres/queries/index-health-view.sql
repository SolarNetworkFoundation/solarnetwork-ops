/* ============================================================================
 * A view of every index's size, estimated bloat and use, with recommendations.
 *
 *   SELECT * FROM public.index_health WHERE reindex_needed;
 *   SELECT * FROM public.index_health WHERE tblname = 'agg_stale_datm';
 *
 * The rows come back worst first: indexes to rebuild, then by estimated bloat.
 *
 * The view reads only the catalogs, the statistics collector and the size of
 * each index file, so it is cheap to run and never reads an index. The price is
 * that bloat is an ESTIMATE, for btree indexes only:
 *
 *  - The size an index ought to be is worked out from its number of entries
 *    (pg_class.reltuples, as of the last VACUUM or ANALYZE) and the average
 *    width of its columns (pg_stats), at its fillfactor. Anything over that is
 *    counted as bloat.
 *  - It ignores the padding between columns and the pages above the leaves,
 *    which makes the estimate a few percent high, and it knows nothing of
 *    deduplication, which makes an index with many equal keys smaller than
 *    estimated: such an index shows no bloat until it is badly bloated.
 *  - An index filled by inserts in random key order, such as one on a UUID,
 *    settles at about 70% full and so shows 20% to 30% bloat when healthy. The
 *    default threshold is well above that.
 *  - bloat_bytes and bloat_pct are NULL where no estimate is possible: an index
 *    that is not a btree, or whose table has never been analyzed.
 *  - bytes_per_tuple needs no estimate: a healthy btree is some tens of bytes
 *    per entry, and one in the thousands is bloated whatever its columns.
 *
 * For an exact figure on one index, pgstatindex() in the pgstattuple extension
 * reads the whole index.
 *
 * reindex_needed is true for an index that is invalid (a failed CREATE INDEX
 * or REINDEX ... CONCURRENTLY), or a btree whose estimated bloat is at least
 * 50% of the index and at least 100 MB. reindex_sql gives the statement.
 *
 * unused is true for a valid index of at least 10 MB that has not been scanned
 * since the statistics were last reset, and that enforces nothing (not unique,
 * not a constraint's). Usage is counted per server: an index only the replica's
 * queries use shows as unused on the primary, so check the replica before
 * dropping anything.
 *
 * The three thresholds can be changed for a session, without recreating the
 * view:
 *
 *   SET index_health.reindex_pct = 30;       -- percent of the index, default 50
 *   SET index_health.reindex_min_mb = 10;    -- MB of bloat, default 100
 *   SET index_health.unused_min_mb = 1;      -- MB, default 10
 *
 * Create the view as a superuser if other roles are to read it for tables they
 * have no access to: pg_stats shows a role only the columns it may read.
 * ============================================================================
 */

CREATE OR REPLACE VIEW public.index_health AS
WITH cfg AS (
	SELECT current_setting('block_size')::numeric AS bs
		, COALESCE(NULLIF(current_setting('index_health.reindex_pct', TRUE), '')::numeric, 50) AS reindex_pct
		, COALESCE(NULLIF(current_setting('index_health.reindex_min_mb', TRUE), '')::numeric, 100) AS reindex_min_mb
		, COALESCE(NULLIF(current_setting('index_health.unused_min_mb', TRUE), '')::numeric, 10) AS unused_min_mb
)
, idx AS (
	SELECT n.nspname
		, ct.relname AS tblname
		, ci.relname AS idxname
		, am.amname
		, i.indexrelid
		, i.indrelid
		, i.indnatts
		, i.indkey
		, i.indisprimary
		, i.indisunique
		, i.indpred IS NOT NULL AS is_partial
		, i.indisvalid AND i.indisready AND i.indislive AS is_valid
		, EXISTS (SELECT 1 FROM pg_constraint con WHERE con.conindid = i.indexrelid) AS backs_constraint
		-- entries in the index as of the last VACUUM or ANALYZE; -1 if there has been none
		, ci.reltuples AS idx_tuples
		, pg_relation_size(i.indexrelid) AS idx_bytes
		, pg_relation_size(i.indrelid) AS tbl_bytes
		, COALESCE((
			SELECT o.option_value::numeric
			FROM pg_options_to_table(ci.reloptions) o
			WHERE o.option_name = 'fillfactor'
			), 90) AS fillfactor
	FROM pg_index i
	INNER JOIN pg_class ci ON ci.oid = i.indexrelid
	INNER JOIN pg_class ct ON ct.oid = i.indrelid
	INNER JOIN pg_namespace n ON n.oid = ci.relnamespace
	INNER JOIN pg_am am ON am.oid = ci.relam
	WHERE ci.relkind = 'i'
		AND n.nspname NOT IN ('pg_catalog', 'information_schema')
		AND n.nspname !~ '^pg_toast'
)
-- the average width of an index entry's columns, from the statistics of the table's columns, or
-- of the index itself for an expression
, width AS (
	SELECT x.indexrelid
		, sum((1 - COALESCE(s.null_frac, 0)) * s.avg_width) AS data_width
		, max(COALESCE(s.null_frac, 0)) AS null_frac
		, count(*) = count(s.avg_width) AS has_stats
	FROM idx x
	CROSS JOIN LATERAL generate_series(1, x.indnatts) AS k(pos)
	INNER JOIN pg_attribute ia ON ia.attrelid = x.indexrelid AND ia.attnum = k.pos
	LEFT JOIN pg_attribute ta ON ta.attrelid = x.indrelid
		AND ta.attnum = x.indkey[k.pos - 1]
		AND x.indkey[k.pos - 1] <> 0
	LEFT JOIN pg_stats s ON s.schemaname = x.nspname
		AND s.tablename = CASE WHEN ta.attnum IS NULL THEN x.idxname ELSE x.tblname END
		AND s.attname = COALESCE(ta.attname, ia.attname)
		AND NOT s.inherited
	GROUP BY x.indexrelid
)
, est AS (
	SELECT x.*
		-- a page holds its size less a 24 byte header and 16 bytes of btree data, filled to the
		-- fillfactor; an entry is an 8 byte header, 8 more when it holds a NULL, and its columns,
		-- padded to 8 bytes, plus a 4 byte pointer; one more page for the metapage
		, CASE WHEN x.amname = 'btree' AND w.has_stats AND x.idx_tuples >= 0 THEN
			(1 + ceil(
				x.idx_tuples::numeric
				* (ceil((8 + 8 * w.null_frac + w.data_width)::numeric / 8) * 8 + 4)
				/ ((cfg.bs - 40) * x.fillfactor / 100)
			)) * cfg.bs
			END AS est_bytes
		, cfg.reindex_pct
		, cfg.reindex_min_mb
		, cfg.unused_min_mb
	FROM idx x
	CROSS JOIN cfg
	LEFT JOIN width w ON w.indexrelid = x.indexrelid
)
, h AS (
	SELECT e.*
		-- GREATEST() ignores NULL, so an index with no estimate has to be left out by hand
		, CASE WHEN e.est_bytes IS NOT NULL
			THEN GREATEST(e.idx_bytes - e.est_bytes, 0)
			END AS bloat_bytes
		, CASE WHEN e.est_bytes IS NOT NULL
			THEN round(100 * GREATEST(e.idx_bytes - e.est_bytes, 0) / NULLIF(e.idx_bytes, 0), 1)
			END AS bloat_pct
		, pg_stat_get_numscans(e.indexrelid) AS idx_scan
	FROM est e
)
SELECT h.nspname
	, h.tblname
	, h.idxname
	, h.amname AS idx_type
	, h.indisprimary AS is_primary
	, h.indisunique AS is_unique
	, h.is_partial
	, h.is_valid
	, pg_size_pretty(h.idx_bytes) AS idx_size
	, pg_size_pretty(h.tbl_bytes) AS tbl_size
	, CASE WHEN h.idx_tuples >= 0 THEN h.idx_tuples::bigint END AS idx_tuples
	, round(h.idx_bytes / NULLIF(GREATEST(h.idx_tuples, 0), 0)::numeric) AS bytes_per_tuple
	, pg_size_pretty(h.bloat_bytes) AS bloat_size
	, h.bloat_pct
	, h.idx_scan
	, date_trunc('minute', pg_stat_get_lastscan(h.indexrelid)) AS last_idx_scan
	, pg_stat_get_tuples_returned(h.indexrelid) AS idx_tup_read
	, pg_stat_get_tuples_fetched(h.indexrelid) AS idx_tup_fetch
	, pg_stat_get_blocks_fetched(h.indexrelid) - pg_stat_get_blocks_hit(h.indexrelid) AS idx_blks_read
	, pg_stat_get_blocks_hit(h.indexrelid) AS idx_blks_hit
	, round(100.0 * pg_stat_get_blocks_hit(h.indexrelid)
		/ NULLIF(pg_stat_get_blocks_fetched(h.indexrelid), 0), 1) AS idx_hit_pct
	, pg_stat_get_live_tuples(h.indrelid) AS tbl_live_tup
	, pg_stat_get_dead_tuples(h.indrelid) AS tbl_dead_tup
	, date_trunc('minute', GREATEST(pg_stat_get_last_vacuum_time(h.indrelid)
		, pg_stat_get_last_autovacuum_time(h.indrelid))) AS tbl_last_vacuum
	, pg_stat_get_vacuum_count(h.indrelid) + pg_stat_get_autovacuum_count(h.indrelid) AS tbl_vacuum_count
	, h.idx_bytes
	, h.tbl_bytes
	, h.bloat_bytes
	, NOT h.is_valid OR COALESCE(
			h.bloat_pct >= h.reindex_pct AND h.bloat_bytes >= h.reindex_min_mb * 1048576
		, FALSE) AS reindex_needed
	, h.is_valid AND h.idx_scan = 0 AND NOT h.indisunique AND NOT h.backs_constraint
		AND h.idx_bytes >= h.unused_min_mb * 1048576 AS unused
	, CASE WHEN NOT h.is_valid OR COALESCE(
			h.bloat_pct >= h.reindex_pct AND h.bloat_bytes >= h.reindex_min_mb * 1048576
		, FALSE)
		THEN format('REINDEX INDEX CONCURRENTLY %I.%I;', h.nspname, h.idxname)
		END AS reindex_sql
FROM h
ORDER BY (NOT h.is_valid OR COALESCE(
		h.bloat_pct >= h.reindex_pct AND h.bloat_bytes >= h.reindex_min_mb * 1048576
	, FALSE)) DESC
	, h.bloat_bytes DESC NULLS LAST
	, h.idx_bytes DESC;

COMMENT ON VIEW public.index_health IS
	'Size, estimated btree bloat and use of every index, with reindex_needed and unused '
	'recommendations. Bloat is estimated from catalog statistics, not measured. Thresholds: '
	'index_health.reindex_pct (50), index_health.reindex_min_mb (100), index_health.unused_min_mb (10).';
