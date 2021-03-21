/**
 * Helper function for reprocessing historic aggregates, oldest to newest, without reprocessing
 * audit or flux data.
 */
CREATE OR REPLACE FUNCTION solardatm.reprocess_agg_stale_datm(
	kind CHARACTER,
	max_ts TIMESTAMP WITH TIME ZONE,
	max_count INTEGER,
	min_ts TIMESTAMP WITH TIME ZONE DEFAULT NULL)
	RETURNS INTEGER LANGUAGE plpgsql VOLATILE AS
$$
DECLARE
	agg_span 				INTERVAL;
	dest_name				TEXT;

	curs 					CURSOR FOR
							SELECT * FROM solardatm.agg_stale_datm
							WHERE agg_kind = kind
								AND ts_start < max_ts
								AND ts_start > CASE
										WHEN min_ts IS NOT NULL THEN min_ts
										ELSE '1970-01-01'::timestamptz
									END
							ORDER BY stream_id, ts_start DESC
							LIMIT max_count
							FOR UPDATE SKIP LOCKED;

	stale 					solardatm.agg_stale_datm;
	sid						UUID;
	tz						TEXT;

	local_ts_start			TIMESTAMP;
	local_ts_end			TIMESTAMP;
	ts_end					TIMESTAMP WITH TIME ZONE;

	num_rows				INTEGER := 0;
BEGIN
	CASE kind
		WHEN 'd' THEN
			agg_span := interval '1 day';
			dest_name := 'agg_datm_daily';
		WHEN 'M' THEN
			agg_span := interval '1 month';
			dest_name := 'agg_datm_monthly';
		ELSE
			agg_span := interval '1 hour';
			dest_name := 'agg_datm_hourly';
	END CASE;

	OPEN curs;
	LOOP
		FETCH NEXT FROM curs INTO stale;
		EXIT WHEN NOT FOUND;
		num_rows := num_rows + 1;

		IF sid IS NULL OR sid <> stale.stream_id THEN
			-- get stream metadata & time zone; will determine if node or location stream
			SELECT stream_id, time_zone
			FROM solardatm.find_metadata_for_stream(stale.stream_id)
			INTO sid, tz;

			tz := COALESCE(tz, 'UTC');
		END IF;

		-- stash local start/end dates to work with calendar intervals
		local_ts_start := stale.ts_start AT TIME ZONE tz;
		local_ts_end   := local_ts_start + agg_span;
		ts_end         := local_ts_end AT TIME ZONE tz;

		BEGIN
			IF kind = 'h' THEN
				EXECUTE format(
						'INSERT INTO solardatm.%I (stream_id, ts_start, data_i, data_a, data_s, data_t, stat_i, read_a) '
						'SELECT stream_id, ts_start, data_i, data_a, data_s, data_t, stat_i, read_a '
						'FROM solardatm.rollup_datm_for_time_span($1, $2, $3) '
						'ON CONFLICT (stream_id, ts_start) DO UPDATE SET '
						'    data_i = EXCLUDED.data_i, '
						'    data_a = EXCLUDED.data_a, '
						'    data_s = EXCLUDED.data_s, '
						'    data_t = EXCLUDED.data_t, '
						'    stat_i = EXCLUDED.stat_i, '
						'    read_a = EXCLUDED.read_a'
						, dest_name)
				USING stale.stream_id, stale.ts_start, ts_end;
			ELSE
				EXECUTE format(
						'INSERT INTO solardatm.%I (stream_id, ts_start, data_i, data_a, data_s, data_t, stat_i, read_a) '
						'SELECT stream_id, ts_start, data_i, data_a, data_s, data_t, stat_i, read_a '
						'FROM solardatm.rollup_agg_data_for_time_span($1, $2, $3, $4) '
						'ON CONFLICT (stream_id, ts_start) DO UPDATE SET '
						'    data_i = EXCLUDED.data_i,'
						'    data_a = EXCLUDED.data_a,'
						'    data_s = EXCLUDED.data_s,'
						'    data_t = EXCLUDED.data_t,'
						'    stat_i = EXCLUDED.stat_i,'
						'    read_a = EXCLUDED.read_a'
						, dest_name)
				USING stale.stream_id, stale.ts_start, ts_end, CASE kind WHEN 'M' THEN 'd' ELSE 'h' END;
			END IF;
		EXCEPTION WHEN invalid_text_representation THEN
			RAISE EXCEPTION 'Invalid text representation processing stream % aggregate % range % - %',
				stale.stream_id, kind, stale.ts_start, ts_end
			USING ERRCODE = 'invalid_text_representation',
				SCHEMA = 'solardatm',
				TABLE = dest_name,
				HINT = 'Check the solardatm.rollup_datm_for_time_span()/da_datum or solardatm.rollup_agg_data_for_time_span()/solardatm.find_agg_datm_for_time_span() with matching stream/date range parameters.';
		END;

		-- now make sure we recalculate the next aggregate level by submitting a stale record
		-- for the next level
		CASE kind
			WHEN 'h' THEN
				INSERT INTO solardatm.agg_stale_datm (stream_id, ts_start, agg_kind)
				VALUES (stale.stream_id, date_trunc('day', local_ts_start) AT TIME ZONE tz, 'd')
				ON CONFLICT DO NOTHING;

			WHEN 'd' THEN
				INSERT INTO solardatm.agg_stale_datm (stream_id, ts_start, agg_kind)
				VALUES (stale.stream_id, date_trunc('month', local_ts_start) AT TIME ZONE tz, 'M')
				ON CONFLICT DO NOTHING;

			ELSE
				-- nothing
		END CASE;

		DELETE FROM solardatm.agg_stale_datm WHERE CURRENT OF curs;
	END LOOP;

	CLOSE curs;

	RETURN num_rows;
END;
$$;
