-- NET-542 read-only production check (the primary or a replica).
--
-- Compares the statement SolarJobs runs today for QueryingDatumStreamsAccessor with the one
-- SelectDatum generates after NET-542, for one stream, under both kinds of plan.
--
-- Give the stream as psql variables, choosing one with plenty of datum in the last 90 days:
--
--   psql ... -v node=1025 -v source=/0039/S1/R1/GEN/100 -f net542-production-check.sql
--
-- The node's owner is looked up, because the statements join solaruser.user_node: given a user
-- that does not own the node they find no stream, and the datum are never read.
--
-- Prepared statements outlive ROLLBACK, so they are deallocated explicitly.
\if :{?node}
\else
	\echo Usage: psql ... -v node=NODE_ID -v source=SOURCE_ID -f net542-production-check.sql
	\quit
\endif
\if :{?source}
\else
	\echo Usage: psql ... -v node=NODE_ID -v source=SOURCE_ID -f net542-production-check.sql
	\quit
\endif

BEGIN READ ONLY;

SELECT un.user_id AS owner FROM solaruser.user_node un WHERE un.node_id = :node \gset
\if :{?owner}
\else
	\echo No owner found for node :node in solaruser.user_node: nothing to check.
	ROLLBACK;
	\quit
\endif
\set ON_ERROR_STOP on

\pset pager 0

\echo == the stream, its owner, and its datum in the 90 days the statements cover
SELECT m.stream_id, :owner AS owner_user_id
	, (
		SELECT count(*)
		FROM solardatm.da_datm d
		WHERE d.stream_id = m.stream_id
			AND d.ts >= now() - INTERVAL '90 days'
			AND d.ts < now()
		) AS datum_in_range
FROM solardatm.da_datm_meta m
WHERE m.node_id = :node
	AND m.source_id = :'source';

-- before: the statement SolarJobs runs today (pg_stat_statements queryid -945842028083317865)
PREPARE net542_before(BIGINT, VARCHAR, BIGINT, TIMESTAMPTZ, TIMESTAMPTZ, INTEGER) AS
WITH s AS (
SELECT s.stream_id, s.node_id, s.source_id
FROM solardatm.da_datm_meta s
INNER JOIN solaruser.user_node un ON un.node_id = s.node_id
WHERE s.node_id = $1
	AND s.source_id = $2
	AND un.user_id = $3
)
SELECT datum.stream_id,
	datum.ts,
	datum.received,
	datum.data_i,
	datum.data_a,
	datum.data_s,
	datum.data_t
FROM s
INNER JOIN solardatm.da_datm datum ON datum.stream_id = s.stream_id
WHERE datum.ts >= $4
	AND datum.ts < $5
ORDER BY stream_id, ts DESC
LIMIT $6;

-- after: what SelectDatum generates for the same criteria with NET-542
PREPARE net542_after(BIGINT, VARCHAR, BIGINT, TIMESTAMPTZ, TIMESTAMPTZ, BIGINT, INTEGER) AS
WITH s AS (
SELECT s.stream_id, s.node_id, s.source_id
FROM solardatm.da_datm_meta s
INNER JOIN solaruser.user_node un ON un.node_id = s.node_id
WHERE s.node_id = $1
	AND s.source_id = $2
	AND un.user_id = $3
)
SELECT datum.stream_id,
	datum.ts,
	datum.received,
	datum.data_i,
	datum.data_a,
	datum.data_s,
	datum.data_t
FROM s
INNER JOIN LATERAL (
		SELECT datum.*
		FROM solardatm.da_datm datum
		WHERE datum.stream_id = s.stream_id
	AND datum.ts >= $4
	AND datum.ts < $5
		ORDER BY datum.ts DESC
		LIMIT $6
	) datum ON datum.stream_id = s.stream_id
ORDER BY stream_id, ts DESC
LIMIT $7;

-- the plan the JDBC driver gets once it switches the statement to server-prepared
SET LOCAL plan_cache_mode = force_generic_plan;
\echo == 1. before, generic plan
EXPLAIN (ANALYZE, BUFFERS) EXECUTE net542_before(:node, :'source', :owner, now() - INTERVAL '90 days', now(), 1);
\echo == 2. after, generic plan
EXPLAIN (ANALYZE, BUFFERS) EXECUTE net542_after(:node, :'source', :owner, now() - INTERVAL '90 days', now(), 1, 1);

-- the plan with the parameter values, as for the first 4 executions
SET LOCAL plan_cache_mode = force_custom_plan;
\echo == 3. before, custom plan
EXPLAIN (ANALYZE, BUFFERS) EXECUTE net542_before(:node, :'source', :owner, now() - INTERVAL '90 days', now(), 1);
\echo == 4. after, custom plan
EXPLAIN (ANALYZE, BUFFERS) EXECUTE net542_after(:node, :'source', :owner, now() - INTERVAL '90 days', now(), 1, 1);

DEALLOCATE net542_before;
DEALLOCATE net542_after;
ROLLBACK;
