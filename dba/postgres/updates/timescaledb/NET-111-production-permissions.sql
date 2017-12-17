GRANT EXECUTE ON FUNCTION solarnet.store_node_meta(timestamp with time zone, bigint, text) TO solarnet;
GRANT EXECUTE ON FUNCTION solarnet.store_node_meta(timestamp with time zone, bigint, text) TO solarinput;
REVOKE ALL ON FUNCTION solarnet.store_node_meta(timestamp with time zone, bigint, text) FROM public;

GRANT EXECUTE ON FUNCTION solaragg.calc_datum_time_slots(bigint, text[], timestamp with time zone, interval, integer, interval) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.calc_datum_time_slots(bigint, text[], timestamp with time zone, interval, integer, interval) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.calc_running_datum_total(bigint, text[], timestamp with time zone) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.calc_running_datum_total(bigint, text[], timestamp with time zone) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.calc_running_total(bigint, text[], timestamp with time zone, boolean) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.calc_running_total(bigint, text[], timestamp with time zone, boolean) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_agg_datum_minute(bigint, text[], timestamp with time zone, timestamp with time zone, integer, interval) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_agg_datum_minute(bigint, text[], timestamp with time zone, timestamp with time zone, integer, interval) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_agg_datum_hod(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_agg_datum_hod(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_agg_datum_seasonal_hod(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_agg_datum_seasonal_hod(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_agg_datum_dow(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_agg_datum_dow(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_agg_datum_seasonal_dow(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_agg_datum_seasonal_dow(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_datum_for_time_span(bigint, text[], timestamp with time zone, interval, interval) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_datum_for_time_span(bigint, text[], timestamp with time zone, interval, interval) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_most_recent_hourly(bigint, text[]) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_most_recent_hourly(bigint, text[]) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_most_recent_daily(bigint, text[]) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_most_recent_daily(bigint, text[]) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_most_recent_monthly(bigint, text[]) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_most_recent_monthly(bigint, text[]) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_running_datum(bigint, text[], timestamp with time zone) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_running_datum(bigint, text[], timestamp with time zone) TO solar;

GRANT EXECUTE ON FUNCTION solardatum.datum_prop_count(jsonb) TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.datum_prop_count(jsonb) TO solar;

GRANT EXECUTE ON FUNCTION solardatum.find_most_recent(bigint[]) TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_most_recent(bigint[]) TO solar;

GRANT EXECUTE ON FUNCTION solardatum.find_most_recent(bigint, text[]) TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_most_recent(bigint, text[]) TO solar;

GRANT EXECUTE ON FUNCTION solardatum.store_datum(timestamp with time zone, bigint, text, timestamp with time zone, text) TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.store_datum(timestamp with time zone, bigint, text, timestamp with time zone, text) TO solar;
REVOKE ALL ON FUNCTION solardatum.store_datum(timestamp with time zone, bigint, text, timestamp with time zone, text) FROM public;

GRANT EXECUTE ON FUNCTION solardatum.store_meta(timestamp with time zone, bigint, text, text) TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.store_meta(timestamp with time zone, bigint, text, text) TO solar;
REVOKE ALL ON FUNCTION solardatum.store_meta(timestamp with time zone, bigint, text, text) FROM public;

GRANT EXECUTE ON FUNCTION solardatum.find_available_sources(bigint, timestamp with time zone, timestamp with time zone) TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_available_sources(bigint, timestamp with time zone, timestamp with time zone) TO solar;

GRANT EXECUTE ON FUNCTION solardatum.find_reportable_interval(bigint, text) TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_reportable_interval(bigint, text) TO solar;

GRANT EXECUTE ON FUNCTION solardatum.find_sources_for_meta(bigint[], text) TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_sources_for_meta(bigint[], text) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.calc_loc_datum_time_slots(bigint, text[], timestamp with time zone, interval, integer, interval) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.calc_loc_datum_time_slots(bigint, text[], timestamp with time zone, interval, integer, interval) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.calc_running_loc_datum_total(bigint, text[], timestamp with time zone) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.calc_running_loc_datum_total(bigint, text[], timestamp with time zone) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_agg_loc_datum_minute(bigint, text[], timestamp with time zone, timestamp with time zone, integer, interval) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_agg_loc_datum_minute(bigint, text[], timestamp with time zone, timestamp with time zone, integer, interval) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_agg_loc_datum_hod(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_agg_loc_datum_hod(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_agg_loc_datum_seasonal_hod(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_agg_loc_datum_seasonal_hod(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_agg_loc_datum_dow(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_agg_loc_datum_dow(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_agg_loc_datum_seasonal_dow(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_agg_loc_datum_seasonal_dow(bigint, text[], text[], timestamp with time zone, timestamp with time zone) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_loc_datum_for_time_span(bigint, text[], timestamp with time zone, interval, interval) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_loc_datum_for_time_span(bigint, text[], timestamp with time zone, interval, interval) TO solar;

GRANT EXECUTE ON FUNCTION solaragg.find_running_loc_datum(bigint, text[], timestamp with time zone) TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.find_running_loc_datum(bigint, text[], timestamp with time zone) TO solar;

GRANT EXECUTE ON FUNCTION solardatum.store_loc_datum(timestamp with time zone, bigint, text, timestamp with time zone, text) TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.store_loc_datum(timestamp with time zone, bigint, text, timestamp with time zone, text) TO solar;
REVOKE ALL ON FUNCTION solardatum.store_loc_datum(timestamp with time zone, bigint, text, timestamp with time zone, text) FROM public;

GRANT EXECUTE ON FUNCTION solardatum.store_loc_meta(timestamp with time zone, bigint, text, text) TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.store_loc_meta(timestamp with time zone, bigint, text, text) TO solar;
REVOKE ALL ON FUNCTION solardatum.store_loc_meta(timestamp with time zone, bigint, text, text) FROM public;

GRANT EXECUTE ON FUNCTION solardatum.find_loc_available_sources(bigint, timestamp with time zone, timestamp with time zone) TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_loc_available_sources(bigint, timestamp with time zone, timestamp with time zone) TO solar;

GRANT EXECUTE ON FUNCTION solardatum.find_loc_reportable_interval(bigint, text) TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_loc_reportable_interval(bigint, text) TO solar;

GRANT EXECUTE ON FUNCTION solardatum.find_loc_most_recent(bigint, text[]) TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_loc_most_recent(bigint, text[]) TO solar;

GRANT EXECUTE ON FUNCTION solardatum.find_sources_for_loc_meta(bigint[], text) TO solarnet;
GRANT EXECUTE ON FUNCTION solardatum.find_sources_for_loc_meta(bigint[], text) TO solar;

GRANT EXECUTE ON FUNCTION solaruser.store_user_meta(timestamp with time zone, bigint, text) TO solarnet;
GRANT EXECUTE ON FUNCTION solaruser.store_user_meta(timestamp with time zone, bigint, text) TO solarinput;
REVOKE ALL ON FUNCTION solaruser.store_user_meta(timestamp with time zone, bigint, text) FROM public;

GRANT EXECUTE ON FUNCTION solaruser.store_user_node_cert(timestamp with time zone, bigint, bigint, character, text, bytea) TO solarnet;
GRANT EXECUTE ON FUNCTION solaruser.store_user_node_cert(timestamp with time zone, bigint, bigint, character, text, bytea) TO solar;
REVOKE ALL ON FUNCTION solaruser.store_user_node_cert(timestamp with time zone, bigint, bigint, character, text, bytea) FROM public;

GRANT EXECUTE ON FUNCTION solaruser.store_user_node_xfer(bigint, bigint, character varying) TO solarnet;
GRANT EXECUTE ON FUNCTION solaruser.store_user_node_xfer(bigint, bigint, character varying) TO solarinput;
REVOKE ALL ON FUNCTION solaruser.store_user_node_xfer(bigint, bigint, character varying) FROM public;
