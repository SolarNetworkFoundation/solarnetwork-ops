-- NET-540: read-only queries for production (run on the replica).
--   psql -X -v day=2026-11-17 -f production-queries.sql
-- Q1 and Q2 read that day; Q4 reads the month holding it (use a day in a complete month).
\pset pager 0

\echo === Q1. status properties: hours where the most frequent of the 15m values differs from the most frequent raw value ===
WITH v AS (
	SELECT d.stream_id
		, time_bucket(INTERVAL 'PT1H', d.ts) AS h
		, time_bucket(INTERVAL 'PT15M', d.ts) AS q
		, p.idx
		, p.val
	FROM solardatm.da_datm d, unnest(d.data_s) WITH ORDINALITY AS p(val, idx)
	WHERE d.ts >= :'day'::timestamptz AND d.ts < :'day'::timestamptz + INTERVAL 'P1D'
		AND d.data_s IS NOT NULL
		AND p.val IS NOT NULL
)
, hm AS (
	SELECT stream_id, h, idx, mode() WITHIN GROUP (ORDER BY val) AS m, count(DISTINCT val) AS vals
	FROM v GROUP BY 1, 2, 3
)
, qm AS (
	SELECT stream_id, h, q, idx, mode() WITHIN GROUP (ORDER BY val) AS m
	FROM v GROUP BY 1, 2, 3, 4
)
, qhm AS (
	SELECT stream_id, h, idx, mode() WITHIN GROUP (ORDER BY m) AS m
	FROM qm GROUP BY 1, 2, 3
)
SELECT count(*) AS hour_properties
	, count(*) FILTER (WHERE hm.vals > 1) AS with_more_than_one_value
	, count(*) FILTER (WHERE hm.m IS DISTINCT FROM qhm.m) AS differ
	, count(DISTINCT hm.stream_id) AS streams
	, count(DISTINCT hm.stream_id) FILTER (WHERE hm.m IS DISTINCT FROM qhm.m) AS streams_differ
FROM hm
INNER JOIN qhm USING (stream_id, h, idx);

\echo === Q2. accumulating properties present in some datum of a stream and missing from others ===
WITH p AS (
	SELECT d.stream_id
		, i.idx
		, count(*) FILTER (WHERE d.data_a[i.idx] IS NOT NULL) AS present
		, count(*) FILTER (WHERE d.data_a[i.idx] IS NULL) AS missing
	FROM solardatm.da_datm d
	INNER JOIN solardatm.da_datm_meta m ON m.stream_id = d.stream_id
	CROSS JOIN LATERAL generate_series(1, cardinality(m.names_a)) AS i(idx)
	WHERE d.ts >= :'day'::timestamptz AND d.ts < :'day'::timestamptz + INTERVAL 'P1D'
		AND d.data_a IS NOT NULL
		AND cardinality(m.names_a) > 1
	GROUP BY 1, 2
)
SELECT count(DISTINCT stream_id) AS streams_with_2_or_more_accumulating
	, count(DISTINCT stream_id) FILTER (WHERE present > 0 AND missing > 0) AS streams_mixed
	, count(*) FILTER (WHERE present > 0 AND missing > 0) AS properties_mixed
	, sum(present) FILTER (WHERE present > 0 AND missing > 0) AS datum_with_the_property
	, sum(missing) FILTER (WHERE present > 0 AND missing > 0) AS datum_without_it
FROM p;

\echo === Q3. reset records: pairs at most 1 hour apart with no datum between them (all time) ===
WITH r AS (
	SELECT stream_id, ts, lead(ts) OVER (PARTITION BY stream_id ORDER BY ts) AS nxt
	FROM solardatm.da_datm_aux
	WHERE atype = 'Reset'::solardatm.da_datm_aux_type
)
, pairs AS (
	SELECT r.*
		, NOT EXISTS (
			SELECT 1 FROM solardatm.da_datm d
			WHERE d.stream_id = r.stream_id AND d.ts > r.ts AND d.ts < r.nxt
		) AS no_datum_between
	FROM r
	WHERE r.nxt IS NOT NULL AND r.nxt - r.ts <= INTERVAL 'PT1H'
)
SELECT (SELECT count(*) FROM solardatm.da_datm_aux WHERE atype = 'Reset'::solardatm.da_datm_aux_type) AS reset_records
	, count(*) AS pairs_within_1h
	, count(*) FILTER (WHERE no_datum_between) AS pairs_with_no_datum_between
	, count(DISTINCT stream_id) FILTER (WHERE no_datum_between) AS streams
	, min(ts) FILTER (WHERE no_datum_between) AS earliest
	, max(ts) FILTER (WHERE no_datum_between) AS latest
FROM pairs;

\echo === Q4. estimated 15m rows by billed account, stored-datum tier and cadence class, for the month holding :day ===
-- Accounts are numbered by stored datum-days, largest first, so no account or user IDs are output.
WITH mth AS (
	SELECT date_trunc('month', :'day'::timestamptz) AS s
		, date_trunc('month', :'day'::timestamptz) + INTERVAL 'P1M' AS e
)
, acct AS (
	-- datum-days stored by billed account over the month, as solarbill.billing_usage() sums them
	-- (but with one month boundary for every node rather than each node's own time zone)
	SELECT un.user_id
		, SUM(acc.datum_count + acc.datum_hourly_count + acc.datum_daily_count + acc.datum_monthly_count) AS datum_days
	FROM mth
	INNER JOIN solardatm.aud_acc_datm_daily acc ON acc.ts_start >= mth.s AND acc.ts_start < mth.e
	INNER JOIN solardatm.da_datm_meta m ON m.stream_id = acc.stream_id
	INNER JOIN solaruser.user_node un ON un.node_id = m.node_id
	INNER JOIN solarbill.bill_account ba ON ba.user_id = un.user_id
	GROUP BY un.user_id
)
, tier AS (
	SELECT user_id
		, datum_days
		, dense_rank() OVER (ORDER BY datum_days DESC, user_id) AS account
		, CASE
			WHEN datum_days > 100000000000 THEN 4
			WHEN datum_days > 1000000000 THEN 3
			WHEN datum_days > 10000000 THEN 2
			ELSE 1 END AS top_tier
	FROM acct
)
, s AS (
	-- per stream over the same month: datum rows, hourly rows, and estimated 15m rows
	SELECT a.stream_id
		, SUM(a.datum_count) AS datum
		, SUM(a.datum_hourly_count) AS rows_hourly
		, SUM(LEAST(a.datum_count, 4 * a.datum_hourly_count)) AS rows_15m
	FROM mth
	INNER JOIN solardatm.aud_datm_daily a ON a.ts_start >= mth.s AND a.ts_start < mth.e
	GROUP BY a.stream_id
	HAVING SUM(a.datum_count) > 0 AND SUM(a.datum_hourly_count) > 0
)
SELECT t.account
	, t.top_tier
	, t.datum_days
	, CASE
		WHEN s.datum::numeric / s.rows_hourly > 4 THEN '1: under 15 min'
		WHEN s.datum::numeric / s.rows_hourly > 1 THEN '2: 15 to 60 min'
		ELSE '3: 60 min or more' END AS cadence
	, count(*) AS streams
	, sum(s.datum) AS datum
	, sum(s.rows_hourly) AS rows_hourly
	, sum(s.rows_15m) AS rows_15m_est
FROM s
INNER JOIN solardatm.da_datm_meta m ON m.stream_id = s.stream_id
INNER JOIN solaruser.user_node un ON un.node_id = m.node_id
INNER JOIN tier t ON t.user_id = un.user_id
GROUP BY 1, 2, 3, 4
ORDER BY 1, 4;
