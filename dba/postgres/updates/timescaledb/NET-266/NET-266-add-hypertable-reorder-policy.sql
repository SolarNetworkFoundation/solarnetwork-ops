-- to be executed after importing all data
SELECT add_reorder_policy('solardatm.da_datm', 				'da_datm_pkey');
SELECT add_reorder_policy('solardatm.agg_datm_hourly', 		'agg_datm_hourly_pkey');
SELECT add_reorder_policy('solardatm.agg_datm_daily', 		'agg_datm_daily_pkey');
SELECT add_reorder_policy('solardatm.agg_datm_monthly', 	'agg_datm_monthly_pkey');
SELECT add_reorder_policy('solardatm.aud_datm_io', 			'aud_datm_io_pkey');
SELECT add_reorder_policy('solardatm.aud_datm_daily', 		'aud_datm_daily_pkey');
SELECT add_reorder_policy('solardatm.aud_datm_monthly', 	'aud_datm_monthly_pkey');
SELECT add_reorder_policy('solardatm.aud_acc_datm_daily', 	'aud_acc_datm_daily_pkey');
