-- allow updating datum audit counts on query
GRANT ALL(stream_id, ts_start, datum_q_count) ON solardatm.aud_datm_io TO solaruser;
GRANT INSERT, UPDATE ON TABLE solardatm.aud_stale_datm TO solaruser;
