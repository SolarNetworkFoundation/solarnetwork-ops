-- anonymize emails; disable accounting
UPDATE solaruser.user_user
SET email = md5((regexp_match(email, '^(.*)@'))[1]) || '_' || (regexp_match(email, '.*@(.*)$'))[1] || '@localhost'
  , disp_name = CASE id WHEN -1 THEN disp_name ELSE md5(disp_name) END
  , jdata = jdata || (CASE WHEN jdata ->> 'accounting' = 'snf' THEN '{"accounting":"_snf"}'::jsonb ELSE '{}'::jsonb END)
;

-- anonymize billing emails
UPDATE solarbill.bill_address
SET email = md5((regexp_match(email, '^(.*)@'))[1]) || '_' || (regexp_match(email, '.*@(.*)$'))[1] || '@localhost'
  , address = ARRAY['123 Main Street']
  , disp_name = md5(disp_name)
;

-- add test user 147 example@localhost, password example
INSERT INTO solaruser.user_user ("id","created","disp_name","email","password","enabled","loc_id","jdata")
VALUES (147,E'2016-07-21 14:42:52.673+12',E'Devel Oper',E'example@localhost',E'$2a$12$/izl8J4w2szEjMfbLBdS0.J0wmdhJz.EFk5ayufu2wpSTonW/dpOK',TRUE,11536819,E'{"accounting": "snf"}');

INSERT INTO solaruser.user_role (user_id, role_name)
SELECT * FROM ( VALUES
			  (147, 'ROLE_BILLING')
			, (147, 'ROLE_CLOUD_INTEGRATIONS')
			, (147, 'ROLE_DATUM_INPUT')
			, (147, 'ROLE_DNP3')
			, (147, 'ROLE_EVENT')
			, (147, 'ROLE_EXPORT')
			, (147, 'ROLE_IMPORT')
			, (147, 'ROLE_INSTRUCTION_INPUT')
			, (147, 'ROLE_OCPP')
			, (147, 'ROLE_OSCP')
			, (147, 'ROLE_USER')
		) AS t(user_id, role_name)
;

-- switch test node 179 to user 147
UPDATE solaruser.user_node
SET user_id = 147
  , archived = FALSE
WHERE node_id = 179
;

-- delete metadata
DELETE FROM solarnet.sn_node_meta;
DELETE FROM solaruser.user_meta;
UPDATE solardatm.da_datm_meta SET jdata = NULL;

-- delete instructions
DELETE FROM solarnet.sn_node_instruction;

-- delete import jobs
DELETE FROM solarnet.sn_datum_import_job;

-- delete export tasks
DELETE FROM solaruser.user_export_task;
DELETE FROM solarnet.sn_datum_export_task;
DELETE FROM solaruser.user_export_datum_conf;
DELETE FROM solaruser.user_export_data_conf;
DELETE FROM solaruser.user_export_dest_conf;
DELETE FROM solaruser.user_export_outp_conf;
DELETE FROM solaruser.user_adhoc_export_task;

-- delete expire jobs
DELETE FROM solaruser.user_datum_delete_job;
DELETE FROM solaruser.user_expire_data_conf;

-- delete OAuth creds
DELETE FROM solarnet.oauth2_authorized_client;

-- delete security tokens
DELETE FROM solaruser.user_auth_token;

-- delete event hooks
DELETE FROM solaruser.user_node_event_hook;

-- delete DIN, ININ
DELETE FROM solardin.cin_integration;
DELETE FROM solardin.cin_datum_stream;
DELETE FROM solardin.din_credential;
DELETE FROM solardin.din_endpoint;
DELETE FROM solardin.din_input_data;
DELETE FROM solardin.din_xform;
DELETE FROM solardin.inin_credential;
DELETE FROM solardin.inin_endpoint;
DELETE FROM solardin.inin_req_xform;
DELETE FROM solardin.inin_res_xform;

-- delete from SolarDNP3
DELETE FROM solardnp3.dnp3_ca_cert;
DELETE FROM solardnp3.dnp3_server;

-- delete from OCPP
DELETE FROM solarev.ocpp_authorization;
DELETE FROM solarev.ocpp_system_user;

-- delete from OSCP
DELETE FROM solaroscp.oscp_cg_conf;
DELETE FROM solaroscp.oscp_co_conf;
DELETE FROM solaroscp.oscp_cp_conf;
DELETE FROM solaroscp.oscp_fp_token;

-- delete from user
DELETE FROM solaruser.http_session;
DELETE FROM solaruser.user_alert;
