-- migrate datum to datum in month chunks
--EXPLAIN
WITH nodetz AS (
	SELECT n.node_id, COALESCE(l.time_zone, 'UTC') AS tz
	FROM solarnet.sn_node n
	LEFT OUTER JOIN solarnet.sn_loc l ON l.id = n.loc_id
	--WHERE n.node_id = 1101
)
, months AS (
	SELECT date_trunc('month', d.ts at time zone nodetz.tz) at time zone nodetz.tz AS ts_start, d.node_id, d.source_id
	FROM solardatum.da_datum d
	INNER JOIN nodetz ON nodetz.node_id = d.node_id
	GROUP BY date_trunc('month', d.ts at time zone nodetz.tz) at time zone nodetz.tz, d.node_id, d.source_id
)
SELECT * FROM months, solardatm.migrate_datum(months.node_id, months.source_id, months.ts_start, months.ts_start + interval '1 month') AS migrated
;
