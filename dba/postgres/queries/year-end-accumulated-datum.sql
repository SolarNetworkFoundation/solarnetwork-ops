-- total datum stored on last day of calendar year (UTC)
SELECT
	  SUM(datum_count) AS datum_count
	, SUM(datum_hourly_count) AS datum_hourly_count
	, SUM(datum_daily_count) AS datum_daily_count
	, SUM(datum_monthly_count) AS datum_monthly_count
	, SUM(datum_count + datum_daily_count + datum_hourly_count + datum_monthly_count) AS datum_total_count
FROM solardatm.aud_acc_datm_daily d
WHERE d.ts_start >= '2022-12-31 00:00Z'::TIMESTAMPTZ
	AND d.ts_start < '2023-01-01 00:00Z'::TIMESTAMPTZ
