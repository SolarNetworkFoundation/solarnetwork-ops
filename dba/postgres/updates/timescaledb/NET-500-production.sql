\i init/updates/NET-500-source-id-aliases.sql

ALTER INDEX solardatm.da_datm_alias_pk SET TABLESPACE solarindex;
ALTER INDEX solardatm.da_datm_alias_unq SET TABLESPACE solarindex;
ALTER INDEX solardatm.da_datm_alias_node_source_idx SET TABLESPACE solarindex;

GRANT ALL ON TABLE solardatm.da_datm_alias TO solaruser;
GRANT ALL ON TABLE solardatm.da_datm_alias TO solarjobs;
REVOKE ALL ON TABLE solardatm.da_datm_alias FROM solarinput;
GRANT SELECT ON TABLE solardatm.da_datm_alias TO solarinput;

GRANT SELECT ON TABLE solaruser.da_datm_meta_aliased TO solar;
