GRANT USAGE ON SCHEMA public TO solardin;
GRANT USAGE ON SCHEMA solardin TO solardin;
GRANT USAGE ON SCHEMA solardin TO solarjobs;
GRANT USAGE ON SCHEMA solardin TO solaruser;

-- allow node ownership check
GRANT SELECT(user_id, node_id, archived) ON solaruser.user_node TO solardin;

-- allow generating datum streams
GRANT INSERT, UPDATE ON solardatm.da_datm_meta TO solardin;
GRANT INSERT, UPDATE ON solardatm.da_datm TO solardin;
GRANT ALL(stream_id, ts_start, datum_count, prop_count, prop_u_count) ON solardatm.aud_datm_io TO solardin;
GRANT INSERT, UPDATE ON TABLE solardatm.agg_stale_datm TO solardin;

-- allow adding instructions
GRANT INSERT ON TABLE solarnet.sn_node_instruction TO solardin;
GRANT INSERT ON TABLE solarnet.sn_node_instruction_param TO solardin;
