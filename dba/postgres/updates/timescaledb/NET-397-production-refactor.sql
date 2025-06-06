-- Refactor of NET-397 to introduce cin_datum_stream_map table, and migrate
-- existing cin_datum_stream_prop data to that.

BEGIN;

CREATE TABLE solardin.cin_datum_stream_map (
	user_id			BIGINT NOT NULL,
	id				BIGINT GENERATED BY DEFAULT AS IDENTITY NOT NULL,
	created			TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	modified		TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
	cname			CHARACTER VARYING(64) NOT NULL,
	int_id 			BIGINT NOT NULL,
	sprops			jsonb,
	CONSTRAINT cin_datum_stream_map_pk PRIMARY KEY (user_id, id),
	CONSTRAINT cin_datum_stream_map_int_fk FOREIGN KEY (user_id, int_id)
		REFERENCES solardin.cin_integration (user_id, id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE CASCADE
);

-- populate new table based on datum stream info
INSERT INTO solardin.cin_datum_stream_map (user_id, id, created, modified, cname, int_id)
SELECT user_id, id, created, modified, cname, int_id
FROM solardin.cin_datum_stream
;

-- reset new table seq next val
LOCK TABLE solardin.cin_datum_stream_map IN SHARE MODE
;
SELECT setval('solardin.cin_datum_stream_map_id_seq', COALESCE(max(id) + 1, 1), FALSE)
FROM   solardin.cin_datum_stream_map
HAVING max(id) > (SELECT last_value FROM solardin.cin_datum_stream_map_id_seq)
;

ALTER TABLE solardin.cin_datum_stream_prop
DROP CONSTRAINT cin_datum_stream_prop_pk,
DROP CONSTRAINT cin_datum_stream_prop_ds_fk
;
ALTER TABLE solardin.cin_datum_stream_prop
RENAME ds_id TO map_id
;
ALTER TABLE solardin.cin_datum_stream_prop
ADD CONSTRAINT cin_datum_stream_prop_pk PRIMARY KEY (user_id, map_id, idx),
ADD CONSTRAINT cin_datum_stream_prop_map_fk FOREIGN KEY (user_id, map_id)
		REFERENCES solardin.cin_datum_stream_map (user_id, id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE CASCADE
;

ALTER TABLE solardin.cin_datum_stream
DROP CONSTRAINT cin_datum_stream_int_fk
;
ALTER TABLE solardin.cin_datum_stream
RENAME int_id TO map_id
;
UPDATE solardin.cin_datum_stream
SET map_id = id
;
ALTER TABLE solardin.cin_datum_stream
ADD CONSTRAINT cin_datum_stream_map_fk FOREIGN KEY (user_id, map_id)
		REFERENCES solardin.cin_datum_stream_map (user_id, id) MATCH SIMPLE
		ON UPDATE NO ACTION ON DELETE SET NULL
;


CREATE OR REPLACE FUNCTION solardin.change_integration_enabled()
	RETURNS "trigger"  LANGUAGE plpgsql VOLATILE AS
$$
BEGIN
	UPDATE solardin.cin_datum_stream_poll_task
	SET status = CASE NEW.enabled WHEN TRUE THEN 'q' ELSE 'c' END
	WHERE status =  CASE NEW.enabled WHEN TRUE THEN 'c' ELSE 'q' END
	AND user_id = NEW.user_id
	AND ds_id IN (
		SELECT cds.id
		FROM solardin.cin_datum_stream cds
		INNER JOIN solardin.cin_datum_stream_map cdsm ON cdsm.id = cds.map_id
		WHERE cds.user_id = NEW.user_id
		AND cdsm.int_id = NEW.id
		AND cds.enabled = TRUE
	);

	RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION solardin.change_datum_stream_enabled()
	RETURNS "trigger"  LANGUAGE plpgsql VOLATILE AS
$$
BEGIN
	UPDATE solardin.cin_datum_stream_poll_task
	SET status = CASE NEW.enabled WHEN TRUE THEN 'q' ELSE 'c' END
	WHERE status =  CASE NEW.enabled WHEN TRUE THEN 'c' ELSE 'q' END
	AND user_id = NEW.user_id
	AND ds_id = NEW.id
	AND EXISTS (
		SELECT 1
		FROM solardin.cin_datum_stream_map cdsm
		INNER JOIN solardin.cin_integration ci ON ci.id = cdsm.int_id
		WHERE ci.user_id = NEW.user_id
		AND cdsm.id = NEW.map_id
		AND ci.enabled = TRUE
	);

	RETURN NEW;
END
$$;

COMMIT;
