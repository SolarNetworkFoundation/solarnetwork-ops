\i init/updates/NET-379-solarflux-agg-pub-settings.sql

ALTER INDEX solaruser.user_flux_default_agg_pub_settings_pk 	SET TABLESPACE solarindex;
ALTER INDEX solaruser.user_flux_agg_pub_settings_pk 			SET TABLESPACE solarindex;
ALTER INDEX solaruser.user_flux_agg_pub_settings_node_idx 		SET TABLESPACE solarindex;

REVOKE ALL ON TABLE solaruser.user_flux_agg_pub_settings FROM solar;

GRANT SELECT ON TABLE solaruser.user_flux_agg_pub_settings TO solar;

GRANT ALL ON TABLE solaruser.user_flux_agg_pub_settings TO solaruser;

REVOKE ALL ON TABLE solaruser.user_flux_default_agg_pub_settings FROM solar;

GRANT SELECT ON TABLE solaruser.user_flux_default_agg_pub_settings TO solar;

GRANT ALL ON TABLE solaruser.user_flux_default_agg_pub_settings TO solaruser;
