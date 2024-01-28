SELECT count(*) AS customer_count
FROM solaruser.user_user
WHERE jdata->>'accounting' = 'snf'
