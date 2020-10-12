-- Fix duplicate external_key value
UPDATE bundles SET external_key = CONCAT(external_key, '_old') WHERE record_id IN (
	SELECT MIN(record_id) FROM bundles WHERE external_key in (
		SELECT external_key FROM bundles GROUP BY external_key HAVING COUNT(*) > 1
	)
	GROUP BY external_key
);
