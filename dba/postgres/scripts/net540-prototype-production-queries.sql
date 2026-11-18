-- NET-540: read-only queries for production (run on the replica).
--
--   psql -X -v day=2026-11-17 -f net540-prototype-production-queries.sql
--
-- Options:
--   -v day=YYYY-MM-DD   the UTC day to examine (required); Q4 uses the UTC month holding it,
--                       so give it a day in a complete month
--   -v q=25             run only the listed queries, here Q2 and Q5 (default: all five)
--   -v explain=1        print each query's plan instead of running it
--
-- Every query reaches the hypertables through their primary keys, one stream at a time, because
-- those are the only indexes and they lead with stream_id. A filter on time alone has to scan the
-- whole chunk (a 30-day chunk of da_datm is about 17 GB), which is what the first version of this
-- file did. Before a first run on production, check with -v explain=1 that the plans show index
-- scans on the chunks of da_datm, aud_datm_daily and aud_acc_datm_daily, and no "Seq Scan" on them.
--
-- What each query reads:
--   Q1  the day's datum of streams that have status properties
--   Q2  the day's datum of streams that have two or more accumulating properties
--   Q3  every reset record (a small table), and da_datm between each pair at most 1 hour apart
--   Q4  the month's two audit rows a day for each stream of a billed account
--   Q5  as Q2, then the day's hourly rows of the streams it finds
\pset pager 0
\set ON_ERROR_STOP on

\if :{?day}
\else
	\echo 'Give the day to examine, for example: psql -X -v day=2026-11-17 -f net540-prototype-production-queries.sql'
	\quit
\endif
\if :{?q}
\else
	\set q 12345
\endif
\if :{?explain}
	\set px 'EXPLAIN (COSTS OFF)'
\else
	\set px ''
\endif

-- the bounds as literals, so the planner can exclude chunks
SELECT (:'day'::date)::timestamp AT TIME ZONE 'UTC' AS day_s
	, ((:'day'::date) + 1)::timestamp AT TIME ZONE 'UTC' AS day_e
	, date_trunc('month', (:'day'::date)::timestamp) AT TIME ZONE 'UTC' AS mth_s
	, (date_trunc('month', (:'day'::date)::timestamp) + INTERVAL 'P1M') AT TIME ZONE 'UTC' AS mth_e
	, position('1' IN :'q') > 0 AS q1
	, position('2' IN :'q') > 0 AS q2
	, position('3' IN :'q') > 0 AS q3
	, position('4' IN :'q') > 0 AS q4
	, position('5' IN :'q') > 0 AS q5
\gset

