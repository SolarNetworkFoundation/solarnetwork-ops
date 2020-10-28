-- function to force using fastest index lookup for single stream ID
CREATE OR REPLACE FUNCTION solardatm.find_time_least(sid uuid)
	RETURNS solardatm.da_datm LANGUAGE sql STABLE AS
$$
	SELECT DISTINCT ON (ts) *
	FROM solardatm.da_datm
	WHERE stream_id = sid
	ORDER BY ts
	LIMIT 1
$$;

CREATE OR REPLACE FUNCTION solardatm.find_time_greatest(sid uuid)
	RETURNS solardatm.da_datm LANGUAGE sql STABLE AS
$$
	SELECT DISTINCT ON (ts) *
	FROM solardatm.da_datm
	WHERE stream_id = sid
	ORDER BY ts DESC
	LIMIT 1
$$;


CREATE OR REPLACE FUNCTION solardatm.find_time_range(stream_ids uuid[])
	RETURNS SETOF solardatm.da_datm LANGUAGE sql ROWS 200 STABLE AS
$$
WITH ids AS (
	SELECT unnest(stream_ids) AS stream_id
)
, d AS (
	(
	SELECT d.*
	FROM ids
	INNER JOIN solardatm.find_time_least(ids.stream_id) d ON d.stream_id = ids.stream_id
	)
	UNION ALL
	(
	SELECT d.*
	FROM ids
	INNER JOIN solardatm.find_time_greatest(ids.stream_id) d ON d.stream_id = ids.stream_id
	)
)
SELECT * FROM d
$$;

/** Example: find min/max dates for set of stream IDs:

SELECT stream_id, min(ts) AS min_date, max(ts) AS max_date
FROM solardatm.find_time_range(
		ARRAY['fb4f7451-f1fd-43a1-9e90-47bad878d635'::uuid
			, 'a696abbc-7c5d-4332-a5c6-c733b29cfa72'::uuid
			, '20f31b6f-ec04-465d-872a-f3b05ba40863'::uuid
			, 'e7771c0c-16a9-4376-989e-db2e0f3669ed'::uuid
			, '8ed32534-cf38-4846-971f-b21ecd371667'::uuid
			, '6413cdf3-6af0-4c7b-8c5a-d7314770a112'::uuid
			, '92d359b1-906b-40df-a55c-81a4e8adb9ac'::uuid
			, '927be37c-bd42-4950-8bdf-e0690caf32aa'::uuid
			, '46ac5b68-4718-418d-8845-6d45fd265ab8'::uuid
			, '625cd889-aa51-4929-ba14-163cfe347f9b'::uuid
			, '7d312402-1b8d-4291-915a-5ddd823696cd'::uuid
			, 'c7b3222b-5285-4cec-8a65-c7000031b477'::uuid
			, 'faaed1a6-7859-4037-b7e6-aac2884c42e6'::uuid
			, '34afef12-0fa5-415b-b701-ea948e10c752'::uuid
			, '149a616a-05bf-487d-8bd9-d645c90201e1'::uuid
			]
		)
GROUP BY stream_id
ORDER BY stream_id
;
*/
