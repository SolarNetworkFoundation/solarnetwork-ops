GRANT ALL ON FUNCTION solardatum.calculate_stale_datum(node BIGINT, source CHARACTER VARYING(64), ts_in TIMESTAMP WITH TIME ZONE) TO solar;
REVOKE ALL ON FUNCTION solardatum.calculate_stale_datum(node BIGINT, source CHARACTER VARYING(64), ts_in TIMESTAMP WITH TIME ZONE) FROM PUBLIC;

GRANT ALL ON FUNCTION solardatum.calculate_stale_datum_range(node BIGINT, source CHARACTER VARYING(64), ts_lower TIMESTAMP WITH TIME ZONE, ts_upper TIMESTAMP WITH TIME ZONE) TO solar;
REVOKE ALL ON FUNCTION solardatum.calculate_stale_datum_range(node BIGINT, source CHARACTER VARYING(64), ts_lower TIMESTAMP WITH TIME ZONE, ts_upper TIMESTAMP WITH TIME ZONE) FROM PUBLIC;

GRANT ALL ON FUNCTION solaragg.mark_datum_stale_hour_slots_range(node BIGINT, source CHARACTER VARYING(64), ts_lower TIMESTAMP WITH TIME ZONE, ts_upper TIMESTAMP WITH TIME ZONE) TO solar;
REVOKE ALL ON FUNCTION solaragg.mark_datum_stale_hour_slots_range(node BIGINT, source CHARACTER VARYING(64), ts_lower TIMESTAMP WITH TIME ZONE, ts_upper TIMESTAMP WITH TIME ZONE) FROM PUBLIC;

GRANT ALL ON FUNCTION solarnet.loc_source_time_ranges_local(locs bigint[], sources text[], ts_min timestamp, ts_max timestamp) TO solar;
REVOKE ALL ON FUNCTION solarnet.loc_source_time_ranges_local(locs bigint[], sources text[], ts_min timestamp, ts_max timestamp) FROM PUBLIC;

GRANT ALL ON FUNCTION solardatum.calculate_stale_loc_datum(loc BIGINT, source CHARACTER VARYING(64), ts_in TIMESTAMP WITH TIME ZONE) TO solar;
REVOKE ALL ON FUNCTION solardatum.calculate_stale_loc_datum(loc BIGINT, source CHARACTER VARYING(64), ts_in TIMESTAMP WITH TIME ZONE) FROM PUBLIC;

GRANT ALL ON FUNCTION solardatum.delete_loc_datum(locs BIGINT[], sources TEXT[], ts_min TIMESTAMP, ts_max TIMESTAMP) TO solar;
REVOKE ALL ON FUNCTION solardatum.delete_loc_datum(locs BIGINT[], sources TEXT[], ts_min TIMESTAMP, ts_max TIMESTAMP)  FROM PUBLIC;
