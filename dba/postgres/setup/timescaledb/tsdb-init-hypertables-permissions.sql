GRANT ALL ON SCHEMA quartz TO solar;
GRANT ALL ON SCHEMA solaragg TO solar;
GRANT ALL ON SCHEMA solarcommon TO solar;
GRANT ALL ON SCHEMA solardatum TO solar;
GRANT ALL ON SCHEMA solarnet TO solar;
GRANT ALL ON SCHEMA solaruser TO solar;

GRANT USAGE ON SCHEMA public TO solarauth;
GRANT USAGE ON SCHEMA solaruser TO solarauth;


GRANT SELECT,USAGE ON SEQUENCE solarnet.solarnet_seq TO solar;
GRANT ALL ON SEQUENCE solarnet.solarnet_seq TO solarinput;

GRANT SELECT,USAGE ON SEQUENCE solarnet.node_seq TO solar;
GRANT ALL ON SEQUENCE solarnet.node_seq TO solarinput;


GRANT ALL ON FUNCTION solaragg.calc_agg_datum_agg(node bigint, sources text[], start_ts timestamp with time zone, end_ts timestamp with time zone, kind character) TO solar;
GRANT ALL ON FUNCTION solaragg.calc_agg_loc_datum_agg(loc bigint, sources text[], start_ts timestamp with time zone, end_ts timestamp with time zone, kind character) TO solar;
GRANT ALL ON FUNCTION solaragg.calc_datum_time_slots(node bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer, tolerance interval) TO solar;
GRANT ALL ON FUNCTION solaragg.calc_datum_time_slots_test(node bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer, tolerance interval) TO solar;
GRANT ALL ON FUNCTION solaragg.calc_loc_datum_time_slots(loc bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer, tolerance interval) TO solar;
GRANT ALL ON FUNCTION solaragg.calc_running_datum_total(nodes bigint[], sources text[], end_ts timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.calc_running_datum_total(node bigint, sources text[], end_ts timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.calc_running_loc_datum_total(locs bigint[], sources text[], end_ts timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.calc_running_loc_datum_total(loc bigint, sources text[], end_ts timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.calc_running_total(pk bigint, sources text[], end_ts timestamp with time zone, loc_mode boolean) TO solar;
GRANT ALL ON FUNCTION solaragg.find_agg_datum_dow(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.find_agg_datum_hod(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.find_agg_datum_minute(node bigint, source text[], start_ts timestamp with time zone, end_ts timestamp with time zone, slotsecs integer, tolerance interval) TO solar;
GRANT ALL ON FUNCTION solaragg.find_agg_datum_seasonal_dow(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.find_agg_datum_seasonal_hod(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.find_agg_loc_datum_dow(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.find_agg_loc_datum_hod(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.find_agg_loc_datum_minute(loc bigint, source text[], start_ts timestamp with time zone, end_ts timestamp with time zone, slotsecs integer, tolerance interval) TO solar;
GRANT ALL ON FUNCTION solaragg.find_agg_loc_datum_seasonal_dow(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.find_agg_loc_datum_seasonal_hod(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.find_audit_acc_datum_daily(node bigint, source text) TO solar;
GRANT ALL ON FUNCTION solaragg.find_available_sources(nodes bigint[]) TO solar;
GRANT ALL ON FUNCTION solaragg.find_available_sources(nodes bigint[], sdate timestamp with time zone, edate timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.find_available_sources_before(nodes bigint[], edate timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.find_available_sources_since(nodes bigint[], sdate timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.find_datum_for_time_span(node bigint, sources text[], start_ts timestamp with time zone, span interval, tolerance interval) TO solar;
GRANT ALL ON FUNCTION solaragg.find_loc_datum_for_time_span(loc bigint, sources text[], start_ts timestamp with time zone, span interval, tolerance interval) TO solar;
GRANT ALL ON FUNCTION solaragg.find_most_recent_daily(node bigint, sources text[]) TO solar;
GRANT ALL ON FUNCTION solaragg.find_most_recent_hourly(node bigint, sources text[]) TO solar;
GRANT ALL ON FUNCTION solaragg.find_most_recent_monthly(node bigint, sources text[]) TO solar;
GRANT ALL ON FUNCTION solaragg.find_running_datum(node bigint, sources text[], end_ts timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.find_running_loc_datum(loc bigint, sources text[], end_ts timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_datum_daily) TO solar;
GRANT ALL ON FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_datum_hourly) TO solar;
GRANT ALL ON FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_datum_monthly) TO solar;
GRANT ALL ON FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_loc_datum_daily) TO solar;
GRANT ALL ON FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_loc_datum_hourly) TO solar;
GRANT ALL ON FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_loc_datum_monthly) TO solar;
GRANT ALL ON FUNCTION solaragg.minute_time_slot(ts timestamp with time zone, sec integer) TO solar;
GRANT ALL ON FUNCTION solaragg.slot_seconds(secs integer) TO solar;

REVOKE ALL ON FUNCTION solaragg.aud_inc_datum_query_count(qdate timestamp with time zone, node bigint, source text, dcount integer) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.aud_inc_datum_query_count(qdate timestamp with time zone, node bigint, source text, dcount integer) TO solar;

REVOKE ALL ON FUNCTION solaragg.populate_audit_acc_datum_daily(node bigint, source text) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.populate_audit_acc_datum_daily(node bigint, source text) TO solarinput;

REVOKE ALL ON FUNCTION solaragg.process_agg_stale_datum(kind character, max integer) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.process_agg_stale_datum(kind character, max integer) TO solarinput;

REVOKE ALL ON FUNCTION solaragg.process_agg_stale_loc_datum(kind character, max integer) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.process_agg_stale_loc_datum(kind character, max integer) TO solarinput;

REVOKE ALL ON FUNCTION solaragg.process_one_agg_stale_datum(kind character) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.process_one_agg_stale_datum(kind character) TO solarinput;

REVOKE ALL ON FUNCTION solaragg.process_one_agg_stale_loc_datum(kind character) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.process_one_agg_stale_loc_datum(kind character) TO solarinput;

REVOKE ALL ON FUNCTION solaragg.process_one_aud_datum_daily_stale(kind character) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.process_one_aud_datum_daily_stale(kind character) TO solarinput;




GRANT ALL ON FUNCTION solarcommon.ant_pattern_to_regexp(pat text) TO solar;
GRANT ALL ON FUNCTION solarcommon.components_from_jdata(jdata jsonb, OUT jdata_i jsonb, OUT jdata_a jsonb, OUT jdata_s jsonb, OUT jdata_t text[]) TO solar;
GRANT ALL ON FUNCTION solarcommon.first_sfunc(anyelement, anyelement) TO solar;
GRANT ALL ON FUNCTION solarcommon.jdata_from_components(jdata_i jsonb, jdata_a jsonb, jdata_s jsonb, jdata_t text[]) TO solar;
GRANT ALL ON FUNCTION solarcommon.json_array_to_text_array(jdata json) TO solar;
GRANT ALL ON FUNCTION solarcommon.json_array_to_text_array(jdata jsonb) TO solar;
GRANT ALL ON FUNCTION solarcommon.jsonb_avg_finalfunc(agg_state jsonb) TO solar;
GRANT ALL ON FUNCTION solarcommon.jsonb_avg_object_finalfunc(agg_state jsonb) TO solar;
GRANT ALL ON FUNCTION solarcommon.jsonb_avg_object_sfunc(agg_state jsonb, el jsonb) TO solar;
GRANT ALL ON FUNCTION solarcommon.jsonb_avg_sfunc(agg_state jsonb, el jsonb) TO solar;
GRANT ALL ON FUNCTION solarcommon.jsonb_diff_object_finalfunc(agg_state jsonb) TO solar;
GRANT ALL ON FUNCTION solarcommon.jsonb_diff_object_sfunc(agg_state jsonb, el jsonb) TO solar;
GRANT ALL ON FUNCTION solarcommon.jsonb_diffsum_jdata_finalfunc(agg_state jsonb) TO solar;
GRANT ALL ON FUNCTION solarcommon.jsonb_diffsum_object_finalfunc(agg_state jsonb) TO solar;
GRANT ALL ON FUNCTION solarcommon.jsonb_diffsum_object_sfunc(agg_state jsonb, el jsonb) TO solar;
GRANT ALL ON FUNCTION solarcommon.jsonb_sum_object_sfunc(agg_state jsonb, el jsonb) TO solar;
GRANT ALL ON FUNCTION solarcommon.jsonb_sum_sfunc(agg_state jsonb, el jsonb) TO solar;
GRANT ALL ON FUNCTION solarcommon.jsonb_weighted_proj_object_finalfunc(agg_state jsonb) TO solar;
GRANT ALL ON FUNCTION solarcommon.jsonb_weighted_proj_object_sfunc(agg_state jsonb, el jsonb, weight double precision) TO solar;
GRANT ALL ON FUNCTION solarcommon.plainto_prefix_tsquery(qtext text) TO solar;
GRANT ALL ON FUNCTION solarcommon.plainto_prefix_tsquery(config regconfig, qtext text) TO solar;
GRANT ALL ON FUNCTION solarcommon.reduce_dim(anyarray) TO solar;
GRANT ALL ON FUNCTION solarcommon.to_rfc1123_utc(d timestamp with time zone) TO solar;


GRANT ALL ON FUNCTION solardatum.calculate_datum_at(nodes bigint[], sources text[], reading_ts timestamp with time zone, span interval) TO solar;
GRANT ALL ON FUNCTION solardatum.calculate_datum_at_local(nodes bigint[], sources text[], reading_ts timestamp without time zone, span interval) TO solar;
GRANT ALL ON FUNCTION solardatum.calculate_datum_diff(nodes bigint[], sources text[], ts_min timestamp with time zone, ts_max timestamp with time zone, tolerance interval) TO solar;
GRANT ALL ON FUNCTION solardatum.calculate_datum_diff_local(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone, tolerance interval) TO solar;
GRANT ALL ON FUNCTION solardatum.calculate_datum_diff_over(nodes bigint[], sources text[], ts_min timestamp with time zone, ts_max timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solardatum.calculate_datum_diff_over(node bigint, source text, ts_min timestamp with time zone, ts_max timestamp with time zone, tolerance interval) TO solar;
GRANT ALL ON FUNCTION solardatum.calculate_datum_diff_over_local(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) TO solar;
GRANT ALL ON FUNCTION solardatum.datum_prop_count(jdata jsonb) TO solar;
GRANT ALL ON FUNCTION solardatum.datum_record_counts(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) TO solar;
GRANT ALL ON FUNCTION solardatum.datum_record_counts_for_filter(jfilter jsonb) TO solar;
GRANT ALL ON FUNCTION solardatum.delete_datum(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) TO solar;
GRANT ALL ON FUNCTION solardatum.delete_datum_for_filter(jfilter jsonb) TO solar;
GRANT ALL ON FUNCTION solardatum.find_available_sources(nodes bigint[]) TO solar;
GRANT ALL ON FUNCTION solardatum.find_available_sources(node bigint, st timestamp with time zone, en timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solardatum.find_earliest_after(nodes bigint[], sources text[], ts_min timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solardatum.find_latest_before(nodes bigint[], sources text[], ts_max timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solardatum.find_least_recent_direct(node bigint) TO solar;
GRANT ALL ON FUNCTION solardatum.find_loc_available_sources(loc bigint, st timestamp with time zone, en timestamp with time zone) TO solar;
GRANT ALL ON FUNCTION solardatum.find_loc_reportable_interval(loc bigint, src text, OUT ts_start timestamp with time zone, OUT ts_end timestamp with time zone, OUT loc_tz text, OUT loc_tz_offset integer) TO solar;
GRANT ALL ON FUNCTION solardatum.find_most_recent(nodes bigint[]) TO solar;
GRANT ALL ON FUNCTION solardatum.find_most_recent(node bigint) TO solar;
GRANT ALL ON FUNCTION solardatum.find_most_recent(node bigint, sources text[]) TO solar;
GRANT ALL ON FUNCTION solardatum.find_most_recent_direct(nodes bigint[]) TO solar;
GRANT ALL ON FUNCTION solardatum.find_most_recent_direct(node bigint) TO solar;
GRANT ALL ON FUNCTION solardatum.find_most_recent_direct(node bigint, sources text[]) TO solar;
GRANT ALL ON FUNCTION solardatum.find_reportable_interval(node bigint, src text, OUT ts_start timestamp with time zone, OUT ts_end timestamp with time zone, OUT node_tz text, OUT node_tz_offset integer) TO solar;
GRANT ALL ON FUNCTION solardatum.find_reportable_intervals(nodes bigint[]) TO solar;
GRANT ALL ON FUNCTION solardatum.find_reportable_intervals(nodes bigint[], sources text[]) TO solar;
GRANT ALL ON FUNCTION solardatum.find_sources_for_loc_meta(locs bigint[], criteria text) TO solar;
GRANT ALL ON FUNCTION solardatum.find_sources_for_meta(nodes bigint[], criteria text) TO solar;
GRANT ALL ON FUNCTION solardatum.jdata_from_datum_aux_final(datum solardatum.da_datum_aux) TO solar;
GRANT ALL ON FUNCTION solardatum.jdata_from_datum_aux_start(datum solardatum.da_datum_aux) TO solar;
GRANT ALL ON FUNCTION solardatum.update_datum_range_dates(node bigint, source character varying, rdate timestamp with time zone) TO solar;

REVOKE ALL ON FUNCTION solardatum.move_datum_aux(cdate_from timestamp with time zone, node_from bigint, src_from character varying, aux_type_from solardatum.da_datum_aux_type, cdate timestamp with time zone, node bigint, src character varying, aux_type solardatum.da_datum_aux_type, aux_notes text, jdata_final text, jdata_start text, meta_json text) FROM PUBLIC;
GRANT ALL ON FUNCTION solardatum.move_datum_aux(cdate_from timestamp with time zone, node_from bigint, src_from character varying, aux_type_from solardatum.da_datum_aux_type, cdate timestamp with time zone, node bigint, src character varying, aux_type solardatum.da_datum_aux_type, aux_notes text, jdata_final text, jdata_start text, meta_json text) TO solarinput;

REVOKE ALL ON FUNCTION solardatum.store_datum(cdate timestamp with time zone, node bigint, src text, pdate timestamp with time zone, jdata text, track_recent boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION solardatum.store_datum(cdate timestamp with time zone, node bigint, src text, pdate timestamp with time zone, jdata text, track_recent boolean) TO solarinput;

REVOKE ALL ON FUNCTION solardatum.store_datum_aux(cdate timestamp with time zone, node bigint, src character varying, aux_type solardatum.da_datum_aux_type, aux_notes text, jdata_final text, jdata_start text, jmeta text) FROM PUBLIC;
GRANT ALL ON FUNCTION solardatum.store_datum_aux(cdate timestamp with time zone, node bigint, src character varying, aux_type solardatum.da_datum_aux_type, aux_notes text, jdata_final text, jdata_start text, jmeta text) TO solarinput;

REVOKE ALL ON FUNCTION solardatum.store_loc_datum(cdate timestamp with time zone, loc bigint, src text, pdate timestamp with time zone, jdata text) FROM PUBLIC;
GRANT ALL ON FUNCTION solardatum.store_loc_datum(cdate timestamp with time zone, loc bigint, src text, pdate timestamp with time zone, jdata text) TO solarinput;

REVOKE ALL ON FUNCTION solardatum.store_loc_meta(cdate timestamp with time zone, loc bigint, src text, jdata text) FROM PUBLIC;
GRANT ALL ON FUNCTION solardatum.store_loc_meta(cdate timestamp with time zone, loc bigint, src text, jdata text) TO solarinput;

REVOKE ALL ON FUNCTION solardatum.store_meta(cdate timestamp with time zone, node bigint, src text, jdata text) FROM PUBLIC;
GRANT ALL ON FUNCTION solardatum.store_meta(cdate timestamp with time zone, node bigint, src text, jdata text) TO solarinput;






GRANT SELECT ON TABLE solarnet.sn_datum_export_task TO solar;
GRANT ALL ON TABLE solarnet.sn_datum_export_task TO solarinput;

GRANT ALL ON FUNCTION solarnet.get_node_local_timestamp(timestamp with time zone, bigint) TO solar;
GRANT ALL ON FUNCTION solarnet.get_node_timezone(bigint) TO solar;
GRANT ALL ON FUNCTION solarnet.get_season(date) TO solar;
GRANT ALL ON FUNCTION solarnet.get_season_monday_start(date) TO solar;
GRANT ALL ON FUNCTION solarnet.node_source_time_ranges_local(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) TO solar;

REVOKE ALL ON FUNCTION solarnet.add_datum_export_task(uid uuid, ex_date timestamp with time zone, cfg text) FROM PUBLIC;
GRANT ALL ON FUNCTION solarnet.add_datum_export_task(uid uuid, ex_date timestamp with time zone, cfg text) TO solarinput;

REVOKE ALL ON FUNCTION solarnet.purge_completed_datum_export_tasks(older_date timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION solarnet.purge_completed_datum_export_tasks(older_date timestamp with time zone) TO solarinput;

REVOKE ALL ON FUNCTION solarnet.purge_completed_datum_import_jobs(older_date timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION solarnet.purge_completed_datum_import_jobs(older_date timestamp with time zone) TO solarinput;

REVOKE ALL ON FUNCTION solarnet.purge_completed_instructions(older_date timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION solarnet.purge_completed_instructions(older_date timestamp with time zone) TO solarinput;

REVOKE ALL ON FUNCTION solarnet.claim_datum_export_task() FROM PUBLIC;
GRANT ALL ON FUNCTION solarnet.claim_datum_export_task() TO solarinput;

REVOKE ALL ON FUNCTION solarnet.claim_datum_import_job()  FROM PUBLIC;
GRANT ALL ON FUNCTION solarnet.claim_datum_import_job() TO solarinput;


REVOKE ALL ON FUNCTION solarnet.store_node_meta(cdate timestamp with time zone, node bigint, jdata text) FROM PUBLIC;
GRANT ALL ON FUNCTION solarnet.store_node_meta(cdate timestamp with time zone, node bigint, jdata text) TO solarinput;




GRANT ALL ON SCHEMA _timescaledb_catalog TO solarinput;



GRANT ALL ON TABLE solardatum.da_datum TO solarinput;
GRANT SELECT ON TABLE solardatum.da_datum TO solar;

GRANT SELECT ON TABLE solardatum.da_datum_aux TO solar;
GRANT ALL ON TABLE solardatum.da_datum_aux TO solarinput;

GRANT ALL ON TABLE solaragg.agg_datum_hourly TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_datum_hourly TO solar;

GRANT ALL ON TABLE solaragg.agg_datum_daily TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_datum_daily TO solar;

GRANT ALL ON TABLE solaragg.agg_datum_monthly TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_datum_monthly TO solar;

GRANT ALL ON TABLE solaragg.agg_datum_hourly_data TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_datum_hourly_data TO solar;

GRANT ALL ON TABLE solaragg.agg_datum_daily_data TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_datum_daily_data TO solar;

GRANT ALL ON TABLE solaragg.agg_datum_monthly_data TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_datum_monthly_data TO solar;

--

GRANT ALL ON TABLE solardatum.da_loc_datum TO solarinput;
GRANT SELECT ON TABLE solardatum.da_loc_datum TO solar;

GRANT ALL ON TABLE solaragg.agg_loc_datum_hourly TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_loc_datum_hourly TO solar;

GRANT ALL ON TABLE solaragg.agg_loc_datum_daily TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_loc_datum_daily TO solar;

GRANT ALL ON TABLE solaragg.agg_loc_datum_monthly TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_loc_datum_monthly TO solar;

GRANT ALL ON TABLE solaragg.agg_loc_datum_hourly_data TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_loc_datum_hourly_data TO solar;

GRANT ALL ON TABLE solaragg.agg_loc_datum_daily_data TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_loc_datum_daily_data TO solar;

GRANT ALL ON TABLE solaragg.agg_loc_datum_monthly_data TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_loc_datum_monthly_data TO solar;


-- GRANT SELECT ON TABLE solarnet.sn_datum_import_job TO solar;
GRANT ALL ON TABLE solarnet.sn_datum_import_job TO solarinput;
