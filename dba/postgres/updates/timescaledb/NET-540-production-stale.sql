/* Production-only follow-up for NET-540 (step 1): mark stale again the hours at or after the 15
 * minute "complete from" boundary that have an hourly row but no 15 minute rows, so that stale
 * processing gives them their 15 minute rows.
 *
 * RUN it straight after NET-540-production.sql has committed (its header has the whole order),
 * as solarnet, and NOT with -1, because it waits for other transactions before it marks:
 *
 *     cd solarnetwork-ops/dba/postgres/updates/timescaledb
 *     psql -d solarnetwork -f NET-540-production-stale.sql
 *
 * It is safe to run again at any time: it marks only hours that still lack 15 minute rows, with
 * ON CONFLICT DO NOTHING, and its last query is a check worth repeating once the stale queue has
 * been worked through.
 *
 * WHY. Stale processing (solardatm.process_one_agg_stale_datm(), one call per transaction) reads
 * the boundary in a statement of its own, after it has claimed a stale hour. A call that read it
 * just before NET-540-production.sql committed found no boundary and processed its hour as
 * before, without 15 minute rows, even when the hour starts at or after the boundary. Hours from
 * the boundary on can also have been processed that way earlier, when their datum are dated in the
 * future. Every hourly row that processing stores from the boundary on comes with at least one 15
 * minute row, so an hour from the boundary on with an hourly row and no 15 minute row is one of
 * those, and is marked stale here.
 *
 * HOW.
 *
 *  1. It waits until no client session whose transaction began before this script holds a lock
 *     on solardatm.agg_stale_datm. A call that could have read the boundary as absent claimed its
 *     stale hour first, and holds such a lock until it commits; so do the short transactions that
 *     add stale hours, which it waits for too. It gives up after 10 minutes, naming the sessions,
 *     and can then be run again.
 *  2. Stream by stream, through the primary keys of solardatm.agg_datm_hourly and
 *     solardatm.agg_datm_15m, with the boundary as a literal so that only chunks from the boundary
 *     on are read, it marks each hour from the boundary on that has an hourly row and no 15 minute
 *     row. The streams are those of solardatm.da_datm_meta and solardatm.da_loc_datm_meta.
 *  3. The same way, it counts the hours from the boundary on that have an hourly row, no 15 minute
 *     row and no stale record. That must be 0.
 */
\set ON_ERROR_STOP on

DO $$
DECLARE
	b	TIMESTAMP WITH TIME ZONE;
BEGIN
	IF to_regclass('solardatm.agg_datm_15m_setting') IS NULL THEN
		RAISE EXCEPTION 'The NET-540 migration has not been run';
	END IF;
	SELECT complete_from INTO b FROM solardatm.agg_datm_15m_setting;
	IF b IS NULL THEN
		RAISE EXCEPTION 'The 15 minute boundary is not set'
		USING HINT = 'Run NET-540-production.sql first.';
	ELSIF b = '-infinity' THEN
		RAISE EXCEPTION 'The 15 minute boundary is -infinity, as in a database built from the setup DDL'
		USING HINT = 'This script is for a migrated database.';
	END IF;
END
$$;

SELECT complete_from AS b FROM solardatm.agg_datm_15m_setting \gset

\echo === waiting for transactions begun before this script that use solardatm.agg_stale_datm ===
DO $$
DECLARE
	started		CONSTANT TIMESTAMP WITH TIME ZONE := now();
	deadline	CONSTANT TIMESTAMP WITH TIME ZONE := clock_timestamp() + INTERVAL 'PT10M';
	pids		INT[];
BEGIN
	LOOP
		-- pg_stat_activity is otherwise read once per transaction
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
			USING HINT = 'Their transactions began before this script and use solardatm.agg_stale_datm. Run this script again later.';
		END IF;
		PERFORM pg_sleep(0.5);
	END LOOP;
END
$$;

\echo === marking stale the hours from :b that have an hourly row and no 15 minute row ===
WITH s AS (
	SELECT stream_id FROM solardatm.da_datm_meta
	UNION
	SELECT stream_id FROM solardatm.da_loc_datm_meta
)
INSERT INTO solardatm.agg_stale_datm (stream_id, ts_start, agg_kind)
SELECT h.stream_id, h.ts_start, 'h'
FROM s
CROSS JOIN LATERAL (
	SELECT h.stream_id, h.ts_start
	FROM solardatm.agg_datm_hourly h
	WHERE h.stream_id = s.stream_id
		AND h.ts_start >= :'b'::TIMESTAMP WITH TIME ZONE
		AND NOT EXISTS (
			SELECT 1
			FROM solardatm.agg_datm_15m f
			WHERE f.stream_id = s.stream_id
				AND f.ts_start >= :'b'::TIMESTAMP WITH TIME ZONE
				AND f.ts_start >= h.ts_start
				AND f.ts_start < h.ts_start + INTERVAL 'PT1H'
		)
	OFFSET 0 -- keeps this a per-stream index range scan
) h
ON CONFLICT (agg_kind, stream_id, ts_start) DO NOTHING;

\echo === hours from :b with an hourly row, no 15 minute row and no stale record: must be 0 ===
WITH s AS (
	SELECT stream_id FROM solardatm.da_datm_meta
	UNION
	SELECT stream_id FROM solardatm.da_loc_datm_meta
)
SELECT count(*) AS hours_missing_15m_rows
FROM s
CROSS JOIN LATERAL (
	SELECT 1
	FROM solardatm.agg_datm_hourly h
	WHERE h.stream_id = s.stream_id
		AND h.ts_start >= :'b'::TIMESTAMP WITH TIME ZONE
		AND NOT EXISTS (
			SELECT 1
			FROM solardatm.agg_datm_15m f
			WHERE f.stream_id = s.stream_id
				AND f.ts_start >= :'b'::TIMESTAMP WITH TIME ZONE
				AND f.ts_start >= h.ts_start
				AND f.ts_start < h.ts_start + INTERVAL 'PT1H'
		)
		AND NOT EXISTS (
			SELECT 1
			FROM solardatm.agg_stale_datm st
			WHERE st.agg_kind = 'h'
				AND st.stream_id = s.stream_id
				AND st.ts_start = h.ts_start
		)
	OFFSET 0 -- keeps this a per-stream index range scan
) h;
