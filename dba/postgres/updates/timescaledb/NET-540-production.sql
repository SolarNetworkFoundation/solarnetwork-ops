/* Production-only DDL for NET-540 (step 1): make solardatm.agg_datm_15m a hypertable with its
 * chunks for all history created in advance, grant the new objects as a freshly built database
 * grants them, and set the "complete from" boundary, which starts the writing of 15 minute rows.
 *
 * RUN ORDER. Each step must have committed before the next starts. Run them as solarnet, the
 * user that runs migrations and owns the solardatm objects:
 *
 *   1. The migration, from the central repo:
 *
 *          cd solarnetwork-central/solarnet-db-setup/postgres
 *          psql -1 -d solarnetwork -f migrations/migrate-20261120.sql
 *
 *      It creates the two tables and two functions and replaces process_one_agg_stale_datm() and
 *      delete_datm(), but inserts no boundary row. Until there is one, stale processing treats
 *      every hour as before the boundary, so it writes no 15 minute row, and delete_datm() has
 *      none to delete: the migration on its own changes no stored value.
 *
 *   2. This script, in one transaction:
 *
 *          cd solarnetwork-ops/dba/postgres/updates/timescaledb
 *          psql -1 -d solarnetwork -f NET-540-production.sql
 *
 *   3. NET-540-production-stale.sql, straight after this script has committed, NOT with -1:
 *
 *          psql -d solarnetwork -f NET-540-production-stale.sql
 *
 *      See its header. It marks stale again the few hours at or after the boundary that were
 *      processed without 15 minute rows, and then checks that every hour from the boundary on
 *      that has an hourly row has 15 minute rows or is waiting to be processed.
 *
 * THE ORDERING HAZARD. A 15 minute row written before the chunks are seeded would create a chunk
 * of its own, at whatever interval was set at the time, and the seeded chunks could no longer be
 * the planned ones. That cannot happen: 15 minute rows are written only by stale processing of an
 * hour that starts at or after the boundary, the boundary is the one row of
 * solardatm.agg_datm_15m_setting, and this script inserts that row last, in the transaction that
 * seeds the chunks. No other session can see the row before the chunks exist. The script refuses
 * to run if the table has rows or chunks, or if the boundary row exists.
 *
 * Locks. The conversion, the index moves and the seeding lock the two new tables for the second
 * or two this script takes. Stale processing reads the setting table, so it waits for that long;
 * delete_datm() waits on agg_datm_15m. Neither holds a lock this script needs, so no deadlock can
 * occur. lock_timeout stops the script, and rolls it back, rather than queue those sessions
 * behind it if some long transaction holds one of the tables; run it again later.
 *
 * THE BOUNDARY is the first UTC hour after the boundary row is inserted:
 *
 *     B = date_trunc('hour', clock_timestamp() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + 1 hour
 *
 *  - Every hour from B on starts after this transaction, so its datum arrive, and mark it stale,
 *    after the boundary is visible, and processing writes its 15 minute rows. The exceptions are
 *    hours from B on that already have datum, dated in the future, and hours whose processing
 *    read the boundary just before it committed. Both were processed without 15 minute rows, and
 *    NET-540-production-stale.sql marks them stale again.
 *  - The hour this script runs in, and earlier ones, may already be processed without 15 minute
 *    rows. They are before the boundary and get none; they are left to the backfill (step 4). B
 *    is not the current hour because that would add every active stream's current hour to the
 *    hours to reprocess, for no gain, since the backfill moves the boundary back anyway.
 *  - B is a UTC hour because hourly rows start on the hours of the session time zone of the apps
 *    that mark hours stale (calc_stale_datm() truncates in it), and on production those are whole
 *    hours from UTC. The check below refuses to run if a pending stale hour does not start on a
 *    UTC hour, as an hour straddling B would get no 15 minute rows for its part after B.
 *
 * INDEX TABLESPACE. change_to_hypertable() recreates only an index that backs a primary key named
 * <table>_pkey. agg_datm_15m_pkey is a plain unique index, as agg_datm_hourly_pkey is, so it is
 * moved with ALTER INDEX. That is done before seeding: a new chunk's index is created in the
 * tablespace of the hypertable's index (checked on TimescaleDB 2.19.3, and checked again below).
 *
 * GRANTS. They match a freshly built database, where the solardatm default privileges apply:
 * tables SELECT to solar and ALL to solarinput and solarjobs, as agg_datm_hourly has; functions
 * EXECUTE to solar and nothing to PUBLIC. They are given explicitly because default privileges
 * apply only to objects created by the role that registered them. The table grants come before
 * the seeding, so the chunks are created with them. CREATE OR REPLACE kept the ACLs of the two
 * replaced functions, whose signatures are unchanged.
 *
 * CHUNK SEEDING (D2 in the plan). TimescaleDB creates a chunk when the first row for its time
 * range arrives, at the chunk interval set at that moment. A chunk covers one whole multiple of
 * the interval counted from 1970-01-01 UTC, trimmed where it would overlap an existing chunk. So
 * for each step below the script sets the interval and inserts one seed row, with the all-zero
 * stream ID, into every chunk of the step. It then checks the chunks are exactly the planned ones
 * and their indexes are in solarindex, deletes the seed rows, and leaves the interval at the last
 * step's, 60 days, which is also the interval for new data. Steps are in days since 1970-01-01
 * UTC: from_day and until_day must be multiples of chunk_days, each step starts where the one
 * before ended, and a NULL until_day means "through the chunk holding today". The first chunk
 * starts at 2002-07-12, the nearest date before the SolarNetwork epoch of 2005-01-01 that is a
 * whole multiple of a suitable interval; rows dated earlier are mistakes, and make small chunks
 * of their own that can be dropped, as for the other tables. The sizes aim at 10 to 20 GB of heap
 * and index per chunk once backfilled (plan section 7.2). OPS-50 adds the solarwarm job later.
 */
