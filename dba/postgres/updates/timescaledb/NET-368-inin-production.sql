\i init/updates/NET-368-instruction-input.sql

SELECT stmt || ';' FROM (SELECT unnest(ARRAY['solardin']) AS schem) AS s,
LATERAL (SELECT * FROM public.set_index_tablespace(s.schem, 'solarindex')) AS res \gexec

GRANT INSERT, UPDATE ON TABLE solarnet.sn_node_instruction TO solardin;
GRANT INSERT ON TABLE solarnet.sn_node_instruction_param TO solardin;