\if :q1
\echo === Q1. status properties: hours where the most frequent of the 15m values differs from the most frequent raw value ===
-- Only streams whose metadata lists status property names are read.
:px WITH v AS (
	SELECT s.stream_id
		, time_bucket(INTERVAL 'PT1H', d.ts) AS h
		, time_bucket(INTERVAL 'PT15M', d.ts) AS q
		, p.idx
		, p.val
	FROM (
		SELECT stream_id FROM solardatm.da_datm_meta WHERE cardinality(names_s) > 0
		UNION ALL
		SELECT stream_id FROM solardatm.da_loc_datm_meta WHERE cardinality(names_s) > 0
	) s
	CROSS JOIN LATERAL (
		SELECT d.ts, d.data_s
		FROM solardatm.da_datm d
		WHERE d.stream_id = s.stream_id
			AND d.ts >= :'day_s'::timestamptz
			AND d.ts < :'day_e'::timestamptz
			AND d.data_s IS NOT NULL
		OFFSET 0 -- keeps this a per-stream index range scan
	) d
	CROSS JOIN LATERAL unnest(d.data_s) WITH ORDINALITY AS p(val, idx)
	WHERE p.val IS NOT NULL
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
\endif

\if :q2
\echo === Q2. accumulating properties present in some datum of a stream and missing from others ===
:px WITH p AS (
	SELECT m.stream_id
		, i.idx
		, count(*) FILTER (WHERE d.data_a[i.idx] IS NOT NULL) AS present
		, count(*) FILTER (WHERE d.data_a[i.idx] IS NULL) AS missing
	FROM solardatm.da_datm_meta m
	CROSS JOIN LATERAL (
		SELECT d.data_a
		FROM solardatm.da_datm d
		WHERE d.stream_id = m.stream_id
			AND d.ts >= :'day_s'::timestamptz
			AND d.ts < :'day_e'::timestamptz
			AND d.data_a IS NOT NULL
		OFFSET 0 -- keeps this a per-stream index range scan
	) d
	CROSS JOIN LATERAL generate_series(1, cardinality(m.names_a)) AS i(idx)
	WHERE cardinality(m.names_a) > 1
	GROUP BY 1, 2
)
SELECT count(DISTINCT stream_id) AS streams_with_2_or_more_accumulating
	, count(DISTINCT stream_id) FILTER (WHERE present > 0 AND missing > 0) AS streams_mixed
	, count(*) FILTER (WHERE present > 0 AND missing > 0) AS properties_mixed
	, sum(present) FILTER (WHERE present > 0 AND missing > 0) AS datum_with_the_property
	, sum(missing) FILTER (WHERE present > 0 AND missing > 0) AS datum_without_it
FROM p;
\endif

\if :q3
\echo === Q3. reset records: pairs at most 1 hour apart with no datum between them (all time) ===
:px WITH r AS (
	SELECT stream_id, ts, lead(ts) OVER (PARTITION BY stream_id ORDER BY ts) AS nxt
	FROM solardatm.da_datm_aux
	WHERE atype = 'Reset'::solardatm.da_datm_aux_type
)
, pairs AS MATERIALIZED ( -- so da_datm is probed once for each pair, not once for each column below
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
\endif

\if :q4
\echo === Q4. estimated 15m rows by billed account, stored-datum tier and cadence class, for the month holding :day ===
-- Accounts are numbered by stored datum-days, largest first, so no account or user IDs are output.
:px WITH st AS (
	-- the streams of billed accounts
	SELECT ba.user_id, m.stream_id
	FROM (SELECT DISTINCT user_id FROM solarbill.bill_account) ba
	INNER JOIN solaruser.user_node un ON un.user_id = ba.user_id
	INNER JOIN solardatm.da_datm_meta m ON m.node_id = un.node_id
)
, sm AS (
	-- per stream over the month, each audit table read through its primary key:
	-- datum-days stored, as solarbill.billing_usage() sums them (but with one month boundary for
	-- every node rather than each node's own time zone); and datum rows, hourly rows and
	-- estimated 15m rows
	SELECT st.user_id, st.stream_id, acc.datum_days, a.datum, a.rows_hourly, a.rows_15m
	FROM st
	CROSS JOIN LATERAL (
		SELECT SUM(acc.datum_count + acc.datum_hourly_count + acc.datum_daily_count + acc.datum_monthly_count) AS datum_days
		FROM solardatm.aud_acc_datm_daily acc
		WHERE acc.stream_id = st.stream_id
			AND acc.ts_start >= :'mth_s'::timestamptz
			AND acc.ts_start < :'mth_e'::timestamptz
	) acc
	CROSS JOIN LATERAL (
		SELECT SUM(a.datum_count) AS datum
			, SUM(a.datum_hourly_count) AS rows_hourly
			, SUM(LEAST(a.datum_count, 4 * a.datum_hourly_count)) AS rows_15m
		FROM solardatm.aud_datm_daily a
		WHERE a.stream_id = st.stream_id
			AND a.ts_start >= :'mth_s'::timestamptz
			AND a.ts_start < :'mth_e'::timestamptz
	) a
)
, acct AS (
	SELECT user_id, SUM(datum_days) AS datum_days
	FROM sm
	GROUP BY user_id
	HAVING SUM(datum_days) IS NOT NULL
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
FROM sm s
INNER JOIN tier t ON t.user_id = s.user_id
WHERE s.datum > 0 AND s.rows_hourly > 0
GROUP BY 1, 2, 3, 4
ORDER BY 1, 4;
\endif

\if :q5
\echo === Q5. for the Q2 streams on :day: hourly reading differences against the first and last readings of the day ===
-- Streams are numbered, so no stream IDs are output. One row for each property that is present in
-- some datum and missing from others. If nothing is lost, reading_short_pct is 0.
:px WITH p AS (
	SELECT m.stream_id
		, i.idx
		, count(*) FILTER (WHERE d.data_a[i.idx] IS NOT NULL) AS present
		, count(*) FILTER (WHERE d.data_a[i.idx] IS NULL) AS missing
	FROM solardatm.da_datm_meta m
	CROSS JOIN LATERAL (
		SELECT d.data_a
		FROM solardatm.da_datm d
		WHERE d.stream_id = m.stream_id
			AND d.ts >= :'day_s'::timestamptz
			AND d.ts < :'day_e'::timestamptz
			AND d.data_a IS NOT NULL
		OFFSET 0 -- keeps this a per-stream index range scan
	) d
	CROSS JOIN LATERAL generate_series(1, cardinality(m.names_a)) AS i(idx)
	WHERE cardinality(m.names_a) > 1
	GROUP BY 1, 2
	HAVING count(*) FILTER (WHERE d.data_a[i.idx] IS NOT NULL) > 0
		AND count(*) FILTER (WHERE d.data_a[i.idx] IS NULL) > 0
)
, h AS (
	SELECT p.stream_id, p.idx, p.present, p.missing
		, count(*) AS hours
		, sum(a.read_a[p.idx][1]) AS reading_diff_sum
		, sum(a.data_a[p.idx]) AS clock_sum
		, (array_agg(a.read_a[p.idx][2] ORDER BY a.ts_start) FILTER (WHERE a.read_a[p.idx][2] IS NOT NULL))[1] AS first_start
		, (array_agg(a.read_a[p.idx][3] ORDER BY a.ts_start DESC) FILTER (WHERE a.read_a[p.idx][3] IS NOT NULL))[1] AS last_end
	FROM p
	CROSS JOIN LATERAL (
		SELECT a.ts_start, a.data_a, a.read_a
		FROM solardatm.agg_datm_hourly a
		WHERE a.stream_id = p.stream_id
			AND a.ts_start >= :'day_s'::timestamptz
			AND a.ts_start < :'day_e'::timestamptz
		OFFSET 0 -- keeps this a per-stream index range scan
	) a
	GROUP BY 1, 2, 3, 4
)
SELECT dense_rank() OVER (ORDER BY h.stream_id) AS stream
	, h.idx AS property
	, h.present
	, h.missing
	, h.hours
	, h.last_end - h.first_start AS first_to_last
	, h.reading_diff_sum
	, h.clock_sum
	, round(100 * (1 - h.reading_diff_sum / NULLIF(h.last_end - h.first_start, 0)), 2) AS reading_short_pct
	, round(100 * (1 - h.clock_sum / NULLIF(h.last_end - h.first_start, 0)), 2) AS clock_short_pct
	, EXISTS (
		SELECT 1 FROM solardatm.da_datm_aux x
		WHERE x.stream_id = h.stream_id
			AND x.ts >= :'day_s'::timestamptz
			AND x.ts < :'day_e'::timestamptz
			AND x.atype = 'Reset'::solardatm.da_datm_aux_type
	) AS has_reset
FROM h
ORDER BY 1, 2;
\endif