\set ON_ERROR_STOP on

SET LOCAL lock_timeout = '30s';

DO $$
BEGIN
	-- with psql -1 the statement before this one began the transaction
	IF transaction_timestamp() = statement_timestamp() THEN
		RAISE EXCEPTION 'Run this script in one transaction'
		USING HINT = 'psql -1 -d solarnetwork -f NET-540-production.sql';
	END IF;
	IF to_regclass('solardatm.agg_datm_15m') IS NULL
			OR to_regclass('solardatm.agg_datm_15m_setting') IS NULL
			OR to_regprocedure('solardatm.agg_datm_15m_complete_from()') IS NULL THEN
		RAISE EXCEPTION 'The NET-540 migration has not been run'
		USING HINT = 'Run migrations/migrate-20261120.sql from the central repo first.';
	END IF;
	IF EXISTS (
		SELECT 1 FROM timescaledb_information.hypertables
		WHERE hypertable_schema = 'solardatm' AND hypertable_name = 'agg_datm_15m'
	) THEN
		RAISE EXCEPTION 'solardatm.agg_datm_15m is already a hypertable: this script has been run';
	END IF;
	IF EXISTS (SELECT 1 FROM solardatm.agg_datm_15m) THEN
		RAISE EXCEPTION 'solardatm.agg_datm_15m has rows; it must be empty before its chunks are seeded';
	END IF;
	IF EXISTS (SELECT 1 FROM solardatm.agg_datm_15m_setting) THEN
		RAISE EXCEPTION 'The 15 minute boundary is already set';
	END IF;
	-- the queue holds only pending rows, so this reads little
	IF EXISTS (
		SELECT 1 FROM solardatm.agg_stale_datm
		WHERE agg_kind = 'h'
			AND ts_start <> date_trunc('hour', ts_start AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'
	) THEN
		RAISE EXCEPTION 'A pending stale hour does not start on a UTC hour'
		USING HINT = 'The boundary must be on the hours that hourly rows start on; see the header.';
	END IF;
END
$$;

SELECT _timescaledb_solarnetwork.change_to_hypertable('solardatm', 'agg_datm_15m', 'ts_start', '60 days', 'solarindex');

ALTER INDEX solardatm.agg_datm_15m_pkey SET TABLESPACE solarindex;
ALTER INDEX solardatm.agg_datm_15m_setting_pkey SET TABLESPACE solarindex;

GRANT SELECT ON TABLE solardatm.agg_datm_15m TO solar;
GRANT ALL ON TABLE solardatm.agg_datm_15m TO solarinput;
GRANT ALL ON TABLE solardatm.agg_datm_15m TO solarjobs;

GRANT SELECT ON TABLE solardatm.agg_datm_15m_setting TO solar;
GRANT ALL ON TABLE solardatm.agg_datm_15m_setting TO solarinput;
GRANT ALL ON TABLE solardatm.agg_datm_15m_setting TO solarjobs;

REVOKE ALL ON FUNCTION solardatm.agg_datm_15m_complete_from() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION solardatm.agg_datm_15m_complete_from() TO solar;

REVOKE ALL ON FUNCTION solardatm.rollup_datm_15m_for_hour(UUID, TIMESTAMP WITH TIME ZONE,
	TIMESTAMP WITH TIME ZONE, INTERVAL, INTERVAL) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION solardatm.rollup_datm_15m_for_hour(UUID, TIMESTAMP WITH TIME ZONE,
	TIMESTAMP WITH TIME ZONE, INTERVAL, INTERVAL) TO solar;

CREATE TEMPORARY TABLE net540_seed_step (
	step		INT PRIMARY KEY,
	chunk_days	INT NOT NULL,
	from_day	INT NOT NULL,
	until_day	INT
) ON COMMIT DROP;

INSERT INTO net540_seed_step (step, chunk_days, from_day, until_day) VALUES
	  (1,  5940, 11880, 17820)	-- 2002-07-12 to 2018-10-16, one chunk
	, (2,   540, 17820, 18360)	-- 2018-10-16 to 2020-04-08
	, (3,   360, 18360, 19080)	-- 2020-04-08 to 2022-03-29
	, (4,   180, 19080, 20160)	-- 2022-03-29 to 2025-03-13
	, (5,    90, 20160, 20700)	-- 2025-03-13 to 2026-09-04
	, (6,    60, 20700,  NULL);	-- 2026-09-04 onwards: the interval for new data

CREATE TEMPORARY TABLE net540_seed_plan (
	range_start	TIMESTAMP WITH TIME ZONE PRIMARY KEY,
	range_end	TIMESTAMP WITH TIME ZONE NOT NULL,
	chunk_days	INT NOT NULL
) ON COMMIT DROP;

DO $$
DECLARE
	ht			CONSTANT regclass := 'solardatm.agg_datm_15m'::regclass;
	seed_id		CONSTANT UUID := '00000000-0000-0000-0000-000000000000';
	today_day	CONSTANT INT := floor(extract(epoch FROM now()) / 86400)::INT;
	s			RECORD;
	until_day	INT;
	prev_until	INT;
	problems	BIGINT;
BEGIN
	IF EXISTS (
		SELECT 1 FROM timescaledb_information.chunks c
		WHERE c.hypertable_schema = 'solardatm' AND c.hypertable_name = 'agg_datm_15m'
	) THEN
		RAISE EXCEPTION 'solardatm.agg_datm_15m already has chunks';
	END IF;

	FOR s IN SELECT * FROM net540_seed_step ORDER BY step LOOP
		until_day := COALESCE(s.until_day, (today_day / s.chunk_days + 1) * s.chunk_days);
		IF s.from_day % s.chunk_days <> 0 OR until_day % s.chunk_days <> 0 OR until_day <= s.from_day THEN
			RAISE EXCEPTION 'Step %: from_day % and until_day % must be increasing multiples of chunk_days %',
				s.step, s.from_day, until_day, s.chunk_days;
		END IF;
		IF prev_until IS NOT NULL AND s.from_day <> prev_until THEN
			RAISE EXCEPTION 'Step % starts at day % but the step before ended at day %',
				s.step, s.from_day, prev_until;
		END IF;

		INSERT INTO net540_seed_plan (range_start, range_end, chunk_days)
		SELECT to_timestamp(d::BIGINT * 86400), to_timestamp((d + s.chunk_days)::BIGINT * 86400), s.chunk_days
		FROM generate_series(s.from_day, until_day - 1, s.chunk_days) d;

		PERFORM public.set_chunk_time_interval(ht, make_interval(days => s.chunk_days));
		INSERT INTO solardatm.agg_datm_15m (stream_id, ts_start)
		SELECT seed_id, to_timestamp(d::BIGINT * 86400)
		FROM generate_series(s.from_day, until_day - 1, s.chunk_days) d;

		prev_until := until_day;
	END LOOP;

	-- the chunks must be exactly the ones planned
	SELECT count(*) INTO problems
	FROM net540_seed_plan p
	FULL OUTER JOIN (
		SELECT c.range_start, c.range_end
		FROM timescaledb_information.chunks c
		WHERE c.hypertable_schema = 'solardatm' AND c.hypertable_name = 'agg_datm_15m'
	) c ON c.range_start = p.range_start AND c.range_end = p.range_end
	WHERE p.range_start IS NULL OR c.range_start IS NULL;
	IF problems > 0 THEN
		RAISE EXCEPTION '% chunks of solardatm.agg_datm_15m differ from the plan', problems;
	END IF;

	-- every chunk has one index, and it is in solarindex
	SELECT count(*) INTO problems
	FROM timescaledb_information.chunks c
	LEFT OUTER JOIN pg_catalog.pg_index i
		ON i.indrelid = format('%I.%I', c.chunk_schema, c.chunk_name)::regclass
	LEFT OUTER JOIN pg_catalog.pg_class ic ON ic.oid = i.indexrelid
	LEFT OUTER JOIN pg_catalog.pg_tablespace t ON t.oid = ic.reltablespace
	WHERE c.hypertable_schema = 'solardatm' AND c.hypertable_name = 'agg_datm_15m'
		AND t.spcname IS DISTINCT FROM 'solarindex';
	IF problems > 0 THEN
		RAISE EXCEPTION '% chunk indexes of solardatm.agg_datm_15m are not in solarindex', problems;
	END IF;
	IF (SELECT count(*) FROM pg_catalog.pg_index i
			INNER JOIN timescaledb_information.chunks c
				ON i.indrelid = format('%I.%I', c.chunk_schema, c.chunk_name)::regclass
			WHERE c.hypertable_schema = 'solardatm' AND c.hypertable_name = 'agg_datm_15m')
		<> (SELECT count(*) FROM net540_seed_plan) THEN
		RAISE EXCEPTION 'The chunks of solardatm.agg_datm_15m do not have one index each';
	END IF;

	DELETE FROM solardatm.agg_datm_15m WHERE stream_id = seed_id;
	IF EXISTS (SELECT 1 FROM solardatm.agg_datm_15m) THEN
		RAISE EXCEPTION 'solardatm.agg_datm_15m has rows after the seed rows were deleted';
	END IF;

	IF (SELECT d.time_interval FROM timescaledb_information.dimensions d
			WHERE d.hypertable_schema = 'solardatm' AND d.hypertable_name = 'agg_datm_15m')
		IS DISTINCT FROM INTERVAL '60 days' THEN
		RAISE EXCEPTION 'The chunk interval of solardatm.agg_datm_15m is not 60 days';
	END IF;
END
$$;

\echo === chunks created ===
SELECT row_number() OVER (ORDER BY c.range_start) AS chunk
	, c.range_start AT TIME ZONE 'UTC' AS range_start_utc
	, c.range_end AT TIME ZONE 'UTC' AS range_end_utc
	, round(extract(epoch FROM c.range_end - c.range_start) / 86400) AS days
	, c.chunk_name
FROM timescaledb_information.chunks c
WHERE c.hypertable_schema = 'solardatm' AND c.hypertable_name = 'agg_datm_15m'
ORDER BY c.range_start;

-- last, so that no session can see the boundary before the chunks exist
INSERT INTO solardatm.agg_datm_15m_setting (complete_from)
VALUES (date_trunc('hour', clock_timestamp() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' + INTERVAL 'PT1H');

\echo === boundary set; run NET-540-production-stale.sql once this has committed ===
SELECT complete_from AT TIME ZONE 'UTC' AS complete_from_utc
FROM solardatm.agg_datm_15m_setting;
