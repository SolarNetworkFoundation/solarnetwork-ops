-- NET-542 read-only production check (solardb-0 or a replica), run in psql.
-- Replace :node, :source and :user with a stream QueryingDatumStreamsAccessor queries: one
-- that has had datum every minute or so for the last 90 days shows the difference best.
-- Prepared statements outlive ROLLBACK, so they are deallocated explicitly.
\set node 123
\set source /some/source
\set user 456

BEGIN READ ONLY;

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
EXPLAIN (ANALYZE, BUFFERS) EXECUTE net542_before(:node, :'source', :user, now() - INTERVAL '90 days', now(), 1);
EXPLAIN (ANALYZE, BUFFERS) EXECUTE net542_after(:node, :'source', :user, now() - INTERVAL '90 days', now(), 1, 1);

-- the plan with the parameter values, as for the first 4 executions
SET LOCAL plan_cache_mode = force_custom_plan;
EXPLAIN (ANALYZE, BUFFERS) EXECUTE net542_before(:node, :'source', :user, now() - INTERVAL '90 days', now(), 1);
EXPLAIN (ANALYZE, BUFFERS) EXECUTE net542_after(:node, :'source', :user, now() - INTERVAL '90 days', now(), 1, 1);

DEALLOCATE net542_before;
DEALLOCATE net542_after;
ROLLBACK;
