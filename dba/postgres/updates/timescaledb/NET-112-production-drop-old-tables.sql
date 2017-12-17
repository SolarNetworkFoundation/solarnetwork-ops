\echo `date` Dropping old tables

DROP TABLE solaragg.agg_datum_hourly_old;
DROP TABLE solaragg.agg_datum_daily_old;
DROP TABLE solaragg.agg_datum_monthly_old;

DROP TABLE solaragg.aud_datum_hourly_old;

DROP TABLE solaragg.agg_loc_datum_hourly_old;
DROP TABLE solaragg.agg_loc_datum_daily_old;
DROP TABLE solaragg.agg_loc_datum_monthly_old;

DROP TABLE solaragg.aud_loc_datum_hourly_old;

DROP TABLE solardatum.da_datum_p2008;
DROP TABLE solardatum.da_datum_p2009;
DROP TABLE solardatum.da_datum_p2010;
DROP TABLE solardatum.da_datum_p2011;
DROP TABLE solardatum.da_datum_p2012;
DROP TABLE solardatum.da_datum_p2013;
DROP TABLE solardatum.da_datum_p2014;
DROP TABLE solardatum.da_datum_p2015;
DROP TABLE solardatum.da_datum_p2016;
DROP TABLE solardatum.da_datum_p2017;
DROP TABLE solardatum.da_datum_p2018;
DROP TABLE solardatum.da_datum_old;

DROP TABLE solardatum.da_loc_datum_p2008;
DROP TABLE solardatum.da_loc_datum_p2009;
DROP TABLE solardatum.da_loc_datum_p2010;
DROP TABLE solardatum.da_loc_datum_p2011;
DROP TABLE solardatum.da_loc_datum_p2012;
DROP TABLE solardatum.da_loc_datum_p2013;
DROP TABLE solardatum.da_loc_datum_p2014;
DROP TABLE solardatum.da_loc_datum_p2015;
DROP TABLE solardatum.da_loc_datum_p2016;
DROP TABLE solardatum.da_loc_datum_p2017;
DROP TABLE solardatum.da_loc_datum_p2018;
DROP TABLE solardatum.da_loc_datum_old;

DROP FUNCTION solardatum.da_datum_part_trig_func();
DROP FUNCTION solardatum.da_loc_datum_part_trig_func();
