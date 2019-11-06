ALTER TABLE solaragg.agg_stale_flux OWNER TO solarnet;
GRANT SELECT ON TABLE solaragg.agg_stale_flux TO solar;
GRANT ALL ON TABLE solaragg.agg_stale_flux TO solarinput;

ALTER FUNCTION solaragg.handle_curr_change() OWNER TO solarnet;
GRANT EXECUTE ON FUNCTION solaragg.handle_curr_change() TO solar;
