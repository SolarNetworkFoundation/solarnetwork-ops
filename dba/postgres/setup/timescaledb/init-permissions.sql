--
-- PostgreSQL database dump
--

-- Dumped from database version 9.6.12
-- Dumped by pg_dump version 11.0

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: timescaledb; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS timescaledb WITH SCHEMA public;


--
-- Name: EXTENSION timescaledb; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION timescaledb IS 'Enables scalable inserts and complex queries for time-series data';


--
-- Name: _timescaledb_solarnetwork; Type: SCHEMA; Schema: -; Owner: solarnet
--

CREATE SCHEMA _timescaledb_solarnetwork;


ALTER SCHEMA _timescaledb_solarnetwork OWNER TO solarnet;

--
-- Name: quartz; Type: SCHEMA; Schema: -; Owner: solarnet
--

CREATE SCHEMA quartz;


ALTER SCHEMA quartz OWNER TO solarnet;

--
-- Name: solaragg; Type: SCHEMA; Schema: -; Owner: solarnet
--

CREATE SCHEMA solaragg;


ALTER SCHEMA solaragg OWNER TO solarnet;

--
-- Name: solarcommon; Type: SCHEMA; Schema: -; Owner: solarnet
--

CREATE SCHEMA solarcommon;


ALTER SCHEMA solarcommon OWNER TO solarnet;

--
-- Name: solardatum; Type: SCHEMA; Schema: -; Owner: solarnet
--

CREATE SCHEMA solardatum;


ALTER SCHEMA solardatum OWNER TO solarnet;

--
-- Name: solarnet; Type: SCHEMA; Schema: -; Owner: solarnet
--

CREATE SCHEMA solarnet;


ALTER SCHEMA solarnet OWNER TO solarnet;

--
-- Name: solaruser; Type: SCHEMA; Schema: -; Owner: solarnet
--

CREATE SCHEMA solaruser;


ALTER SCHEMA solaruser OWNER TO solarnet;

--
-- Name: plv8; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plv8 WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plv8; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plv8 IS 'PL/JavaScript (v8) trusted procedural language';


--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pg_stat_statements IS 'track execution statistics of all SQL statements executed';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: da_datum_aux_type; Type: TYPE; Schema: solardatum; Owner: solarnet
--

CREATE TYPE solardatum.da_datum_aux_type AS ENUM (
    'Reset'
);


ALTER TYPE solardatum.da_datum_aux_type OWNER TO solarnet;

--
-- Name: created; Type: DOMAIN; Schema: solarnet; Owner: solarnet
--

CREATE DOMAIN solarnet.created AS timestamp with time zone NOT NULL DEFAULT now();


ALTER DOMAIN solarnet.created OWNER TO solarnet;

--
-- Name: instruction_delivery_state; Type: TYPE; Schema: solarnet; Owner: solarnet
--

CREATE TYPE solarnet.instruction_delivery_state AS ENUM (
    'Unknown',
    'Queued',
    'Queuing',
    'Received',
    'Executing',
    'Declined',
    'Completed'
);


ALTER TYPE solarnet.instruction_delivery_state OWNER TO solarnet;

--
-- Name: solarnet_seq; Type: SEQUENCE; Schema: solarnet; Owner: solarnet
--

CREATE SEQUENCE solarnet.solarnet_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE solarnet.solarnet_seq OWNER TO solarnet;

--
-- Name: pk_i; Type: DOMAIN; Schema: solarnet; Owner: solarnet
--

CREATE DOMAIN solarnet.pk_i AS bigint NOT NULL DEFAULT nextval('solarnet.solarnet_seq'::regclass);


ALTER DOMAIN solarnet.pk_i OWNER TO solarnet;

--
-- Name: user_alert_sit_status; Type: TYPE; Schema: solaruser; Owner: solarnet
--

CREATE TYPE solaruser.user_alert_sit_status AS ENUM (
    'Active',
    'Resolved'
);


ALTER TYPE solaruser.user_alert_sit_status OWNER TO solarnet;

--
-- Name: user_alert_status; Type: TYPE; Schema: solaruser; Owner: solarnet
--

CREATE TYPE solaruser.user_alert_status AS ENUM (
    'Active',
    'Disabled',
    'Suppressed'
);


ALTER TYPE solaruser.user_alert_status OWNER TO solarnet;

--
-- Name: user_alert_type; Type: TYPE; Schema: solaruser; Owner: solarnet
--

CREATE TYPE solaruser.user_alert_type AS ENUM (
    'NodeStaleData'
);


ALTER TYPE solaruser.user_alert_type OWNER TO solarnet;

--
-- Name: user_auth_token_status; Type: TYPE; Schema: solaruser; Owner: solarnet
--

CREATE TYPE solaruser.user_auth_token_status AS ENUM (
    'Active',
    'Disabled'
);


ALTER TYPE solaruser.user_auth_token_status OWNER TO solarnet;

--
-- Name: user_auth_token_type; Type: TYPE; Schema: solaruser; Owner: solarnet
--

CREATE TYPE solaruser.user_auth_token_type AS ENUM (
    'User',
    'ReadNodeData'
);


ALTER TYPE solaruser.user_auth_token_type OWNER TO solarnet;

--
-- Name: find_chunk_index_need_cluster_maint(interval, interval, interval, integer); Type: FUNCTION; Schema: _timescaledb_solarnetwork; Owner: solarnet
--

CREATE FUNCTION _timescaledb_solarnetwork.find_chunk_index_need_cluster_maint(chunk_max_age interval DEFAULT '168 days'::interval, chunk_min_age interval DEFAULT '7 days'::interval, reindex_min_age interval DEFAULT '77 days'::interval, mod_threshold integer DEFAULT 50) RETURNS TABLE(schema_name name, table_name name, index_name name)
    LANGUAGE sql STABLE
    AS $$
WITH ranked AS (
	SELECT DISTINCT ON (chunk_id)
		chunk_id,
		chunk_schema_name,
		chunk_table_name,
		chunk_index_name,
		chunk_upper_range,
		chunk_index_last_cluster,
		n_dead_tup
	FROM _timescaledb_solarnetwork.chunk_time_index_maint
	ORDER BY chunk_id, chunk_index_name
)
SELECT
	chunk_schema_name,
	chunk_table_name,
	chunk_index_name
FROM ranked
WHERE (chunk_upper_range BETWEEN CURRENT_TIMESTAMP - chunk_max_age AND CURRENT_TIMESTAMP - chunk_min_age
		AND (chunk_index_last_cluster IS NULL OR chunk_index_last_cluster < CURRENT_TIMESTAMP - reindex_min_age))
	OR (chunk_upper_range < CURRENT_TIMESTAMP - chunk_min_age AND n_dead_tup >= mod_threshold)
ORDER BY chunk_id
$$;


ALTER FUNCTION _timescaledb_solarnetwork.find_chunk_index_need_cluster_maint(chunk_max_age interval, chunk_min_age interval, reindex_min_age interval, mod_threshold integer) OWNER TO solarnet;

--
-- Name: find_chunk_index_need_maint(interval, interval, interval); Type: FUNCTION; Schema: _timescaledb_solarnetwork; Owner: solarnet
--

CREATE FUNCTION _timescaledb_solarnetwork.find_chunk_index_need_maint(chunk_max_age interval DEFAULT '168 days'::interval, chunk_min_age interval DEFAULT '7 days'::interval, reindex_min_age interval DEFAULT '77 days'::interval) RETURNS TABLE(schema_name name, table_name name, index_name name)
    LANGUAGE sql STABLE
    AS $$
SELECT
	chunk_schema_name,
	chunk_table_name,
	chunk_index_name
FROM _timescaledb_solarnetwork.chunk_time_index_maint
WHERE chunk_upper_range BETWEEN CURRENT_TIMESTAMP - chunk_max_age AND CURRENT_TIMESTAMP - chunk_min_age
AND (
		(chunk_index_last_reindex IS NULL OR chunk_index_last_reindex < CURRENT_TIMESTAMP - reindex_min_age)
		OR (chunk_index_last_cluster IS NULL OR chunk_index_last_cluster < CURRENT_TIMESTAMP - reindex_min_age)
	)
ORDER BY chunk_id
$$;


ALTER FUNCTION _timescaledb_solarnetwork.find_chunk_index_need_maint(chunk_max_age interval, chunk_min_age interval, reindex_min_age interval) OWNER TO solarnet;

--
-- Name: find_chunk_index_need_reindex_maint(interval, interval, interval); Type: FUNCTION; Schema: _timescaledb_solarnetwork; Owner: solarnet
--

CREATE FUNCTION _timescaledb_solarnetwork.find_chunk_index_need_reindex_maint(chunk_max_age interval DEFAULT '168 days'::interval, chunk_min_age interval DEFAULT '7 days'::interval, reindex_min_age interval DEFAULT '77 days'::interval) RETURNS TABLE(schema_name name, table_name name, index_name name)
    LANGUAGE sql STABLE
    AS $$
SELECT
	chunk_schema_name,
	chunk_table_name,
	chunk_index_name
FROM _timescaledb_solarnetwork.chunk_time_index_maint
WHERE chunk_upper_range BETWEEN CURRENT_TIMESTAMP - chunk_max_age AND CURRENT_TIMESTAMP - chunk_min_age
AND (chunk_index_last_reindex IS NULL OR chunk_index_last_reindex < CURRENT_TIMESTAMP - reindex_min_age)
ORDER BY chunk_id
$$;


ALTER FUNCTION _timescaledb_solarnetwork.find_chunk_index_need_reindex_maint(chunk_max_age interval, chunk_min_age interval, reindex_min_age interval) OWNER TO solarnet;

--
-- Name: perform_chunk_reindex_maintenance(interval, interval, interval, boolean); Type: FUNCTION; Schema: _timescaledb_solarnetwork; Owner: solarnet
--

CREATE FUNCTION _timescaledb_solarnetwork.perform_chunk_reindex_maintenance(chunk_max_age interval DEFAULT '168 days'::interval, chunk_min_age interval DEFAULT '7 days'::interval, reindex_min_age interval DEFAULT '77 days'::interval, not_dry_run boolean DEFAULT false) RETURNS TABLE(schema_name name, table_name name, index_name name)
    LANGUAGE plpgsql
    AS $_$
DECLARE
    mtn RECORD;
BEGIN
	FOR mtn IN
		SELECT * FROM _timescaledb_solarnetwork.find_chunk_index_need_maint(chunk_max_age, chunk_min_age, reindex_min_age)
	LOOP
		EXECUTE 'SELECT _timescaledb_solarnetwork.perform_one_chunk_reindex_maintenance($1,$2,$3)'
		USING mtn.schema_name, mtn.table_name, mtn.index_name;

		schema_name := mtn.schema_name;
		table_name := mtn.table_name;
		index_name := mtn.index_name;
		RETURN NEXT;
	END LOOP;
	RETURN;
END
$_$;


ALTER FUNCTION _timescaledb_solarnetwork.perform_chunk_reindex_maintenance(chunk_max_age interval, chunk_min_age interval, reindex_min_age interval, not_dry_run boolean) OWNER TO solarnet;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: chunk_index_maint; Type: TABLE; Schema: _timescaledb_solarnetwork; Owner: solarnet
--

CREATE TABLE _timescaledb_solarnetwork.chunk_index_maint (
    chunk_id integer NOT NULL,
    index_name name NOT NULL,
    last_reindex timestamp with time zone,
    last_cluster timestamp with time zone
);


ALTER TABLE _timescaledb_solarnetwork.chunk_index_maint OWNER TO solarnet;

--
-- Name: perform_one_chunk_cluster_maintenance(text, text, text, boolean); Type: FUNCTION; Schema: _timescaledb_solarnetwork; Owner: solarnet
--

CREATE FUNCTION _timescaledb_solarnetwork.perform_one_chunk_cluster_maintenance(chunk_schema text, chunk_table text, chunk_index text, not_dry_run boolean DEFAULT false) RETURNS SETOF _timescaledb_solarnetwork.chunk_index_maint
    LANGUAGE plpgsql
    AS $_$
DECLARE
    rec _timescaledb_solarnetwork.chunk_index_maint%rowtype;
    mtn _timescaledb_solarnetwork.chunk_time_index_maint%rowtype;
BEGIN
	FOR mtn IN
		SELECT * FROM _timescaledb_solarnetwork.chunk_time_index_maint
		WHERE
			chunk_schema_name = chunk_schema::name
			AND chunk_table_name = chunk_table::name
			AND chunk_index_name = chunk_index::name
	LOOP
		IF not_dry_run THEN
			RAISE NOTICE 'Clustering chunk table %', mtn.chunk_table_name;

			EXECUTE 'CLUSTER ' || quote_ident(mtn.chunk_schema_name) || '.' || quote_ident(mtn.chunk_table_name)
				|| ' USING ' || quote_ident(mtn.chunk_index_name);

			RAISE NOTICE 'Analyzing chunk table %', mtn.chunk_table_name;

			EXECUTE 'ANALYZE ' || quote_ident(mtn.chunk_schema_name) || '.' || quote_ident(mtn.chunk_table_name);

			EXECUTE 'INSERT INTO _timescaledb_solarnetwork.chunk_index_maint (chunk_id, index_name, last_cluster)'
				|| ' VALUES ($1, $2, $3) ON CONFLICT (chunk_id, index_name)'
				|| ' DO UPDATE SET last_cluster = EXCLUDED.last_cluster'
			USING mtn.chunk_id, mtn.chunk_index_name, CURRENT_TIMESTAMP;

			rec.last_cluster := CURRENT_TIMESTAMP;
		ELSE
			rec.last_cluster := mtn.chunk_index_last_cluster;
		END IF;

		rec.chunk_id := mtn.chunk_id;
		rec.index_name := mtn.chunk_index_name;
		RETURN NEXT rec;
	END LOOP;
	RETURN;
END
$_$;


ALTER FUNCTION _timescaledb_solarnetwork.perform_one_chunk_cluster_maintenance(chunk_schema text, chunk_table text, chunk_index text, not_dry_run boolean) OWNER TO solarnet;

--
-- Name: perform_one_chunk_reindex_maintenance(text, text, text, boolean); Type: FUNCTION; Schema: _timescaledb_solarnetwork; Owner: solarnet
--

CREATE FUNCTION _timescaledb_solarnetwork.perform_one_chunk_reindex_maintenance(chunk_schema text, chunk_table text, chunk_index text, not_dry_run boolean DEFAULT false) RETURNS SETOF _timescaledb_solarnetwork.chunk_index_maint
    LANGUAGE plpgsql
    AS $_$
DECLARE
    rec _timescaledb_solarnetwork.chunk_index_maint%rowtype;
    mtn _timescaledb_solarnetwork.chunk_time_index_maint%rowtype;
BEGIN
	FOR mtn IN
		SELECT * FROM _timescaledb_solarnetwork.chunk_time_index_maint
		WHERE
			chunk_schema_name = chunk_schema::name
			AND chunk_table_name = chunk_table::name
			AND chunk_index_name = chunk_index::name
	LOOP
		IF not_dry_run THEN
			RAISE NOTICE 'Reindexing chunk index % on table %', mtn.chunk_index_name, mtn.chunk_table_name;

			EXECUTE 'REINDEX INDEX ' || quote_ident(mtn.chunk_schema_name) || '.' || quote_ident(mtn.chunk_index_name);

			EXECUTE 'INSERT INTO _timescaledb_solarnetwork.chunk_index_maint (chunk_id, index_name, last_reindex)'
				|| ' VALUES ($1, $2, $3) ON CONFLICT (chunk_id, index_name)'
				|| ' DO UPDATE SET last_reindex = EXCLUDED.last_reindex'
			USING mtn.chunk_id, mtn.chunk_index_name, CURRENT_TIMESTAMP;

			rec.last_reindex := CURRENT_TIMESTAMP;
		ELSE
			rec.last_reindex := mtn.chunk_index_last_reindex;
		END IF;

		rec.chunk_id := mtn.chunk_id;
		rec.index_name := mtn.chunk_index_name;
		RETURN NEXT rec;
	END LOOP;
	RETURN;
END
$_$;


ALTER FUNCTION _timescaledb_solarnetwork.perform_one_chunk_reindex_maintenance(chunk_schema text, chunk_table text, chunk_index text, not_dry_run boolean) OWNER TO solarnet;

--
-- Name: move_solarindex_tablespace(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.move_solarindex_tablespace() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	index_name text;
	schema_name text;
BEGIN
	FOR index_name, schema_name IN 
	SELECT indexname, schemaname FROM pg_indexes
	WHERE schemaname IN ('solarnet', 'solarrep', 'solaruser')
	ORDER BY 1
	LOOP
		EXECUTE 'ALTER INDEX ' || quote_ident(schema_name) || '.' || quote_ident(index_name) || ' SET TABLESPACE solarindex';
	END LOOP;
	RETURN 1;
END;
$$;


ALTER FUNCTION public.move_solarindex_tablespace() OWNER TO postgres;

--
-- Name: plv8_startup(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.plv8_startup() RETURNS void
    LANGUAGE plv8
    AS $_$
'use strict';

var moduleCache = {};

function load(key, source) {
	var module = {exports: {}};
	eval("(function(module, exports) {" + source + "; })")(module, module.exports);

	// store in cache
	moduleCache[key] = module.exports;
	return module.exports;
}

/**
 * Load a module.
 *
 * Inspired by https://rymc.io/2016/03/22/a-deep-dive-into-plv8/.
 *
 * @param {String} modulePath The path of the module to load. Relative path portions will be stripped
 *                            to form the final module name used to lookup a matching row in the
 *                            <code>plv8_modules</code> table.
 *
 * @returns {Object} The loaded module, or <code>null</code> if not found.
 */
this.require = function(modulePath) {
	var module = modulePath.replace(/\.{1,2}\//g, '');
	var code = moduleCache[module];
	if ( code ) {
		return code;
	}

	plv8.elog(NOTICE, 'Loading plv8 module: ' + module);
	var rows = plv8.execute("SELECT source FROM public.plv8_modules WHERE module = $1 LIMIT 1", [module]);

	if ( rows.length < 1 ) {
		plv8.elog(WARNING, 'Could not load module: ' + module);
		return null;
	}

	return load(module, rows[0].source);
};

/**
 * Release all cached modules.
 */
this.resetRequireCache = function() {
	var prop;
	for ( prop in moduleCache ) {
		delete moduleCache[prop];
	}
};

(function() {
	// Grab modules worth auto-loading at context start and let them cache
    var query = 'SELECT module, source from public.plv8_modules WHERE autoload = true';
    plv8.execute(query).forEach(function(row) {
		plv8.elog(NOTICE, 'Autoloading plv8 module: ' + row.module);
        load(row.module, row.source);
	});
}());

/**
 * TODO: remaining for backwards compatibility ONLY and should be REMOVED in the future.
 */

this.sn = {
	math : {
		util : {
			addto : require('util/addTo').default,
			calculateAverageOverHours : require('math/calculateAverageOverHours').default,
			calculateAverages : require('math/calculateAverages').default,
			fixPrecision : require('math/fixPrecision').default
		}
	},
	util : {
		merge : require('util/mergeObjects').default,
		intervalMs : require('util/intervalMs').default
	}
};

$_$;


ALTER FUNCTION public.plv8_startup() OWNER TO postgres;

--
-- Name: plv8_test(text[], text[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.plv8_test(keys text[], vals text[]) RETURNS text
    LANGUAGE plv8 IMMUTABLE STRICT
    AS $$
var o = {};
for(var i=0; i<keys.length; i++){
o[keys[i]] = vals[i];
}
return JSON.stringify(o);
$$;


ALTER FUNCTION public.plv8_test(keys text[], vals text[]) OWNER TO postgres;

--
-- Name: aud_inc_datum_query_count(timestamp with time zone, bigint, text, integer); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.aud_inc_datum_query_count(qdate timestamp with time zone, node bigint, source text, dcount integer) RETURNS void
    LANGUAGE sql
    AS $$
	INSERT INTO solaragg.aud_datum_hourly(ts_start, node_id, source_id, datum_q_count)
	VALUES (date_trunc('hour', qdate), node, source, dcount)
	ON CONFLICT (node_id, ts_start, source_id) DO UPDATE
	SET datum_q_count = aud_datum_hourly.datum_q_count + EXCLUDED.datum_q_count;
$$;


ALTER FUNCTION solaragg.aud_inc_datum_query_count(qdate timestamp with time zone, node bigint, source text, dcount integer) OWNER TO solarnet;

--
-- Name: calc_agg_datum_agg(bigint, text[], timestamp with time zone, timestamp with time zone, character); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.calc_agg_datum_agg(node bigint, sources text[], start_ts timestamp with time zone, end_ts timestamp with time zone, kind character) RETURNS TABLE(node_id bigint, ts_start timestamp with time zone, source_id text, jdata jsonb, jmeta jsonb)
    LANGUAGE plv8 STABLE
    AS $_$
'use strict';

var aggregator = require('datum/aggregator').default;

var stmt,
	cur,
	rec,
	helper,
	aggResult,
	i;

helper = aggregator({
	startTs : start_ts.getTime(),
	endTs : end_ts.getTime(),
});

stmt = plv8.prepare(
	'SELECT d.ts_start, d.source_id, solaragg.jdata_from_datum(d.*) AS jdata, d.jmeta FROM solaragg.agg_datum_'
	+(kind === 'h' ? 'hourly' : kind === 'd' ? 'daily' : 'monthly')
	+' d WHERE node_id = $1 AND source_id = ANY($2) AND ts_start >= $3 AND ts_start < $4',
	['bigint', 'text[]', 'timestamp with time zone', 'timestamp with time zone']);

cur = stmt.cursor([node, sources, start_ts, end_ts]);

while ( rec = cur.fetch() ) {
	if ( !rec.jdata ) {
		continue;
	}
	helper.addDatumRecord(rec);
}
aggResult = helper.finish();
if ( Array.isArray(aggResult) ) {
	for ( i = 0; i < aggResult.length; i += 1 ) {
		aggResult[i].node_id = node;
		plv8.return_next(aggResult[i]);
	}
}

cur.close();
stmt.free();
$_$;


ALTER FUNCTION solaragg.calc_agg_datum_agg(node bigint, sources text[], start_ts timestamp with time zone, end_ts timestamp with time zone, kind character) OWNER TO solarnet;

--
-- Name: calc_agg_loc_datum_agg(bigint, text[], timestamp with time zone, timestamp with time zone, character); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.calc_agg_loc_datum_agg(loc bigint, sources text[], start_ts timestamp with time zone, end_ts timestamp with time zone, kind character) RETURNS TABLE(loc_id bigint, ts_start timestamp with time zone, source_id text, jdata jsonb, jmeta jsonb)
    LANGUAGE plv8 STABLE
    AS $_$
'use strict';

var aggregator = require('datum/aggregator').default;

var stmt,
	cur,
	rec,
	helper,
	aggResult,
	i;

helper = aggregator({
	startTs : start_ts.getTime(),
	endTs : end_ts.getTime(),
});

stmt = plv8.prepare(
	'SELECT d.ts_start, d.source_id, solaragg.jdata_from_datum(d.*) AS jdata, d.jmeta FROM solaragg.agg_loc_datum_'
	+(kind === 'h' ? 'hourly' : kind === 'd' ? 'daily' : 'monthly')
	+' d WHERE loc_id = $1 AND source_id = ANY($2) AND ts_start >= $3 AND ts_start < $4',
	['bigint', 'text[]', 'timestamp with time zone', 'timestamp with time zone']);

cur = stmt.cursor([loc, sources, start_ts, end_ts]);

while ( rec = cur.fetch() ) {
	if ( !rec.jdata ) {
		continue;
	}
	helper.addDatumRecord(rec);
}
aggResult = helper.finish();
if ( Array.isArray(aggResult) ) {
	for ( i = 0; i < aggResult.length; i += 1 ) {
		aggResult[i].loc_id = loc;
		plv8.return_next(aggResult[i]);
	}
}

cur.close();
stmt.free();
$_$;


ALTER FUNCTION solaragg.calc_agg_loc_datum_agg(loc bigint, sources text[], start_ts timestamp with time zone, end_ts timestamp with time zone, kind character) OWNER TO solarnet;

--
-- Name: calc_datum_time_slots(bigint, text[], timestamp with time zone, interval, integer, interval); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.calc_datum_time_slots(node bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer DEFAULT 600, tolerance interval DEFAULT '01:00:00'::interval) RETURNS TABLE(node_id bigint, ts_start timestamp with time zone, source_id text, jdata jsonb, jmeta jsonb)
    LANGUAGE plv8 STABLE
    AS $_$
'use strict';

var intervalMs = require('util/intervalMs').default;
var aggregator = require('datum/aggregator').default;
var slotAggregator = require('datum/slotAggregator').default;

var spanMs = intervalMs(span),
	endTs = start_ts.getTime() + spanMs,
	slotMode = (slotsecs >= 60 && slotsecs <= 1800),
	ignoreLogMessages = (slotMode === true || spanMs !== 3600000),
	stmt,
	cur,
	rec,
	helper,
	aggResult,
	i;

if ( slotMode ) {
	stmt = plv8.prepare(
		'SELECT ts, solaragg.minute_time_slot(ts, '+slotsecs+') as ts_start, source_id, jdata FROM solaragg.find_datum_for_time_span($1, $2, $3, $4, $5)',
		['bigint', 'text[]', 'timestamp with time zone', 'interval', 'interval']);
	helper = slotAggregator({
		startTs : start_ts.getTime(),
		endTs : endTs,
		slotSecs : slotsecs
	});
} else {
	stmt = plv8.prepare(
		'SELECT ts, source_id, jdata FROM solaragg.find_datum_for_time_span($1, $2, $3, $4, $5)',
		['bigint', 'text[]', 'timestamp with time zone', 'interval', 'interval']);
	helper = aggregator({
		startTs : start_ts.getTime(),
		endTs : endTs,
	});
}

cur = stmt.cursor([node, sources, start_ts, span, tolerance]);

while ( rec = cur.fetch() ) {
	if ( !rec.jdata ) {
		continue;
	}
	aggResult = helper.addDatumRecord(rec);
	if ( aggResult ) {
		aggResult.node_id = node;
		plv8.return_next(aggResult);
	}
}
aggResult = helper.finish();
if ( Array.isArray(aggResult) ) {
	for ( i = 0; i < aggResult.length; i += 1 ) {
		aggResult[i].node_id = node;
		plv8.return_next(aggResult[i]);
	}
}

cur.close();
stmt.free();
$_$;


ALTER FUNCTION solaragg.calc_datum_time_slots(node bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer, tolerance interval) OWNER TO solarnet;

--
-- Name: calc_datum_time_slots_test(bigint, text[], timestamp with time zone, interval, integer, interval); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.calc_datum_time_slots_test(node bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer DEFAULT 600, tolerance interval DEFAULT '01:00:00'::interval) RETURNS TABLE(ts_start timestamp with time zone, source_id text, jdata json)
    LANGUAGE plv8 STABLE
    AS $_$
'use strict';
var runningAvgDiff,
	runningAvgMax = 5,
	toleranceMs = sn.util.intervalMs(tolerance),
	hourFill = {'watts' : 'wattHours'},
	slotMode = (slotsecs > 0 && slotsecs < 3600),
	ignoreLogMessages = (slotMode === true || sn.util.intervalMs(span) !== 3600000),
	logInsertStmt;

function logMessage(nodeId, sourceId, ts, msg) {
	plv8.elog(INFO, Array.prototype.slice.call(arguments, 0).join(' '));
	return;
	if ( ignoreLogMessages ) {
		return;
	}
	var msg;
	if ( !logInsertStmt ) {
		logInsertStmt = plv8.prepare('INSERT INTO solaragg.agg_messages (node_id, source_id, ts, msg) VALUES ($1, $2, $3, $4)', 
			['bigint', 'text', 'timestamp with time zone', 'text']);
	}
	var dbMsg = Array.prototype.slice.call(arguments, 3).join(' ');
	logInsertStmt.execute([nodeId, sourceId, ts, dbMsg]);
}

function calculateAccumulatingValue(rec, r, val, prevVal, prop, ms) {
	var avgObj = r.accAvg[prop],
		offsetT = 0,
		diff,
		diffT,
		minutes;
	if ( 
			// disallow negative values for records tagged 'power', e.g. inverters that reset each night their reported accumulated energy
			(val < prevVal * 0.5 && rec.jdata.t && Array.isArray(rec.jdata.t) && rec.jdata.t.indexOf('power') >= 0)
			||
			// the running average is 0, the previous value > 0, and the current val <= 1.5% of previous value (i.e. close to 0);
			// don't treat this as a negative accumulation in this case if diff non trivial;
			(prevVal > 0 && (!avgObj || avgObj.average < 1) && val < (prevVal * 0.015))
			) {
		logMessage(node, r.source_id, new Date(rec.tsms), 'Forcing node prevVal', prevVal, 'to 0, val =', val);
		prevVal = 0;
	}
	diff = (val - prevVal);
	minutes = ms / 60000;
	diffT = (diff / minutes);
	if ( avgObj ) {
		if ( avgObj.average > 0 ) {
			offsetT = (diffT / avgObj.average) 
				* (avgObj.next < runningAvgMax ? Math.pow(avgObj.next / runningAvgMax, 2) : 1)
				* (minutes > 2 ? 4 : Math.pow(minutes, 2));
		} else {
			offsetT = (diffT * (minutes > 5 ? 25 : Math.pow(minutes, 2)));
		}
	}
	if ( offsetT > 1000 ) {
		logMessage(node, r.source_id, new Date(rec.tsms), 'Rejecting diff', diff, 'offset(t)', offsetT.toFixed(1), 
			'diff(t)', sn.math.util.fixPrecision(diffT, 100), '; ravg', (avgObj ? sn.math.util.fixPrecision(avgObj.average, 100) : 'N/A'), 
			(avgObj ? JSON.stringify(avgObj.samples.map(function(e) { return sn.math.util.fixPrecision(e, 100); })) : 'N/A'));
		return 0;
	}
		logMessage(node, r.source_id, new Date(rec.tsms), 'Diff', diff, 'offset(t)', offsetT.toFixed(1), 
			'diff(t)', sn.math.util.fixPrecision(diffT, 100), '; ravg', (avgObj ? sn.math.util.fixPrecision(avgObj.average, 100) : 'N/A'), 
			(avgObj ? JSON.stringify(avgObj.samples.map(function(e) { return sn.math.util.fixPrecision(e, 100); })) : 'N/A'));
	maintainAccumulatingRunningAverageDifference(r.accAvg, prop, diffT)
	return diff;
}

function maintainAccumulatingRunningAverageDifference(accAvg, prop, diff) {
	var i,
		avg = 0,
		avgObj = accAvg[prop],
		val,
		samples;
	if ( avgObj === undefined ) {
		avgObj = { samples : new Array(runningAvgMax), average : diff, next : 1 }; // wanted Float32Array, but not available in plv8
		avgObj.samples[0] = diff;
		for ( i = 1; i < runningAvgMax; i += 1 ) {
			avgObj.samples[i] = 0x7FC00000;
		}
		accAvg[prop] = avgObj;
		avg = diff;
	} else {
		samples = avgObj.samples;
		samples[avgObj.next % runningAvgMax] = diff;
		avgObj.next += 1;
		for ( i = 0; i < runningAvgMax; i += 1 ) {
			val = samples[i];
			if ( val === 0x7FC00000 ) {
				break;
			}
			avg += val;
		}
		avg /= i;
		avgObj.average = avg;
	}
}

function finishResultObject(r, endts) {
	var prop,
		robj,
		ri,
		ra;
	if ( r.tsms < start_ts.getTime() || (slotMode && r.tsms >= endts) ) {
		// not included in output because before time start, or end time >= end time
		return;
	}
	robj = {
		ts_start : new Date(r.tsms),
		source_id : r.source_id,
		jdata : {}
	};
	ri = sn.math.util.calculateAverages(r.iobj, r.iobjCounts);
	ra = r.aobj;
	
	for ( prop in ri ) {
		robj.jdata.i = ri;
		break;
	}
	for ( prop in ra ) {
		robj.jdata.a = sn.util.merge({}, ra); // call merge() to pick up sn.math.util.fixPrecision
		break;
	}

	if ( r.prevRec && r.prevRec.percent > 0 ) {
		// merge last record s obj into results, but not overwriting any existing properties
		if ( r.prevRec.jdata.s ) {
			for ( prop in r.prevRec.jdata.s ) {
				robj.jdata.s = r.prevRec.jdata.s;
				break;
			}
		}
		if ( Array.isArray(r.prevRec.jdata.t) && r.prevRec.jdata.t.length > 0 ) {
			robj.jdata.t = r.prevRec.jdata.t;
		}
	}
	plv8.return_next(robj);
}

function handleAccumulatingResult(rec, result) {
	var acc = rec.jdata.a,
		prevAcc = result.prevAcc,
		aobj = result.aobj,
		prop;
	if ( acc && prevAcc && rec.tdiffms <= toleranceMs ) {
		// accumulating data
		for ( prop in acc ) {
			if ( prevAcc[prop] !== undefined ) {				
				sn.math.util.addto(prop, calculateAccumulatingValue(rec, result, acc[prop], prevAcc[prop], prop, rec.tdiffms), aobj, rec.percent);
			}
		}
	}
}

function handleInstantaneousResult(rec, result, onlyHourFill) {
	var inst = rec.jdata.i,
		prevInst = result.prevInst,
		iobj = result.iobj,
		iobjCounts = result.iobjCounts,
		prop,
		propHour;
	if ( inst && rec.percent > 0 && rec.tdiffms <= toleranceMs ) {
		// instant data
		for ( prop in inst ) {
			if ( onlyHourFill !== true ) {
				// only add instantaneous average values for 100% records; we may have to use percent to hour-fill below
				sn.math.util.addto(prop, inst[prop], iobj, 1, iobjCounts);
			}
			if ( result.prevRec && hourFill[prop] ) {
				// calculate hour value, if not already defined for given property
				propHour = hourFill[prop];
				if ( !(rec.jdata.a && rec.jdata.a[propHour]) && prevInst && prevInst[prop] !== undefined ) {
					sn.math.util.addto(propHour, sn.math.util.calculateAverageOverHours(inst[prop], prevInst[prop], rec.tdiffms), result.aobj, rec.percent);
				}
			}
		}
	}
}

function handleFractionalAccumulatingResult(rec, result) {
	var fracRec = {
		source_id 	: rec.source_id,
		tsms		: result.prevRec.tsms,
		percent		: (1 - rec.percent),
		tdiffms		: rec.tdiffms,
		jdata		: rec.jdata
	};
	handleAccumulatingResult(fracRec, result);
	handleInstantaneousResult(fracRec, result, true);
}

(function() {
	var results = {}, // { ts_start : 123, source_id : 'A', aobj : {}, iobj : {}, iobjCounts : {}, sobj : {} ...}
		sourceId,
		result,
		rec,
		prop,
		stmt,
		cur,
		spanMs = sn.util.intervalMs(span),
		endts = start_ts.getTime() + spanMs;
	
	if ( slotMode ) {
		stmt = plv8.prepare('SELECT source_id, tsms, percent, tdiffms, jdata FROM solaragg.find_datum_for_minute_time_slots($1, $2, $3, $4, $5, $6)', 
				['bigint', 'text[]', 'timestamp with time zone', 'interval', 'integer', 'interval']);
		cur = stmt.cursor([node, sources, start_ts, span, slotsecs, tolerance]);
	} else {
		stmt = plv8.prepare('SELECT source_id, tsms, percent, tdiffms, jdata FROM solaragg.find_datum_for_time_slot($1, $2, $3, $4, $5)', 
				['bigint', 'text[]', 'timestamp with time zone', 'interval', 'interval']);
		cur = stmt.cursor([node, sources, start_ts, span, tolerance]);
	}

	while ( rec = cur.fetch() ) {
		if ( !rec.jdata ) {
			continue;
		}
		sourceId = rec.source_id;
		result = results[sourceId];
		if ( result === undefined ) {
			result = { 
				tsms : (slotMode ? rec.tsms : start_ts.getTime()), 
				source_id : sourceId, 
				aobj : {}, 
				iobj : {}, 
				iobjCounts : {}, 
				sobj: {}, 
				accAvg : {}
			};
			results[sourceId] = result;
		} else if ( slotMode && rec.tsms !== result.tsms ) {
			if ( rec.percent < 1 && result.prevRec && result.prevRec.tsms >= start_ts.getTime() ) {
				// add 1-rec.percent to the previous time slot results
				handleFractionalAccumulatingResult(rec, result);
			}
			finishResultObject(result, endts);
			result.tsms = rec.tsms;
			result.aobj = {};
			result.iobj = {};
			result.iobjCounts = {};
			result.sobj = {};
		}
	
		handleAccumulatingResult(rec, result);
		handleInstantaneousResult(rec, result);
	
		result.prevRec = rec;
		result.prevAcc = rec.jdata.a;
		result.prevInst = rec.jdata.i;
	}
	cur.close();
	stmt.free();

	for ( prop in results ) {
		finishResultObject(results[prop], endts);
	}
	
	if ( logInsertStmt ) {
		logInsertStmt.free();
	}
}());
$_$;


ALTER FUNCTION solaragg.calc_datum_time_slots_test(node bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer, tolerance interval) OWNER TO solarnet;

--
-- Name: calc_loc_datum_time_slots(bigint, text[], timestamp with time zone, interval, integer, interval); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.calc_loc_datum_time_slots(loc bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer DEFAULT 600, tolerance interval DEFAULT '01:00:00'::interval) RETURNS TABLE(ts_start timestamp with time zone, source_id text, jdata jsonb, jmeta jsonb)
    LANGUAGE plv8 STABLE
    AS $_$
'use strict';

var intervalMs = require('util/intervalMs').default;
var aggregator = require('datum/aggregator').default;
var slotAggregator = require('datum/slotAggregator').default;

var spanMs = intervalMs(span),
	endTs = start_ts.getTime() + spanMs,
	slotMode = (slotsecs >= 60 && slotsecs <= 1800),
	ignoreLogMessages = (slotMode === true || spanMs !== 3600000),
	stmt,
	cur,
	rec,
	helper,
	aggResult,
	i;

if ( slotMode ) {
	stmt = plv8.prepare(
		'SELECT ts, solaragg.minute_time_slot(ts, '+slotsecs+') as ts_start, source_id, jdata FROM solaragg.find_loc_datum_for_time_span($1, $2, $3, $4, $5)',
		['bigint', 'text[]', 'timestamp with time zone', 'interval', 'interval']);
	helper = slotAggregator({
		startTs : start_ts.getTime(),
		endTs : endTs,
		slotSecs : slotsecs
	});
} else {
	stmt = plv8.prepare(
		'SELECT ts, source_id, jdata FROM solaragg.find_loc_datum_for_time_span($1, $2, $3, $4, $5)',
		['bigint', 'text[]', 'timestamp with time zone', 'interval', 'interval']);
	helper = aggregator({
		startTs : start_ts.getTime(),
		endTs : endTs,
	});
}

cur = stmt.cursor([loc, sources, start_ts, span, tolerance]);

while ( rec = cur.fetch() ) {
	if ( !rec.jdata ) {
		continue;
	}
	aggResult = helper.addDatumRecord(rec);
	if ( aggResult ) {
		plv8.return_next(aggResult);
	}
}
aggResult = helper.finish();
if ( Array.isArray(aggResult) ) {
	for ( i = 0; i < aggResult.length; i += 1 ) {
		plv8.return_next(aggResult[i]);
	}
}

cur.close();
stmt.free();
$_$;


ALTER FUNCTION solaragg.calc_loc_datum_time_slots(loc bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer, tolerance interval) OWNER TO solarnet;

--
-- Name: calc_running_datum_total(bigint[], text[], timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.calc_running_datum_total(nodes bigint[], sources text[], end_ts timestamp with time zone DEFAULT now()) RETURNS TABLE(ts_start timestamp with time zone, local_date timestamp without time zone, node_id bigint, source_id text, jdata jsonb)
    LANGUAGE sql STABLE ROWS 10
    AS $$
	WITH nodetz AS (
		SELECT nids.node_id, COALESCE(l.time_zone, 'UTC') AS tz
		FROM (SELECT unnest(nodes) AS node_id) AS nids
		LEFT OUTER JOIN solarnet.sn_node n ON n.node_id = nids.node_id
		LEFT OUTER JOIN solarnet.sn_loc l ON l.id = n.loc_id
	)
	SELECT end_ts, end_ts AT TIME ZONE nodetz.tz AS local_date, r.node_id, r.source_id, r.jdata
	FROM nodetz
	CROSS JOIN LATERAL (
		SELECT nodetz.node_id, t.*
		FROM solaragg.calc_running_total(
			nodetz.node_id,
			sources,
			end_ts,
			FALSE) t
	) AS r
$$;


ALTER FUNCTION solaragg.calc_running_datum_total(nodes bigint[], sources text[], end_ts timestamp with time zone) OWNER TO solarnet;

--
-- Name: calc_running_datum_total(bigint, text[], timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.calc_running_datum_total(node bigint, sources text[], end_ts timestamp with time zone DEFAULT now()) RETURNS TABLE(ts_start timestamp with time zone, local_date timestamp without time zone, node_id bigint, source_id text, jdata jsonb)
    LANGUAGE sql STABLE ROWS 10
    AS $$
	WITH nodetz AS (
		SELECT nids.node_id, COALESCE(l.time_zone, 'UTC') AS tz
		FROM (SELECT node AS node_id) nids
		LEFT OUTER JOIN solarnet.sn_node n ON n.node_id = nids.node_id
		LEFT OUTER JOIN solarnet.sn_loc l ON l.id = n.loc_id
	)
	SELECT end_ts, end_ts AT TIME ZONE nodetz.tz AS local_date, node, r.source_id, r.jdata
	FROM solaragg.calc_running_total(
		node,
		sources,
		end_ts,
		FALSE
	) AS r
	INNER JOIN nodetz ON nodetz.node_id = node;
$$;


ALTER FUNCTION solaragg.calc_running_datum_total(node bigint, sources text[], end_ts timestamp with time zone) OWNER TO solarnet;

--
-- Name: calc_running_loc_datum_total(bigint[], text[], timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.calc_running_loc_datum_total(locs bigint[], sources text[], end_ts timestamp with time zone DEFAULT now()) RETURNS TABLE(ts_start timestamp with time zone, local_date timestamp without time zone, loc_id bigint, source_id text, jdata jsonb)
    LANGUAGE sql STABLE ROWS 10
    AS $$
	WITH loctz AS (
		SELECT lids.loc_id, COALESCE(l.time_zone, 'UTC') AS tz
		FROM (SELECT unnest(locs) AS loc_id) AS lids
		LEFT OUTER JOIN solarnet.sn_loc l ON l.id = lids.loc_id
	)
	SELECT end_ts, end_ts AT TIME ZONE loctz.tz AS local_date, r.loc_id, r.source_id, r.jdata
	FROM loctz
	CROSS JOIN LATERAL (
		SELECT loctz.loc_id, t.*
		FROM solaragg.calc_running_total(
			loctz.loc_id,
			sources,
			end_ts,
			TRUE) t
	) AS r
$$;


ALTER FUNCTION solaragg.calc_running_loc_datum_total(locs bigint[], sources text[], end_ts timestamp with time zone) OWNER TO solarnet;

--
-- Name: calc_running_loc_datum_total(bigint, text[], timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.calc_running_loc_datum_total(loc bigint, sources text[], end_ts timestamp with time zone DEFAULT now()) RETURNS TABLE(ts_start timestamp with time zone, local_date timestamp without time zone, loc_id bigint, source_id text, jdata jsonb)
    LANGUAGE sql STABLE ROWS 10
    AS $$
	WITH loctz AS (
		SELECT lids.loc_id, COALESCE(l.time_zone, 'UTC') AS tz
		FROM (SELECT loc AS loc_id) lids
		LEFT OUTER JOIN solarnet.sn_loc l ON l.id = lids.loc_id
	)
	SELECT end_ts, end_ts AT TIME ZONE loctz.tz AS local_date, loc, r.source_id, r.jdata
	FROM solaragg.calc_running_total(
		loc,
		sources,
		end_ts,
		TRUE
	) AS r
	INNER JOIN loctz ON loctz.loc_id = loc;
$$;


ALTER FUNCTION solaragg.calc_running_loc_datum_total(loc bigint, sources text[], end_ts timestamp with time zone) OWNER TO solarnet;

--
-- Name: calc_running_total(bigint, text[], timestamp with time zone, boolean); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.calc_running_total(pk bigint, sources text[], end_ts timestamp with time zone DEFAULT now(), loc_mode boolean DEFAULT false) RETURNS TABLE(source_id text, jdata jsonb)
    LANGUAGE plv8 STABLE ROWS 10
    AS $_$
'use strict';

var totalor = require('datum/totalor').default;

var query = (loc_mode === true
		? 'SELECT * FROM solaragg.find_running_loc_datum($1, $2, $3)'
		: 'SELECT * FROM solaragg.find_running_datum($1, $2, $3)'),
	stmt,
	cur,
	rec,
	helper = totalor(),
	aggResult,
	i;

stmt = plv8.prepare(query, ['bigint', 'text[]', 'timestamp with time zone']);
cur = stmt.cursor([pk, sources, end_ts]);

while ( rec = cur.fetch() ) {
	if ( !rec.jdata ) {
		continue;
	}
	helper.addDatumRecord(rec);
}

aggResult = helper.finish();
if ( Array.isArray(aggResult) ) {
	for ( i = 0; i < aggResult.length; i += 1 ) {
		plv8.return_next(aggResult[i]);
	}
}

cur.close();
stmt.free();

$_$;


ALTER FUNCTION solaragg.calc_running_total(pk bigint, sources text[], end_ts timestamp with time zone, loc_mode boolean) OWNER TO solarnet;

--
-- Name: find_agg_datum_dow(bigint, text[], text[], timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_agg_datum_dow(node bigint, source text[], path text[], start_ts timestamp with time zone DEFAULT '2001-01-01 13:00:00+13'::timestamp with time zone, end_ts timestamp with time zone DEFAULT now()) RETURNS TABLE(node_id bigint, ts_start timestamp with time zone, local_date timestamp without time zone, source_id text, jdata jsonb)
    LANGUAGE sql STABLE
    AS $$
SELECT
	node AS node_id,
	(DATE '2001-01-01' + CAST((EXTRACT(isodow FROM d.local_date) - 1) || ' day' AS INTERVAL)) AT TIME ZONE 'UTC' AS ts_start,
	(DATE '2001-01-01' + CAST((EXTRACT(isodow FROM d.local_date) - 1) || ' day' AS INTERVAL)) AS local_date,
	d.source_id,
	('{"' || path[1] || '":{"' || path[2] || '":'
		|| ROUND(AVG(CAST(jsonb_extract_path_text(solaragg.jdata_from_datum(d), VARIADIC path) AS double precision)) * 1000) / 1000
		|| '}}')::jsonb as jdata
FROM solaragg.agg_datum_daily d
WHERE
	d.node_id = node
	AND d.source_id = ANY(source)
	AND d.ts_start >= start_ts
	AND d.ts_start < end_ts
GROUP BY
	EXTRACT(isodow FROM d.local_date),
	d.source_id
$$;


ALTER FUNCTION solaragg.find_agg_datum_dow(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) OWNER TO solarnet;

--
-- Name: find_agg_datum_hod(bigint, text[], text[], timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_agg_datum_hod(node bigint, source text[], path text[], start_ts timestamp with time zone DEFAULT '2008-01-01 13:00:00+13'::timestamp with time zone, end_ts timestamp with time zone DEFAULT now()) RETURNS TABLE(node_id bigint, ts_start timestamp with time zone, local_date timestamp without time zone, source_id text, jdata jsonb)
    LANGUAGE sql STABLE
    AS $$
SELECT
	node AS node_id,
	(CAST('2001-01-01 ' || to_char(EXTRACT(hour FROM d.local_date), '00') || ':00' AS TIMESTAMP)) AT TIME ZONE 'UTC' AS ts_start,
	(CAST('2001-01-01 ' || to_char(EXTRACT(hour FROM d.local_date), '00') || ':00' AS TIMESTAMP)) AS local_date,
	d.source_id,
	('{"' || path[1] || '":{"' || path[2] || '":'
		|| ROUND(AVG(CAST(jsonb_extract_path_text(solaragg.jdata_from_datum(d), VARIADIC path) AS double precision)) * 1000) / 1000
		|| '}}')::jsonb as jdata
FROM solaragg.agg_datum_hourly d
WHERE
	d.node_id = node
	AND d.source_id = ANY(source)
	AND d.ts_start >= start_ts
	AND d.ts_start < end_ts
GROUP BY
	EXTRACT(hour FROM d.local_date),
	d.source_id
$$;


ALTER FUNCTION solaragg.find_agg_datum_hod(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) OWNER TO solarnet;

--
-- Name: find_agg_datum_minute(bigint[], text[], timestamp with time zone, timestamp with time zone, integer, interval); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_agg_datum_minute(node bigint[], source text[], start_ts timestamp with time zone, end_ts timestamp with time zone, slotsecs integer DEFAULT 600, tolerance interval DEFAULT '01:00:00'::interval) RETURNS TABLE(node_id bigint, ts_start timestamp with time zone, local_date timestamp without time zone, source_id text, jdata_i jsonb, jdata_a jsonb, jdata_s jsonb, jdata_t text[])
    LANGUAGE sql STABLE
    AS $$
SELECT
	d.node_id,
	d.ts_start,
	d.local_date,
	d.source_id,
	d.jdata->'i' AS jdata_i,
	d.jdata->'a' AS jdata_a,
	d.jdata->'s' AS jdata_s,
	solarcommon.json_array_to_text_array(d.jdata->'t') AS jdata_t
FROM solaragg.find_agg_datum_minute_data(
	node,
	source,
	start_ts,
	end_ts,
	slotsecs,
	tolerance
) d
$$;


ALTER FUNCTION solaragg.find_agg_datum_minute(node bigint[], source text[], start_ts timestamp with time zone, end_ts timestamp with time zone, slotsecs integer, tolerance interval) OWNER TO solarnet;

--
-- Name: find_agg_datum_minute(bigint, text[], timestamp with time zone, timestamp with time zone, integer, interval); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_agg_datum_minute(node bigint, source text[], start_ts timestamp with time zone, end_ts timestamp with time zone, slotsecs integer DEFAULT 600, tolerance interval DEFAULT '01:00:00'::interval) RETURNS TABLE(node_id bigint, ts_start timestamp with time zone, local_date timestamp without time zone, source_id text, jdata jsonb)
    LANGUAGE sql STABLE
    AS $$
SELECT
	node AS node_id,
	d.ts_start,
	d.ts_start AT TIME ZONE COALESCE(l.time_zone, 'UTC') AS local_date,
	d.source_id,
	d.jdata
 FROM solaragg.calc_datum_time_slots(
	node,
	source,
	solaragg.minute_time_slot(start_ts, solaragg.slot_seconds(slotsecs)),
	(end_ts - solaragg.minute_time_slot(start_ts, solaragg.slot_seconds(slotsecs))),
	solaragg.slot_seconds(slotsecs),
	tolerance
) AS d
JOIN solarnet.sn_node n ON n.node_id = node
LEFT OUTER JOIN solarnet.sn_loc l ON l.id = n.loc_id
$$;


ALTER FUNCTION solaragg.find_agg_datum_minute(node bigint, source text[], start_ts timestamp with time zone, end_ts timestamp with time zone, slotsecs integer, tolerance interval) OWNER TO solarnet;

--
-- Name: find_agg_datum_minute_data(bigint[], text[], timestamp with time zone, timestamp with time zone, integer, interval); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_agg_datum_minute_data(node bigint[], source text[], start_ts timestamp with time zone, end_ts timestamp with time zone, slotsecs integer DEFAULT 600, tolerance interval DEFAULT '01:00:00'::interval) RETURNS TABLE(node_id bigint, ts_start timestamp with time zone, local_date timestamp without time zone, source_id text, jdata jsonb)
    LANGUAGE sql STABLE
    AS $$
SELECT
	n.node_id,
	d.ts_start,
	d.ts_start AT TIME ZONE COALESCE(l.time_zone, 'UTC') AS local_date,
	d.source_id,
	d.jdata
FROM solarnet.sn_node n
INNER JOIN LATERAL solaragg.calc_datum_time_slots(
	n.node_id,
	source,
	solaragg.minute_time_slot(start_ts, solaragg.slot_seconds(slotsecs)),
	(end_ts - solaragg.minute_time_slot(start_ts, solaragg.slot_seconds(slotsecs))),
	solaragg.slot_seconds(slotsecs),
	tolerance
) d ON d.node_id = n.node_id
LEFT OUTER JOIN solarnet.sn_loc l ON l.id = n.loc_id
WHERE n.node_id = ANY(node)
$$;


ALTER FUNCTION solaragg.find_agg_datum_minute_data(node bigint[], source text[], start_ts timestamp with time zone, end_ts timestamp with time zone, slotsecs integer, tolerance interval) OWNER TO solarnet;

--
-- Name: find_agg_datum_seasonal_dow(bigint, text[], text[], timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_agg_datum_seasonal_dow(node bigint, source text[], path text[], start_ts timestamp with time zone DEFAULT '2001-01-01 13:00:00+13'::timestamp with time zone, end_ts timestamp with time zone DEFAULT now()) RETURNS TABLE(node_id bigint, ts_start timestamp with time zone, local_date timestamp without time zone, source_id text, jdata jsonb)
    LANGUAGE sql STABLE
    AS $$
SELECT
	node AS node_id,
	(solarnet.get_season_monday_start(d.local_date)
		+ CAST((EXTRACT(isodow FROM d.local_date) - 1) || ' day' AS INTERVAL)) AT TIME ZONE 'UTC' AS ts_start,
	(solarnet.get_season_monday_start(d.local_date)
		+ CAST((EXTRACT(isodow FROM d.local_date) - 1) || ' day' AS INTERVAL)) AS local_date,
	d.source_id,
	('{"' || path[1] || '":{"' || path[2] || '":'
		|| ROUND(AVG(CAST(jsonb_extract_path_text(solaragg.jdata_from_datum(d), VARIADIC path) AS double precision)) * 1000) / 1000
		|| '}}')::jsonb as jdata
FROM solaragg.agg_datum_daily d
WHERE
	d.node_id = node
	AND d.source_id = ANY(source)
	AND d.ts_start >= start_ts
	AND d.ts_start < end_ts
GROUP BY
	solarnet.get_season_monday_start(CAST(d.local_date AS date)),
	EXTRACT(isodow FROM d.local_date),
	d.source_id
$$;


ALTER FUNCTION solaragg.find_agg_datum_seasonal_dow(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) OWNER TO solarnet;

--
-- Name: find_agg_datum_seasonal_hod(bigint, text[], text[], timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_agg_datum_seasonal_hod(node bigint, source text[], path text[], start_ts timestamp with time zone DEFAULT '2008-01-01 13:00:00+13'::timestamp with time zone, end_ts timestamp with time zone DEFAULT now()) RETURNS TABLE(node_id bigint, ts_start timestamp with time zone, local_date timestamp without time zone, source_id text, jdata jsonb)
    LANGUAGE sql STABLE
    AS $$
SELECT
	node AS node_id,
	(solarnet.get_season_monday_start(CAST(d.local_date AS DATE))
		+ CAST(EXTRACT(hour FROM d.local_date) || ' hour' AS INTERVAL)) AT TIME ZONE 'UTC' AS ts_start,
	solarnet.get_season_monday_start(CAST(d.local_date AS DATE))
		+ CAST(EXTRACT(hour FROM d.local_date) || ' hour' AS INTERVAL) AS local_date,
	d.source_id,
	('{"' || path[1] || '":{"' || path[2] || '":'
		|| ROUND(AVG(CAST(jsonb_extract_path_text(solaragg.jdata_from_datum(d), VARIADIC path) AS double precision)) * 1000) / 1000
		|| '}}')::jsonb as jdata
FROM solaragg.agg_datum_hourly d
WHERE
	d.node_id = node
	AND d.source_id = ANY(source)
	AND d.ts_start >= start_ts
	AND d.ts_start < end_ts
GROUP BY
	solarnet.get_season_monday_start(CAST(d.local_date AS date)),
	EXTRACT(hour FROM d.local_date),
	d.source_id
$$;


ALTER FUNCTION solaragg.find_agg_datum_seasonal_hod(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) OWNER TO solarnet;

--
-- Name: find_agg_loc_datum_dow(bigint, text[], text[], timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_agg_loc_datum_dow(loc bigint, source text[], path text[], start_ts timestamp with time zone DEFAULT '2001-01-01 13:00:00+13'::timestamp with time zone, end_ts timestamp with time zone DEFAULT now()) RETURNS TABLE(loc_id bigint, ts_start timestamp with time zone, local_date timestamp without time zone, source_id text, jdata jsonb)
    LANGUAGE sql STABLE
    AS $$
SELECT
	loc AS loc_id,
	(DATE '2001-01-01' + CAST((EXTRACT(isodow FROM d.local_date) - 1) || ' day' AS INTERVAL)) AT TIME ZONE 'UTC' AS ts_start,
	(DATE '2001-01-01' + CAST((EXTRACT(isodow FROM d.local_date) - 1) || ' day' AS INTERVAL)) AS local_date,
	d.source_id,
	('{"' || path[1] || '":{"' || path[2] || '":'
		|| ROUND(AVG(CAST(jsonb_extract_path_text(solaragg.jdata_from_datum(d), VARIADIC path) AS double precision)) * 1000) / 1000
		|| '}}')::jsonb as jdata
FROM solaragg.agg_loc_datum_daily d
WHERE
	d.loc_id = loc
	AND d.source_id = ANY(source)
	AND d.ts_start >= start_ts
	AND d.ts_start < end_ts
GROUP BY
	EXTRACT(isodow FROM d.local_date),
	d.source_id
$$;


ALTER FUNCTION solaragg.find_agg_loc_datum_dow(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) OWNER TO solarnet;

--
-- Name: find_agg_loc_datum_hod(bigint, text[], text[], timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_agg_loc_datum_hod(loc bigint, source text[], path text[], start_ts timestamp with time zone DEFAULT '2008-01-01 13:00:00+13'::timestamp with time zone, end_ts timestamp with time zone DEFAULT now()) RETURNS TABLE(loc_id bigint, ts_start timestamp with time zone, local_date timestamp without time zone, source_id text, jdata jsonb)
    LANGUAGE sql STABLE
    AS $$
SELECT
	loc AS loc_id,
	(CAST('2001-01-01 ' || to_char(EXTRACT(hour FROM d.local_date), '00') || ':00' AS TIMESTAMP)) AT TIME ZONE 'UTC' AS ts_start,
	(CAST('2001-01-01 ' || to_char(EXTRACT(hour FROM d.local_date), '00') || ':00' AS TIMESTAMP)) AS local_date,
	d.source_id,
	('{"' || path[1] || '":{"' || path[2] || '":'
		|| ROUND(AVG(CAST(jsonb_extract_path_text(solaragg.jdata_from_datum(d), VARIADIC path) AS double precision)) * 1000) / 1000
		|| '}}')::jsonb as jdata
FROM solaragg.agg_loc_datum_hourly d
WHERE
	d.loc_id = loc
	AND d.source_id = ANY(source)
	AND d.ts_start >= start_ts
	AND d.ts_start < end_ts
GROUP BY
	EXTRACT(hour FROM d.local_date),
	d.source_id
$$;


ALTER FUNCTION solaragg.find_agg_loc_datum_hod(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) OWNER TO solarnet;

--
-- Name: find_agg_loc_datum_minute(bigint, text[], timestamp with time zone, timestamp with time zone, integer, interval); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_agg_loc_datum_minute(loc bigint, source text[], start_ts timestamp with time zone, end_ts timestamp with time zone, slotsecs integer DEFAULT 600, tolerance interval DEFAULT '01:00:00'::interval) RETURNS TABLE(loc_id bigint, ts_start timestamp with time zone, local_date timestamp without time zone, source_id text, jdata jsonb)
    LANGUAGE sql STABLE
    AS $$
SELECT
	loc AS loc_id,
	d.ts_start,
	d.ts_start AT TIME ZONE COALESCE(l.time_zone, 'UTC') AS local_date,
	d.source_id,
	d.jdata
 FROM solaragg.calc_loc_datum_time_slots(
	loc,
	source,
	solaragg.minute_time_slot(start_ts, solaragg.slot_seconds(slotsecs)),
	(end_ts - solaragg.minute_time_slot(start_ts, solaragg.slot_seconds(slotsecs))),
	solaragg.slot_seconds(slotsecs),
	tolerance
) AS d
LEFT OUTER JOIN solarnet.sn_loc l ON l.id = loc
$$;


ALTER FUNCTION solaragg.find_agg_loc_datum_minute(loc bigint, source text[], start_ts timestamp with time zone, end_ts timestamp with time zone, slotsecs integer, tolerance interval) OWNER TO solarnet;

--
-- Name: find_agg_loc_datum_seasonal_dow(bigint, text[], text[], timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_agg_loc_datum_seasonal_dow(loc bigint, source text[], path text[], start_ts timestamp with time zone DEFAULT '2001-01-01 13:00:00+13'::timestamp with time zone, end_ts timestamp with time zone DEFAULT now()) RETURNS TABLE(loc_id bigint, ts_start timestamp with time zone, local_date timestamp without time zone, source_id text, jdata jsonb)
    LANGUAGE sql STABLE
    AS $$
SELECT
	loc AS loc_id,
	(solarnet.get_season_monday_start(d.local_date)
		+ CAST((EXTRACT(isodow FROM d.local_date) - 1) || ' day' AS INTERVAL)) AT TIME ZONE 'UTC' AS ts_start,
	(solarnet.get_season_monday_start(d.local_date)
		+ CAST((EXTRACT(isodow FROM d.local_date) - 1) || ' day' AS INTERVAL)) AS local_date,
	d.source_id,
	('{"' || path[1] || '":{"' || path[2] || '":'
		|| ROUND(AVG(CAST(jsonb_extract_path_text(solaragg.jdata_from_datum(d), VARIADIC path) AS double precision)) * 1000) / 1000
		|| '}}')::jsonb as jdata
FROM solaragg.agg_loc_datum_daily d
WHERE
	d.loc_id = loc
	AND d.source_id = ANY(source)
	AND d.ts_start >= start_ts
	AND d.ts_start < end_ts
GROUP BY
	solarnet.get_season_monday_start(CAST(d.local_date AS date)),
	EXTRACT(isodow FROM d.local_date),
	d.source_id
$$;


ALTER FUNCTION solaragg.find_agg_loc_datum_seasonal_dow(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) OWNER TO solarnet;

--
-- Name: find_agg_loc_datum_seasonal_hod(bigint, text[], text[], timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_agg_loc_datum_seasonal_hod(loc bigint, source text[], path text[], start_ts timestamp with time zone DEFAULT '2008-01-01 13:00:00+13'::timestamp with time zone, end_ts timestamp with time zone DEFAULT now()) RETURNS TABLE(loc_id bigint, ts_start timestamp with time zone, local_date timestamp without time zone, source_id text, jdata jsonb)
    LANGUAGE sql STABLE
    AS $$
SELECT
	loc AS loc_id,
	(solarnet.get_season_monday_start(CAST(d.local_date AS DATE))
		+ CAST(EXTRACT(hour FROM d.local_date) || ' hour' AS INTERVAL)) AT TIME ZONE 'UTC' AS ts_start,
	solarnet.get_season_monday_start(CAST(d.local_date AS DATE))
		+ CAST(EXTRACT(hour FROM d.local_date) || ' hour' AS INTERVAL) AS local_date,
	d.source_id,
	('{"' || path[1] || '":{"' || path[2] || '":'
		|| ROUND(AVG(CAST(jsonb_extract_path_text(solaragg.jdata_from_datum(d), VARIADIC path) AS double precision)) * 1000) / 1000
		|| '}}')::jsonb as jdata
FROM solaragg.agg_loc_datum_hourly d
WHERE
	d.loc_id = loc
	AND d.source_id = ANY(source)
	AND d.ts_start >= start_ts
	AND d.ts_start < end_ts
GROUP BY
	solarnet.get_season_monday_start(CAST(d.local_date AS date)),
	EXTRACT(hour FROM d.local_date),
	d.source_id
$$;


ALTER FUNCTION solaragg.find_agg_loc_datum_seasonal_hod(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) OWNER TO solarnet;

--
-- Name: find_audit_acc_datum_daily(bigint, text); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_audit_acc_datum_daily(node bigint, source text) RETURNS TABLE(ts_start timestamp with time zone, node_id bigint, source_id character varying, datum_count integer, datum_hourly_count integer, datum_daily_count integer, datum_monthly_count integer)
    LANGUAGE sql
    AS $$
	WITH acc AS (
		SELECT
			sum(d.datum_count) AS datum_count,
			sum(d.datum_hourly_count) AS datum_hourly_count,
			sum(d.datum_daily_count) AS datum_daily_count,
			sum(CASE d.datum_monthly_pres WHEN TRUE THEN 1 ELSE 0 END) AS datum_monthly_count
		FROM solaragg.aud_datum_monthly d
		WHERE d.node_id = node
			AND d.source_id = source
	)
	SELECT
		date_trunc('day', CURRENT_TIMESTAMP AT TIME ZONE nlt.time_zone) AT TIME ZONE nlt.time_zone,
		node,
		source,
		acc.datum_count::integer,
		acc.datum_hourly_count::integer,
		acc.datum_daily_count::integer,
		acc.datum_monthly_count::integer
	FROM solarnet.node_local_time nlt
	CROSS JOIN acc
	WHERE nlt.node_id = node
$$;


ALTER FUNCTION solaragg.find_audit_acc_datum_daily(node bigint, source text) OWNER TO solarnet;

--
-- Name: find_audit_datum_interval(bigint, text); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_audit_datum_interval(node bigint, src text DEFAULT NULL::text, OUT ts_start timestamp with time zone, OUT ts_end timestamp with time zone, OUT node_tz text, OUT node_tz_offset integer) RETURNS record
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
	CASE
		WHEN src IS NULL THEN
			SELECT min(a.ts_start) FROM solaragg.aud_datum_hourly a WHERE node_id = node
			INTO ts_start;
		ELSE
			SELECT min(a.ts_start) FROM solaragg.aud_datum_hourly a WHERE node_id = node AND source_id = src
			INTO ts_start;
	END CASE;

	CASE
		WHEN src IS NULL THEN
			SELECT max(a.ts_start) FROM solaragg.aud_datum_hourly a WHERE node_id = node
			INTO ts_end;
		ELSE
			SELECT max(a.ts_start) FROM solaragg.aud_datum_hourly a WHERE node_id = node AND source_id = src
			INTO ts_end;
	END CASE;

	SELECT
		l.time_zone,
		CAST(EXTRACT(epoch FROM z.utc_offset) / 60 AS INTEGER)
	FROM solarnet.sn_node n
	INNER JOIN solarnet.sn_loc l ON l.id = n.loc_id
	INNER JOIN pg_timezone_names z ON z.name = l.time_zone
	WHERE n.node_id = node
	INTO node_tz, node_tz_offset;

	IF NOT FOUND THEN
		node_tz := 'UTC';
		node_tz_offset := 0;
	END IF;

END;$$;


ALTER FUNCTION solaragg.find_audit_datum_interval(node bigint, src text, OUT ts_start timestamp with time zone, OUT ts_end timestamp with time zone, OUT node_tz text, OUT node_tz_offset integer) OWNER TO solarnet;

--
-- Name: find_available_sources(bigint[]); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_available_sources(nodes bigint[]) RETURNS TABLE(node_id bigint, source_id text)
    LANGUAGE sql STABLE ROWS 50
    AS $$
	SELECT node_id, source_id
	FROM solardatum.da_datum_range
	WHERE node_id = ANY(nodes)
	ORDER BY source_id, node_id
$$;


ALTER FUNCTION solaragg.find_available_sources(nodes bigint[]) OWNER TO solarnet;

--
-- Name: find_available_sources(bigint[], timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_available_sources(nodes bigint[], sdate timestamp with time zone, edate timestamp with time zone) RETURNS TABLE(node_id bigint, source_id text)
    LANGUAGE sql STABLE ROWS 50
    AS $$
	SELECT DISTINCT d.node_id, CAST(d.source_id AS text)
	FROM solaragg.agg_datum_daily d
	WHERE d.node_id = ANY(nodes)
		AND d.ts_start >= sdate
		AND d.ts_start < edate
	ORDER BY source_id, node_id
$$;


ALTER FUNCTION solaragg.find_available_sources(nodes bigint[], sdate timestamp with time zone, edate timestamp with time zone) OWNER TO solarnet;

--
-- Name: find_available_sources_before(bigint[], timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_available_sources_before(nodes bigint[], edate timestamp with time zone) RETURNS TABLE(node_id bigint, source_id text)
    LANGUAGE sql STABLE ROWS 50
    AS $$
	SELECT DISTINCT d.node_id, CAST(d.source_id AS text)
	FROM solaragg.agg_datum_daily d
	WHERE d.node_id = ANY(nodes)
		AND d.ts_start < edate
	ORDER BY source_id, node_id
$$;


ALTER FUNCTION solaragg.find_available_sources_before(nodes bigint[], edate timestamp with time zone) OWNER TO solarnet;

--
-- Name: find_available_sources_since(bigint[], timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_available_sources_since(nodes bigint[], sdate timestamp with time zone) RETURNS TABLE(node_id bigint, source_id text)
    LANGUAGE sql STABLE ROWS 50
    AS $$
	SELECT DISTINCT d.node_id, CAST(d.source_id AS text)
	FROM solaragg.agg_datum_daily d
	WHERE d.node_id = ANY(nodes)
		AND d.ts_start >= sdate
	ORDER BY source_id, node_id
$$;


ALTER FUNCTION solaragg.find_available_sources_since(nodes bigint[], sdate timestamp with time zone) OWNER TO solarnet;

--
-- Name: find_datum_for_time_span(bigint, text[], timestamp with time zone, interval, interval); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_datum_for_time_span(node bigint, sources text[], start_ts timestamp with time zone, span interval, tolerance interval DEFAULT '01:00:00'::interval) RETURNS TABLE(ts timestamp with time zone, source_id text, jdata jsonb)
    LANGUAGE sql STABLE ROWS 500
    AS $$
	-- find raw data with support for filtering out "extra" leading/lagging rows from results
	WITH d AS (
		SELECT
			d.ts,
			d.source_id,
			CASE
				WHEN lead(d.ts) over win < start_ts OR lag(d.ts) over win > (start_ts + span)
					THEN TRUE
				ELSE FALSE
			END AS outside,
			solardatum.jdata_from_datum(d) as jdata
		FROM solardatum.da_datum d
		WHERE d.node_id = node
			AND d.source_id = ANY(sources)
			AND d.ts >= start_ts - tolerance
			AND d.ts <= start_ts + span + tolerance
		WINDOW win AS (PARTITION BY d.source_id ORDER BY d.ts)
	)
	-- find all reset records per node, source within [start, final] date ranges, producing pairs
	-- of rows for each matching record, of [FINAL, STARTING] data
	, resets AS (
		SELECT aux.ts - unnest(ARRAY['1 millisecond','0'])::interval AS ts
			, aux.source_id
			, CASE
				WHEN lead(aux.ts) over win < start_ts OR lag(aux.ts) over win > (start_ts + span)
					THEN TRUE
				ELSE FALSE
			END AS outside
			, unnest(ARRAY[solardatum.jdata_from_datum_aux_final(aux), solardatum.jdata_from_datum_aux_start(aux)]) AS jdata
		FROM solardatum.da_datum_aux aux
		WHERE aux.atype = 'Reset'::solardatum.da_datum_aux_type
			AND aux.node_id = node
			AND aux.source_id = ANY(sources)
			AND aux.ts >= start_ts - tolerance
			AND aux.ts < start_ts + span + tolerance
		WINDOW win AS (PARTITION BY aux.source_id ORDER BY aux.ts)
	)
	-- combine raw data with reset pairs
	, combined AS (
		SELECT * FROM d WHERE outside = FALSE
		UNION
		SELECT * FROM resets WHERE outside = FALSE
	)
	SELECT ts, source_id, jdata
	FROM combined
	ORDER BY ts, source_id
$$;


ALTER FUNCTION solaragg.find_datum_for_time_span(node bigint, sources text[], start_ts timestamp with time zone, span interval, tolerance interval) OWNER TO solarnet;

--
-- Name: find_loc_datum_for_time_span(bigint, text[], timestamp with time zone, interval, interval); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_loc_datum_for_time_span(loc bigint, sources text[], start_ts timestamp with time zone, span interval, tolerance interval DEFAULT '01:00:00'::interval) RETURNS TABLE(ts timestamp with time zone, source_id text, jdata jsonb)
    LANGUAGE sql STABLE
    AS $$
SELECT sub.ts, sub.source_id, sub.jdata FROM (
	-- subselect filters out "extra" leading/lagging rows from results
	SELECT
		d.ts,
		d.source_id,
		CASE
			WHEN lead(d.ts) over win < start_ts OR lag(d.ts) over win > (start_ts + span)
				THEN TRUE
			ELSE FALSE
		END AS outside,
		solardatum.jdata_from_datum(d) as jdata
	FROM solardatum.da_loc_datum d
	WHERE d.loc_id = loc
		AND d.source_id = ANY(sources)
		AND d.ts >= start_ts - tolerance
		AND d.ts <= start_ts + span + tolerance
	WINDOW win AS (PARTITION BY d.source_id ORDER BY d.ts)
	ORDER BY d.ts, d.source_id
) AS sub
WHERE
	sub.outside = FALSE
$$;


ALTER FUNCTION solaragg.find_loc_datum_for_time_span(loc bigint, sources text[], start_ts timestamp with time zone, span interval, tolerance interval) OWNER TO solarnet;

--
-- Name: agg_datum_daily; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.agg_datum_daily (
    ts_start timestamp with time zone NOT NULL,
    local_date date NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[],
    jmeta jsonb,
    jdata_as jsonb,
    jdata_af jsonb,
    jdata_ad jsonb
);


ALTER TABLE solaragg.agg_datum_daily OWNER TO solarnet;

--
-- Name: jdata_from_datum(solaragg.agg_datum_daily); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_datum_daily) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
	SELECT solarcommon.jdata_from_components(datum.jdata_i, datum.jdata_a, datum.jdata_s, datum.jdata_t);
$$;


ALTER FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_datum_daily) OWNER TO solarnet;

--
-- Name: agg_datum_daily_data; Type: VIEW; Schema: solaragg; Owner: solarnet
--

CREATE VIEW solaragg.agg_datum_daily_data AS
 SELECT d.ts_start,
    d.local_date,
    d.node_id,
    d.source_id,
    solaragg.jdata_from_datum(d.*) AS jdata
   FROM solaragg.agg_datum_daily d;


ALTER TABLE solaragg.agg_datum_daily_data OWNER TO solarnet;

--
-- Name: find_most_recent_daily(bigint, text[]); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_most_recent_daily(node bigint, sources text[] DEFAULT NULL::text[]) RETURNS SETOF solaragg.agg_datum_daily_data
    LANGUAGE plpgsql STABLE ROWS 20
    AS $$
BEGIN
	IF sources IS NULL OR array_length(sources, 1) < 1 THEN
		RETURN QUERY
		WITH maxes AS (
			SELECT max(d.ts_start) as ts_start, d.source_id, node as node_id FROM solaragg.agg_datum_daily d
			INNER JOIN (SELECT solardatum.find_available_sources(node) AS source_id) AS s ON s.source_id = d.source_id
			WHERE d. node_id = node
			GROUP BY d.source_id
		)
		SELECT d.* FROM solaragg.agg_datum_daily_data d
		INNER JOIN maxes ON maxes.node_id = d.node_id AND maxes.source_id = d.source_id AND maxes.ts_start = d.ts_start
		ORDER BY d.source_id ASC;
	ELSE
		RETURN QUERY
		WITH maxes AS (
			SELECT max(d.ts_start) as ts_start, d.source_id, node as node_id FROM solaragg.agg_datum_daily d
			INNER JOIN (SELECT unnest(sources) AS source_id) AS s ON s.source_id = d.source_id
			WHERE d. node_id = node
			GROUP BY d.source_id
		)
		SELECT d.* FROM solaragg.agg_datum_daily_data d
		INNER JOIN maxes ON maxes.node_id = d.node_id AND maxes.source_id = d.source_id AND maxes.ts_start = d.ts_start
		ORDER BY d.source_id ASC;
	END IF;
END;$$;


ALTER FUNCTION solaragg.find_most_recent_daily(node bigint, sources text[]) OWNER TO solarnet;

--
-- Name: agg_datum_hourly; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.agg_datum_hourly (
    ts_start timestamp with time zone NOT NULL,
    local_date timestamp without time zone NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[],
    jmeta jsonb,
    jdata_as jsonb,
    jdata_af jsonb,
    jdata_ad jsonb
);


ALTER TABLE solaragg.agg_datum_hourly OWNER TO solarnet;

--
-- Name: jdata_from_datum(solaragg.agg_datum_hourly); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_datum_hourly) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
	SELECT solarcommon.jdata_from_components(datum.jdata_i, datum.jdata_a, datum.jdata_s, datum.jdata_t);
$$;


ALTER FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_datum_hourly) OWNER TO solarnet;

--
-- Name: agg_datum_hourly_data; Type: VIEW; Schema: solaragg; Owner: solarnet
--

CREATE VIEW solaragg.agg_datum_hourly_data AS
 SELECT d.ts_start,
    d.local_date,
    d.node_id,
    d.source_id,
    solaragg.jdata_from_datum(d.*) AS jdata
   FROM solaragg.agg_datum_hourly d;


ALTER TABLE solaragg.agg_datum_hourly_data OWNER TO solarnet;

--
-- Name: find_most_recent_hourly(bigint, text[]); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_most_recent_hourly(node bigint, sources text[] DEFAULT NULL::text[]) RETURNS SETOF solaragg.agg_datum_hourly_data
    LANGUAGE plpgsql STABLE ROWS 20
    AS $$
BEGIN
	IF sources IS NULL OR array_length(sources, 1) < 1 THEN
		RETURN QUERY
		WITH maxes AS (
			SELECT max(d.ts_start) as ts_start, d.source_id, node as node_id FROM solaragg.agg_datum_hourly d
			INNER JOIN (SELECT solardatum.find_available_sources(node) AS source_id) AS s ON s.source_id = d.source_id
			WHERE d. node_id = node
			GROUP BY d.source_id
		)
		SELECT d.* FROM solaragg.agg_datum_hourly_data d
		INNER JOIN maxes ON maxes.node_id = d.node_id AND maxes.source_id = d.source_id AND maxes.ts_start = d.ts_start
		ORDER BY d.source_id ASC;
	ELSE
		RETURN QUERY
		WITH maxes AS (
			SELECT max(d.ts_start) as ts_start, d.source_id, node as node_id FROM solaragg.agg_datum_hourly d
			INNER JOIN (SELECT unnest(sources) AS source_id) AS s ON s.source_id = d.source_id
			WHERE d. node_id = node
			GROUP BY d.source_id
		)
		SELECT d.* FROM solaragg.agg_datum_hourly_data d
		INNER JOIN maxes ON maxes.node_id = d.node_id AND maxes.source_id = d.source_id AND maxes.ts_start = d.ts_start
		ORDER BY d.source_id ASC;
	END IF;
END;$$;


ALTER FUNCTION solaragg.find_most_recent_hourly(node bigint, sources text[]) OWNER TO solarnet;

--
-- Name: agg_datum_monthly; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.agg_datum_monthly (
    ts_start timestamp with time zone NOT NULL,
    local_date date NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[],
    jmeta jsonb,
    jdata_as jsonb,
    jdata_af jsonb,
    jdata_ad jsonb
);


ALTER TABLE solaragg.agg_datum_monthly OWNER TO solarnet;

--
-- Name: jdata_from_datum(solaragg.agg_datum_monthly); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_datum_monthly) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
	SELECT solarcommon.jdata_from_components(datum.jdata_i, datum.jdata_a, datum.jdata_s, datum.jdata_t);
$$;


ALTER FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_datum_monthly) OWNER TO solarnet;

--
-- Name: agg_datum_monthly_data; Type: VIEW; Schema: solaragg; Owner: solarnet
--

CREATE VIEW solaragg.agg_datum_monthly_data AS
 SELECT d.ts_start,
    d.local_date,
    d.node_id,
    d.source_id,
    solaragg.jdata_from_datum(d.*) AS jdata
   FROM solaragg.agg_datum_monthly d;


ALTER TABLE solaragg.agg_datum_monthly_data OWNER TO solarnet;

--
-- Name: find_most_recent_monthly(bigint, text[]); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_most_recent_monthly(node bigint, sources text[] DEFAULT NULL::text[]) RETURNS SETOF solaragg.agg_datum_monthly_data
    LANGUAGE plpgsql STABLE ROWS 20
    AS $$
BEGIN
	IF sources IS NULL OR array_length(sources, 1) < 1 THEN
		RETURN QUERY
		WITH maxes AS (
			SELECT max(d.ts_start) as ts_start, d.source_id, node as node_id FROM solaragg.agg_datum_monthly d
			INNER JOIN (SELECT solardatum.find_available_sources(node) AS source_id) AS s ON s.source_id = d.source_id
			WHERE d. node_id = node
			GROUP BY d.source_id
		)
		SELECT d.* FROM solaragg.agg_datum_monthly_data d
		INNER JOIN maxes ON maxes.node_id = d.node_id AND maxes.source_id = d.source_id AND maxes.ts_start = d.ts_start
		ORDER BY d.source_id ASC;
	ELSE
		RETURN QUERY
		WITH maxes AS (
			SELECT max(d.ts_start) as ts_start, d.source_id, node as node_id FROM solaragg.agg_datum_monthly d
			INNER JOIN (SELECT unnest(sources) AS source_id) AS s ON s.source_id = d.source_id
			WHERE d. node_id = node
			GROUP BY d.source_id
		)
		SELECT d.* FROM solaragg.agg_datum_monthly_data d
		INNER JOIN maxes ON maxes.node_id = d.node_id AND maxes.source_id = d.source_id AND maxes.ts_start = d.ts_start
		ORDER BY d.source_id ASC;
	END IF;
END;$$;


ALTER FUNCTION solaragg.find_most_recent_monthly(node bigint, sources text[]) OWNER TO solarnet;

--
-- Name: find_running_datum(bigint, text[], timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_running_datum(node bigint, sources text[], end_ts timestamp with time zone DEFAULT now()) RETURNS TABLE(ts_start timestamp with time zone, local_date timestamp without time zone, node_id bigint, source_id text, jdata jsonb, weight integer)
    LANGUAGE sql STABLE
    AS $$
	-- get the node TZ, falling back to UTC if not available so we always have a time zone even if node not found
	WITH nodetz AS (
		SELECT nids.node_id, COALESCE(l.time_zone, 'UTC') AS tz
		FROM (SELECT node AS node_id) nids
		LEFT OUTER JOIN solarnet.sn_node n ON n.node_id = nids.node_id
		LEFT OUTER JOIN solarnet.sn_loc l ON l.id = n.loc_id
	)
	SELECT d.ts_start, d.local_date, d.node_id, d.source_id, solaragg.jdata_from_datum(d),
		CAST(extract(epoch from (local_date + interval '1 month') - local_date) / 3600 AS integer) AS weight
	FROM solaragg.agg_datum_monthly d
	INNER JOIN nodetz ON nodetz.node_id = d.node_id
	WHERE d.ts_start < date_trunc('month', end_ts AT TIME ZONE nodetz.tz) AT TIME ZONE nodetz.tz
		AND d.source_id = ANY(sources)
	UNION ALL
	SELECT d.ts_start, d.local_date, d.node_id, d.source_id, solaragg.jdata_from_datum(d),
		24::integer as weight
	FROM solaragg.agg_datum_daily d
	INNER JOIN nodetz ON nodetz.node_id = d.node_id
	WHERE ts_start < date_trunc('day', end_ts AT TIME ZONE nodetz.tz) AT TIME ZONE nodetz.tz
		AND d.ts_start >= date_trunc('month', end_ts AT TIME ZONE nodetz.tz) AT TIME ZONE nodetz.tz
		AND d.source_id = ANY(sources)
	UNION ALL
	SELECT d.ts_start, d.local_date, d.node_id, d.source_id, solaragg.jdata_from_datum(d),
		1::INTEGER as weight
	FROM solaragg.agg_datum_hourly d
	INNER JOIN nodetz ON nodetz.node_id = d.node_id
	WHERE d.ts_start < date_trunc('hour', end_ts AT TIME ZONE nodetz.tz) AT TIME ZONE nodetz.tz
		AND d.ts_start >= date_trunc('day', end_ts AT TIME ZONE nodetz.tz) AT TIME ZONE nodetz.tz
		AND d.source_id = ANY(sources)
	UNION ALL
	SELECT ts_start, ts_start at time zone nodetz.tz AS local_date, nodetz.node_id, source_id, jdata, 1::integer as weight
	FROM solaragg.calc_datum_time_slots(
		node,
		sources,
		date_trunc('hour', end_ts),
		interval '1 hour',
		0,
		interval '1 hour')
	INNER JOIN nodetz ON nodetz.node_id = node
	ORDER BY ts_start, source_id
$$;


ALTER FUNCTION solaragg.find_running_datum(node bigint, sources text[], end_ts timestamp with time zone) OWNER TO solarnet;

--
-- Name: find_running_loc_datum(bigint, text[], timestamp with time zone); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.find_running_loc_datum(loc bigint, sources text[], end_ts timestamp with time zone DEFAULT now()) RETURNS TABLE(ts_start timestamp with time zone, local_date timestamp without time zone, loc_id bigint, source_id text, jdata jsonb, weight integer)
    LANGUAGE sql STABLE
    AS $$
	WITH loctz AS (
		SELECT lids.loc_id, COALESCE(l.time_zone, 'UTC') AS tz
		FROM (SELECT loc AS loc_id) lids
		LEFT OUTER JOIN solarnet.sn_loc l ON l.id = lids.loc_id
	)
	SELECT d.ts_start, d.local_date, d.loc_id, d.source_id, solaragg.jdata_from_datum(d), CAST(extract(epoch from (local_date + interval '1 month') - local_date) / 3600 AS integer) AS weight
	FROM solaragg.agg_loc_datum_monthly d
	INNER JOIN loctz ON loctz.loc_id = d.loc_id
	WHERE d.ts_start < date_trunc('month', end_ts AT TIME ZONE loctz.tz) AT TIME ZONE loctz.tz
		AND d.source_id = ANY(sources)
	UNION ALL
	SELECT d.ts_start, d.local_date, d.loc_id, d.source_id, solaragg.jdata_from_datum(d), 24::integer as weight
	FROM solaragg.agg_loc_datum_daily d
	INNER JOIN loctz ON loctz.loc_id = d.loc_id
	WHERE ts_start < date_trunc('day', end_ts AT TIME ZONE loctz.tz) AT TIME ZONE loctz.tz
		AND d.ts_start >= date_trunc('month', end_ts AT TIME ZONE loctz.tz) AT TIME ZONE loctz.tz
		AND d.source_id = ANY(sources)
	UNION ALL
	SELECT d.ts_start, d.local_date, d.loc_id, d.source_id, solaragg.jdata_from_datum(d), 1::INTEGER as weight
	FROM solaragg.agg_loc_datum_hourly d
	INNER JOIN loctz ON loctz.loc_id = d.loc_id
	WHERE d.ts_start < date_trunc('hour', end_ts AT TIME ZONE loctz.tz) AT TIME ZONE loctz.tz
		AND d.ts_start >= date_trunc('day', end_ts AT TIME ZONE loctz.tz) AT TIME ZONE loctz.tz
		AND d.source_id = ANY(sources)
	UNION ALL
	SELECT ts_start, ts_start at time zone loctz.tz AS local_date, loctz.loc_id, source_id, jdata, 1::integer as weight
	FROM solaragg.calc_loc_datum_time_slots(
		loc,
		sources,
		date_trunc('hour', end_ts),
		interval '1 hour',
		0,
		interval '1 hour')
	INNER JOIN loctz ON loctz.loc_id = loc_id
	ORDER BY ts_start, source_id
$$;


ALTER FUNCTION solaragg.find_running_loc_datum(loc bigint, sources text[], end_ts timestamp with time zone) OWNER TO solarnet;

--
-- Name: agg_loc_datum_daily; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.agg_loc_datum_daily (
    ts_start timestamp with time zone NOT NULL,
    local_date date NOT NULL,
    loc_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[],
    jmeta jsonb
);


ALTER TABLE solaragg.agg_loc_datum_daily OWNER TO solarnet;

--
-- Name: jdata_from_datum(solaragg.agg_loc_datum_daily); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_loc_datum_daily) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
	SELECT solarcommon.jdata_from_components(datum.jdata_i, datum.jdata_a, datum.jdata_s, datum.jdata_t);
$$;


ALTER FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_loc_datum_daily) OWNER TO solarnet;

--
-- Name: agg_loc_datum_hourly; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.agg_loc_datum_hourly (
    ts_start timestamp with time zone NOT NULL,
    local_date timestamp without time zone NOT NULL,
    loc_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[],
    jmeta jsonb
);


ALTER TABLE solaragg.agg_loc_datum_hourly OWNER TO solarnet;

--
-- Name: jdata_from_datum(solaragg.agg_loc_datum_hourly); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_loc_datum_hourly) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
	SELECT solarcommon.jdata_from_components(datum.jdata_i, datum.jdata_a, datum.jdata_s, datum.jdata_t);
$$;


ALTER FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_loc_datum_hourly) OWNER TO solarnet;

--
-- Name: agg_loc_datum_monthly; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.agg_loc_datum_monthly (
    ts_start timestamp with time zone NOT NULL,
    local_date date NOT NULL,
    loc_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[],
    jmeta jsonb
);


ALTER TABLE solaragg.agg_loc_datum_monthly OWNER TO solarnet;

--
-- Name: jdata_from_datum(solaragg.agg_loc_datum_monthly); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_loc_datum_monthly) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
	SELECT solarcommon.jdata_from_components(datum.jdata_i, datum.jdata_a, datum.jdata_s, datum.jdata_t);
$$;


ALTER FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_loc_datum_monthly) OWNER TO solarnet;

--
-- Name: minute_time_slot(timestamp with time zone, integer); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.minute_time_slot(ts timestamp with time zone, sec integer DEFAULT 600) RETURNS timestamp with time zone
    LANGUAGE sql IMMUTABLE
    AS $$
	SELECT date_trunc('hour', ts) + (
		ceil(extract('epoch' from ts) - extract('epoch' from date_trunc('hour', ts))) 
		- ceil(extract('epoch' from ts))::bigint % sec
	) * interval '1 second'
$$;


ALTER FUNCTION solaragg.minute_time_slot(ts timestamp with time zone, sec integer) OWNER TO solarnet;

--
-- Name: populate_audit_acc_datum_daily(bigint, text); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.populate_audit_acc_datum_daily(node bigint, source text) RETURNS void
    LANGUAGE sql
    AS $$
	INSERT INTO solaragg.aud_acc_datum_daily (ts_start, node_id, source_id,
		datum_count, datum_hourly_count, datum_daily_count, datum_monthly_count)
	SELECT
		ts_start,
		node_id,
		source_id,
		COALESCE(datum_count, 0) AS datum_count,
		COALESCE(datum_hourly_count, 0) AS datum_hourly_count,
		COALESCE(datum_daily_count, 0) AS datum_daily_count,
		COALESCE(datum_monthly_count, 0) AS datum_monthly_count
	FROM solaragg.find_audit_acc_datum_daily(node, source)
	ON CONFLICT (node_id, ts_start, source_id) DO UPDATE
	SET datum_count = EXCLUDED.datum_count,
		datum_hourly_count = EXCLUDED.datum_hourly_count,
		datum_daily_count = EXCLUDED.datum_daily_count,
		datum_monthly_count = EXCLUDED.datum_monthly_count,
		processed = CURRENT_TIMESTAMP;
$$;


ALTER FUNCTION solaragg.populate_audit_acc_datum_daily(node bigint, source text) OWNER TO solarnet;

--
-- Name: process_agg_stale_datum(character, integer); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.process_agg_stale_datum(kind character, max integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	one_result INTEGER := 1;
	total_result INTEGER := 0;
BEGIN
	LOOP
		IF one_result < 1 OR (max > -1 AND total_result >= max) THEN
			EXIT;
		END IF;
		SELECT solaragg.process_one_agg_stale_datum(kind) INTO one_result;
		total_result := total_result + one_result;
	END LOOP;
	RETURN total_result;
END;$$;


ALTER FUNCTION solaragg.process_agg_stale_datum(kind character, max integer) OWNER TO solarnet;

--
-- Name: process_agg_stale_loc_datum(character, integer); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.process_agg_stale_loc_datum(kind character, max integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	one_result INTEGER := 1;
	total_result INTEGER := 0;
BEGIN
	LOOP
		IF one_result < 1 OR (max > -1 AND total_result >= max) THEN
			EXIT;
		END IF;
		SELECT solaragg.process_one_agg_stale_loc_datum(kind) INTO one_result;
		total_result := total_result + one_result;
	END LOOP;
	RETURN total_result;
END;$$;


ALTER FUNCTION solaragg.process_agg_stale_loc_datum(kind character, max integer) OWNER TO solarnet;

--
-- Name: process_one_agg_stale_datum(character); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.process_one_agg_stale_datum(kind character) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	stale 					record;
	agg_span 				interval;
	agg_json 				jsonb := NULL;
	agg_jmeta 				jsonb := NULL;
	agg_reading 			jsonb := NULL;
	agg_reading_ts_start 	timestamptz := NULL;
	agg_reading_ts_end 		timestamptz := NULL;
	node_tz 				text := 'UTC';
	proc_count 				integer := 0;
	curs CURSOR FOR SELECT * FROM solaragg.agg_stale_datum WHERE agg_kind = kind
		-- Too slow to order; not strictly fair but process much faster
		-- ORDER BY ts_start ASC, created ASC, node_id ASC, source_id ASC
		LIMIT 1
		FOR UPDATE SKIP LOCKED;
BEGIN
	CASE kind
		WHEN 'h' THEN
			agg_span := interval '1 hour';
		WHEN 'd' THEN
			agg_span := interval '1 day';
		ELSE
			agg_span := interval '1 month';
	END CASE;

	OPEN curs;
	FETCH NEXT FROM curs INTO stale;

	IF FOUND THEN
		-- get the node TZ for local date/time
		SELECT l.time_zone FROM solarnet.sn_node n
		INNER JOIN solarnet.sn_loc l ON l.id = n.loc_id
		WHERE n.node_id = stale.node_id
		INTO node_tz;

		IF NOT FOUND THEN
			RAISE NOTICE 'Node % has no time zone, will use UTC.', stale.node_id;
			node_tz := 'UTC';
		END IF;

		CASE kind
			WHEN 'h' THEN
				SELECT jdata, jmeta
				FROM solaragg.calc_datum_time_slots(stale.node_id, ARRAY[stale.source_id::text], stale.ts_start, agg_span, 0, interval '1 hour')
				INTO agg_json, agg_jmeta;
				
				SELECT jdata, ts_start, ts_end
				FROM solardatum.calculate_datum_diff_over(stale.node_id, stale.source_id::text, stale.ts_start, stale.ts_start + agg_span)
				INTO agg_reading, agg_reading_ts_start, agg_reading_ts_end;

			WHEN 'd' THEN
				SELECT jdata, jmeta
				FROM solaragg.calc_agg_datum_agg(stale.node_id, ARRAY[stale.source_id::text], stale.ts_start, stale.ts_start + agg_span, 'h')
				INTO agg_json, agg_jmeta;
				
				SELECT jsonb_strip_nulls(jsonb_build_object(
					 'as', solarcommon.first(jdata_as ORDER BY ts_start),
					 'af', solarcommon.first(jdata_af ORDER BY ts_start DESC),
					 'a', solarcommon.jsonb_sum_object(jdata_ad)
				))
				FROM solaragg.agg_datum_hourly
				WHERE node_id = stale.node_id
					AND source_id = stale.source_id
					AND ts_start >= stale.ts_start
					AND ts_start < (stale.ts_start + agg_span)
				GROUP BY node_id, source_id
				INTO agg_reading;

			ELSE
				SELECT jdata, jmeta
				FROM solaragg.calc_agg_datum_agg(stale.node_id, ARRAY[stale.source_id::text], stale.ts_start, stale.ts_start + agg_span, 'd')
				INTO agg_json, agg_jmeta;
				
				SELECT jsonb_strip_nulls(jsonb_build_object(
					 'as', solarcommon.first(jdata_as ORDER BY ts_start),
					 'af', solarcommon.first(jdata_af ORDER BY ts_start DESC),
					 'a', solarcommon.jsonb_sum_object(jdata_ad)
				))
				FROM solaragg.agg_datum_daily
				WHERE node_id = stale.node_id
					AND source_id = stale.source_id
					AND ts_start >= stale.ts_start
					AND ts_start < (stale.ts_start + agg_span)
				GROUP BY node_id, source_id
				INTO agg_reading;
		END CASE;

		IF agg_json IS NULL AND (agg_reading IS NULL 
				OR (agg_reading_ts_start IS NOT NULL AND agg_reading_ts_start = agg_reading_ts_end)
				) THEN
			-- delete agg, using date range in case time zone of node has changed
			CASE kind
				WHEN 'h' THEN
					DELETE FROM solaragg.agg_datum_hourly
					WHERE node_id = stale.node_id
						AND source_id = stale.source_id
						AND ts_start > stale.ts_start - agg_span
						AND ts_start < stale.ts_start + agg_span;
				WHEN 'd' THEN
					DELETE FROM solaragg.agg_datum_daily
					WHERE node_id = stale.node_id
						AND source_id = stale.source_id
						AND ts_start > stale.ts_start - agg_span
						AND ts_start < stale.ts_start + agg_span;
				ELSE
					DELETE FROM solaragg.agg_datum_monthly
					WHERE node_id = stale.node_id
						AND source_id = stale.source_id
						AND ts_start > stale.ts_start - agg_span
						AND ts_start < stale.ts_start + agg_span;
			END CASE;
		ELSE
			CASE kind
				WHEN 'h' THEN
					INSERT INTO solaragg.agg_datum_hourly (
						ts_start, local_date, node_id, source_id,
						jdata_i, jdata_a, jdata_s, jdata_t, jmeta,
						jdata_as, jdata_af, jdata_ad)
					VALUES (
						stale.ts_start,
						stale.ts_start at time zone node_tz,
						stale.node_id,
						stale.source_id,
						agg_json->'i',
						agg_json->'a',
						agg_json->'s',
						solarcommon.json_array_to_text_array(agg_json->'t'),
						agg_jmeta,
						agg_reading->'as',
						agg_reading->'af',
						agg_reading->'a'
					)
					ON CONFLICT (node_id, ts_start, source_id) DO UPDATE
					SET jdata_i = EXCLUDED.jdata_i,
						jdata_a = EXCLUDED.jdata_a,
						jdata_s = EXCLUDED.jdata_s,
						jdata_t = EXCLUDED.jdata_t,
						jmeta = EXCLUDED.jmeta,
						jdata_as = EXCLUDED.jdata_as,
						jdata_af = EXCLUDED.jdata_af,
						jdata_ad = EXCLUDED.jdata_ad;

					-- in case node tz changed, remove stale record(s)
					DELETE FROM solaragg.agg_datum_hourly
					WHERE node_id = stale.node_id
						AND source_id = stale.source_id
						AND ts_start > stale.ts_start - agg_span
						AND ts_start < stale.ts_start + agg_span
						AND ts_start <> stale.ts_start;
				WHEN 'd' THEN
					INSERT INTO solaragg.agg_datum_daily (
						ts_start, local_date, node_id, source_id,
						jdata_i, jdata_a, jdata_s, jdata_t, jmeta,
						jdata_as, jdata_af, jdata_ad)
					VALUES (
						stale.ts_start,
						CAST(stale.ts_start at time zone node_tz AS DATE),
						stale.node_id,
						stale.source_id,
						agg_json->'i',
						agg_json->'a',
						agg_json->'s',
						solarcommon.json_array_to_text_array(agg_json->'t'),
						agg_jmeta,
						agg_reading->'as',
						agg_reading->'af',
						agg_reading->'a'
					)
					ON CONFLICT (node_id, ts_start, source_id) DO UPDATE
					SET jdata_i = EXCLUDED.jdata_i,
						jdata_a = EXCLUDED.jdata_a,
						jdata_s = EXCLUDED.jdata_s,
						jdata_t = EXCLUDED.jdata_t,
						jmeta = EXCLUDED.jmeta,
						jdata_as = EXCLUDED.jdata_as,
						jdata_af = EXCLUDED.jdata_af,
						jdata_ad = EXCLUDED.jdata_ad;

					-- in case node tz changed, remove stale record(s)
					DELETE FROM solaragg.agg_datum_daily
					WHERE node_id = stale.node_id
						AND source_id = stale.source_id
						AND ts_start > stale.ts_start - agg_span
						AND ts_start < stale.ts_start + agg_span
						AND ts_start <> stale.ts_start;
				ELSE
					INSERT INTO solaragg.agg_datum_monthly (
						ts_start, local_date, node_id, source_id,
						jdata_i, jdata_a, jdata_s, jdata_t, jmeta,
						jdata_as, jdata_af, jdata_ad)
					VALUES (
						stale.ts_start,
						CAST(stale.ts_start at time zone node_tz AS DATE),
						stale.node_id,
						stale.source_id,
						agg_json->'i',
						agg_json->'a',
						agg_json->'s',
						solarcommon.json_array_to_text_array(agg_json->'t'),
						agg_jmeta,
						agg_reading->'as',
						agg_reading->'af',
						agg_reading->'a'
					)
					ON CONFLICT (node_id, ts_start, source_id) DO UPDATE
					SET jdata_i = EXCLUDED.jdata_i,
						jdata_a = EXCLUDED.jdata_a,
						jdata_s = EXCLUDED.jdata_s,
						jdata_t = EXCLUDED.jdata_t,
						jmeta = EXCLUDED.jmeta,
						jdata_as = EXCLUDED.jdata_as,
						jdata_af = EXCLUDED.jdata_af,
						jdata_ad = EXCLUDED.jdata_ad;

					-- in case node tz changed, remove stale record(s)
					DELETE FROM solaragg.agg_datum_monthly
					WHERE node_id = stale.node_id
						AND source_id = stale.source_id
						AND ts_start > stale.ts_start - agg_span
						AND ts_start < stale.ts_start + agg_span
						AND ts_start <> stale.ts_start;
			END CASE;
		END IF;
		DELETE FROM solaragg.agg_stale_datum WHERE CURRENT OF curs;
		proc_count := 1;

		-- now make sure we recalculate the next aggregate level by submitting a stale record for the next level
		-- and also update daily audit stats
		CASE kind
			WHEN 'h' THEN
				INSERT INTO solaragg.agg_stale_datum (ts_start, node_id, source_id, agg_kind)
				VALUES (date_trunc('day', stale.ts_start at time zone node_tz) at time zone node_tz, stale.node_id, stale.source_id, 'd')
				ON CONFLICT DO NOTHING;

			WHEN 'd' THEN
				INSERT INTO solaragg.agg_stale_datum (ts_start, node_id, source_id, agg_kind)
				VALUES (date_trunc('month', stale.ts_start at time zone node_tz) at time zone node_tz, stale.node_id, stale.source_id, 'm')
				ON CONFLICT DO NOTHING;

				-- handle update to raw audit data
				INSERT INTO solaragg.aud_datum_daily_stale (ts_start, node_id, source_id, aud_kind)
				VALUES (date_trunc('day', stale.ts_start at time zone node_tz) at time zone node_tz, stale.node_id, stale.source_id, 'r')
				ON CONFLICT DO NOTHING;

				-- handle update to hourly audit data
				INSERT INTO solaragg.aud_datum_daily_stale (ts_start, node_id, source_id, aud_kind)
				VALUES (date_trunc('day', stale.ts_start at time zone node_tz) at time zone node_tz, stale.node_id, stale.source_id, 'h')
				ON CONFLICT DO NOTHING;

				-- handle update to daily audit data
				INSERT INTO solaragg.aud_datum_daily_stale (ts_start, node_id, source_id, aud_kind)
				VALUES (date_trunc('day', stale.ts_start at time zone node_tz) at time zone node_tz, stale.node_id, stale.source_id, 'd')
				ON CONFLICT DO NOTHING;
			ELSE
				-- handle update to monthly audit data
				INSERT INTO solaragg.aud_datum_daily_stale (ts_start, node_id, source_id, aud_kind)
				VALUES (date_trunc('month', stale.ts_start at time zone node_tz) at time zone node_tz, stale.node_id, stale.source_id, 'm')
				ON CONFLICT DO NOTHING;
		END CASE;
	END IF;
	CLOSE curs;
	RETURN proc_count;
END;
$$;


ALTER FUNCTION solaragg.process_one_agg_stale_datum(kind character) OWNER TO solarnet;

--
-- Name: process_one_agg_stale_loc_datum(character); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.process_one_agg_stale_loc_datum(kind character) RETURNS integer
    LANGUAGE plpgsql
    AS $$

DECLARE
	stale record;
	curs CURSOR FOR SELECT * FROM solaragg.agg_stale_loc_datum
			WHERE agg_kind = kind
			--ORDER BY ts_start ASC, created ASC, loc_id ASC, source_id ASC
			LIMIT 1
			FOR UPDATE SKIP LOCKED;
	agg_span interval;
	agg_json jsonb := NULL;
	agg_jmeta jsonb := NULL;
	loc_tz text := 'UTC';
	proc_count integer := 0;
BEGIN
	CASE kind
		WHEN 'h' THEN
			agg_span := interval '1 hour';
		WHEN 'd' THEN
			agg_span := interval '1 day';
		ELSE
			agg_span := interval '1 month';
	END CASE;

	OPEN curs;
	FETCH NEXT FROM curs INTO stale;

	IF FOUND THEN
		-- get the loc TZ for local date/time
		SELECT l.time_zone FROM solarnet.sn_loc l
		WHERE l.id = stale.loc_id
		INTO loc_tz;

		IF NOT FOUND THEN
			RAISE NOTICE 'Location % has no time zone, will use UTC.', stale.loc_id;
			loc_tz := 'UTC';
		END IF;

		CASE kind
			WHEN 'h' THEN
				SELECT jdata, jmeta
				FROM solaragg.calc_loc_datum_time_slots(stale.loc_id, ARRAY[stale.source_id::text], stale.ts_start, agg_span, 0, interval '1 hour')
				INTO agg_json, agg_jmeta;

			WHEN 'd' THEN
				SELECT jdata, jmeta
				FROM solaragg.calc_agg_loc_datum_agg(stale.loc_id, ARRAY[stale.source_id::text], stale.ts_start, stale.ts_start + agg_span, 'h')
				INTO agg_json, agg_jmeta;

			ELSE
				SELECT jdata, jmeta
				FROM solaragg.calc_agg_loc_datum_agg(stale.loc_id, ARRAY[stale.source_id::text], stale.ts_start, stale.ts_start + agg_span, 'd')
				INTO agg_json, agg_jmeta;
		END CASE;

		IF agg_json IS NULL THEN
			CASE kind
				WHEN 'h' THEN
					DELETE FROM solaragg.agg_loc_datum_hourly
					WHERE loc_id = stale.loc_id
						AND source_id = stale.source_id
						AND ts_start = stale.ts_start;
				WHEN 'd' THEN
					DELETE FROM solaragg.agg_loc_datum_daily
					WHERE loc_id = stale.loc_id
						AND source_id = stale.source_id
						AND ts_start = stale.ts_start;
				ELSE
					DELETE FROM solaragg.agg_loc_datum_monthly
					WHERE loc_id = stale.loc_id
						AND source_id = stale.source_id
						AND ts_start = stale.ts_start;
			END CASE;
		ELSE
			CASE kind
				WHEN 'h' THEN
					INSERT INTO solaragg.agg_loc_datum_hourly (
						ts_start, local_date, loc_id, source_id,
						jdata_i, jdata_a, jdata_s, jdata_t, jmeta)
					VALUES (
						stale.ts_start,
						stale.ts_start at time zone loc_tz,
						stale.loc_id,
						stale.source_id,
						agg_json->'i',
						agg_json->'a',
						agg_json->'s',
						solarcommon.json_array_to_text_array(agg_json->'t'),
						agg_jmeta
					)
					ON CONFLICT (loc_id, ts_start, source_id) DO UPDATE
					SET jdata_i = EXCLUDED.jdata_i,
						jdata_a = EXCLUDED.jdata_a,
						jdata_s = EXCLUDED.jdata_s,
						jdata_t = EXCLUDED.jdata_t,
						jmeta = EXCLUDED.jmeta;

				WHEN 'd' THEN
					INSERT INTO solaragg.agg_loc_datum_daily (
						ts_start, local_date, loc_id, source_id,
						jdata_i, jdata_a, jdata_s, jdata_t, jmeta)
					VALUES (
						stale.ts_start,
						CAST(stale.ts_start at time zone loc_tz AS DATE),
						stale.loc_id,
						stale.source_id,
						agg_json->'i',
						agg_json->'a',
						agg_json->'s',
						solarcommon.json_array_to_text_array(agg_json->'t'),
						agg_jmeta
					)
					ON CONFLICT (loc_id, ts_start, source_id) DO UPDATE
					SET jdata_i = EXCLUDED.jdata_i,
						jdata_a = EXCLUDED.jdata_a,
						jdata_s = EXCLUDED.jdata_s,
						jdata_t = EXCLUDED.jdata_t,
						jmeta = EXCLUDED.jmeta;
				ELSE
					INSERT INTO solaragg.agg_loc_datum_monthly (
						ts_start, local_date, loc_id, source_id,
						jdata_i, jdata_a, jdata_s, jdata_t, jmeta)
					VALUES (
						stale.ts_start,
						CAST(stale.ts_start at time zone loc_tz AS DATE),
						stale.loc_id,
						stale.source_id,
						agg_json->'i',
						agg_json->'a',
						agg_json->'s',
						solarcommon.json_array_to_text_array(agg_json->'t'),
						agg_jmeta
					)
					ON CONFLICT (loc_id, ts_start, source_id) DO UPDATE
					SET jdata_i = EXCLUDED.jdata_i,
						jdata_a = EXCLUDED.jdata_a,
						jdata_s = EXCLUDED.jdata_s,
						jdata_t = EXCLUDED.jdata_t,
						jmeta = EXCLUDED.jmeta;
			END CASE;
		END IF;
		DELETE FROM solaragg.agg_stale_loc_datum WHERE CURRENT OF curs;
		proc_count := 1;

		-- now make sure we recalculate the next aggregate level by submitting a stale record for the next level
		CASE kind
			WHEN 'h' THEN
				INSERT INTO solaragg.agg_stale_loc_datum (ts_start, loc_id, source_id, agg_kind)
				VALUES (date_trunc('day', stale.ts_start at time zone loc_tz) at time zone loc_tz, stale.loc_id, stale.source_id, 'd')
				ON CONFLICT (agg_kind, loc_id, ts_start, source_id) DO NOTHING;
			WHEN 'd' THEN
				INSERT INTO solaragg.agg_stale_loc_datum (ts_start, loc_id, source_id, agg_kind)
				VALUES (date_trunc('month', stale.ts_start at time zone loc_tz) at time zone loc_tz, stale.loc_id, stale.source_id, 'm')
				ON CONFLICT (agg_kind, loc_id, ts_start, source_id) DO NOTHING;
			ELSE
				-- nothing
		END CASE;
	END IF;
	CLOSE curs;
	RETURN proc_count;
END;

$$;


ALTER FUNCTION solaragg.process_one_agg_stale_loc_datum(kind character) OWNER TO solarnet;

--
-- Name: process_one_aud_datum_daily_stale(character); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.process_one_aud_datum_daily_stale(kind character) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
	stale record;
	curs CURSOR FOR SELECT * FROM solaragg.aud_datum_daily_stale
			WHERE aud_kind = kind
			ORDER BY ts_start ASC, created ASC, node_id ASC, source_id ASC
			LIMIT 1
			FOR UPDATE SKIP LOCKED;
	result integer := 0;
BEGIN
	OPEN curs;
	FETCH NEXT FROM curs INTO stale;

	IF FOUND THEN
		CASE kind
			WHEN 'r' THEN
				-- raw data counts
				INSERT INTO solaragg.aud_datum_daily (node_id, source_id, ts_start, datum_count)
				SELECT
					node_id,
					source_id,
					stale.ts_start,
					count(*) AS datum_count
				FROM solardatum.da_datum
				WHERE node_id = stale.node_id
					AND source_id = stale.source_id
					AND ts >= stale.ts_start
					AND ts < stale.ts_start + interval '1 day'
				GROUP BY node_id, source_id
				ON CONFLICT (node_id, ts_start, source_id) DO UPDATE
				SET datum_count = EXCLUDED.datum_count,
					processed_count = CURRENT_TIMESTAMP;

			WHEN 'h' THEN
				-- hour data counts
				INSERT INTO solaragg.aud_datum_daily (node_id, source_id, ts_start, datum_hourly_count)
				SELECT
					node_id,
					source_id,
					stale.ts_start,
					count(*) AS datum_hourly_count
				FROM solaragg.agg_datum_hourly
				WHERE node_id = stale.node_id
					AND source_id = stale.source_id
					AND ts_start >= stale.ts_start
					AND ts_start < stale.ts_start + interval '1 day'
				GROUP BY node_id, source_id
				ON CONFLICT (node_id, ts_start, source_id) DO UPDATE
				SET datum_hourly_count = EXCLUDED.datum_hourly_count,
					processed_hourly_count = CURRENT_TIMESTAMP;

			WHEN 'd' THEN
				-- day data counts, including sum of hourly audit prop_count, datum_q_count
				INSERT INTO solaragg.aud_datum_daily (node_id, source_id, ts_start, datum_daily_pres, prop_count, datum_q_count)
				WITH datum AS (
					SELECT count(*)::integer::boolean AS datum_daily_pres
					FROM solaragg.agg_datum_daily d
					WHERE d.node_id = stale.node_id
					AND d.source_id = stale.source_id
					AND d.ts_start = stale.ts_start
				)
				SELECT
					aud.node_id,
					aud.source_id,
					stale.ts_start,
					bool_or(d.datum_daily_pres) AS datum_daily_pres,
					sum(aud.prop_count) AS prop_count,
					sum(aud.datum_q_count) AS datum_q_count
				FROM solaragg.aud_datum_hourly aud
				CROSS JOIN datum d
				WHERE aud.node_id = stale.node_id
					AND aud.source_id = stale.source_id
					AND aud.ts_start >= stale.ts_start
					AND aud.ts_start < stale.ts_start + interval '1 day'
				GROUP BY aud.node_id, aud.source_id
				ON CONFLICT (node_id, ts_start, source_id) DO UPDATE
				SET datum_daily_pres = EXCLUDED.datum_daily_pres,
					prop_count = EXCLUDED.prop_count,
					datum_q_count = EXCLUDED.datum_q_count,
					processed_io_count = CURRENT_TIMESTAMP;

			ELSE
				-- month data counts
				INSERT INTO solaragg.aud_datum_monthly (node_id, source_id, ts_start,
					datum_count, datum_hourly_count, datum_daily_count, datum_monthly_pres,
					prop_count, datum_q_count)
				WITH datum AS (
					SELECT count(*)::integer::boolean AS datum_monthly_pres
					FROM solaragg.agg_datum_monthly d
					WHERE d.node_id = stale.node_id
					AND d.source_id = stale.source_id
					AND d.ts_start = stale.ts_start
				)
				SELECT
					aud.node_id,
					aud.source_id,
					stale.ts_start,
					sum(aud.datum_count) AS datum_count,
					sum(aud.datum_hourly_count) AS datum_hourly_count,
					sum(CASE aud.datum_daily_pres WHEN TRUE THEN 1 ELSE 0 END) AS datum_daily_count,
					bool_or(d.datum_monthly_pres) AS datum_monthly_pres,
					sum(aud.prop_count) AS prop_count,
					sum(aud.datum_q_count) AS datum_q_count
				FROM solaragg.aud_datum_daily aud
				CROSS JOIN datum d
				WHERE aud.node_id = stale.node_id
					AND aud.source_id = stale.source_id
					AND aud.ts_start >= stale.ts_start
					AND aud.ts_start < stale.ts_start + interval '1 month'
				GROUP BY aud.node_id, aud.source_id
				ON CONFLICT (node_id, ts_start, source_id) DO UPDATE
				SET datum_count = EXCLUDED.datum_count,
					datum_hourly_count = EXCLUDED.datum_hourly_count,
					datum_daily_count = EXCLUDED.datum_daily_count,
					datum_monthly_pres = EXCLUDED.datum_monthly_pres,
					prop_count = EXCLUDED.prop_count,
					datum_q_count = EXCLUDED.datum_q_count,
					processed = CURRENT_TIMESTAMP;
		END CASE;

		CASE kind
			WHEN 'm' THEN
				-- in case node tz changed, remove record(s) from other zone
				-- monthly records clean 1 month on either side
				DELETE FROM solaragg.aud_datum_monthly
				WHERE node_id = stale.node_id
					AND source_id = stale.source_id
					AND ts_start > stale.ts_start - interval '1 month'
					AND ts_start < stale.ts_start + interval '1 month'
					AND ts_start <> stale.ts_start;

				-- recalculate full accumulated audit counts for today
				PERFORM solaragg.populate_audit_acc_datum_daily(stale.node_id, stale.source_id);
			ELSE
				-- in case node tz changed, remove record(s) from other zone
				-- daily records clean 1 day on either side
				DELETE FROM solaragg.aud_datum_daily
				WHERE node_id = stale.node_id
					AND source_id = stale.source_id
					AND ts_start > stale.ts_start - interval '1 day'
					AND ts_start < stale.ts_start + interval '1 day'
					AND ts_start <> stale.ts_start;

				-- recalculate monthly audit based on updated daily values
				INSERT INTO solaragg.aud_datum_daily_stale (ts_start, node_id, source_id, aud_kind)
				SELECT
					date_trunc('month', stale.ts_start AT TIME ZONE node.time_zone) AT TIME ZONE node.time_zone,
					stale.node_id,
					stale.source_id,
					'm'
				FROM solarnet.node_local_time node
				WHERE node.node_id = stale.node_id
				ON CONFLICT DO NOTHING;
		END CASE;

		-- remove processed stale record
		DELETE FROM solaragg.aud_datum_daily_stale WHERE CURRENT OF curs;
		result := 1;
	END IF;
	CLOSE curs;
	RETURN result;
END;
$$;


ALTER FUNCTION solaragg.process_one_aud_datum_daily_stale(kind character) OWNER TO solarnet;

--
-- Name: slot_seconds(integer); Type: FUNCTION; Schema: solaragg; Owner: solarnet
--

CREATE FUNCTION solaragg.slot_seconds(secs integer DEFAULT 600) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$
	SELECT 
	CASE 
		WHEN secs < 60 OR secs > 1800 OR 1800 % secs <> 0 THEN 600 
	ELSE
		secs
	END
$$;


ALTER FUNCTION solaragg.slot_seconds(secs integer) OWNER TO solarnet;

--
-- Name: ant_pattern_to_regexp(text); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.ant_pattern_to_regexp(pat text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
SELECT '^' ||
regexp_replace(
regexp_replace(
regexp_replace(
regexp_replace(pat, '([!$()+.:<=>[\\\]^{|}-])', '\\\1', 'g'),
E'[?]', E'[^/]', 'g'),
E'(?<![*])[*](?![*])', E'[^/]*', 'g'),
E'[*]{2}', '(?<=/|^).*(?=/|$)', 'g')
|| '$';
$_$;


ALTER FUNCTION solarcommon.ant_pattern_to_regexp(pat text) OWNER TO solarnet;

--
-- Name: components_from_jdata(jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.components_from_jdata(jdata jsonb, OUT jdata_i jsonb, OUT jdata_a jsonb, OUT jdata_s jsonb, OUT jdata_t text[]) RETURNS record
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT jdata->'i', jdata->'a', jdata->'s', solarcommon.json_array_to_text_array(jdata->'t')
$$;


ALTER FUNCTION solarcommon.components_from_jdata(jdata jsonb, OUT jdata_i jsonb, OUT jdata_a jsonb, OUT jdata_s jsonb, OUT jdata_t text[]) OWNER TO solarnet;

--
-- Name: first_sfunc(anyelement, anyelement); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.first_sfunc(anyelement, anyelement) RETURNS anyelement
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
    SELECT $1;
$_$;


ALTER FUNCTION solarcommon.first_sfunc(anyelement, anyelement) OWNER TO solarnet;

--
-- Name: jdata_from_components(jsonb, jsonb, jsonb, text[]); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jdata_from_components(jdata_i jsonb, jdata_a jsonb, jdata_s jsonb, jdata_t text[]) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT jsonb_strip_nulls(jsonb_build_object('i', jdata_i, 'a', jdata_a, 's', jdata_s, 't', to_jsonb(jdata_t)));
$$;


ALTER FUNCTION solarcommon.jdata_from_components(jdata_i jsonb, jdata_a jsonb, jdata_s jsonb, jdata_t text[]) OWNER TO solarnet;

--
-- Name: json_array_to_bigint_array(json); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.json_array_to_bigint_array(json) RETURNS bigint[]
    LANGUAGE sql IMMUTABLE
    AS $_$
    SELECT array_agg(x)::bigint[] || ARRAY[]::bigint[] FROM json_array_elements_text($1) t(x);
$_$;


ALTER FUNCTION solarcommon.json_array_to_bigint_array(json) OWNER TO solarnet;

--
-- Name: json_array_to_text_array(json); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.json_array_to_text_array(jdata json) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT
	CASE
		WHEN jdata IS NULL THEN NULL::text[]
		ELSE ARRAY(SELECT json_array_elements_text(jdata))
	END
$$;


ALTER FUNCTION solarcommon.json_array_to_text_array(jdata json) OWNER TO solarnet;

--
-- Name: json_array_to_text_array(jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.json_array_to_text_array(jdata jsonb) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT
	CASE
		WHEN jdata IS NULL THEN NULL::text[]
		ELSE ARRAY(SELECT jsonb_array_elements_text(jdata))
	END
$$;


ALTER FUNCTION solarcommon.json_array_to_text_array(jdata jsonb) OWNER TO solarnet;

--
-- Name: jsonb_array_to_bigint_array(jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_array_to_bigint_array(jsonb) RETURNS bigint[]
    LANGUAGE sql IMMUTABLE
    AS $_$
    SELECT array_agg(x)::bigint[] || ARRAY[]::bigint[] FROM jsonb_array_elements_text($1) t(x);
$_$;


ALTER FUNCTION solarcommon.jsonb_array_to_bigint_array(jsonb) OWNER TO solarnet;

--
-- Name: jsonb_avg_finalfunc(jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_avg_finalfunc(agg_state jsonb) RETURNS jsonb
    LANGUAGE plv8 IMMUTABLE
    AS $$
	'use strict';
    return (agg_state.c > 0 ? agg_state.s / agg_state.c : null);
$$;


ALTER FUNCTION solarcommon.jsonb_avg_finalfunc(agg_state jsonb) OWNER TO solarnet;

--
-- Name: jsonb_avg_object_finalfunc(jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_avg_object_finalfunc(agg_state jsonb) RETURNS jsonb
    LANGUAGE plv8 IMMUTABLE
    AS $$
	'use strict';
	var calculateAverages = require('math/calculateAverages').default;
	return calculateAverages(agg_state.d, agg_state.c);
$$;


ALTER FUNCTION solarcommon.jsonb_avg_object_finalfunc(agg_state jsonb) OWNER TO solarnet;

--
-- Name: jsonb_avg_object_sfunc(jsonb, jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_avg_object_sfunc(agg_state jsonb, el jsonb) RETURNS jsonb
    LANGUAGE plv8 IMMUTABLE
    AS $$
	'use strict';
	var addTo,
		prop,
		d,
		c;
	if ( !agg_state ) {
		c = {};
		for ( prop in el ) {
			c[prop] = 1;
		}
		agg_state = {d:el, c:c};
	} else if ( el ) {
		addTo = require('util/addTo').default;
		d = agg_state.d;
		c = agg_state.c;
		for ( prop in el ) {
			addTo(prop, el[prop], d, 1, c);
		}
	}
	return agg_state;
$$;


ALTER FUNCTION solarcommon.jsonb_avg_object_sfunc(agg_state jsonb, el jsonb) OWNER TO solarnet;

--
-- Name: jsonb_avg_sfunc(jsonb, jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_avg_sfunc(agg_state jsonb, el jsonb) RETURNS jsonb
    LANGUAGE plv8 IMMUTABLE
    AS $$
	'use strict';
	if ( !agg_state ) {
		return {s:el,c:(el !== null ? 1 : 0)};
	}
	agg_state.s += el;
	if ( el !== null ) {
		agg_state.c += 1;
	}
	return agg_state;
$$;


ALTER FUNCTION solarcommon.jsonb_avg_sfunc(agg_state jsonb, el jsonb) OWNER TO solarnet;

--
-- Name: jsonb_diff_object_finalfunc(jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_diff_object_finalfunc(agg_state jsonb) RETURNS jsonb
    LANGUAGE plv8 IMMUTABLE
    AS $$
	'use strict';
	var prop,
		val,
		f = (agg_state ? agg_state.first : null),
		l = (agg_state ? agg_state.last : null),
		r;
	if ( l ) {
		r = {};
		for ( prop in l ) {
			val = f[prop];
			if ( val !== undefined ) {
				r[prop +'_start'] = val;
				r[prop +'_end'] = l[prop];
				r[prop] = l[prop] - val;
			}
		}
	} else {
		r = null;
	}
    return r;
$$;


ALTER FUNCTION solarcommon.jsonb_diff_object_finalfunc(agg_state jsonb) OWNER TO solarnet;

--
-- Name: jsonb_diff_object_sfunc(jsonb, jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_diff_object_sfunc(agg_state jsonb, el jsonb) RETURNS jsonb
    LANGUAGE plv8 IMMUTABLE
    AS $$
	'use strict';
	var prop,
		f,
		curr;
	if ( !agg_state && el ) {
		agg_state = {first:el, last:el};
	} else if ( el ) {
		f = agg_state.first;
		curr = agg_state.last;
		for ( prop in el ) {
			curr[prop] = el[prop];
			if ( f[prop] === undefined ) {
				// property discovered mid-way while aggregating; add to "first" now
				f[prop] = el[prop];
			}
		}
	}
	return agg_state;
$$;


ALTER FUNCTION solarcommon.jsonb_diff_object_sfunc(agg_state jsonb, el jsonb) OWNER TO solarnet;

--
-- Name: jsonb_diffsum_jdata_finalfunc(jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_diffsum_jdata_finalfunc(agg_state jsonb) RETURNS jsonb
    LANGUAGE plv8 IMMUTABLE
    AS $$
	'use strict';
	var prop,
		val,
		f = (agg_state ? agg_state.first : null),
		p = (agg_state ? agg_state.prev : null),
		t = (agg_state ? agg_state.total : null),
		l = (agg_state ? agg_state.last : null);
	if ( p ) {
		for ( prop in p ) {
			if ( t[prop] === undefined ) {
				t[prop] = 0;
			}
		}
	}
	
	for ( prop in t ) {
		return {'a':t, 'af':l, 'as':f};
	}
    return null;
$$;


ALTER FUNCTION solarcommon.jsonb_diffsum_jdata_finalfunc(agg_state jsonb) OWNER TO solarnet;

--
-- Name: jsonb_diffsum_object_finalfunc(jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_diffsum_object_finalfunc(agg_state jsonb) RETURNS jsonb
    LANGUAGE plv8 IMMUTABLE
    AS $$
	'use strict';
	var prop,
		val,
		f = (agg_state ? agg_state.first : null),
		p = (agg_state ? agg_state.prev : null),
		t = (agg_state ? agg_state.total : null),
		l = (agg_state ? agg_state.last : null);
	if ( p ) {
		for ( prop in p ) {
			if ( t[prop] === undefined ) {
				t[prop] = 0;
			}
		}
	}
	
	// add in _start/_end props
	for ( prop in t ) {
		val = f[prop];
		if ( val !== undefined ) {
			t[prop +'_start'] = val;
			t[prop +'_end'] = l[prop];
		}
	}
	for ( prop in t ) {
		return t;
	}
    return null;
$$;


ALTER FUNCTION solarcommon.jsonb_diffsum_object_finalfunc(agg_state jsonb) OWNER TO solarnet;

--
-- Name: jsonb_diffsum_object_sfunc(jsonb, jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_diffsum_object_sfunc(agg_state jsonb, el jsonb) RETURNS jsonb
    LANGUAGE plv8 IMMUTABLE
    AS $$
	'use strict';
	var prop,
		f,
		p,
		l,
		t,
		val;
	if ( !agg_state && el ) {
		agg_state = {first:el, last:el, prev:el, total:{}};
	} else if ( el ) {
		f = agg_state.first;
		p = agg_state.prev;
		t = agg_state.total;
		l = agg_state.last;
		if ( p ) {
			// right-hand side; diff from prev and add to total
			for ( prop in el ) {
				// stash current val on "last" record
				l[prop] = el[prop];
				
				if ( f[prop] === undefined ) {
					// property discovered mid-way while aggregating; add to "first" now
					f[prop] = el[prop];
				}
				if ( p[prop] === undefined ) {
					// property discovered mid-way while aggregating; diff is 0
					val = 0;
				} else {
					val = el[prop] - p[prop];
				}
				if ( t[prop] ) {
					t[prop] += val;
				} else {
					t[prop] = val;
				}
			}
			
			// clear prev record
			delete agg_state.prev;
		} else {
			for ( prop in el ) {
				// stash current val on "last" record
				l[prop] = el[prop];

				if ( f[prop] === undefined ) {
					// property discovered mid-way while aggregating; add to "first" now
					f[prop] = el[prop];
				}
			}

			// stash prev side for next diff
			agg_state.prev = el;
		}
	}
	return agg_state;
$$;


ALTER FUNCTION solarcommon.jsonb_diffsum_object_sfunc(agg_state jsonb, el jsonb) OWNER TO solarnet;

--
-- Name: jsonb_sum_object_sfunc(jsonb, jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_sum_object_sfunc(agg_state jsonb, el jsonb) RETURNS jsonb
    LANGUAGE plv8 IMMUTABLE
    AS $$
	'use strict';
	var addTo,
		prop;
	if ( !agg_state ) {
		agg_state = el;
	} else if ( el ) {
		addTo = require('util/addTo').default;
		for ( prop in el ) {
			addTo(prop, el[prop], agg_state);
		}
	}
	return agg_state;
$$;


ALTER FUNCTION solarcommon.jsonb_sum_object_sfunc(agg_state jsonb, el jsonb) OWNER TO solarnet;

--
-- Name: jsonb_sum_sfunc(jsonb, jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_sum_sfunc(agg_state jsonb, el jsonb) RETURNS jsonb
    LANGUAGE plv8 IMMUTABLE
    AS $$
	return (!agg_state ? el : agg_state + el);
$$;


ALTER FUNCTION solarcommon.jsonb_sum_sfunc(agg_state jsonb, el jsonb) OWNER TO solarnet;

--
-- Name: jsonb_weighted_proj_object_finalfunc(jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_weighted_proj_object_finalfunc(agg_state jsonb) RETURNS jsonb
    LANGUAGE plv8 IMMUTABLE
    AS $$
	'use strict';
	var w = agg_state.weight,
		f = agg_state.first,
		l = agg_state.last,
		prop,
		firstVal,
		res = {};
	if ( !(f && l) ) {
		return f;
	}
	for ( prop in l ) {
		firstVal = f[prop];
		if ( firstVal ) {
			res[prop] = firstVal + ((l[prop] - firstVal) * w);
		}
	}
	return res;
$$;


ALTER FUNCTION solarcommon.jsonb_weighted_proj_object_finalfunc(agg_state jsonb) OWNER TO solarnet;

--
-- Name: jsonb_weighted_proj_object_sfunc(jsonb, jsonb, double precision); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_weighted_proj_object_sfunc(agg_state jsonb, el jsonb, weight double precision) RETURNS jsonb
    LANGUAGE plv8 IMMUTABLE
    AS $$
	'use strict';
	var prop;
	if ( !agg_state ) {
		agg_state = {weight:weight, first:el};
	} else if ( el ) {
		agg_state.last = el;
	}
	return agg_state;
$$;


ALTER FUNCTION solarcommon.jsonb_weighted_proj_object_sfunc(agg_state jsonb, el jsonb, weight double precision) OWNER TO solarnet;

--
-- Name: jsonb_weighted_proj_sum_object_finalfunc(jsonb); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_weighted_proj_sum_object_finalfunc(agg_state jsonb) RETURNS jsonb
    LANGUAGE plv8 IMMUTABLE
    AS $_$
	'use strict';
	var fixPrecision = require('math/fixPrecision').default,
		w = agg_state.weight,
		s = agg_state.suffix,
		el = agg_state.el,
		prop,
		val,
		matches,
		res = {};
	if ( !el ) {
		return el;
	}
	for ( prop in el ) {
		val = el[prop];
		if ( /s$/.test(prop) ) {
			prop = prop.substring(0, prop.length - 1) + s;
		} else {
			matches = /^(.*)(_min|_max)$/.exec(prop);
			if ( matches ) {
				prop = matches[1] + s + matches[2];
			} else {
				prop += s;
			}
		}
		res[prop] = fixPrecision(val * w);
	}
	return res;
$_$;


ALTER FUNCTION solarcommon.jsonb_weighted_proj_sum_object_finalfunc(agg_state jsonb) OWNER TO solarnet;

--
-- Name: jsonb_weighted_proj_sum_object_sfunc(jsonb, jsonb, text, double precision); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.jsonb_weighted_proj_sum_object_sfunc(agg_state jsonb, el jsonb, suffix text, weight double precision) RETURNS jsonb
    LANGUAGE plv8 IMMUTABLE
    AS $$
	'use strict';
	var addTo,
		prop;
	if ( !agg_state ) {
		agg_state = {
			weight: weight, 
			suffix: suffix,
			el: {}
		};
	}
	if ( el ) {
		addTo = require('util/addTo').default;
		for ( prop in el ) {
			addTo(prop, el[prop], agg_state.el);
		}
	}
	return agg_state;
$$;


ALTER FUNCTION solarcommon.jsonb_weighted_proj_sum_object_sfunc(agg_state jsonb, el jsonb, suffix text, weight double precision) OWNER TO solarnet;

--
-- Name: plainto_prefix_tsquery(text); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.plainto_prefix_tsquery(qtext text) RETURNS tsquery
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
SELECT solarcommon.plainto_prefix_tsquery(get_current_ts_config(), qtext); 
$$;


ALTER FUNCTION solarcommon.plainto_prefix_tsquery(qtext text) OWNER TO solarnet;

--
-- Name: plainto_prefix_tsquery(regconfig, text); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.plainto_prefix_tsquery(config regconfig, qtext text) RETURNS tsquery
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
SELECT to_tsquery(config,
	regexp_replace(
			regexp_replace(
				regexp_replace(qtext, E'[^\\w ]', '', 'g'), 
			E'\\M', ':*', 'g'),
		E'\\s+',' & ','g')
);
$$;


ALTER FUNCTION solarcommon.plainto_prefix_tsquery(config regconfig, qtext text) OWNER TO solarnet;

--
-- Name: reduce_dim(anyarray); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.reduce_dim(anyarray) RETURNS SETOF anyarray
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
DECLARE
	s $1%TYPE;
BEGIN
	FOREACH s SLICE 1  IN ARRAY $1 LOOP
		RETURN NEXT s;
	END LOOP;
	RETURN;
END;
$_$;


ALTER FUNCTION solarcommon.reduce_dim(anyarray) OWNER TO solarnet;

--
-- Name: to_rfc1123_utc(timestamp with time zone); Type: FUNCTION; Schema: solarcommon; Owner: solarnet
--

CREATE FUNCTION solarcommon.to_rfc1123_utc(d timestamp with time zone) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
	SELECT to_char(d at time zone 'UTC', 'Dy, DD Mon YYYY HH24:MI:SS "GMT"');
$$;


ALTER FUNCTION solarcommon.to_rfc1123_utc(d timestamp with time zone) OWNER TO solarnet;

--
-- Name: calculate_datum_at(bigint[], text[], timestamp with time zone, interval); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.calculate_datum_at(nodes bigint[], sources text[], reading_ts timestamp with time zone, span interval DEFAULT '1 mon'::interval) RETURNS TABLE(ts timestamp with time zone, node_id bigint, source_id text, jdata_i jsonb, jdata_a jsonb)
    LANGUAGE sql STABLE
    AS $$
	WITH slice AS (
		SELECT
			d.ts,
			CASE
				WHEN d.ts <= reading_ts THEN last_value(d.ts) OVER win
				ELSE first_value(d.ts) OVER win
			END AS slot_ts,
			lead(d.ts) OVER win_full AS next_ts,
			EXTRACT(epoch FROM (reading_ts - d.ts))
				/ EXTRACT(epoch FROM (lead(d.ts) OVER win_full - d.ts)) AS weight,
			d.node_id,
			d.source_id,
			d.jdata_i,
			d.jdata_a
		FROM solardatum.da_datum d
		WHERE d.node_id = ANY(nodes)
			AND d.source_id = ANY(sources)
			AND d.ts >= reading_ts - span
			AND d.ts < reading_ts + span
		WINDOW win AS (PARTITION BY d.node_id, d.source_id, CASE WHEN d.ts <= reading_ts
			THEN 0 ELSE 1 END ORDER BY d.ts RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING),
			win_full AS (PARTITION BY d.node_id, d.source_id)
		ORDER BY d.node_id, d.source_id, d.ts
	)
	SELECT reading_ts AS ts,
		node_id,
		source_id,
		CASE solarcommon.first(ts ORDER BY ts)
			-- we have exact timestamp (improbable!)
			WHEN reading_ts THEN solarcommon.first(jdata_i ORDER BY ts)

			-- more likely, project prop values based on linear difference between start/end samples
			ELSE solarcommon.jsonb_avg_object(jdata_i)
		END AS jdata_i,
		CASE solarcommon.first(ts ORDER BY ts)
			-- we have exact timestamp (improbable!)
			WHEN reading_ts THEN solarcommon.first(jdata_a ORDER BY ts)

			-- more likely, project prop values based on linear difference between start/end samples
			ELSE solarcommon.jsonb_weighted_proj_object(jdata_a, weight)
		END AS jdata_a
	FROM slice
	WHERE ts = slot_ts
	GROUP BY node_id, source_id
	HAVING count(*) > 1 OR solarcommon.first(ts ORDER BY ts) = reading_ts OR solarcommon.first(ts ORDER BY ts DESC) = reading_ts
	ORDER BY node_id, source_id
$$;


ALTER FUNCTION solardatum.calculate_datum_at(nodes bigint[], sources text[], reading_ts timestamp with time zone, span interval) OWNER TO solarnet;

--
-- Name: calculate_datum_at_local(bigint[], text[], timestamp without time zone, interval); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.calculate_datum_at_local(nodes bigint[], sources text[], reading_ts timestamp without time zone, span interval DEFAULT '1 mon'::interval) RETURNS TABLE(ts timestamp with time zone, node_id bigint, source_id text, jdata_i jsonb, jdata_a jsonb)
    LANGUAGE sql STABLE
    AS $$
	WITH t AS (
		SELECT node_id, reading_ts AT TIME ZONE time_zone AS ts
		FROM solarnet.node_local_time
		WHERE node_id = ANY(nodes)
	), slice AS (
		SELECT
			d.ts,
			t.ts AS ts_slot,
			CASE
				WHEN d.ts <= t.ts THEN last_value(d.ts) OVER win
				ELSE first_value(d.ts) OVER win
			END AS slot_ts,
			lead(d.ts) OVER win_full AS next_ts,
			EXTRACT(epoch FROM (t.ts - d.ts))
				/ EXTRACT(epoch FROM (lead(d.ts) OVER win_full - d.ts)) AS weight,
			d.node_id,
			d.source_id,
			d.jdata_i,
			d.jdata_a
		FROM solardatum.da_datum d
		INNER JOIN t ON t.node_id = d.node_id
		WHERE d.node_id = ANY(nodes)
			AND d.source_id = ANY(sources)
			AND d.ts >= t.ts - span
			AND d.ts < t.ts + span
		WINDOW win AS (PARTITION BY d.node_id, d.source_id, CASE WHEN d.ts <= t.ts
			THEN 0 ELSE 1 END ORDER BY d.ts RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING),
			win_full AS (PARTITION BY d.node_id, d.source_id)
		ORDER BY d.node_id, d.source_id, d.ts
	)
	SELECT
		ts_slot AS ts,
		node_id,
		source_id,
		CASE solarcommon.first(ts ORDER BY ts)
			-- we have exact timestamp (improbable!)
			WHEN ts_slot THEN solarcommon.first(jdata_i ORDER BY ts)

			-- more likely, project prop values based on linear difference between start/end samples
			ELSE solarcommon.jsonb_avg_object(jdata_i)
		END AS jdata_i,
		CASE solarcommon.first(ts ORDER BY ts)
			-- we have exact timestamp (improbable!)
			WHEN ts_slot THEN solarcommon.first(jdata_a ORDER BY ts)

			-- more likely, project prop values based on linear difference between start/end samples
			ELSE solarcommon.jsonb_weighted_proj_object(jdata_a, weight)
		END AS jdata_a
	FROM slice
	WHERE ts = slot_ts
	GROUP BY ts_slot, node_id, source_id
	HAVING count(*) > 1 OR solarcommon.first(ts ORDER BY ts) = ts_slot OR solarcommon.first(ts ORDER BY ts DESC) = ts_slot
	ORDER BY ts_slot, node_id, source_id
$$;


ALTER FUNCTION solardatum.calculate_datum_at_local(nodes bigint[], sources text[], reading_ts timestamp without time zone, span interval) OWNER TO solarnet;

--
-- Name: calculate_datum_diff(bigint[], text[], timestamp with time zone, timestamp with time zone, interval); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.calculate_datum_diff(nodes bigint[], sources text[], ts_min timestamp with time zone, ts_max timestamp with time zone, tolerance interval DEFAULT '1 mon'::interval) RETURNS TABLE(ts_start timestamp with time zone, ts_end timestamp with time zone, time_zone text, node_id bigint, source_id character varying, jdata_a jsonb)
    LANGUAGE sql STABLE
    AS $$
	-- find records closest to, but not after, min date
	-- also considering reset records, using their STARTING sample value
	WITH latest_before_start AS (
		SELECT DISTINCT ON (d.node_id, d.source_id) d.*
		FROM (
			(
				SELECT DISTINCT ON (d.node_id, d.source_id) d.ts, d.node_id, d.source_id, d.jdata_a
				FROM solardatum.da_datum d 
				WHERE d.node_id = ANY(nodes)
					AND d.source_id = ANY(sources)
					AND d.ts <= ts_min
					AND d.ts > ts_min - tolerance
				ORDER BY d.node_id, d.source_id, d.ts DESC
			)
			UNION
			(
				SELECT DISTINCT ON (aux.node_id, aux.source_id) aux.ts, aux.node_id, aux.source_id, aux.jdata_as AS jdata_a
				FROM solardatum.da_datum_aux aux
				WHERE aux.atype = 'Reset'::solardatum.da_datum_aux_type
					AND aux.node_id = ANY(nodes)
					AND aux.source_id = ANY(sources)
					AND aux.ts <= ts_min
					AND aux.ts > ts_min - tolerance
				ORDER BY aux.node_id, aux.source_id, aux.ts DESC
			)
		) d
		ORDER BY d.node_id, d.source_id, d.ts DESC
	)
	-- find records closest to, but not after max date (could be same as latest_before_start or earliest_after_start)
	-- also considering reset records, using their FINAL sample value
	, latest_before_end AS (
		SELECT DISTINCT ON (d.node_id, d.source_id) d.*
		FROM (
			(
				SELECT DISTINCT ON (d.node_id, d.source_id) d.ts, d.node_id, d.source_id, d.jdata_a
				FROM solardatum.da_datum d
				WHERE d.node_id = ANY(nodes)
					AND d.source_id = ANY(sources)
					AND d.ts <= ts_max
					AND d.ts > ts_max - tolerance
				ORDER BY d.node_id, d.source_id, d.ts DESC
			)
			UNION
			(
				SELECT DISTINCT ON (aux.node_id, aux.source_id) aux.ts, aux.node_id, aux.source_id, aux.jdata_af AS jdata_a
				FROM solardatum.da_datum_aux aux
				WHERE aux.atype = 'Reset'::solardatum.da_datum_aux_type
					AND aux.node_id = ANY(nodes)
					AND aux.source_id = ANY(sources)
					AND aux.ts <= ts_max
					AND aux.ts > ts_max - tolerance
				ORDER BY aux.node_id, aux.source_id, aux.ts DESC
			)
		) d
		ORDER BY d.node_id, d.source_id, d.ts DESC
	)
	-- narrow data to [start, final] pairs of rows by node,source by choosing
	-- latest_before_start in preference to earliest_after_start
	, d AS (
		SELECT * FROM latest_before_start
		UNION
		SELECT * FROM latest_before_end
	)
	-- begin search for reset records WITHIN [start, final] date ranges via table of found [start, final] dates
	, ranges AS (
		SELECT node_id
			, source_id
			, min(ts) AS sdate
			, max(ts) AS edate
		FROM d
		GROUP BY node_id, source_id
	)
	-- find all reset records per node, source within [start, final] date ranges, producing pairs
	-- of rows for each matching record, of [FINAL, STARTING] data
	, resets AS (
		SELECT aux.ts - unnest(ARRAY['1 millisecond','0'])::interval AS ts
			, aux.node_id
			, aux.source_id
			, unnest(ARRAY[aux.jdata_af, aux.jdata_as]) AS jdata_a
		FROM ranges
		INNER JOIN solardatum.da_datum_aux aux ON aux.node_id = ranges.node_id AND aux.source_id = ranges.source_id
			AND aux.ts > ranges.sdate AND aux.ts < ranges.edate
		WHERE atype = 'Reset'::solardatum.da_datum_aux_type
	)
	-- combine [start, final] pairs with reset pairs
	, combined AS (
		SELECT * FROM d
		UNION
		SELECT * FROM resets
	)
	-- calculate difference by node,source, of {start[, resetFinal1, resetStart1, ...], final}
	SELECT min(d.ts) AS ts_start,
		max(d.ts) AS ts_end,
		min(nlt.time_zone) AS time_zone,
		d.node_id,
		d.source_id,
		solarcommon.jsonb_diffsum_object(d.jdata_a ORDER BY d.ts) AS jdata_a
	FROM combined d
	INNER JOIN solarnet.node_local_time nlt ON nlt.node_id = d.node_id
	GROUP BY d.node_id, d.source_id
	ORDER BY d.node_id, d.source_id
$$;


ALTER FUNCTION solardatum.calculate_datum_diff(nodes bigint[], sources text[], ts_min timestamp with time zone, ts_max timestamp with time zone, tolerance interval) OWNER TO solarnet;

--
-- Name: calculate_datum_diff_local(bigint[], text[], timestamp without time zone, timestamp without time zone, interval); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.calculate_datum_diff_local(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone, tolerance interval DEFAULT '1 mon'::interval) RETURNS TABLE(ts_start timestamp with time zone, ts_end timestamp with time zone, time_zone text, node_id bigint, source_id character varying, jdata_a jsonb)
    LANGUAGE sql STABLE
    AS $$
	-- generate rows of nodes grouped by time zone, get absolute start/end dates for all nodes
	-- but grouped into as few rows as possible to minimize subsequent query times
	WITH tz AS (
		SELECT time_zone, ts_start AS sdate, ts_end AS edate, node_ids AS nodes, source_ids AS sources
		FROM solarnet.node_source_time_ranges_local(nodes, sources, ts_min, ts_max)
	)
	-- find records closest to, but not after, min date
	-- also considering reset records, using their STARTING sample value
	, latest_before_start AS (
		SELECT DISTINCT ON (d.node_id, d.source_id) d.*
		FROM (
			(
				SELECT DISTINCT ON (d.node_id, d.source_id) tz.time_zone, d.ts, d.node_id, d.source_id, d.jdata_a
				FROM tz
				INNER JOIN solardatum.da_datum d ON d.node_id = ANY(tz.nodes) AND d.source_id = ANY(tz.sources)
				WHERE d.node_id = ANY(tz.nodes)
					AND d.source_id = ANY(tz.sources)
					AND d.ts <= tz.sdate
					AND d.ts > tz.sdate - tolerance
				ORDER BY d.node_id, d.source_id, d.ts DESC
			)
			UNION
			(
				SELECT DISTINCT ON (tz.time_zone, aux.node_id, aux.source_id)
					tz.time_zone, aux.ts, aux.node_id, aux.source_id, aux.jdata_as AS jdata_a
				FROM tz
				INNER JOIN solardatum.da_datum_aux aux ON aux.node_id = ANY(tz.nodes) AND aux.source_id = ANY(tz.sources)
				WHERE aux.atype = 'Reset'::solardatum.da_datum_aux_type
					AND aux.ts < tz.sdate
				ORDER BY tz.time_zone, aux.node_id, aux.source_id, aux.ts DESC
			)
		) d
		ORDER BY d.node_id, d.source_id, d.ts DESC
	)
	-- find records closest to, but not after max date (could be same as latest_before_start or earliest_after_start)
	-- also considering reset records, using their FINAL sample value
	, latest_before_end AS (
		SELECT DISTINCT ON (d.node_id, d.source_id) d.*
		FROM (
			(
				SELECT DISTINCT ON (d.node_id, d.source_id) tz.time_zone, d.ts, d.node_id, d.source_id, d.jdata_a
				FROM tz
				INNER JOIN solardatum.da_datum d ON d.node_id = ANY(tz.nodes) AND d.source_id = ANY(tz.sources)
				WHERE d.node_id = ANY(tz.nodes)
					AND d.source_id = ANY(tz.sources)
					AND d.ts <= tz.edate
					AND d.ts > tz.edate - tolerance
				ORDER BY d.node_id, d.source_id, d.ts DESC
			)
			UNION
			(
				SELECT DISTINCT ON (tz.time_zone, aux.node_id, aux.source_id)
					tz.time_zone, aux.ts, aux.node_id, aux.source_id, aux.jdata_af AS jdata_a
				FROM tz
				INNER JOIN solardatum.da_datum_aux aux ON aux.node_id = ANY(tz.nodes) AND aux.source_id = ANY(tz.sources)
				WHERE aux.atype = 'Reset'::solardatum.da_datum_aux_type
					AND aux.ts < tz.edate
				ORDER BY tz.time_zone, aux.node_id, aux.source_id, aux.ts DESC
			)
		) d
		ORDER BY d.node_id, d.source_id, d.ts DESC
	)
	-- narrow data to [start, final] pairs of rows by node,source by choosing
	-- latest_before_start in preference to earliest_after_start
	, d AS (
		SELECT * FROM latest_before_start
		UNION
		SELECT * FROM latest_before_end
	)
	-- begin search for reset records WITHIN [start, final] date ranges via table of found [start, final] dates
	, ranges AS (
		SELECT time_zone
			, node_id
			, source_id
			, min(ts) AS sdate
			, max(ts) AS edate
		FROM d
		GROUP BY time_zone, node_id, source_id
	)
	-- find all reset records per node, source within [start, final] date ranges, producing pairs
	-- of rows for each matching record, of [FINAL, STARTING] data
	, resets AS (
		SELECT ranges.time_zone
			, aux.ts - unnest(ARRAY['1 millisecond','0'])::interval AS ts
			, aux.node_id
			, aux.source_id
			, unnest(ARRAY[aux.jdata_af, aux.jdata_as]) AS jdata_a
		FROM ranges
		INNER JOIN solardatum.da_datum_aux aux ON aux.node_id = ranges.node_id AND aux.source_id = ranges.source_id
			AND aux.ts > ranges.sdate AND aux.ts < ranges.edate
		WHERE atype = 'Reset'::solardatum.da_datum_aux_type
	)
	-- combine [start, final] pairs with reset pairs
	, combined AS (
		SELECT * FROM d
		UNION
		SELECT * FROM resets
	)
	-- calculate difference by node,source, of {start[, resetFinal1, resetStart1, ...], final}
	SELECT min(d.ts) AS ts_start,
		max(d.ts) AS ts_end,
		min(d.time_zone) AS time_zone,
		d.node_id,
		d.source_id,
		solarcommon.jsonb_diffsum_object(d.jdata_a ORDER BY d.ts) AS jdata_a
	FROM combined d
	GROUP BY d.node_id, d.source_id
	ORDER BY d.node_id, d.source_id
$$;


ALTER FUNCTION solardatum.calculate_datum_diff_local(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone, tolerance interval) OWNER TO solarnet;

--
-- Name: calculate_datum_diff_over(bigint[], text[], timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.calculate_datum_diff_over(nodes bigint[], sources text[], ts_min timestamp with time zone, ts_max timestamp with time zone) RETURNS TABLE(ts_start timestamp with time zone, ts_end timestamp with time zone, time_zone text, node_id bigint, source_id character varying, jdata_a jsonb)
    LANGUAGE sql STABLE
    AS $$
	-- find records closest to, but not after, min date
	-- also considering reset records, using their STARTING sample value
	WITH latest_before_start AS (
		SELECT DISTINCT ON (d.node_id, d.source_id) d.*
		FROM (
			SELECT d.ts, d.node_id, d.source_id, d.jdata_a
			FROM  solardatum.find_latest_before(nodes, sources, ts_min) dates
			INNER JOIN solardatum.da_datum d ON d.ts = dates.ts AND d.node_id = dates.node_id AND d.source_id = dates.source_id
			UNION
			SELECT DISTINCT ON (node_id, source_id) ts, node_id, source_id, jdata_as AS jdata_a
			FROM solardatum.da_datum_aux
			WHERE atype = 'Reset'::solardatum.da_datum_aux_type
				AND node_id = ANY(nodes)
				AND source_id = ANY(sources)
				AND ts < ts_min
			ORDER BY node_id, source_id, ts DESC
		) d
		ORDER BY d.node_id, d.source_id, d.ts DESC
	)
	-- in case no data before min date, find closest to min date or after
	-- also considering reset records, using their STARTING sample value
	, earliest_after_start AS (
		SELECT DISTINCT ON (d.node_id, d.source_id) d.*
		FROM (
			(
				SELECT d.ts, d.node_id, d.source_id, d.jdata_a
				FROM solardatum.find_earliest_after(nodes, sources, ts_min) dates
				INNER JOIN solardatum.da_datum d ON d.ts = dates.ts AND d.node_id = dates.node_id AND d.source_id = dates.source_id
			)
			UNION
			(
				SELECT DISTINCT ON (node_id, source_id) ts, node_id, source_id, jdata_as AS jdata_a
				FROM solardatum.da_datum_aux
				WHERE atype = 'Reset'::solardatum.da_datum_aux_type
					AND node_id = ANY(nodes)
					AND source_id = ANY(sources)
					AND ts >= ts_min
				ORDER BY node_id, source_id, ts
			)
		) d
		ORDER BY d.node_id, d.source_id, d.ts
	)
	-- find records closest to, but not after max date (could be same as latest_before_start or earliest_after_start)
	-- also considering reset records, using their FINAL sample value
	, latest_before_end AS (
		SELECT DISTINCT ON (d.node_id, d.source_id) d.*
		FROM (
			(
				SELECT d.ts, d.node_id, d.source_id, d.jdata_a
				FROM solardatum.find_latest_before(nodes, sources, ts_max) dates
				INNER JOIN solardatum.da_datum d ON d.ts = dates.ts AND d.node_id = dates.node_id AND d.source_id = dates.source_id
			)
			UNION
			(
				SELECT DISTINCT ON (node_id, source_id) ts, node_id, source_id, jdata_af AS jdata_a
				FROM solardatum.da_datum_aux
				WHERE atype = 'Reset'::solardatum.da_datum_aux_type
					AND node_id = ANY(nodes)
					AND source_id = ANY(sources)
					AND ts < ts_max
				ORDER BY node_id, source_id, ts DESC
			)
		) d
		ORDER BY d.node_id, d.source_id, d.ts DESC
	)
	-- narrow data to [start, final] pairs of rows by node,source by choosing
	-- latest_before_start in preference to earliest_after_start
	, d AS (
		SELECT * FROM (
			SELECT DISTINCT ON (d.node_id, d.source_id) d.*
			FROM (
				SELECT * FROM latest_before_start
				UNION
				SELECT * FROM earliest_after_start
			) d
			ORDER BY d.node_id, d.source_id, d.ts
		) earliest
		UNION 
		SELECT * FROM latest_before_end
	)
	-- begin search for reset records WITHIN [start, final] date ranges via table of found [start, final] dates
	, ranges AS (
		SELECT node_id
			, source_id
			, min(ts) AS sdate
			, max(ts) AS edate
		FROM d
		GROUP BY node_id, source_id
	)
	-- find all reset records per node, source within [start, final] date ranges, producing pairs
	-- of rows for each matching record, of [FINAL, STARTING] data
	, resets AS (
		SELECT aux.ts - unnest(ARRAY['1 millisecond','0'])::interval AS ts
			, aux.node_id
			, aux.source_id
			, unnest(ARRAY[aux.jdata_af, aux.jdata_as]) AS jdata_a
		FROM ranges
		INNER JOIN solardatum.da_datum_aux aux ON aux.node_id = ranges.node_id AND aux.source_id = ranges.source_id
			AND aux.ts > ranges.sdate AND aux.ts < ranges.edate
		WHERE atype = 'Reset'::solardatum.da_datum_aux_type
	)
	-- combine [start, final] pairs with reset pairs
	, combined AS (
		SELECT * FROM d
		UNION
		SELECT * FROM resets
	)
	-- calculate difference by node,source, of {start[, resetFinal1, resetStart1, ...], final}
	SELECT min(d.ts) AS ts_start,
		max(d.ts) AS ts_end,
		min(COALESCE(nlt.time_zone, 'UTC')) AS time_zone,
		d.node_id,
		d.source_id,
		solarcommon.jsonb_diffsum_object(d.jdata_a ORDER BY d.ts) AS jdata_a
	FROM combined d
	LEFT OUTER JOIN solarnet.node_local_time nlt ON nlt.node_id = d.node_id
	GROUP BY d.node_id, d.source_id
	ORDER BY d.node_id, d.source_id
$$;


ALTER FUNCTION solardatum.calculate_datum_diff_over(nodes bigint[], sources text[], ts_min timestamp with time zone, ts_max timestamp with time zone) OWNER TO solarnet;

--
-- Name: calculate_datum_diff_over(bigint, text, timestamp with time zone, timestamp with time zone, interval); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.calculate_datum_diff_over(node bigint, source text, ts_min timestamp with time zone, ts_max timestamp with time zone, tolerance interval DEFAULT '3 mons'::interval) RETURNS TABLE(ts_start timestamp with time zone, ts_end timestamp with time zone, time_zone text, node_id bigint, source_id character varying, jdata jsonb)
    LANGUAGE sql STABLE ROWS 1
    AS $$
	WITH latest_before_start AS (
		SELECT ts, node_id, source_id, jdata_a FROM (
			(
				-- find latest before
				SELECT ts, node_id, source_id, jdata_a, 0 AS rr
				FROM solardatum.da_datum
				WHERE node_id = node
					AND source_id = source
					AND ts < ts_min
					AND ts >= ts_min - tolerance
				ORDER BY ts DESC 
				LIMIT 1
			)
			UNION
			(
				-- find latest before reset
				SELECT ts, node_id, source_id, jdata_as AS jdata_a, 1 AS rr
				FROM solardatum.da_datum_aux
				WHERE atype = 'Reset'::solardatum.da_datum_aux_type
					AND node_id = node
					AND source_id = source
					AND ts < ts_min
					AND ts >= ts_min - tolerance
				ORDER BY ts DESC
				LIMIT 1
			)
		) d
		-- add order by rr so that when datum & reset have equivalent ts, reset has priority
		ORDER BY d.ts DESC, rr DESC
		LIMIT 1
	)
	, earliest_after_start AS (
		SELECT ts, node_id, source_id, jdata_a FROM (
			(
				-- find earliest on/after
				SELECT ts, node_id, source_id, jdata_a, 0 AS rr
				FROM solardatum.da_datum
				WHERE node_id = node
					AND source_id = source
					AND ts >= ts_min
					AND ts < ts_max
				ORDER BY ts 
				LIMIT 1
			)
			UNION ALL
			(
				-- find earliest on/after reset
				SELECT ts, node_id, source_id, jdata_as AS jdata_a, 1 AS rr
				FROM solardatum.da_datum_aux
				WHERE atype = 'Reset'::solardatum.da_datum_aux_type
					AND node_id = node
					AND source_id = source
					AND ts >= ts_min
					AND ts < ts_max
				ORDER BY ts
				LIMIT 1
			)
		) d
		-- add order by rr so that when datum & reset have equivalent ts, reset has priority
		ORDER BY d.ts, rr DESC
		LIMIT 1
	)
	, latest_before_end AS (
		SELECT ts, node_id, source_id, jdata_a FROM (
			(
				-- find latest before
				SELECT ts, node_id, source_id, jdata_a, 0 AS rr
				FROM solardatum.da_datum
				WHERE node_id = node
					AND source_id = source
					AND ts < ts_max
					AND ts >= ts_min
				ORDER BY ts DESC 
				LIMIT 1
			)
			UNION ALL
			(
				-- find latest before reset
				SELECT ts, node_id, source_id, jdata_af AS jdata_a, 1 AS rr
				FROM solardatum.da_datum_aux
				WHERE atype = 'Reset'::solardatum.da_datum_aux_type
					AND node_id = node
					AND source_id = source
					AND ts < ts_max
					AND ts >= ts_min
				ORDER BY ts DESC
				LIMIT 1
			)
		) d
		-- add order by rr so that when datum & reset have equivalent ts, reset has priority
		ORDER BY d.ts DESC, rr DESC
		LIMIT 1
	)
	, d AS (
		(
			SELECT *
			FROM (
				SELECT * FROM latest_before_start
				UNION
				SELECT * FROM earliest_after_start
			) d
			ORDER BY d.ts
			LIMIT 1
		)
		UNION ALL
		(
			SELECT * FROM latest_before_end
		)
	)
	, ranges AS (
		SELECT min(ts) AS sdate
			, max(ts) AS edate
		FROM d
	)
	, combined AS (
		SELECT * FROM d
	
		UNION ALL
		SELECT aux.ts - unnest(ARRAY['1 millisecond','0'])::interval AS ts
			, aux.node_id
			, aux.source_id
			, unnest(ARRAY[aux.jdata_af, aux.jdata_as]) AS jdata_a
		FROM ranges, solardatum.da_datum_aux aux 
		WHERE atype = 'Reset'::solardatum.da_datum_aux_type
			AND aux.node_id = node 
			AND aux.source_id = source
			AND aux.ts > ranges.sdate
			AND aux.ts < ranges.edate
	)
	-- calculate difference by node,source, of {start[, resetFinal1, resetStart1, ...], final}
	SELECT min(d.ts) AS ts_start,
		max(d.ts) AS ts_end,
		min(COALESCE(nlt.time_zone, 'UTC')) AS time_zone,
		d.node_id,
		d.source_id,
		solarcommon.jsonb_diffsum_jdata(d.jdata_a ORDER BY d.ts) AS jdata
	FROM combined d
	LEFT OUTER JOIN solarnet.node_local_time nlt ON nlt.node_id = d.node_id
	GROUP BY d.node_id, d.source_id
$$;


ALTER FUNCTION solardatum.calculate_datum_diff_over(node bigint, source text, ts_min timestamp with time zone, ts_max timestamp with time zone, tolerance interval) OWNER TO solarnet;

--
-- Name: calculate_datum_diff_over_local(bigint[], text[], timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.calculate_datum_diff_over_local(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) RETURNS TABLE(ts_start timestamp with time zone, ts_end timestamp with time zone, time_zone text, node_id bigint, source_id character varying, jdata_a jsonb)
    LANGUAGE sql STABLE
    AS $$
	-- generate rows of nodes grouped by time zone, get absolute start/end dates for all nodes
	-- but grouped into as few rows as possible to minimize subsequent query times
	WITH tz AS (
		SELECT time_zone, ts_start AS sdate, ts_end AS edate, node_ids AS nodes, source_ids AS sources
		FROM solarnet.node_source_time_ranges_local(nodes, sources, ts_min, ts_max)
	)
	-- find records closest to, but not after, min date
	-- also considering reset records, using their STARTING sample value
	, latest_before_start AS (
		SELECT DISTINCT ON (d.node_id, d.source_id) d.*
		FROM (
			(
				SELECT tz.time_zone, d.ts, d.node_id, d.source_id, d.jdata_a
				FROM tz
				INNER JOIN solardatum.find_latest_before(tz.nodes, tz.sources, tz.sdate) dates ON dates.node_id = ANY(tz.nodes) AND dates.source_id = ANY(tz.sources)
				INNER JOIN solardatum.da_datum d ON d.ts = dates.ts AND d.node_id = dates.node_id AND d.source_id = dates.source_id
			)
			UNION
			(
				SELECT DISTINCT ON (tz.time_zone, aux.node_id, aux.source_id)
					tz.time_zone, aux.ts, aux.node_id, aux.source_id, aux.jdata_as AS jdata_a
				FROM tz
				INNER JOIN solardatum.da_datum_aux aux ON aux.node_id = ANY(tz.nodes) AND aux.source_id = ANY(tz.sources)
				WHERE aux.atype = 'Reset'::solardatum.da_datum_aux_type
					AND aux.ts < tz.sdate
				ORDER BY tz.time_zone, aux.node_id, aux.source_id, aux.ts DESC
			)
		) d
		ORDER BY d.node_id, d.source_id, d.ts DESC
	)
	-- in case no data before min date, find closest to min date or after
	-- also considering reset records, using their STARTING sample value
	, earliest_after_start AS (
		SELECT DISTINCT ON (d.node_id, d.source_id) d.*
		FROM (
			(
				SELECT tz.time_zone, d.ts, d.node_id, d.source_id, d.jdata_a
				FROM tz
				INNER JOIN solardatum.find_earliest_after(tz.nodes, tz.sources, tz.sdate) dates ON dates.node_id = ANY(tz.nodes) AND dates.source_id = ANY(tz.sources)
				INNER JOIN solardatum.da_datum d ON d.ts = dates.ts AND d.node_id = dates.node_id AND d.source_id = dates.source_id
			)
			UNION
			(
				SELECT DISTINCT ON (tz.time_zone, aux.node_id, aux.source_id)
					tz.time_zone, aux.ts, aux.node_id, aux.source_id, aux.jdata_as AS jdata_a
				FROM tz
				INNER JOIN solardatum.da_datum_aux aux ON aux.node_id = ANY(tz.nodes) AND aux.source_id = ANY(tz.sources)
				WHERE aux.atype = 'Reset'::solardatum.da_datum_aux_type
					AND aux.ts >= tz.sdate
				ORDER BY tz.time_zone, aux.node_id, aux.source_id, aux.ts
			)
		) d
		ORDER BY d.node_id, d.source_id, d.ts
	)
	-- find records closest to, but not after max date (could be same as latest_before_start or earliest_after_start)
	-- also considering reset records, using their FINAL sample value
	, latest_before_end AS (
		SELECT DISTINCT ON (d.node_id, d.source_id) d.*
		FROM (
			(
				SELECT tz.time_zone, d.ts, d.node_id, d.source_id, d.jdata_a
				FROM tz
				INNER JOIN solardatum.find_latest_before(tz.nodes, tz.sources, tz.edate) dates ON dates.node_id = ANY(tz.nodes) AND dates.source_id = ANY(tz.sources)
				INNER JOIN solardatum.da_datum d ON d.ts = dates.ts AND d.node_id = dates.node_id AND d.source_id = dates.source_id
			)
			UNION
			(
				SELECT DISTINCT ON (tz.time_zone, aux.node_id, aux.source_id)
					tz.time_zone, aux.ts, aux.node_id, aux.source_id, aux.jdata_af AS jdata_a
				FROM tz
				INNER JOIN solardatum.da_datum_aux aux ON aux.node_id = ANY(tz.nodes) AND aux.source_id = ANY(tz.sources)
				WHERE aux.atype = 'Reset'::solardatum.da_datum_aux_type
					AND aux.ts < tz.edate
				ORDER BY tz.time_zone, aux.node_id, aux.source_id, aux.ts DESC
			)
		) d
		ORDER BY d.node_id, d.source_id, d.ts DESC
	)
	-- narrow data to [start, final] pairs of rows by node,source by choosing
	-- latest_before_start in preference to earliest_after_start
	, d AS (
		SELECT * FROM (
			SELECT DISTINCT ON (d.node_id, d.source_id) d.*
			FROM (
				SELECT * FROM latest_before_start
				UNION
				SELECT * FROM earliest_after_start
			) d
			ORDER BY d.node_id, d.source_id, d.ts
		) earliest
		UNION 
		SELECT * FROM latest_before_end
	)
	-- begin search for reset records WITHIN [start, final] date ranges via table of found [start, final] dates
	, ranges AS (
		SELECT time_zone
			, node_id
			, source_id
			, min(ts) AS sdate
			, max(ts) AS edate
		FROM d
		GROUP BY time_zone, node_id, source_id
	)
	-- find all reset records per node, source within [start, final] date ranges, producing pairs
	-- of rows for each matching record, of [FINAL, STARTING] data
	, resets AS (
		SELECT ranges.time_zone
			, aux.ts - unnest(ARRAY['1 millisecond','0'])::interval AS ts
			, aux.node_id
			, aux.source_id
			, unnest(ARRAY[aux.jdata_af, aux.jdata_as]) AS jdata_a
		FROM ranges
		INNER JOIN solardatum.da_datum_aux aux ON aux.node_id = ranges.node_id AND aux.source_id = ranges.source_id
			AND aux.ts > ranges.sdate AND aux.ts < ranges.edate
		WHERE atype = 'Reset'::solardatum.da_datum_aux_type
	)
	-- combine [start, final] pairs with reset pairs
	, combined AS (
		SELECT * FROM d
		UNION
		SELECT * FROM resets
	)
	-- calculate difference by node,source, of {start[, resetFinal1, resetStart1, ...], final}
	SELECT min(d.ts) AS ts_start,
		max(d.ts) AS ts_end,
		min(d.time_zone) AS time_zone,
		d.node_id,
		d.source_id,
		solarcommon.jsonb_diffsum_object(d.jdata_a ORDER BY d.ts) AS jdata_a
	FROM combined d
	GROUP BY d.node_id, d.source_id
	ORDER BY d.node_id, d.source_id
$$;


ALTER FUNCTION solardatum.calculate_datum_diff_over_local(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) OWNER TO solarnet;

--
-- Name: cleanse_datum(bigint[], text[]); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.cleanse_datum(nodes bigint[], sources text[]) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
	nodes_str TEXT := array_to_string(nodes, ',');
	sources_str TEXT := array_to_string(sources, ',');
    num_rows BIGINT := 0;
BEGIN
	-- delete from raw data table
	DELETE FROM solardatum.da_datum
	WHERE node_id = ANY(nodes)
		AND source_id = ANY(sources);
	GET DIAGNOSTICS num_rows = ROW_COUNT;
	RAISE NOTICE 'Deleted % raw datum rows matching nodes %, sources %', num_rows, nodes_str, sources_str;
	RETURN num_rows;
END
$$;


ALTER FUNCTION solardatum.cleanse_datum(nodes bigint[], sources text[]) OWNER TO solarnet;

--
-- Name: datum_prop_count(jsonb); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.datum_prop_count(jdata jsonb) RETURNS integer
    LANGUAGE plv8 IMMUTABLE
    AS $$
'use strict';
var count = 0, prop, val;
if ( jdata ) {
	for ( prop in jdata ) {
		val = jdata[prop];
		if ( Array.isArray(val) ) {
			count += val.length;
		} else {
			count += Object.keys(val).length;
		}
	}
}
return count;
$$;


ALTER FUNCTION solardatum.datum_prop_count(jdata jsonb) OWNER TO solarnet;

--
-- Name: datum_record_counts(bigint[], text[], timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.datum_record_counts(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) RETURNS TABLE(query_date timestamp with time zone, datum_count bigint, datum_hourly_count integer, datum_daily_count integer, datum_monthly_count integer)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
	all_source_ids boolean := sources IS NULL OR array_length(sources, 1) < 1;
	start_date timestamp := COALESCE(ts_min, CURRENT_TIMESTAMP);
	end_date timestamp := COALESCE(ts_max, CURRENT_TIMESTAMP);
BEGIN
	-- raw count
	WITH nlt AS (
		SELECT time_zone, ts_start, ts_end, node_ids, source_ids
		FROM solarnet.node_source_time_ranges_local(nodes, sources, start_date, end_date)
	)
	SELECT count(*)
	FROM solardatum.da_datum d, nlt
	WHERE 
		d.ts >= nlt.ts_start
		AND d.ts < nlt.ts_end
		AND d.node_id = ANY(nlt.node_ids)
		AND (all_source_ids OR d.source_id = ANY(nlt.source_ids))
	INTO datum_count;

	-- count hourly data
	WITH nlt AS (
		SELECT time_zone, ts_start, ts_end, node_ids, source_ids
		FROM solarnet.node_source_time_ranges_local(nodes, sources, start_date, end_date)
	)
	SELECT count(*)
	FROM solaragg.agg_datum_hourly d, nlt
	WHERE 
		d.ts_start >= nlt.ts_start
		AND d.ts_start < date_trunc('hour', nlt.ts_end)
		AND d.node_id = ANY(nlt.node_ids)
		AND (all_source_ids OR d.source_id = ANY(nlt.source_ids))
	INTO datum_hourly_count;

	-- count daily data
	WITH nlt AS (
		SELECT time_zone, ts_start, ts_end, node_ids, source_ids
		FROM solarnet.node_source_time_ranges_local(nodes, sources, start_date, end_date)
	)
	SELECT count(*)
	FROM solaragg.agg_datum_daily d, nlt
	WHERE 
		d.ts_start >= nlt.ts_start
		AND d.ts_start < date_trunc('day', nlt.ts_end)
		AND d.node_id = ANY(nlt.node_ids)
		AND (all_source_ids OR d.source_id = ANY(nlt.source_ids))
	INTO datum_daily_count;

	-- count daily data
	WITH nlt AS (
		SELECT time_zone, ts_start, ts_end, node_ids, source_ids
		FROM solarnet.node_source_time_ranges_local(nodes, sources, start_date, end_date)
	)
	SELECT count(*)
	FROM solaragg.agg_datum_monthly d, nlt
	WHERE 
		d.ts_start >= nlt.ts_start
		AND d.ts_start < date_trunc('month', nlt.ts_end)
		AND d.node_id = ANY(nlt.node_ids)
		AND (all_source_ids OR d.source_id = ANY(nlt.source_ids))
	INTO datum_monthly_count;

	query_date = CURRENT_TIMESTAMP;
	RETURN NEXT;
END
$$;


ALTER FUNCTION solardatum.datum_record_counts(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) OWNER TO solarnet;

--
-- Name: datum_record_counts_for_filter(jsonb); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.datum_record_counts_for_filter(jfilter jsonb) RETURNS TABLE(query_date timestamp with time zone, datum_count bigint, datum_hourly_count integer, datum_daily_count integer, datum_monthly_count integer)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
	node_ids bigint[] := solarcommon.jsonb_array_to_bigint_array(jfilter->'nodeIds');
	source_ids text[] := solarcommon.json_array_to_text_array(jfilter->'sourceIds');
	ts_min timestamp := jfilter->>'localStartDate';
	ts_max timestamp := jfilter->>'localEndDate';
BEGIN
	RETURN QUERY
	SELECT * FROM solardatum.datum_record_counts(node_ids, source_ids, ts_min, ts_max);
END
$$;


ALTER FUNCTION solardatum.datum_record_counts_for_filter(jfilter jsonb) OWNER TO solarnet;

--
-- Name: delete_datum(bigint[], text[], timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.delete_datum(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
	all_source_ids boolean := sources IS NULL OR array_length(sources, 1) < 1;
	start_date timestamp := COALESCE(ts_min, CURRENT_TIMESTAMP);
	end_date timestamp := COALESCE(ts_max, CURRENT_TIMESTAMP);
	total_count bigint := 0;
BEGIN
	WITH nlt AS (
		SELECT time_zone, ts_start, ts_end, node_ids, source_ids
		FROM solarnet.node_source_time_ranges_local(nodes, sources, start_date, end_date)
	)
	DELETE FROM solardatum.da_datum d
	USING nlt
	WHERE 
		d.ts >= nlt.ts_start
		AND d.ts < nlt.ts_end
		AND d.node_id = ANY(nlt.node_ids)
		AND (all_source_ids OR d.source_id = ANY(nlt.source_ids));
	GET DIAGNOSTICS total_count = ROW_COUNT;

	RETURN total_count;
END
$$;


ALTER FUNCTION solardatum.delete_datum(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) OWNER TO solarnet;

--
-- Name: delete_datum_for_filter(jsonb); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.delete_datum_for_filter(jfilter jsonb) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
	node_ids bigint[] := solarcommon.jsonb_array_to_bigint_array(jfilter->'nodeIds');
	source_ids text[] := solarcommon.json_array_to_text_array(jfilter->'sourceIds');
	ts_min timestamp := jfilter->>'localStartDate';
	ts_max timestamp := jfilter->>'localEndDate';
	total_count bigint := 0;
BEGIN
	SELECT solardatum.delete_datum(node_ids, source_ids, ts_min, ts_max) INTO total_count;
	RETURN total_count;
END
$$;


ALTER FUNCTION solardatum.delete_datum_for_filter(jfilter jsonb) OWNER TO solarnet;

--
-- Name: find_available_sources(bigint[]); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_available_sources(nodes bigint[]) RETURNS TABLE(node_id bigint, source_id text)
    LANGUAGE sql STABLE ROWS 50
    AS $$
	SELECT node_id, source_id
	FROM solardatum.da_datum_range
	WHERE node_id = ANY(nodes)
$$;


ALTER FUNCTION solardatum.find_available_sources(nodes bigint[]) OWNER TO solarnet;

--
-- Name: find_available_sources(bigint, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_available_sources(node bigint, st timestamp with time zone, en timestamp with time zone) RETURNS TABLE(source_id text)
    LANGUAGE sql STABLE ROWS 50
    AS $$
	SELECT DISTINCT CAST(d.source_id AS text)
	FROM solaragg.agg_datum_daily d
	WHERE d.node_id = node
		AND d.ts_start >= st
		AND d.ts_start <= en;
$$;


ALTER FUNCTION solardatum.find_available_sources(node bigint, st timestamp with time zone, en timestamp with time zone) OWNER TO solarnet;

--
-- Name: da_datum; Type: TABLE; Schema: solardatum; Owner: solarnet
--

CREATE TABLE solardatum.da_datum (
    ts timestamp with time zone NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    posted timestamp with time zone NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[]
);


ALTER TABLE solardatum.da_datum OWNER TO solarnet;

--
-- Name: find_datum_upto(bigint, text, timestamp with time zone, interval); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_datum_upto(node bigint, source text, ts timestamp with time zone, span interval) RETURNS SETOF solardatum.da_datum
    LANGUAGE sql STABLE
    AS $$
	SELECT d.*
	FROM solardatum.da_datum d
	WHERE d.node_id = node
		AND d.source_id = source
		AND d.ts <= ts
		AND d.ts > ts - span
	ORDER BY d.ts DESC
	LIMIT 1
$$;


ALTER FUNCTION solardatum.find_datum_upto(node bigint, source text, ts timestamp with time zone, span interval) OWNER TO solarnet;

--
-- Name: find_earliest_after(bigint[], text[], timestamp with time zone); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_earliest_after(nodes bigint[], sources text[], ts_min timestamp with time zone) RETURNS TABLE(ts timestamp with time zone, node_id bigint, source_id character varying)
    LANGUAGE sql STABLE
    AS $$
	-- first find min day quickly for each node+source
	WITH min_dates AS (
		SELECT min(ts_start) AS ts_start, node_id, source_id
		FROM solaragg.agg_datum_daily
		WHERE node_id = ANY(nodes)
			AND source_id = ANY(sources)
			AND ts_start >= ts_min
		GROUP BY node_id, source_id
	)
	, -- then group by day (start of day), so we can batch day+node+source queries together
	min_date_groups AS (
		SELECT ts_start AS ts_start, array_agg(DISTINCT node_id) AS nodes, array_agg(DISTINCT source_id) AS sources
		FROM min_dates
		GROUP BY ts_start
	)
	-- now for each day+node+source find minimum exact date
	SELECT min(d.ts) AS ts, d.node_id, d.source_id
	FROM min_date_groups mdg
	INNER JOIN solardatum.da_datum d ON d.node_id = ANY(mdg.nodes) AND d.source_id = ANY(mdg.sources)
	WHERE d.ts >= ts_min
		AND d.ts <= mdg.ts_start + interval '1 day'
	GROUP BY d.node_id, d.source_id
$$;


ALTER FUNCTION solardatum.find_earliest_after(nodes bigint[], sources text[], ts_min timestamp with time zone) OWNER TO solarnet;

--
-- Name: find_latest_before(bigint[], text[], timestamp with time zone); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_latest_before(nodes bigint[], sources text[], ts_max timestamp with time zone) RETURNS TABLE(ts timestamp with time zone, node_id bigint, source_id character varying)
    LANGUAGE sql STABLE
    AS $$
	-- first find max day quickly for each node+source
	WITH max_dates AS (
		SELECT max(ts_start) AS ts_start, node_id, source_id
		FROM solaragg.agg_datum_daily
		WHERE node_id = ANY(nodes)
			AND source_id = ANY(sources)
			AND ts_start < ts_max
		GROUP BY node_id, source_id
	)
	, -- then group by day (start of day), so we can batch day+node+source queries together
	max_date_groups AS (
		SELECT ts_start AS ts_start, array_agg(DISTINCT node_id) AS nodes, array_agg(DISTINCT source_id) AS sources
		FROM max_dates
		GROUP BY ts_start
	)
	-- now for each day+node+source find maximum exact date
	SELECT max(d.ts) AS ts, d.node_id, d.source_id
	FROM max_date_groups mdg
	INNER JOIN solardatum.da_datum d ON d.node_id = ANY(mdg.nodes) AND d.source_id = ANY(mdg.sources)
	WHERE d.ts >= mdg.ts_start
		AND d.ts <= ts_max
	GROUP BY d.node_id, d.source_id
$$;


ALTER FUNCTION solardatum.find_latest_before(nodes bigint[], sources text[], ts_max timestamp with time zone) OWNER TO solarnet;

--
-- Name: jdata_from_datum(solardatum.da_datum); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.jdata_from_datum(datum solardatum.da_datum) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
	SELECT solarcommon.jdata_from_components(datum.jdata_i, datum.jdata_a, datum.jdata_s, datum.jdata_t);
$$;


ALTER FUNCTION solardatum.jdata_from_datum(datum solardatum.da_datum) OWNER TO solarnet;

--
-- Name: node_seq; Type: SEQUENCE; Schema: solarnet; Owner: solarnet
--

CREATE SEQUENCE solarnet.node_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE solarnet.node_seq OWNER TO solarnet;

--
-- Name: sn_loc; Type: TABLE; Schema: solarnet; Owner: solarnet
--

CREATE TABLE solarnet.sn_loc (
    id bigint DEFAULT nextval('solarnet.solarnet_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    country character varying(2) NOT NULL,
    time_zone character varying(64) NOT NULL,
    region character varying(128),
    state_prov character varying(128),
    locality character varying(128),
    postal_code character varying(32),
    address character varying(256),
    latitude numeric(9,6),
    longitude numeric(9,6),
    fts_default tsvector,
    elevation numeric(8,3)
);


ALTER TABLE solarnet.sn_loc OWNER TO solarnet;

--
-- Name: sn_node; Type: TABLE; Schema: solarnet; Owner: solarnet
--

CREATE TABLE solarnet.sn_node (
    node_id bigint DEFAULT nextval('solarnet.node_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    loc_id bigint NOT NULL,
    wloc_id bigint,
    node_name character varying(128)
);


ALTER TABLE solarnet.sn_node OWNER TO solarnet;

--
-- Name: da_datum_data; Type: VIEW; Schema: solardatum; Owner: solarnet
--

CREATE VIEW solardatum.da_datum_data AS
 SELECT d.ts,
    d.node_id,
    d.source_id,
    d.posted,
    solardatum.jdata_from_datum(d.*) AS jdata,
    timezone((COALESCE(l.time_zone, 'UTC'::character varying))::text, d.ts) AS local_date
   FROM ((solardatum.da_datum d
     LEFT JOIN solarnet.sn_node n ON ((n.node_id = d.node_id)))
     LEFT JOIN solarnet.sn_loc l ON ((l.id = n.loc_id)));


ALTER TABLE solardatum.da_datum_data OWNER TO solarnet;

--
-- Name: find_least_recent_direct(bigint); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_least_recent_direct(node bigint) RETURNS SETOF solardatum.da_datum_data
    LANGUAGE sql STABLE ROWS 20
    AS $$
	-- first look for least recent hours, because this more quickly narrows down the time range for each source
	WITH hours AS (
		SELECT min(d.ts_start) as ts_start, d.source_id, node AS node_id
		FROM solaragg.agg_datum_hourly d
		WHERE d. node_id = node
		GROUP BY d.source_id
	)
	-- next find the exact maximum time per source within each found hour, which is an index-only scan so quick
	, mins AS (
		SELECT min(d.ts) AS ts, d.source_id, node AS node_id
		FROM solardatum.da_datum d
		INNER JOIN hours ON d.node_id = hours.node_id AND d.source_id = hours.source_id AND d.ts >= hours.ts_start AND d.ts < hours.ts_start + interval '1 hour'
		GROUP BY d.source_id
	)
	-- finally query the raw data using the exact found timestamps, so loop over each (ts,source) tuple found in mins
	SELECT d.* 
	FROM solardatum.da_datum_data d
	INNER JOIN mins ON mins.node_id = d.node_id AND mins.source_id = d.source_id AND mins.ts = d.ts
	ORDER BY d.source_id ASC
$$;


ALTER FUNCTION solardatum.find_least_recent_direct(node bigint) OWNER TO solarnet;

--
-- Name: find_loc_available_sources(bigint, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_loc_available_sources(loc bigint, st timestamp with time zone DEFAULT NULL::timestamp with time zone, en timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS TABLE(source_id text)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
	loc_tz text;
BEGIN
	IF st IS NOT NULL OR en IS NOT NULL THEN
		-- get the node TZ for local date/time
		SELECT l.time_zone FROM solarnet.sn_loc l
		WHERE l.id = loc
		INTO loc_tz;

		IF NOT FOUND THEN
			RAISE NOTICE 'Loc % has no time zone, will use UTC.', node;
			loc_tz := 'UTC';
		END IF;
	END IF;

	CASE
		WHEN st IS NULL AND en IS NULL THEN
			RETURN QUERY SELECT DISTINCT CAST(d.source_id AS text)
			FROM solaragg.agg_loc_datum_daily d
			WHERE d.loc_id = loc;

		WHEN st IS NULL THEN
			RETURN QUERY SELECT DISTINCT CAST(d.source_id AS text)
			FROM solaragg.agg_loc_datum_daily d
			WHERE d.loc_id = loc
				AND d.ts_start >= CAST(st at time zone loc_tz AS DATE);

		ELSE
			RETURN QUERY SELECT DISTINCT CAST(d.source_id AS text)
			FROM solaragg.agg_loc_datum_daily d
			WHERE d.loc_id = loc
				AND d.ts_start >= CAST(st at time zone loc_tz AS DATE)
				AND d.ts_start <= CAST(en at time zone loc_tz AS DATE);
	END CASE;
END;$$;


ALTER FUNCTION solardatum.find_loc_available_sources(loc bigint, st timestamp with time zone, en timestamp with time zone) OWNER TO solarnet;

--
-- Name: da_loc_datum; Type: TABLE; Schema: solardatum; Owner: solarnet
--

CREATE TABLE solardatum.da_loc_datum (
    ts timestamp with time zone NOT NULL,
    loc_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    posted timestamp with time zone NOT NULL,
    jdata_i jsonb,
    jdata_a jsonb,
    jdata_s jsonb,
    jdata_t text[]
);


ALTER TABLE solardatum.da_loc_datum OWNER TO solarnet;

--
-- Name: jdata_from_datum(solardatum.da_loc_datum); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.jdata_from_datum(datum solardatum.da_loc_datum) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
	SELECT solarcommon.jdata_from_components(datum.jdata_i, datum.jdata_a, datum.jdata_s, datum.jdata_t);
$$;


ALTER FUNCTION solardatum.jdata_from_datum(datum solardatum.da_loc_datum) OWNER TO solarnet;

--
-- Name: da_loc_datum_data; Type: VIEW; Schema: solardatum; Owner: solarnet
--

CREATE VIEW solardatum.da_loc_datum_data AS
 SELECT d.ts,
    d.loc_id,
    d.source_id,
    d.posted,
    solardatum.jdata_from_datum(d.*) AS jdata
   FROM solardatum.da_loc_datum d;


ALTER TABLE solardatum.da_loc_datum_data OWNER TO solarnet;

--
-- Name: find_loc_most_recent(bigint, text[]); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_loc_most_recent(loc bigint, sources text[] DEFAULT NULL::text[]) RETURNS SETOF solardatum.da_loc_datum_data
    LANGUAGE plpgsql STABLE ROWS 20
    AS $$
BEGIN
	IF sources IS NULL OR array_length(sources, 1) < 1 THEN
		RETURN QUERY
		SELECT dd.* FROM solardatum.da_loc_datum_data dd
		INNER JOIN (
			-- to speed up query for sources (which can be very slow when queried directly on da_loc_datum),
			-- we find the most recent hour time slot in agg_loc_datum_hourly, and then join to da_loc_datum with that narrow time range
			WITH days AS (
				SELECT max(d.ts_start) as ts_start, d.source_id FROM solaragg.agg_loc_datum_hourly d
				INNER JOIN (SELECT solardatum.find_loc_available_sources(loc) AS source_id) AS s ON s.source_id = d.source_id
				WHERE d.loc_id = loc
				GROUP BY d.source_id
			)
			SELECT max(d.ts) as ts, d.source_id FROM solardatum.da_loc_datum d
			INNER JOIN days ON days.source_id = d.source_id
			WHERE d.loc_id = loc
				AND d.ts >= days.ts_start
				AND d.ts < days.ts_start + interval '1 hour'
			GROUP BY d.source_id
		) AS r ON r.ts = dd.ts AND r.source_id = dd.source_id AND dd.loc_id = loc
		ORDER BY dd.source_id ASC;
	ELSE
		RETURN QUERY
		SELECT dd.* FROM solardatum.da_loc_datum_data dd
		INNER JOIN (
			WITH days AS (
				SELECT max(d.ts_start) as ts_start, d.source_id FROM solaragg.agg_loc_datum_hourly d
				INNER JOIN (SELECT unnest(sources) AS source_id) AS s ON s.source_id = d.source_id
				WHERE d. loc_id = loc
				GROUP BY d.source_id
			)
			SELECT max(d.ts) as ts, d.source_id FROM solardatum.da_loc_datum d
			INNER JOIN days ON days.source_id = d.source_id
			WHERE d.loc_id = loc
				AND d.ts >= days.ts_start
				AND d.ts < days.ts_start + interval '1 hour'
			GROUP BY d.source_id
		) AS r ON r.ts = dd.ts AND r.source_id = dd.source_id AND dd.loc_id = loc
		ORDER BY dd.source_id ASC;
	END IF;
END;$$;


ALTER FUNCTION solardatum.find_loc_most_recent(loc bigint, sources text[]) OWNER TO solarnet;

--
-- Name: find_loc_reportable_interval(bigint, text); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_loc_reportable_interval(loc bigint, src text DEFAULT NULL::text, OUT ts_start timestamp with time zone, OUT ts_end timestamp with time zone, OUT loc_tz text, OUT loc_tz_offset integer) RETURNS record
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
	CASE
		WHEN src IS NULL THEN
			SELECT min(ts) FROM solardatum.da_loc_datum WHERE loc_id = loc
			INTO ts_start;
		ELSE
			SELECT min(ts) FROM solardatum.da_loc_datum WHERE loc_id = loc AND source_id = src
			INTO ts_start;
	END CASE;

	CASE
		WHEN src IS NULL THEN
			SELECT max(ts) FROM solardatum.da_loc_datum WHERE loc_id = loc
			INTO ts_end;
		ELSE
			SELECT max(ts) FROM solardatum.da_loc_datum WHERE loc_id = loc AND source_id = src
			INTO ts_end;
	END CASE;

	SELECT
		l.time_zone,
		CAST(EXTRACT(epoch FROM z.utc_offset) / 60 AS INTEGER)
	FROM solarnet.sn_loc l
	INNER JOIN pg_timezone_names z ON z.name = l.time_zone
	WHERE l.id = loc
	INTO loc_tz, loc_tz_offset;

	IF NOT FOUND THEN
		loc_tz := 'UTC';
		loc_tz_offset := 0;
	END IF;

END;$$;


ALTER FUNCTION solardatum.find_loc_reportable_interval(loc bigint, src text, OUT ts_start timestamp with time zone, OUT ts_end timestamp with time zone, OUT loc_tz text, OUT loc_tz_offset integer) OWNER TO solarnet;

--
-- Name: find_most_recent(bigint[]); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_most_recent(nodes bigint[]) RETURNS SETOF solardatum.da_datum_data
    LANGUAGE sql STABLE ROWS 100
    AS $$
	SELECT d.*
	FROM  solardatum.da_datum_range mr
	INNER JOIN solardatum.da_datum_data d ON d.node_id = mr.node_id AND d.source_id = mr.source_id AND d.ts = mr.ts_max
	WHERE mr.node_id = ANY(nodes)
	ORDER BY d.node_id, d.source_id
$$;


ALTER FUNCTION solardatum.find_most_recent(nodes bigint[]) OWNER TO solarnet;

--
-- Name: find_most_recent(bigint); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_most_recent(node bigint) RETURNS SETOF solardatum.da_datum_data
    LANGUAGE sql STABLE ROWS 20
    AS $$
	SELECT d.*
	FROM  solardatum.da_datum_range mr
	INNER JOIN solardatum.da_datum_data d ON d.node_id = mr.node_id AND d.source_id = mr.source_id AND d.ts = mr.ts_max
	WHERE mr.node_id = node
	ORDER BY d.source_id
$$;


ALTER FUNCTION solardatum.find_most_recent(node bigint) OWNER TO solarnet;

--
-- Name: find_most_recent(bigint, text[]); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_most_recent(node bigint, sources text[]) RETURNS SETOF solardatum.da_datum_data
    LANGUAGE sql STABLE ROWS 50
    AS $$
	SELECT d.*
	FROM  solardatum.da_datum_range mr
	INNER JOIN solardatum.da_datum_data d ON d.node_id = mr.node_id AND d.source_id = mr.source_id AND d.ts = mr.ts_max
	WHERE mr.node_id = node
		AND mr.source_id = ANY(sources)
	ORDER BY d.source_id
$$;


ALTER FUNCTION solardatum.find_most_recent(node bigint, sources text[]) OWNER TO solarnet;

--
-- Name: find_most_recent_direct(bigint[]); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_most_recent_direct(nodes bigint[]) RETURNS SETOF solardatum.da_datum_data
    LANGUAGE sql STABLE ROWS 100
    AS $$
	SELECT r.*
	FROM (SELECT unnest(nodes) AS node_id) AS n,
	LATERAL (SELECT * FROM solardatum.find_most_recent_direct(n.node_id)) AS r
	ORDER BY r.node_id, r.source_id;
$$;


ALTER FUNCTION solardatum.find_most_recent_direct(nodes bigint[]) OWNER TO solarnet;

--
-- Name: find_most_recent_direct(bigint); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_most_recent_direct(node bigint) RETURNS SETOF solardatum.da_datum_data
    LANGUAGE sql STABLE ROWS 20
    AS $$
	-- first look for most recent hours, because this more quickly narrows down the time range for each source
	WITH hours AS (
		SELECT max(d.ts_start) as ts_start, d.source_id, node AS node_id
		FROM solaragg.agg_datum_hourly d
		WHERE d. node_id = node
		GROUP BY d.source_id
	)
	-- next find the exact maximum time per source within each found hour, which is an index-only scan so quick
	, maxes AS (
		SELECT max(d.ts) AS ts, d.source_id, node AS node_id
		FROM solardatum.da_datum d
		INNER JOIN hours ON d.node_id = hours.node_id AND d.source_id = hours.source_id AND d.ts >= hours.ts_start AND d.ts < hours.ts_start + interval '1 hour'
		GROUP BY d.source_id
	)
	-- finally query the raw data using the exact found timestamps, so loop over each (ts,source) tuple found in maxes
	SELECT d.* 
	FROM solardatum.da_datum_data d
	INNER JOIN maxes ON maxes.node_id = d.node_id AND maxes.source_id = d.source_id AND maxes.ts = d.ts
	ORDER BY d.source_id ASC
$$;


ALTER FUNCTION solardatum.find_most_recent_direct(node bigint) OWNER TO solarnet;

--
-- Name: find_most_recent_direct(bigint, text[]); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_most_recent_direct(node bigint, sources text[]) RETURNS SETOF solardatum.da_datum_data
    LANGUAGE sql STABLE ROWS 50
    AS $$
	-- first look for most recent hours, because this more quickly narrows down the time range for each source
	WITH hours AS (
		SELECT max(d.ts_start) as ts_start, d.source_id, node AS node_id
		FROM solaragg.agg_datum_hourly d
		INNER JOIN (SELECT unnest(sources) AS source_id) AS s ON s.source_id = d.source_id
		WHERE d. node_id = node
		GROUP BY d.source_id
	)
	-- next find the exact maximum time per source within each found hour, which is an index-only scan so quick
	, maxes AS (
		SELECT max(d.ts) AS ts, d.source_id, node AS node_id
		FROM solardatum.da_datum d
		INNER JOIN hours ON d.node_id = hours.node_id AND d.source_id = hours.source_id AND d.ts >= hours.ts_start AND d.ts < hours.ts_start + interval '1 hour'
		GROUP BY d.source_id
	)
	-- finally query the raw data using the exact found timestamps, so loop over each (ts,source) tuple found in maxes
	SELECT d.* 
	FROM solardatum.da_datum_data d
	INNER JOIN maxes ON maxes.node_id = d.node_id AND maxes.source_id = d.source_id AND maxes.ts = d.ts
	ORDER BY d.source_id ASC
$$;


ALTER FUNCTION solardatum.find_most_recent_direct(node bigint, sources text[]) OWNER TO solarnet;

--
-- Name: find_most_recent_test(bigint, text[]); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_most_recent_test(node bigint, sources text[]) RETURNS SETOF solardatum.da_datum_data
    LANGUAGE sql STABLE ROWS 20
    AS $$
	-- first look for most recent hours, because this more quickly narrows down the time range for each source
	WITH hours AS (
		SELECT max(d.ts_start) as ts_start, d.source_id, node AS node_id
		FROM solaragg.agg_datum_hourly d
		INNER JOIN (SELECT unnest(sources) AS source_id) AS s ON s.source_id = d.source_id
		WHERE d. node_id = node
		GROUP BY d.source_id
	)
	-- next find the exact maximum time per source within each found hour, which is an index-only scan so quick
	, maxes AS (
		SELECT max(d.ts) AS ts, d.source_id, node AS node_id
		FROM solardatum.da_datum d
		INNER JOIN hours ON d.node_id = hours.node_id AND d.source_id = hours.source_id AND d.ts >= hours.ts_start AND d.ts < hours.ts_start + interval '1 hour'
		GROUP BY d.source_id
	)
	-- finally query the raw data using the exact found timestamps, so loop over each (ts,source) tuple found in maxes
	SELECT d.* 
	FROM solardatum.da_datum_data d
	INNER JOIN maxes ON maxes.node_id = d.node_id AND maxes.source_id = d.source_id AND maxes.ts = d.ts
	ORDER BY d.source_id ASC
$$;


ALTER FUNCTION solardatum.find_most_recent_test(node bigint, sources text[]) OWNER TO solarnet;

--
-- Name: find_reading_at_1(bigint[], text[], timestamp without time zone, interval); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_reading_at_1(nodes bigint[], sources text[], reading_ts timestamp without time zone, span interval) RETURNS TABLE(ts timestamp with time zone, node_id bigint, source_id text, jdata_i jsonb, jdata_a jsonb)
    LANGUAGE sql STABLE
    AS $$
	WITH t AS (
		SELECT node_id, reading_ts AT TIME ZONE time_zone AS ts
		FROM solarnet.node_local_time
		WHERE node_id = ANY(nodes)
	), slice AS (
		SELECT
			d.ts,
			t.ts AS ts_slot,
			CASE
				WHEN d.ts <= t.ts THEN last_value(d.ts) OVER win
				ELSE first_value(d.ts) OVER win
			END AS slot_ts,
			lead(d.ts) OVER win_full AS next_ts,
			EXTRACT(epoch FROM (t.ts - d.ts))
				/ EXTRACT(epoch FROM (lead(d.ts) OVER win_full - d.ts)) AS weight,
			d.node_id,
			d.source_id,
			d.jdata_i,
			d.jdata_a
		FROM solardatum.da_datum d
		INNER JOIN t ON t.node_id = d.node_id
		WHERE d.node_id = ANY(nodes)
			AND d.source_id = ANY(sources)
			AND d.ts >= t.ts - span
			AND d.ts < t.ts + span
		WINDOW win AS (PARTITION BY d.node_id, d.source_id, CASE WHEN d.ts <= t.ts
			THEN 0 ELSE 1 END ORDER BY d.ts RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING),
			win_full AS (PARTITION BY d.node_id, d.source_id)
		ORDER BY d.node_id, d.source_id, d.ts
	)
	SELECT ts_slot AS ts,
		node_id,
		source_id,
		CASE solarcommon.first(ts ORDER BY ts)
			-- we have exact timestamp (improbable!)
			WHEN ts_slot THEN solarcommon.first(jdata_i ORDER BY ts)

			-- more likely, project prop values based on linear difference between start/end samples
			ELSE solarcommon.jsonb_avg_object(jdata_i)
		END AS jdata_i,
		CASE solarcommon.first(ts ORDER BY ts)
			-- we have exact timestamp (improbable!)
			WHEN ts_slot THEN solarcommon.first(jdata_a ORDER BY ts)

			-- more likely, project prop values based on linear difference between start/end samples
			ELSE solarcommon.jsonb_weighted_proj_object(jdata_a, weight)
		END AS jdata_a
	FROM slice
	WHERE ts = slot_ts
	GROUP BY ts_slot, node_id, source_id
	ORDER BY ts_slot, node_id, source_id
$$;


ALTER FUNCTION solardatum.find_reading_at_1(nodes bigint[], sources text[], reading_ts timestamp without time zone, span interval) OWNER TO solarnet;

--
-- Name: find_reading_at_2(bigint[], text[], timestamp without time zone, interval); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_reading_at_2(nodes bigint[], sources text[], reading_ts timestamp without time zone, span interval) RETURNS TABLE(ts timestamp with time zone, node_id bigint, source_id text, jdata_i jsonb, jdata_a jsonb)
    LANGUAGE sql STABLE
    AS $$
	WITH t AS (
		SELECT node_id, reading_ts AT TIME ZONE time_zone AS ts
		FROM solarnet.node_local_time
		WHERE node_id = ANY(nodes)
	), p AS (
		SELECT DISTINCT ON (d.node_id, d.source_id)
			d.ts,
			d.node_id,
			d.source_id,
			d.jdata_i,
			d.jdata_a
		FROM solardatum.da_datum d
		INNER JOIN t ON t.node_id = d.node_id
		WHERE d.node_id = ANY(nodes)
			AND d.source_id = ANY(sources)
			AND d.ts <= t.ts
			AND d.ts > t.ts - span
		ORDER BY d.node_id, d.source_id, d.ts DESC
	), 	n AS (
		SELECT DISTINCT ON (d.node_id, d.source_id)
			d.ts,
			d.node_id,
			d.source_id,
			d.jdata_i,
			d.jdata_a
		FROM solardatum.da_datum d
		INNER JOIN t ON t.node_id = d.node_id
		WHERE d.node_id = ANY(nodes)
			AND d.source_id = ANY(sources)
			AND d.ts > t.ts
			AND d.ts < t.ts + span
		ORDER BY d.node_id, d.source_id, d.ts
	), d AS (
		SELECT * FROM p
		UNION
		SELECT * FROM n
	), w AS (
		SELECT
			d.ts,
			t.ts AS ts_slot,
			d.node_id,
			d.source_id,
			d.jdata_i,
			d.jdata_a,
			EXTRACT(epoch FROM (t.ts - d.ts))
				/ EXTRACT(epoch FROM (lead(d.ts) OVER win - d.ts)) AS weight
		FROM d
		INNER JOIN t ON t.node_id = d.node_id
		WINDOW win AS (PARTITION BY d.node_id, d.source_id ORDER BY d.ts)
	)
	SELECT ts_slot AS ts,
		node_id,
		source_id,
		CASE solarcommon.first(ts ORDER BY ts)
			-- we have exact timestamp (improbable!)
			WHEN reading_ts THEN solarcommon.first(jdata_i ORDER BY ts)

			-- more likely, project prop values based on linear difference between start/end samples
			ELSE solarcommon.jsonb_avg_object(jdata_i)
		END AS jdata_i,
		CASE solarcommon.first(ts ORDER BY ts)
			-- we have exact timestamp (improbable!)
			WHEN reading_ts THEN solarcommon.first(jdata_a ORDER BY ts)

			-- more likely, project prop values based on linear difference between start/end samples
			ELSE solarcommon.jsonb_weighted_proj_object(jdata_a, weight)
		END AS jdata_a
	FROM w
	GROUP BY ts_slot, node_id, source_id
	ORDER BY ts_slot, node_id, source_id
$$;


ALTER FUNCTION solardatum.find_reading_at_2(nodes bigint[], sources text[], reading_ts timestamp without time zone, span interval) OWNER TO solarnet;

--
-- Name: find_reportable_interval(bigint, text); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_reportable_interval(node bigint, src text DEFAULT NULL::text, OUT ts_start timestamp with time zone, OUT ts_end timestamp with time zone, OUT node_tz text, OUT node_tz_offset integer) RETURNS record
    LANGUAGE sql STABLE
    AS $$
	WITH range AS (
		SELECT min(r.ts_min) AS ts_start, max(r.ts_max) AS ts_end
		FROM solardatum.da_datum_range r
		WHERE r.node_id = node
			AND (src IS NULL OR r.source_id = src)
	)
	SELECT r.ts_start
		, r.ts_end
		, COALESCE(l.time_zone, 'UTC') AS node_tz
		, COALESCE(CAST(EXTRACT(epoch FROM z.utc_offset) / 60 AS INTEGER), 0) AS node_tz_offset
	FROM range r
	LEFT OUTER JOIN solarnet.sn_node n ON n.node_id = node
	LEFT OUTER JOIN solarnet.sn_loc l ON l.id = n.loc_id
	LEFT OUTER JOIN pg_timezone_names z ON z.name = l.time_zone
$$;


ALTER FUNCTION solardatum.find_reportable_interval(node bigint, src text, OUT ts_start timestamp with time zone, OUT ts_end timestamp with time zone, OUT node_tz text, OUT node_tz_offset integer) OWNER TO solarnet;

--
-- Name: find_reportable_intervals(bigint[]); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_reportable_intervals(nodes bigint[]) RETURNS TABLE(node_id bigint, source_id text, ts_start timestamp with time zone, ts_end timestamp with time zone, node_tz text, node_tz_offset integer)
    LANGUAGE sql STABLE ROWS 50
    AS $$
	WITH range AS (
		SELECT r.node_id, r.source_id, min(r.ts_min) AS ts_min, max(r.ts_max) AS ts_max
		FROM solardatum.da_datum_range r
		WHERE r.node_id = ANY(nodes)
		GROUP BY r.node_id, r.source_id
	)
	SELECT r.node_id
		, r.source_id
		, r.ts_min AS ts_start
		, r.ts_max AS ts_end
		, COALESCE(l.time_zone, 'UTC') AS node_tz
		, COALESCE(CAST(EXTRACT(epoch FROM z.utc_offset) / 60 AS INTEGER), 0) AS node_tz_offset
	FROM range r
	LEFT OUTER JOIN solarnet.sn_node n ON n.node_id = r.node_id
	LEFT OUTER JOIN solarnet.sn_loc l ON l.id = n.loc_id
	LEFT OUTER JOIN pg_timezone_names z ON z.name = l.time_zone
$$;


ALTER FUNCTION solardatum.find_reportable_intervals(nodes bigint[]) OWNER TO solarnet;

--
-- Name: find_reportable_intervals(bigint[], text[]); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_reportable_intervals(nodes bigint[], sources text[]) RETURNS TABLE(node_id bigint, source_id text, ts_start timestamp with time zone, ts_end timestamp with time zone, node_tz text, node_tz_offset integer)
    LANGUAGE sql STABLE ROWS 50
    AS $$
	WITH range AS (
		SELECT r.node_id, r.source_id, min(r.ts_min) AS ts_min, max(r.ts_max) AS ts_max
		FROM solardatum.da_datum_range r
		WHERE r.node_id = ANY(nodes)
			AND r.source_id = ANY(sources)
		GROUP BY r.node_id, r.source_id
	)
	SELECT r.node_id
		, r.source_id
		, r.ts_min AS ts_start
		, r.ts_max AS ts_end
		, COALESCE(l.time_zone, 'UTC') AS node_tz
		, COALESCE(CAST(EXTRACT(epoch FROM z.utc_offset) / 60 AS INTEGER), 0) AS node_tz_offset
	FROM range r
	LEFT OUTER JOIN solarnet.sn_node n ON n.node_id = r.node_id
	LEFT OUTER JOIN solarnet.sn_loc l ON l.id = n.loc_id
	LEFT OUTER JOIN pg_timezone_names z ON z.name = l.time_zone
$$;


ALTER FUNCTION solardatum.find_reportable_intervals(nodes bigint[], sources text[]) OWNER TO solarnet;

--
-- Name: find_sources_for_loc_meta(bigint[], text); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_sources_for_loc_meta(locs bigint[], criteria text) RETURNS TABLE(loc_id bigint, source_id text)
    LANGUAGE plv8 STABLE ROWS 100
    AS $_$
'use strict';

var objectPathMatcher = require('util/objectPathMatcher').default,
	searchFilter = require('util/searchFilter').default;

var filter = searchFilter(criteria),
	stmt,
	curs,
	rec,
	meta,
	matcher,
	resultRec = {};

if ( !filter.rootNode ) {
	plv8.elog(NOTICE, 'Malformed search filter:', criteria);
	return;
}

stmt = plv8.prepare('SELECT loc_id, source_id, jdata FROM solardatum.da_loc_meta WHERE loc_id = ANY($1)', ['bigint[]']);
curs = stmt.cursor([locs]);

while ( rec = curs.fetch() ) {
	meta = rec.jdata;
	matcher = objectPathMatcher(meta);
	if ( matcher.matchesFilter(filter) ) {
		resultRec.loc_id = rec.loc_id;
		resultRec.source_id = rec.source_id;
		plv8.return_next(resultRec);
	}
}

curs.close();
stmt.free();

$_$;


ALTER FUNCTION solardatum.find_sources_for_loc_meta(locs bigint[], criteria text) OWNER TO solarnet;

--
-- Name: find_sources_for_meta(bigint[], text); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.find_sources_for_meta(nodes bigint[], criteria text) RETURNS TABLE(node_id bigint, source_id text)
    LANGUAGE plv8 STABLE ROWS 100
    AS $_$
'use strict';

var objectPathMatcher = require('util/objectPathMatcher').default,
	searchFilter = require('util/searchFilter').default;

var filter = searchFilter(criteria),
	stmt,
	curs,
	rec,
	meta,
	matcher,
	resultRec = {};

if ( !filter.rootNode ) {
	plv8.elog(NOTICE, 'Malformed search filter:', criteria);
	return;
}

stmt = plv8.prepare('SELECT node_id, source_id, jdata FROM solardatum.da_meta WHERE node_id = ANY($1)', ['bigint[]']);
curs = stmt.cursor([nodes]);

while ( rec = curs.fetch() ) {
	meta = rec.jdata;
	matcher = objectPathMatcher(meta);
	if ( matcher.matchesFilter(filter) ) {
		resultRec.node_id = rec.node_id;
		resultRec.source_id = rec.source_id;
		plv8.return_next(resultRec);
	}
}

curs.close();
stmt.free();

$_$;


ALTER FUNCTION solardatum.find_sources_for_meta(nodes bigint[], criteria text) OWNER TO solarnet;

--
-- Name: da_datum_aux; Type: TABLE; Schema: solardatum; Owner: solarnet
--

CREATE TABLE solardatum.da_datum_aux (
    ts timestamp with time zone NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    atype solardatum.da_datum_aux_type DEFAULT 'Reset'::solardatum.da_datum_aux_type NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL,
    notes text,
    jdata_af jsonb,
    jdata_as jsonb,
    jmeta jsonb
);


ALTER TABLE solardatum.da_datum_aux OWNER TO solarnet;

--
-- Name: jdata_from_datum_aux_final(solardatum.da_datum_aux); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.jdata_from_datum_aux_final(datum solardatum.da_datum_aux) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
	SELECT solarcommon.jdata_from_components(NULL, datum.jdata_af, NULL, ARRAY[datum.atype::text, 'final']);
$$;


ALTER FUNCTION solardatum.jdata_from_datum_aux_final(datum solardatum.da_datum_aux) OWNER TO solarnet;

--
-- Name: jdata_from_datum_aux_start(solardatum.da_datum_aux); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.jdata_from_datum_aux_start(datum solardatum.da_datum_aux) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
	SELECT solarcommon.jdata_from_components(NULL, datum.jdata_as, NULL, ARRAY[datum.atype::text, 'start']);
$$;


ALTER FUNCTION solardatum.jdata_from_datum_aux_start(datum solardatum.da_datum_aux) OWNER TO solarnet;

--
-- Name: move_datum_aux(timestamp with time zone, bigint, character varying, solardatum.da_datum_aux_type, timestamp with time zone, bigint, character varying, solardatum.da_datum_aux_type, text, text, text, text); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.move_datum_aux(cdate_from timestamp with time zone, node_from bigint, src_from character varying, aux_type_from solardatum.da_datum_aux_type, cdate timestamp with time zone, node bigint, src character varying, aux_type solardatum.da_datum_aux_type, aux_notes text, jdata_final text, jdata_start text, meta_json text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
	del_count integer := 0;
BEGIN
	-- note we are doing DELETE/INSERT so that trigger_agg_stale_datum can correctly pick up old/new stale rows
	DELETE FROM solardatum.da_datum_aux
	WHERE ts = cdate_from AND node_id = node_from AND source_id = src_from AND atype = aux_type_from;
	
	GET DIAGNOSTICS del_count = ROW_COUNT;
	
	IF del_count > 0 THEN
		PERFORM solardatum.store_datum_aux(cdate, node, src, aux_type, aux_notes, jdata_final, jdata_start, meta_json);
	END IF;
	
	RETURN (del_count > 0);
END;
$$;


ALTER FUNCTION solardatum.move_datum_aux(cdate_from timestamp with time zone, node_from bigint, src_from character varying, aux_type_from solardatum.da_datum_aux_type, cdate timestamp with time zone, node bigint, src character varying, aux_type solardatum.da_datum_aux_type, aux_notes text, jdata_final text, jdata_start text, meta_json text) OWNER TO solarnet;

--
-- Name: populate_updated(); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.populate_updated() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
	NEW.updated := now();
	RETURN NEW;
END;$$;


ALTER FUNCTION solardatum.populate_updated() OWNER TO solarnet;

--
-- Name: store_datum(timestamp with time zone, bigint, text, timestamp with time zone, text, boolean); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.store_datum(cdate timestamp with time zone, node bigint, src text, pdate timestamp with time zone, jdata text, track_recent boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	ts_crea timestamp with time zone := COALESCE(cdate, now());
	ts_post timestamp with time zone := COALESCE(pdate, now());
	jdata_json jsonb := jdata::jsonb;
	jdata_prop_count integer := solardatum.datum_prop_count(jdata_json);
	ts_post_hour timestamp with time zone := date_trunc('hour', ts_post);
	is_insert boolean := false;
BEGIN
	INSERT INTO solardatum.da_datum(ts, node_id, source_id, posted, jdata_i, jdata_a, jdata_s, jdata_t)
	VALUES (ts_crea, node, src, ts_post, jdata_json->'i', jdata_json->'a', jdata_json->'s', solarcommon.json_array_to_text_array(jdata_json->'t'))
	ON CONFLICT (node_id, ts, source_id) DO UPDATE
	SET jdata_i = EXCLUDED.jdata_i,
		jdata_a = EXCLUDED.jdata_a,
		jdata_s = EXCLUDED.jdata_s,
		jdata_t = EXCLUDED.jdata_t,
		posted = EXCLUDED.posted
	RETURNING (xmax = 0)
	INTO is_insert;

	INSERT INTO solaragg.aud_datum_hourly (
		ts_start, node_id, source_id, datum_count, prop_count)
	VALUES (ts_post_hour, node, src, 1, jdata_prop_count)
	ON CONFLICT (node_id, ts_start, source_id) DO UPDATE
	SET datum_count = aud_datum_hourly.datum_count + (CASE is_insert WHEN TRUE THEN 1 ELSE 0 END),
		prop_count = aud_datum_hourly.prop_count + EXCLUDED.prop_count;
		
	IF track_recent AND is_insert THEN
		PERFORM solardatum.update_datum_range_dates(node, src, cdate);
	END IF;
END;
$$;


ALTER FUNCTION solardatum.store_datum(cdate timestamp with time zone, node bigint, src text, pdate timestamp with time zone, jdata text, track_recent boolean) OWNER TO solarnet;

--
-- Name: store_datum_aux(timestamp with time zone, bigint, character varying, solardatum.da_datum_aux_type, text, text, text, text); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.store_datum_aux(cdate timestamp with time zone, node bigint, src character varying, aux_type solardatum.da_datum_aux_type, aux_notes text, jdata_final text, jdata_start text, jmeta text) RETURNS void
    LANGUAGE sql
    AS $$
	INSERT INTO solardatum.da_datum_aux(ts, node_id, source_id, atype, updated, notes, jdata_af, jdata_as, jmeta)
	VALUES (cdate, node, src, aux_type, CURRENT_TIMESTAMP, aux_notes, 
		(jdata_final::jsonb)->'a', (jdata_start::jsonb)->'a', jmeta::jsonb)
	ON CONFLICT (ts, node_id, source_id, atype) DO UPDATE
	SET notes = EXCLUDED.notes,
		jdata_af = EXCLUDED.jdata_af,
		jdata_as = EXCLUDED.jdata_as, 
		jmeta = EXCLUDED.jmeta,
		updated = EXCLUDED.updated;
$$;


ALTER FUNCTION solardatum.store_datum_aux(cdate timestamp with time zone, node bigint, src character varying, aux_type solardatum.da_datum_aux_type, aux_notes text, jdata_final text, jdata_start text, jmeta text) OWNER TO solarnet;

--
-- Name: store_loc_datum(timestamp with time zone, bigint, text, timestamp with time zone, text); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.store_loc_datum(cdate timestamp with time zone, loc bigint, src text, pdate timestamp with time zone, jdata text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	ts_crea timestamp with time zone := COALESCE(cdate, now());
	ts_post timestamp with time zone := COALESCE(pdate, now());
	jdata_json jsonb := jdata::jsonb;
	jdata_prop_count integer := solardatum.datum_prop_count(jdata_json);
	ts_post_hour timestamp with time zone := date_trunc('hour', ts_post);
BEGIN
	INSERT INTO solardatum.da_loc_datum(ts, loc_id, source_id, posted, jdata_i, jdata_a, jdata_s, jdata_t)
	VALUES (ts_crea, loc, src, ts_post, jdata_json->'i', jdata_json->'a', jdata_json->'s', solarcommon.json_array_to_text_array(jdata_json->'t'))
	ON CONFLICT (loc_id, ts, source_id) DO UPDATE
	SET jdata_i = EXCLUDED.jdata_i,
		jdata_a = EXCLUDED.jdata_a,
		jdata_s = EXCLUDED.jdata_s,
		jdata_t = EXCLUDED.jdata_t,
		posted = EXCLUDED.posted;

	INSERT INTO solaragg.aud_loc_datum_hourly (
		ts_start, loc_id, source_id, prop_count)
	VALUES (ts_post_hour, loc, src, jdata_prop_count)
	ON CONFLICT (loc_id, ts_start, source_id) DO UPDATE
	SET prop_count = aud_loc_datum_hourly.prop_count + EXCLUDED.prop_count;
END;
$$;


ALTER FUNCTION solardatum.store_loc_datum(cdate timestamp with time zone, loc bigint, src text, pdate timestamp with time zone, jdata text) OWNER TO solarnet;

--
-- Name: store_loc_meta(timestamp with time zone, bigint, text, text); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.store_loc_meta(cdate timestamp with time zone, loc bigint, src text, jdata text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	udate timestamp with time zone := now();
	jdata_json jsonb := jdata::jsonb;
BEGIN
	INSERT INTO solardatum.da_loc_meta(loc_id, source_id, created, updated, jdata)
	VALUES (loc, src, cdate, udate, jdata_json)
	ON CONFLICT (loc_id, source_id) DO UPDATE
	SET jdata = EXCLUDED.jdata, updated = EXCLUDED.updated;
END;
$$;


ALTER FUNCTION solardatum.store_loc_meta(cdate timestamp with time zone, loc bigint, src text, jdata text) OWNER TO solarnet;

--
-- Name: store_meta(timestamp with time zone, bigint, text, text); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.store_meta(cdate timestamp with time zone, node bigint, src text, jdata text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	udate timestamp with time zone := now();
	jdata_json jsonb := jdata::jsonb;
BEGIN
	INSERT INTO solardatum.da_meta(node_id, source_id, created, updated, jdata)
	VALUES (node, src, cdate, udate, jdata_json)
	ON CONFLICT (node_id, source_id) DO UPDATE
	SET jdata = EXCLUDED.jdata, updated = EXCLUDED.updated;
END;
$$;


ALTER FUNCTION solardatum.store_meta(cdate timestamp with time zone, node bigint, src text, jdata text) OWNER TO solarnet;

--
-- Name: trigger_agg_stale_datum(); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.trigger_agg_stale_datum() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	neighbor solardatum.da_datum;
BEGIN
	IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
		-- curr hour
		INSERT INTO solaragg.agg_stale_datum (ts_start, node_id, source_id, agg_kind)
		VALUES (date_trunc('hour', NEW.ts), NEW.node_id, NEW.source_id, 'h')
		ON CONFLICT (agg_kind, node_id, ts_start, source_id) DO NOTHING;

		-- prev hour; if the previous record for this source falls on the previous hour, we have to mark that hour as stale as well
		SELECT * FROM solardatum.da_datum d
		WHERE d.ts < NEW.ts
			AND d.ts > NEW.ts - interval '1 hour'
			AND d.node_id = NEW.node_id
			AND d.source_id = NEW.source_id
		ORDER BY d.ts DESC
		LIMIT 1
		INTO neighbor;
		IF FOUND AND neighbor.ts < date_trunc('hour', NEW.ts) THEN
			INSERT INTO solaragg.agg_stale_datum (ts_start, node_id, source_id, agg_kind)
			VALUES (date_trunc('hour', neighbor.ts), neighbor.node_id, neighbor.source_id, 'h')
			ON CONFLICT (agg_kind, node_id, ts_start, source_id) DO NOTHING;
		END IF;

		-- next slot; if there is another record in a future hour, we have to mark that hour as stale as well
		SELECT * FROM solardatum.da_datum d
		WHERE d.ts > NEW.ts
			AND d.ts < NEW.ts + interval '3 months'
			AND d.node_id = NEW.node_id
			AND d.source_id = NEW.source_id
		ORDER BY d.ts ASC
		LIMIT 1
		INTO neighbor;
		IF FOUND AND neighbor.ts > date_trunc('hour', NEW.ts) THEN
			INSERT INTO solaragg.agg_stale_datum (ts_start, node_id, source_id, agg_kind)
			VALUES (date_trunc('hour', neighbor.ts), neighbor.node_id, neighbor.source_id, 'h')
			ON CONFLICT (agg_kind, node_id, ts_start, source_id) DO NOTHING;
		END IF;
	END IF;

	IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND (OLD.source_id <> NEW.source_id OR OLD.node_id <> NEW.node_id)) THEN
		-- curr hour
		INSERT INTO solaragg.agg_stale_datum (ts_start, node_id, source_id, agg_kind)
		VALUES (date_trunc('hour', OLD.ts), OLD.node_id, OLD.source_id, 'h')
		ON CONFLICT (agg_kind, node_id, ts_start, source_id) DO NOTHING;

		-- prev hour; if the previous record for this source falls on the previous hour, we have to mark that hour as stale as well
		SELECT * FROM solardatum.da_datum d
		WHERE d.ts < OLD.ts
			AND d.ts > OLD.ts - interval '1 hour'
			AND d.node_id = OLD.node_id
			AND d.source_id = OLD.source_id
		ORDER BY d.ts DESC
		LIMIT 1
		INTO neighbor;
		IF FOUND AND neighbor.ts < date_trunc('hour', OLD.ts) THEN
			INSERT INTO solaragg.agg_stale_datum (ts_start, node_id, source_id, agg_kind)
			VALUES (date_trunc('hour', neighbor.ts), neighbor.node_id, neighbor.source_id, 'h')
			ON CONFLICT (agg_kind, node_id, ts_start, source_id) DO NOTHING;
		END IF;

		-- next slot; if there is another record in a future hour, we have to mark that hour as stale as well
		SELECT * FROM solardatum.da_datum d
		WHERE d.ts > OLD.ts
			AND d.ts < OLD.ts + interval '3 months'
			AND d.node_id = OLD.node_id
			AND d.source_id = OLD.source_id
		ORDER BY d.ts ASC
		LIMIT 1
		INTO neighbor;
		IF FOUND AND neighbor.ts > date_trunc('hour', OLD.ts) THEN
			INSERT INTO solaragg.agg_stale_datum (ts_start, node_id, source_id, agg_kind)
			VALUES (date_trunc('hour', neighbor.ts), neighbor.node_id, neighbor.source_id, 'h')
			ON CONFLICT (agg_kind, node_id, ts_start, source_id) DO NOTHING;
		END IF;
	END IF;

	CASE TG_OP
		WHEN 'INSERT', 'UPDATE' THEN
			RETURN NEW;
		ELSE
			RETURN OLD;
	END CASE;
END;$$;


ALTER FUNCTION solardatum.trigger_agg_stale_datum() OWNER TO solarnet;

--
-- Name: trigger_agg_stale_loc_datum(); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.trigger_agg_stale_loc_datum() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
	neighbor solardatum.da_loc_datum;
BEGIN
	IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
		-- curr hour
		INSERT INTO solaragg.agg_stale_loc_datum (ts_start, loc_id, source_id, agg_kind)
		VALUES (date_trunc('hour', NEW.ts), NEW.loc_id, NEW.source_id, 'h')
		ON CONFLICT (agg_kind, loc_id, ts_start, source_id) DO NOTHING;

		-- prev hour; if the previous record for this source falls on the previous hour; we have to mark that hour as stale as well
		SELECT * FROM solardatum.da_loc_datum d
		WHERE d.ts < NEW.ts
			AND d.ts > NEW.ts - interval '1 hour'
			AND d.loc_id = NEW.loc_id
			AND d.source_id = NEW.source_id
		ORDER BY d.ts DESC
		LIMIT 1
		INTO neighbor;
		IF FOUND AND neighbor.ts < date_trunc('hour', NEW.ts) THEN
			INSERT INTO solaragg.agg_stale_loc_datum (ts_start, loc_id, source_id, agg_kind)
			VALUES (date_trunc('hour', neighbor.ts), neighbor.loc_id, neighbor.source_id, 'h')
			ON CONFLICT (agg_kind, loc_id, ts_start, source_id) DO NOTHING;
		END IF;

		-- next hour; if the next record for this source falls on the next hour; we have to mark that hour as stale as well
		SELECT * FROM solardatum.da_loc_datum d
		WHERE d.ts > NEW.ts
			AND d.ts < NEW.ts + interval '1 hour'
			AND d.loc_id = NEW.loc_id
			AND d.source_id = NEW.source_id
		ORDER BY d.ts ASC
		LIMIT 1
		INTO neighbor;
		IF FOUND AND neighbor.ts > date_trunc('hour', NEW.ts) THEN
			INSERT INTO solaragg.agg_stale_loc_datum (ts_start, loc_id, source_id, agg_kind)
			VALUES (date_trunc('hour', neighbor.ts), neighbor.loc_id, neighbor.source_id, 'h')
			ON CONFLICT (agg_kind, loc_id, ts_start, source_id) DO NOTHING;
		END IF;
	END IF;

	IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND (OLD.source_id <> NEW.source_id OR OLD.loc_id <> NEW.loc_id)) THEN
		-- curr hour
		INSERT INTO solaragg.agg_stale_loc_datum (ts_start, loc_id, source_id, agg_kind)
		VALUES (date_trunc('hour', OLD.ts), OLD.loc_id, OLD.source_id, 'h')
		ON CONFLICT (agg_kind, loc_id, ts_start, source_id) DO NOTHING;

		-- prev hour; if the previous record for this source falls on the previous hour; we have to mark that hour as stale as well
		SELECT * FROM solardatum.da_loc_datum d
		WHERE d.ts < OLD.ts
			AND d.ts > OLD.ts - interval '1 hour'
			AND d.loc_id = OLD.loc_id
			AND d.source_id = OLD.source_id
		ORDER BY d.ts DESC
		LIMIT 1
		INTO neighbor;
		IF FOUND AND neighbor.ts < date_trunc('hour', OLD.ts) THEN
			INSERT INTO solaragg.agg_stale_loc_datum (ts_start, loc_id, source_id, agg_kind)
			VALUES (date_trunc('hour', neighbor.ts), neighbor.loc_id, neighbor.source_id, 'h')
			ON CONFLICT (agg_kind, loc_id, ts_start, source_id) DO NOTHING;
		END IF;

		-- next hour; if the next record for this source falls on the next hour; we have to mark that hour as stale as well
		SELECT * FROM solardatum.da_loc_datum d
		WHERE d.ts > OLD.ts
			AND d.ts < OLD.ts + interval '1 hour'
			AND d.loc_id = OLD.loc_id
			AND d.source_id = OLD.source_id
		ORDER BY d.ts ASC
		LIMIT 1
		INTO neighbor;
		IF FOUND AND neighbor.ts > date_trunc('hour', OLD.ts) THEN
			INSERT INTO solaragg.agg_stale_loc_datum (ts_start, loc_id, source_id, agg_kind)
			VALUES (date_trunc('hour', neighbor.ts), neighbor.loc_id, neighbor.source_id, 'h')
			ON CONFLICT (agg_kind, loc_id, ts_start, source_id) DO NOTHING;
		END IF;
	END IF;

	CASE TG_OP
		WHEN 'INSERT', 'UPDATE' THEN
			RETURN NEW;
		ELSE
			RETURN OLD;
	END CASE;
END;$$;


ALTER FUNCTION solardatum.trigger_agg_stale_loc_datum() OWNER TO solarnet;

--
-- Name: update_datum_range_dates(bigint, character varying, timestamp with time zone); Type: FUNCTION; Schema: solardatum; Owner: solarnet
--

CREATE FUNCTION solardatum.update_datum_range_dates(node bigint, source character varying, rdate timestamp with time zone) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	tsmin timestamp with time zone;
	tsmax timestamp with time zone;
BEGIN
	SELECT ts_min, ts_max
	FROM solardatum.da_datum_range
	WHERE node_id = node AND source_id = source
	INTO tsmin, tsmax;

	IF tsmin IS NULL THEN
		INSERT INTO solardatum.da_datum_range (ts_min, ts_max, node_id, source_id)
		VALUES (rdate, rdate, node, source)
		ON CONFLICT (node_id, source_id) DO NOTHING;
	ELSEIF rdate > tsmax THEN
		UPDATE solardatum.da_datum_range SET ts_max = rdate
		WHERE node_id = node AND source_id = source;
	ELSEIF rdate < tsmin THEN
		UPDATE solardatum.da_datum_range SET ts_min = rdate
		WHERE node_id = node AND source_id = source;
	END IF;

END;
$$;


ALTER FUNCTION solardatum.update_datum_range_dates(node bigint, source character varying, rdate timestamp with time zone) OWNER TO solarnet;

--
-- Name: add_datum_export_task(uuid, timestamp with time zone, text); Type: FUNCTION; Schema: solarnet; Owner: solarnet
--

CREATE FUNCTION solarnet.add_datum_export_task(uid uuid, ex_date timestamp with time zone, cfg text) RETURNS character
    LANGUAGE plpgsql
    AS $$
BEGIN
	INSERT INTO solarnet.sn_datum_export_task
		(id, created, export_date, config, status)
	VALUES
		(uid, CURRENT_TIMESTAMP, ex_date, cfg::jsonb, 'q');
	RETURN 'q';
END;
$$;


ALTER FUNCTION solarnet.add_datum_export_task(uid uuid, ex_date timestamp with time zone, cfg text) OWNER TO solarnet;

--
-- Name: sn_datum_export_task; Type: TABLE; Schema: solarnet; Owner: solarnet
--

CREATE TABLE solarnet.sn_datum_export_task (
    id uuid NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    modified timestamp with time zone DEFAULT now() NOT NULL,
    export_date timestamp with time zone NOT NULL,
    status character(1) NOT NULL,
    config jsonb NOT NULL,
    success boolean,
    message text,
    completed timestamp with time zone
);


ALTER TABLE solarnet.sn_datum_export_task OWNER TO solarnet;

--
-- Name: claim_datum_export_task(); Type: FUNCTION; Schema: solarnet; Owner: solarnet
--

CREATE FUNCTION solarnet.claim_datum_export_task() RETURNS solarnet.sn_datum_export_task
    LANGUAGE plpgsql
    AS $$
DECLARE
	rec solarnet.sn_datum_export_task;
	curs CURSOR FOR SELECT * FROM solarnet.sn_datum_export_task
			WHERE status = 'q'
			ORDER BY created ASC, ID ASC
			LIMIT 1
			FOR UPDATE SKIP LOCKED;
BEGIN
	OPEN curs;
	FETCH NEXT FROM curs INTO rec;
	IF FOUND THEN
		UPDATE solarnet.sn_datum_export_task SET status = 'p' WHERE CURRENT OF curs;
	END IF;
	CLOSE curs;
	RETURN rec;
END;
$$;


ALTER FUNCTION solarnet.claim_datum_export_task() OWNER TO solarnet;

--
-- Name: sn_datum_import_job; Type: TABLE; Schema: solarnet; Owner: solarnet
--

CREATE TABLE solarnet.sn_datum_import_job (
    id uuid NOT NULL,
    user_id bigint NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    modified timestamp with time zone DEFAULT now() NOT NULL,
    import_date timestamp with time zone NOT NULL,
    state character(1) NOT NULL,
    success boolean,
    load_count bigint DEFAULT 0 NOT NULL,
    completed timestamp with time zone,
    message text,
    config jsonb NOT NULL,
    progress double precision DEFAULT 0 NOT NULL,
    started timestamp with time zone
);


ALTER TABLE solarnet.sn_datum_import_job OWNER TO solarnet;

--
-- Name: claim_datum_import_job(); Type: FUNCTION; Schema: solarnet; Owner: solarnet
--

CREATE FUNCTION solarnet.claim_datum_import_job() RETURNS solarnet.sn_datum_import_job
    LANGUAGE plpgsql
    AS $$
DECLARE
	rec solarnet.sn_datum_import_job;
	curs CURSOR FOR SELECT * FROM solarnet.sn_datum_import_job
			WHERE state = 'q'
			ORDER BY created ASC, ID ASC
			LIMIT 1
			FOR UPDATE SKIP LOCKED;
BEGIN
	OPEN curs;
	FETCH NEXT FROM curs INTO rec;
	IF FOUND THEN
		UPDATE solarnet.sn_datum_import_job SET state = 'p' WHERE CURRENT OF curs;
	END IF;
	CLOSE curs;
	RETURN rec;
END;
$$;


ALTER FUNCTION solarnet.claim_datum_import_job() OWNER TO solarnet;

--
-- Name: get_node_local_timestamp(timestamp with time zone, bigint); Type: FUNCTION; Schema: solarnet; Owner: solarnet
--

CREATE FUNCTION solarnet.get_node_local_timestamp(timestamp with time zone, bigint) RETURNS timestamp without time zone
    LANGUAGE sql STABLE
    AS $_$
	SELECT $1 AT TIME ZONE l.time_zone
	FROM solarnet.sn_node n
	INNER JOIN solarnet.sn_loc l ON l.id = n.loc_id
	WHERE n.node_id = $2
$_$;


ALTER FUNCTION solarnet.get_node_local_timestamp(timestamp with time zone, bigint) OWNER TO solarnet;

--
-- Name: get_node_timezone(bigint); Type: FUNCTION; Schema: solarnet; Owner: solarnet
--

CREATE FUNCTION solarnet.get_node_timezone(bigint) RETURNS text
    LANGUAGE sql STABLE
    AS $_$
	SELECT l.time_zone 
	FROM solarnet.sn_node n
	INNER JOIN solarnet.sn_loc l ON l.id = n.loc_id
	WHERE n.node_id = $1
$_$;


ALTER FUNCTION solarnet.get_node_timezone(bigint) OWNER TO solarnet;

--
-- Name: get_season(date); Type: FUNCTION; Schema: solarnet; Owner: solarnet
--

CREATE FUNCTION solarnet.get_season(date) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $_$
	SELECT
	CASE EXTRACT(MONTH FROM $1) 
		WHEN 12 THEN 0
		WHEN 1 THEN 0
		WHEN 2 THEN 0
		WHEN 3 THEN 1
		WHEN 4 THEN 1
		WHEN 5 THEN 1
		WHEN 6 THEN 2
		WHEN 7 THEN 2
		WHEN 8 THEN 2
		WHEN 9 THEN 3
		WHEN 10 THEN 3
		WHEN 11 THEN 3
	END AS season
$_$;


ALTER FUNCTION solarnet.get_season(date) OWNER TO solarnet;

--
-- Name: get_season_monday_start(date); Type: FUNCTION; Schema: solarnet; Owner: solarnet
--

CREATE FUNCTION solarnet.get_season_monday_start(date) RETURNS date
    LANGUAGE sql IMMUTABLE
    AS $_$
	SELECT
	CASE solarnet.get_season($1)
		WHEN 0 THEN DATE '2000-12-04'
		WHEN 1 THEN DATE '2001-03-05'
		WHEN 2 THEN DATE '2001-06-04'
		ELSE DATE '2001-09-03'
  END AS season_monday
$_$;


ALTER FUNCTION solarnet.get_season_monday_start(date) OWNER TO solarnet;

--
-- Name: jsonb_array_to_bigint_array(jsonb); Type: FUNCTION; Schema: solarnet; Owner: solarnet
--

CREATE FUNCTION solarnet.jsonb_array_to_bigint_array(jsonb) RETURNS bigint[]
    LANGUAGE sql IMMUTABLE
    AS $_$
    SELECT array_agg(x)::bigint[] || ARRAY[]::bigint[] FROM jsonb_array_elements_text($1) t(x);
$_$;


ALTER FUNCTION solarnet.jsonb_array_to_bigint_array(jsonb) OWNER TO solarnet;

--
-- Name: node_source_time_ranges_local(bigint[], text[], timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: solarnet; Owner: solarnet
--

CREATE FUNCTION solarnet.node_source_time_ranges_local(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) RETURNS TABLE(ts_start timestamp with time zone, ts_end timestamp with time zone, time_zone text, node_ids bigint[], source_ids character varying[])
    LANGUAGE sql STABLE
    AS $$
	SELECT ts_min AT TIME ZONE nlt.time_zone AS sdate,
		ts_max AT TIME ZONE nlt.time_zone AS edate,
		nlt.time_zone AS time_zone,
		array_agg(DISTINCT nlt.node_id) AS nodes,
		array_agg(DISTINCT s.source_id::character varying(64)) FILTER (WHERE s.source_id IS NOT NULL) AS sources
	FROM solarnet.node_local_time nlt
	LEFT JOIN (
		SELECT unnest(sources) AS source_id
	) s ON TRUE
	WHERE nlt.node_id = ANY(nodes)
	GROUP BY time_zone
$$;


ALTER FUNCTION solarnet.node_source_time_ranges_local(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) OWNER TO solarnet;

--
-- Name: purge_completed_datum_export_tasks(timestamp with time zone); Type: FUNCTION; Schema: solarnet; Owner: solarnet
--

CREATE FUNCTION solarnet.purge_completed_datum_export_tasks(older_date timestamp with time zone) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
	num_rows BIGINT := 0;
BEGIN
	DELETE FROM solarnet.sn_datum_export_task
	WHERE completed < older_date AND status = 'c';
	GET DIAGNOSTICS num_rows = ROW_COUNT;
	RETURN num_rows;
END;
$$;


ALTER FUNCTION solarnet.purge_completed_datum_export_tasks(older_date timestamp with time zone) OWNER TO solarnet;

--
-- Name: purge_completed_datum_import_jobs(timestamp with time zone); Type: FUNCTION; Schema: solarnet; Owner: solarnet
--

CREATE FUNCTION solarnet.purge_completed_datum_import_jobs(older_date timestamp with time zone) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
	num_rows BIGINT := 0;
BEGIN
	DELETE FROM solarnet.sn_datum_import_job
	WHERE completed < older_date AND state = 'c';
	GET DIAGNOSTICS num_rows = ROW_COUNT;
	RETURN num_rows;
END;
$$;


ALTER FUNCTION solarnet.purge_completed_datum_import_jobs(older_date timestamp with time zone) OWNER TO solarnet;

--
-- Name: purge_completed_instructions(timestamp with time zone); Type: FUNCTION; Schema: solarnet; Owner: solarnet
--

CREATE FUNCTION solarnet.purge_completed_instructions(older_date timestamp with time zone) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
num_rows BIGINT := 0;
BEGIN
DELETE FROM solarnet.sn_node_instruction
WHERE instr_date < older_date
AND deliver_state IN (
'Declined'::solarnet.instruction_delivery_state, 
'Completed'::solarnet.instruction_delivery_state);
GET DIAGNOSTICS num_rows = ROW_COUNT;
RETURN num_rows;
END;$$;


ALTER FUNCTION solarnet.purge_completed_instructions(older_date timestamp with time zone) OWNER TO solarnet;

--
-- Name: store_node_meta(timestamp with time zone, bigint, text); Type: FUNCTION; Schema: solarnet; Owner: solarnet
--

CREATE FUNCTION solarnet.store_node_meta(cdate timestamp with time zone, node bigint, jdata text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	udate timestamp with time zone := now();
	jdata_json jsonb := jdata::jsonb;
BEGIN
	INSERT INTO solarnet.sn_node_meta(node_id, created, updated, jdata)
	VALUES (node, cdate, udate, jdata_json)
	ON CONFLICT (node_id) DO UPDATE
	SET jdata = EXCLUDED.jdata, updated = EXCLUDED.updated;
END;
$$;


ALTER FUNCTION solarnet.store_node_meta(cdate timestamp with time zone, node bigint, jdata text) OWNER TO solarnet;

--
-- Name: user_datum_delete_job; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_datum_delete_job (
    id uuid NOT NULL,
    user_id bigint NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    modified timestamp with time zone DEFAULT now() NOT NULL,
    progress double precision DEFAULT 0 NOT NULL,
    started timestamp with time zone,
    completed timestamp with time zone,
    result_count bigint,
    state character(1) NOT NULL,
    success boolean,
    message text,
    config jsonb NOT NULL
);


ALTER TABLE solaruser.user_datum_delete_job OWNER TO solarnet;

--
-- Name: claim_datum_delete_job(); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.claim_datum_delete_job() RETURNS solaruser.user_datum_delete_job
    LANGUAGE plpgsql
    AS $$
DECLARE
	rec solaruser.user_datum_delete_job;
	curs CURSOR FOR SELECT * FROM solaruser.user_datum_delete_job
			WHERE state = 'q'
			ORDER BY created ASC, ID ASC
			LIMIT 1
			FOR UPDATE SKIP LOCKED;
BEGIN
	OPEN curs;
	FETCH NEXT FROM curs INTO rec;
	IF FOUND THEN
		UPDATE solaruser.user_datum_delete_job SET state = 'p' WHERE CURRENT OF curs;
	END IF;
	CLOSE curs;
	RETURN rec;
END;
$$;


ALTER FUNCTION solaruser.claim_datum_delete_job() OWNER TO solarnet;

--
-- Name: expire_datum_for_policy(bigint, jsonb, interval); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.expire_datum_for_policy(userid bigint, jpolicy jsonb, age interval) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
	total_count bigint := 0;
	one_count bigint := 0;
	node_ids bigint[];
	have_source_ids boolean := jpolicy->'sourceIds' IS NULL;
	source_id_regexs text[];
	agg_key text := jpolicy->>'aggregationKey';
BEGIN
	-- filter node IDs to only those owned by user
	SELECT ARRAY(SELECT node_id
				 FROM solaruser.user_node un
				 WHERE un.user_id = userid
					AND (
						jpolicy->'nodeIds' IS NULL
						OR jpolicy->'nodeIds' @> un.node_id::text::jsonb
					)
				)
	INTO node_ids;

	-- get array of source ID regexs
	SELECT ARRAY(SELECT solarcommon.ant_pattern_to_regexp(jsonb_array_elements_text(jpolicy->'sourceIds')))
	INTO source_id_regexs;

	-- delete raw data
	WITH nlt AS (
		SELECT
			node_id,
			(date_trunc('day', CURRENT_TIMESTAMP AT TIME ZONE time_zone) - age) AT TIME ZONE time_zone AS older_than
		FROM solarnet.node_local_time
		WHERE node_id = ANY (node_ids)
	)
	DELETE FROM solardatum.da_datum d
	USING nlt
	WHERE d.node_id = nlt.node_id
		AND d.ts < nlt.older_than
		AND (have_source_ids OR d.source_id ~ ANY(source_id_regexs));
	GET DIAGNOSTICS total_count = ROW_COUNT;

	-- delete any triggered stale rows
	WITH nlt AS (
		SELECT
			node_id,
			(date_trunc('day', CURRENT_TIMESTAMP AT TIME ZONE time_zone) - age) AT TIME ZONE time_zone AS older_than
		FROM solarnet.node_local_time
		WHERE node_id = ANY (node_ids)
	)
	DELETE FROM solaragg.agg_stale_datum d
	USING nlt
	WHERE d.node_id = nlt.node_id
		AND d.ts_start <= nlt.older_than
		AND (have_source_ids OR d.source_id ~ ANY(source_id_regexs))
		AND d.agg_kind = 'h';

	-- update daily audit datum counts
	WITH nlt AS (
		SELECT
			node_id,
			(date_trunc('day', CURRENT_TIMESTAMP AT TIME ZONE time_zone) - age) AT TIME ZONE time_zone AS older_than
		FROM solarnet.node_local_time
		WHERE node_id = ANY (node_ids)
	)
	UPDATE solaragg.aud_datum_daily d
	SET datum_count = 0
	FROM nlt
	WHERE d.node_id = nlt.node_id
		AND d.ts_start < nlt.older_than
		AND (have_source_ids OR d.source_id ~ ANY(source_id_regexs));

	IF agg_key IN ('h', 'd', 'M') THEN
		-- delete hourly data
		WITH nlt AS (
			SELECT
				node_id,
				(date_trunc('day', CURRENT_TIMESTAMP AT TIME ZONE time_zone) - age) AT TIME ZONE time_zone AS older_than
			FROM solarnet.node_local_time
			WHERE node_id = ANY (node_ids)
		)
		DELETE FROM solaragg.agg_datum_hourly d
		USING nlt
		WHERE d.node_id = nlt.node_id
			AND d.ts_start < older_than
			AND (have_source_ids OR d.source_id ~ ANY(source_id_regexs));
		GET DIAGNOSTICS one_count = ROW_COUNT;
		total_count := total_count + one_count;

		-- update daily audit datum counts
		WITH nlt AS (
			SELECT
				node_id,
				(date_trunc('day', CURRENT_TIMESTAMP AT TIME ZONE time_zone) - age) AT TIME ZONE time_zone AS older_than
			FROM solarnet.node_local_time
			WHERE node_id = ANY (node_ids)
		)
		UPDATE solaragg.aud_datum_daily d
		SET datum_hourly_count = 0
		FROM nlt
		WHERE d.node_id = nlt.node_id
			AND d.ts_start < nlt.older_than
			AND (have_source_ids OR d.source_id ~ ANY(source_id_regexs));
	END IF;

	IF agg_key IN ('d', 'M') THEN
		-- delete daily data
		WITH nlt AS (
			SELECT
				node_id,
				(date_trunc('day', CURRENT_TIMESTAMP AT TIME ZONE time_zone) - age) AT TIME ZONE time_zone AS older_than
			FROM solarnet.node_local_time
			WHERE node_id = ANY (node_ids)
		)
		DELETE FROM solaragg.agg_datum_daily d
		USING nlt
		WHERE d.node_id = nlt.node_id
			AND d.ts_start < older_than
			AND (have_source_ids OR d.source_id ~ ANY(source_id_regexs));
		GET DIAGNOSTICS one_count = ROW_COUNT;
		total_count := total_count + one_count;

		-- update daily audit datum counts
		WITH nlt AS (
			SELECT
				node_id,
				(date_trunc('day', CURRENT_TIMESTAMP AT TIME ZONE time_zone) - age) AT TIME ZONE time_zone AS older_than
			FROM solarnet.node_local_time
			WHERE node_id = ANY (node_ids)
		)
		UPDATE solaragg.aud_datum_daily d
		SET datum_daily_pres = FALSE
		FROM nlt
		WHERE d.node_id = nlt.node_id
			AND d.ts_start < nlt.older_than
			AND (have_source_ids OR d.source_id ~ ANY(source_id_regexs));
	END IF;

	IF agg_key = 'M' THEN
		-- delete monthly data (round down to whole months only)
		WITH nlt AS (
			SELECT
				node_id,
				(date_trunc('month', CURRENT_TIMESTAMP AT TIME ZONE time_zone) - age) AT TIME ZONE time_zone AS older_than
			FROM solarnet.node_local_time
			WHERE node_id = ANY (node_ids)
		)
		DELETE FROM solaragg.agg_datum_monthly d
		USING nlt
		WHERE d.node_id = nlt.node_id
			AND d.ts_start < older_than
			AND (have_source_ids OR d.source_id ~ ANY(source_id_regexs));
		GET DIAGNOSTICS one_count = ROW_COUNT;
		total_count := total_count + one_count;
	END IF;

	-- mark all monthly audit data as stale for recalculation
	IF total_count > 0 THEN
		INSERT INTO solaragg.aud_datum_daily_stale (node_id, ts_start, source_id, aud_kind)
		WITH nlt AS (
			SELECT
				node_id,
				(date_trunc('day', CURRENT_TIMESTAMP AT TIME ZONE time_zone) - age) AT TIME ZONE time_zone AS older_than
			FROM solarnet.node_local_time
			WHERE node_id = ANY (node_ids)
		)
		SELECT d.node_id, d.ts_start, d.source_id, 'm'
		FROM solaragg.aud_datum_monthly d
		INNER JOIN nlt ON nlt.node_id = d.node_id
		WHERE d.ts_start < nlt.older_than
			AND (have_source_ids OR d.source_id ~ ANY(source_id_regexs))
		ON CONFLICT DO NOTHING;
	END IF;
	
	RETURN total_count;
END;
$$;


ALTER FUNCTION solaruser.expire_datum_for_policy(userid bigint, jpolicy jsonb, age interval) OWNER TO solarnet;

--
-- Name: find_most_recent_datum_for_user(bigint[]); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.find_most_recent_datum_for_user(users bigint[]) RETURNS SETOF solardatum.da_datum_data
    LANGUAGE sql STABLE ROWS 100
    AS $$
	SELECT d.*
	FROM solaruser.user_node un
	INNER JOIN solardatum.da_datum_range mr ON mr.node_id = un.node_id
	INNER JOIN solardatum.da_datum_data d ON d.node_id = mr.node_id AND d.source_id = mr.source_id AND d.ts = mr.ts_max
	WHERE un.user_id = ANY(users)
	ORDER BY d.node_id, d.source_id
$$;


ALTER FUNCTION solaruser.find_most_recent_datum_for_user(users bigint[]) OWNER TO solarnet;

--
-- Name: find_most_recent_datum_for_user_direct(bigint[]); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.find_most_recent_datum_for_user_direct(users bigint[]) RETURNS SETOF solardatum.da_datum_data
    LANGUAGE sql STABLE ROWS 100
    AS $$
	SELECT r.*
	FROM (SELECT node_id FROM solaruser.user_node WHERE user_id = ANY(users)) AS n,
	LATERAL (SELECT * FROM solardatum.find_most_recent_direct(n.node_id)) AS r
	ORDER BY r.node_id, r.source_id;
$$;


ALTER FUNCTION solaruser.find_most_recent_datum_for_user_direct(users bigint[]) OWNER TO solarnet;

--
-- Name: node_ownership_transfer(); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.node_ownership_transfer() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
	UPDATE solaruser.user_node_cert
	SET user_id = NEW.user_id
	WHERE user_id = OLD.user_id
		AND node_id = NEW.node_id;
	
	UPDATE solaruser.user_node_conf
	SET user_id = NEW.user_id
	WHERE user_id = OLD.user_id
		AND node_id = NEW.node_id;
	
	RETURN NEW;
END;$$;


ALTER FUNCTION solaruser.node_ownership_transfer() OWNER TO solarnet;

--
-- Name: preview_expire_datum_for_policy(bigint, jsonb, interval); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.preview_expire_datum_for_policy(userid bigint, jpolicy jsonb, age interval) RETURNS TABLE(query_date timestamp with time zone, datum_count bigint, datum_hourly_count integer, datum_daily_count integer, datum_monthly_count integer)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
	node_ids bigint[];
	have_source_ids boolean := jpolicy->'sourceIds' IS NULL;
	source_id_regexs text[];
	agg_key text := jpolicy->>'aggregationKey';
BEGIN
	-- filter node IDs to only those owned by user
	SELECT ARRAY(SELECT node_id
				 FROM solaruser.user_node un
				 WHERE un.user_id = userid
					AND (
						jpolicy->'nodeIds' IS NULL
						OR jpolicy->'nodeIds' @> un.node_id::text::jsonb
					)
				)
	INTO node_ids;

	-- get array of source ID regexs
	SELECT ARRAY(SELECT solarcommon.ant_pattern_to_regexp(jsonb_array_elements_text(jpolicy->'sourceIds')))
	INTO source_id_regexs;

	-- count raw data
	WITH nlt AS (
		SELECT
			node_id,
			(date_trunc('day', CURRENT_TIMESTAMP AT TIME ZONE time_zone) - age) AT TIME ZONE time_zone AS older_than
		FROM solarnet.node_local_time
		WHERE node_id = ANY (node_ids)
	)
	SELECT count(*)
	FROM solardatum.da_datum d, nlt
	WHERE d.node_id = nlt.node_id
		AND d.ts < nlt.older_than
		AND (have_source_ids OR d.source_id ~ ANY(source_id_regexs))
	INTO datum_count;

	IF agg_key IN ('h', 'd', 'M') THEN
		-- count hourly data
		WITH nlt AS (
			SELECT
				node_id,
				(date_trunc('day', CURRENT_TIMESTAMP AT TIME ZONE time_zone) - age) AT TIME ZONE time_zone AS older_than
			FROM solarnet.node_local_time
			WHERE node_id = ANY (node_ids)
		)
		SELECT count(*)
		FROM solaragg.agg_datum_hourly d, nlt
		WHERE d.node_id = nlt.node_id
			AND d.ts_start < older_than
			AND (have_source_ids OR d.source_id ~ ANY(source_id_regexs))
		INTO datum_hourly_count;
	END IF;

	IF agg_key IN ('d', 'M') THEN
		-- count daily data
		WITH nlt AS (
			SELECT
				node_id,
				(date_trunc('day', CURRENT_TIMESTAMP AT TIME ZONE time_zone) - age) AT TIME ZONE time_zone AS older_than
			FROM solarnet.node_local_time
			WHERE node_id = ANY (node_ids)
		)
		SELECT count(*)
		FROM solaragg.agg_datum_daily d, nlt
		WHERE d.node_id = nlt.node_id
			AND d.ts_start < older_than
			AND (have_source_ids OR d.source_id ~ ANY(source_id_regexs))
		INTO datum_daily_count;
	END IF;

	IF agg_key = 'M' THEN
		-- count monthly data (round down to whole months only)
		WITH nlt AS (
			SELECT
				node_id,
				(date_trunc('month', CURRENT_TIMESTAMP AT TIME ZONE time_zone) - age) AT TIME ZONE time_zone AS older_than
			FROM solarnet.node_local_time
			WHERE node_id = ANY (node_ids)
		)
		SELECT count(*)
		FROM solaragg.agg_datum_monthly d, nlt
		WHERE d.node_id = nlt.node_id
			AND d.ts_start < older_than
			AND (have_source_ids OR d.source_id ~ ANY(source_id_regexs))
		INTO datum_monthly_count;
	END IF;

	query_date = date_trunc('day', CURRENT_TIMESTAMP);
	RETURN NEXT;
END;
$$;


ALTER FUNCTION solaruser.preview_expire_datum_for_policy(userid bigint, jpolicy jsonb, age interval) OWNER TO solarnet;

--
-- Name: purge_completed_datum_delete_jobs(timestamp with time zone); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.purge_completed_datum_delete_jobs(older_date timestamp with time zone) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
	num_rows BIGINT := 0;
BEGIN
	DELETE FROM solaruser.user_datum_delete_job
	WHERE completed < older_date AND state = 'c';
	GET DIAGNOSTICS num_rows = ROW_COUNT;
	RETURN num_rows;
END;
$$;


ALTER FUNCTION solaruser.purge_completed_datum_delete_jobs(older_date timestamp with time zone) OWNER TO solarnet;

--
-- Name: purge_completed_user_adhoc_export_tasks(timestamp with time zone); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.purge_completed_user_adhoc_export_tasks(older_date timestamp with time zone) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
	num_rows BIGINT := 0;
BEGIN
	DELETE FROM solaruser.user_adhoc_export_task
	USING solarnet.sn_datum_export_task
	WHERE task_id = sn_datum_export_task.id
		AND sn_datum_export_task.completed < older_date
		AND sn_datum_export_task.status = 'c';
	GET DIAGNOSTICS num_rows = ROW_COUNT;
	RETURN num_rows;
END;
$$;


ALTER FUNCTION solaruser.purge_completed_user_adhoc_export_tasks(older_date timestamp with time zone) OWNER TO solarnet;

--
-- Name: purge_completed_user_export_tasks(timestamp with time zone); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.purge_completed_user_export_tasks(older_date timestamp with time zone) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
	num_rows BIGINT := 0;
BEGIN
	DELETE FROM solaruser.user_export_task
	USING solarnet.sn_datum_export_task
	WHERE task_id = sn_datum_export_task.id
		AND sn_datum_export_task.completed < older_date
		AND sn_datum_export_task.status = 'c';
	GET DIAGNOSTICS num_rows = ROW_COUNT;
	RETURN num_rows;
END;
$$;


ALTER FUNCTION solaruser.purge_completed_user_export_tasks(older_date timestamp with time zone) OWNER TO solarnet;

--
-- Name: purge_resolved_situations(timestamp with time zone); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.purge_resolved_situations(older_date timestamp with time zone) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE
	num_rows BIGINT := 0;
BEGIN
	DELETE FROM solaruser.user_alert_sit
	WHERE notified < older_date
		AND status = 'Resolved'::solaruser.user_alert_sit_status;
	GET DIAGNOSTICS num_rows = ROW_COUNT;
	RETURN num_rows;
END;$$;


ALTER FUNCTION solaruser.purge_resolved_situations(older_date timestamp with time zone) OWNER TO solarnet;

--
-- Name: snws2_canon_request_data(timestamp with time zone, text, text); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.snws2_canon_request_data(req_date timestamp with time zone, host text, path text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
	SELECT E'GET\n'
		|| path || E'\n'
		|| E'\n' -- query params
		|| 'host:' || host || E'\n'
		|| 'x-sn-date:' || solarcommon.to_rfc1123_utc(req_date) || E'\n'
		|| E'host;x-sn-date\n'
		|| 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
$$;


ALTER FUNCTION solaruser.snws2_canon_request_data(req_date timestamp with time zone, host text, path text) OWNER TO solarnet;

--
-- Name: snws2_find_token_details(text, timestamp with time zone, text, text, text); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.snws2_find_token_details(token_id text, req_date timestamp with time zone, host text, path text, signature text) RETURNS TABLE(user_id bigint, token_type solaruser.user_auth_token_type, jpolicy jsonb, sign_date date, sign_data text, canon_req_data text, calc_signature text)
    LANGUAGE sql STABLE STRICT SECURITY DEFINER ROWS 1
    AS $$
	WITH sign_dates AS (
		SELECT CAST(generate_series(
			(req_date at time zone 'UTC')::date,
			(req_date at time zone 'UTC')::date - interval '6 days',
			-interval '1 day') at time zone 'UTC' AS DATE) as sign_date
	), canon_data AS (
		SELECT solaruser.snws2_signature_data(
			req_date,
			solaruser.snws2_canon_request_data(req_date, host, path)
		) AS sign_data,
		solaruser.snws2_canon_request_data(req_date, host, path) AS canon_req_data
	)
	SELECT
		user_id,
		token_type,
		jpolicy,
		sign_date,
		sign_data,
		canon_req_data,
		solaruser.snws2_signature(
				sign_data,
				solaruser.snws2_signing_key(sd.sign_date, auth.auth_secret)
			)
	FROM solaruser.user_auth_token auth
	INNER JOIN sign_dates sd ON TRUE
	INNER JOIN canon_data cd ON TRUE
	WHERE auth.auth_token = token_id
		AND auth.status = 'Active'::solaruser.user_auth_token_status
		AND COALESCE(to_timestamp((jpolicy->>'notAfter')::double precision / 1000), req_date) >= req_date;
$$;


ALTER FUNCTION solaruser.snws2_find_token_details(token_id text, req_date timestamp with time zone, host text, path text, signature text) OWNER TO solarnet;

--
-- Name: snws2_find_verified_token_details(text, timestamp with time zone, text, text, text); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.snws2_find_verified_token_details(token_id text, req_date timestamp with time zone, host text, path text, signature text) RETURNS TABLE(user_id bigint, token_type solaruser.user_auth_token_type, jpolicy jsonb)
    LANGUAGE sql STABLE STRICT SECURITY DEFINER ROWS 1
    AS $$
	WITH sign_dates AS (
		SELECT CAST(generate_series(
			(req_date at time zone 'UTC')::date,
			(req_date at time zone 'UTC')::date - interval '6 days',
			-interval '1 day') at time zone 'UTC' AS DATE) as sign_date
	), canon_data AS (
		SELECT solaruser.snws2_signature_data(
			req_date,
			solaruser.snws2_canon_request_data(req_date, host, path)
		) AS sign_data
	)
	SELECT
		user_id,
		token_type,
		jpolicy
	FROM solaruser.user_auth_token auth
	INNER JOIN sign_dates sd ON TRUE
	INNER JOIN canon_data cd ON TRUE
	WHERE auth.auth_token = token_id
		AND auth.status = 'Active'::solaruser.user_auth_token_status
		AND COALESCE(to_timestamp((jpolicy->>'notAfter')::double precision / 1000), req_date) >= req_date
		AND solaruser.snws2_signature(
				sign_data,
				solaruser.snws2_signing_key(sd.sign_date, auth.auth_secret)
			) = signature;
$$;


ALTER FUNCTION solaruser.snws2_find_verified_token_details(token_id text, req_date timestamp with time zone, host text, path text, signature text) OWNER TO solarnet;

--
-- Name: snws2_signature(text, bytea); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.snws2_signature(signature_data text, sign_key bytea) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
	SELECT encode(hmac(convert_to(signature_data, 'UTF8'), sign_key, 'sha256'), 'hex');
$$;


ALTER FUNCTION solaruser.snws2_signature(signature_data text, sign_key bytea) OWNER TO solarnet;

--
-- Name: snws2_signature_data(timestamp with time zone, text); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.snws2_signature_data(req_date timestamp with time zone, canon_request_data text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
	SELECT E'SNWS2-HMAC-SHA256\n'
		|| to_char(req_date at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"') || E'\n'
		|| encode(digest(canon_request_data, 'sha256'), 'hex');
$$;


ALTER FUNCTION solaruser.snws2_signature_data(req_date timestamp with time zone, canon_request_data text) OWNER TO solarnet;

--
-- Name: snws2_signing_key(date, text); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.snws2_signing_key(sign_date date, secret text) RETURNS bytea
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
	SELECT hmac('snws2_request', hmac(to_char(sign_date, 'YYYYMMDD'), 'SNWS2' || secret, 'sha256'), 'sha256');
$$;


ALTER FUNCTION solaruser.snws2_signing_key(sign_date date, secret text) OWNER TO solarnet;

--
-- Name: snws2_signing_key_hex(date, text); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.snws2_signing_key_hex(sign_date date, secret text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
	SELECT encode(solaruser.snws2_signing_key(sign_date, secret), 'hex');
$$;


ALTER FUNCTION solaruser.snws2_signing_key_hex(sign_date date, secret text) OWNER TO solarnet;

--
-- Name: snws2_validated_request_date(timestamp with time zone, interval); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.snws2_validated_request_date(req_date timestamp with time zone, tolerance interval DEFAULT '00:05:00'::interval) RETURNS boolean
    LANGUAGE sql STABLE STRICT
    AS $$
	SELECT req_date BETWEEN CURRENT_TIMESTAMP - tolerance AND CURRENT_TIMESTAMP + tolerance
$$;


ALTER FUNCTION solaruser.snws2_validated_request_date(req_date timestamp with time zone, tolerance interval) OWNER TO solarnet;

--
-- Name: store_adhoc_export_task(bigint, character, text); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.store_adhoc_export_task(usr bigint, sched character, cfg text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
	t_id uuid;
BEGIN
	t_id := gen_random_uuid();
	PERFORM solarnet.add_datum_export_task(t_id, CURRENT_TIMESTAMP, cfg);
	INSERT INTO solaruser.user_adhoc_export_task
		(user_id, schedule, task_id)
	VALUES
		(usr, sched, t_id);

	RETURN t_id;
END;
$$;


ALTER FUNCTION solaruser.store_adhoc_export_task(usr bigint, sched character, cfg text) OWNER TO solarnet;

--
-- Name: store_adhoc_export_task(bigint, character, timestamp with time zone, text); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.store_adhoc_export_task(usr bigint, sched character, ex_date timestamp with time zone, cfg text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
	t_id uuid;
BEGIN
	SELECT task_id INTO t_id
	FROM solaruser.user_adhoc_export_task
	WHERE user_id = usr
		AND schedule = sched
		AND export_date = ex_date
	LIMIT 1
	FOR UPDATE;

	IF NOT FOUND THEN
		t_id := gen_random_uuid();
		PERFORM solarnet.add_datum_export_task(t_id, ex_date, cfg);
		INSERT INTO solaruser.user_adhoc_export_task
			(user_id, schedule, export_date, task_id)
		VALUES
			(usr, sched, ex_date, t_id);
	END IF;

	RETURN t_id;
END;
$$;


ALTER FUNCTION solaruser.store_adhoc_export_task(usr bigint, sched character, ex_date timestamp with time zone, cfg text) OWNER TO solarnet;

--
-- Name: store_export_task(bigint, character, timestamp with time zone, bigint, text); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.store_export_task(usr bigint, sched character, ex_date timestamp with time zone, cfg_id bigint, cfg text) RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
	t_id uuid;
BEGIN
	SELECT task_id INTO t_id
	FROM solaruser.user_export_task
	WHERE user_id = usr
		AND schedule = sched
		AND export_date = ex_date
	LIMIT 1
	FOR UPDATE;

	IF NOT FOUND THEN
		t_id := gen_random_uuid();
		PERFORM solarnet.add_datum_export_task(t_id, ex_date, cfg);
		INSERT INTO solaruser.user_export_task
			(user_id, schedule, export_date, task_id, conf_id)
		VALUES
			(usr, sched, ex_date, t_id, cfg_id);
	END IF;

	RETURN t_id;
END;
$$;


ALTER FUNCTION solaruser.store_export_task(usr bigint, sched character, ex_date timestamp with time zone, cfg_id bigint, cfg text) OWNER TO solarnet;

--
-- Name: store_user_data(bigint, jsonb); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.store_user_data(user_id bigint, json_obj jsonb) RETURNS void
    LANGUAGE sql
    AS $$
	UPDATE solaruser.user_user
	SET jdata = jsonb_strip_nulls(COALESCE(jdata, '{}'::jsonb) || json_obj)
	WHERE id = user_id
$$;


ALTER FUNCTION solaruser.store_user_data(user_id bigint, json_obj jsonb) OWNER TO solarnet;

--
-- Name: store_user_meta(timestamp with time zone, bigint, text); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.store_user_meta(cdate timestamp with time zone, userid bigint, jdata text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	udate timestamp with time zone := now();
	jdata_json jsonb := jdata::jsonb;
BEGIN
	INSERT INTO solaruser.user_meta(user_id, created, updated, jdata)
	VALUES (userid, cdate, udate, jdata_json)
	ON CONFLICT (user_id) DO UPDATE
	SET jdata = EXCLUDED.jdata, updated = EXCLUDED.updated;
END;
$$;


ALTER FUNCTION solaruser.store_user_meta(cdate timestamp with time zone, userid bigint, jdata text) OWNER TO solarnet;

--
-- Name: store_user_node_cert(timestamp with time zone, bigint, bigint, character, text, bytea); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.store_user_node_cert(created timestamp with time zone, node bigint, userid bigint, stat character, request text, keydata bytea) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
	ts TIMESTAMP WITH TIME ZONE := (CASE WHEN created IS NULL THEN now() ELSE created END);
BEGIN
	BEGIN
		INSERT INTO solaruser.user_node_cert(created, node_id, user_id, status, request_id, keystore)
		VALUES (ts, node, userid, stat, request, keydata);
	EXCEPTION WHEN unique_violation THEN
		UPDATE solaruser.user_node_cert SET
			keystore = keydata,
			status = stat,
			request_id = request
		WHERE
			node_id = node
			AND user_id = userid;
	END;
END;$$;


ALTER FUNCTION solaruser.store_user_node_cert(created timestamp with time zone, node bigint, userid bigint, stat character, request text, keydata bytea) OWNER TO solarnet;

--
-- Name: store_user_node_xfer(bigint, bigint, character varying); Type: FUNCTION; Schema: solaruser; Owner: solarnet
--

CREATE FUNCTION solaruser.store_user_node_xfer(node bigint, userid bigint, recip character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
	BEGIN
		INSERT INTO solaruser.user_node_xfer(node_id, user_id, recipient)
		VALUES (node, userid, recip);
	EXCEPTION WHEN unique_violation THEN
		UPDATE solaruser.user_node_xfer SET
			recipient = recip
		WHERE
			node_id = node
			AND user_id = userid;
	END;
END;$$;


ALTER FUNCTION solaruser.store_user_node_xfer(node bigint, userid bigint, recip character varying) OWNER TO solarnet;

--
-- Name: first(anyelement); Type: AGGREGATE; Schema: solarcommon; Owner: solarnet
--

CREATE AGGREGATE solarcommon.first(anyelement) (
    SFUNC = solarcommon.first_sfunc,
    STYPE = anyelement
);


ALTER AGGREGATE solarcommon.first(anyelement) OWNER TO solarnet;

--
-- Name: jsonb_avg(jsonb); Type: AGGREGATE; Schema: solarcommon; Owner: solarnet
--

CREATE AGGREGATE solarcommon.jsonb_avg(jsonb) (
    SFUNC = solarcommon.jsonb_avg_sfunc,
    STYPE = jsonb,
    FINALFUNC = solarcommon.jsonb_avg_finalfunc
);


ALTER AGGREGATE solarcommon.jsonb_avg(jsonb) OWNER TO solarnet;

--
-- Name: jsonb_avg_object(jsonb); Type: AGGREGATE; Schema: solarcommon; Owner: solarnet
--

CREATE AGGREGATE solarcommon.jsonb_avg_object(jsonb) (
    SFUNC = solarcommon.jsonb_avg_object_sfunc,
    STYPE = jsonb,
    FINALFUNC = solarcommon.jsonb_avg_object_finalfunc
);


ALTER AGGREGATE solarcommon.jsonb_avg_object(jsonb) OWNER TO solarnet;

--
-- Name: jsonb_diff_object(jsonb); Type: AGGREGATE; Schema: solarcommon; Owner: solarnet
--

CREATE AGGREGATE solarcommon.jsonb_diff_object(jsonb) (
    SFUNC = solarcommon.jsonb_diff_object_sfunc,
    STYPE = jsonb,
    FINALFUNC = solarcommon.jsonb_diff_object_finalfunc
);


ALTER AGGREGATE solarcommon.jsonb_diff_object(jsonb) OWNER TO solarnet;

--
-- Name: jsonb_diffsum_jdata(jsonb); Type: AGGREGATE; Schema: solarcommon; Owner: solarnet
--

CREATE AGGREGATE solarcommon.jsonb_diffsum_jdata(jsonb) (
    SFUNC = solarcommon.jsonb_diffsum_object_sfunc,
    STYPE = jsonb,
    FINALFUNC = solarcommon.jsonb_diffsum_jdata_finalfunc
);


ALTER AGGREGATE solarcommon.jsonb_diffsum_jdata(jsonb) OWNER TO solarnet;

--
-- Name: jsonb_diffsum_object(jsonb); Type: AGGREGATE; Schema: solarcommon; Owner: solarnet
--

CREATE AGGREGATE solarcommon.jsonb_diffsum_object(jsonb) (
    SFUNC = solarcommon.jsonb_diffsum_object_sfunc,
    STYPE = jsonb,
    FINALFUNC = solarcommon.jsonb_diffsum_object_finalfunc
);


ALTER AGGREGATE solarcommon.jsonb_diffsum_object(jsonb) OWNER TO solarnet;

--
-- Name: jsonb_sum(jsonb); Type: AGGREGATE; Schema: solarcommon; Owner: solarnet
--

CREATE AGGREGATE solarcommon.jsonb_sum(jsonb) (
    SFUNC = solarcommon.jsonb_sum_sfunc,
    STYPE = jsonb
);


ALTER AGGREGATE solarcommon.jsonb_sum(jsonb) OWNER TO solarnet;

--
-- Name: jsonb_sum_object(jsonb); Type: AGGREGATE; Schema: solarcommon; Owner: solarnet
--

CREATE AGGREGATE solarcommon.jsonb_sum_object(jsonb) (
    SFUNC = solarcommon.jsonb_sum_object_sfunc,
    STYPE = jsonb
);


ALTER AGGREGATE solarcommon.jsonb_sum_object(jsonb) OWNER TO solarnet;

--
-- Name: jsonb_weighted_proj_object(jsonb, double precision); Type: AGGREGATE; Schema: solarcommon; Owner: solarnet
--

CREATE AGGREGATE solarcommon.jsonb_weighted_proj_object(jsonb, double precision) (
    SFUNC = solarcommon.jsonb_weighted_proj_object_sfunc,
    STYPE = jsonb,
    FINALFUNC = solarcommon.jsonb_weighted_proj_object_finalfunc
);


ALTER AGGREGATE solarcommon.jsonb_weighted_proj_object(jsonb, double precision) OWNER TO solarnet;

--
-- Name: jsonb_weighted_proj_sum_object(jsonb, text, double precision); Type: AGGREGATE; Schema: solarcommon; Owner: solarnet
--

CREATE AGGREGATE solarcommon.jsonb_weighted_proj_sum_object(jsonb, text, double precision) (
    SFUNC = solarcommon.jsonb_weighted_proj_sum_object_sfunc,
    STYPE = jsonb,
    FINALFUNC = solarcommon.jsonb_weighted_proj_sum_object_finalfunc
);


ALTER AGGREGATE solarcommon.jsonb_weighted_proj_sum_object(jsonb, text, double precision) OWNER TO solarnet;

--
-- Name: aud_loc_datum_hourly; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.aud_loc_datum_hourly (
    ts_start timestamp with time zone NOT NULL,
    loc_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    prop_count integer NOT NULL
);


ALTER TABLE solaragg.aud_loc_datum_hourly OWNER TO solarnet;

--
-- Name: _hyper_10_1864_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_10_1864_chunk (
    CONSTRAINT constraint_1864 CHECK (((ts_start >= '2019-01-01 19:00:00+13'::timestamp with time zone) AND (ts_start < '2020-01-02 01:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.aud_loc_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_10_1864_chunk OWNER TO solarnet;

--
-- Name: _hyper_10_82_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_10_82_chunk (
    CONSTRAINT constraint_82 CHECK (((ts_start >= '2017-01-01 07:00:00+13'::timestamp with time zone) AND (ts_start < '2018-01-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.aud_loc_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_10_82_chunk OWNER TO solarnet;

--
-- Name: _hyper_10_85_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_10_85_chunk (
    CONSTRAINT constraint_85 CHECK (((ts_start >= '2018-01-01 13:00:00+13'::timestamp with time zone) AND (ts_start < '2019-01-01 19:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.aud_loc_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_10_85_chunk OWNER TO solarnet;

--
-- Name: aud_datum_daily; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.aud_datum_daily (
    ts_start timestamp with time zone NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    prop_count bigint DEFAULT 0 NOT NULL,
    datum_q_count bigint DEFAULT 0 NOT NULL,
    datum_count integer DEFAULT 0 NOT NULL,
    datum_hourly_count smallint DEFAULT 0 NOT NULL,
    datum_daily_pres boolean DEFAULT false NOT NULL,
    processed_count timestamp with time zone DEFAULT now() NOT NULL,
    processed_hourly_count timestamp with time zone DEFAULT now() NOT NULL,
    processed_io_count timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE solaragg.aud_datum_daily OWNER TO solarnet;

--
-- Name: _hyper_11_1826_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_11_1826_chunk (
    CONSTRAINT constraint_1826 CHECK (((ts_start >= '2016-04-29 12:00:00+12'::timestamp with time zone) AND (ts_start < '2017-04-24 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_11_1826_chunk OWNER TO solarnet;

--
-- Name: _hyper_11_1827_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_11_1827_chunk (
    CONSTRAINT constraint_1827 CHECK (((ts_start >= '2018-04-19 12:00:00+12'::timestamp with time zone) AND (ts_start < '2019-04-14 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_11_1827_chunk OWNER TO solarnet;

--
-- Name: _hyper_11_1829_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_11_1829_chunk (
    CONSTRAINT constraint_1829 CHECK (((ts_start >= '2010-05-31 12:00:00+12'::timestamp with time zone) AND (ts_start < '2011-05-26 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_11_1829_chunk OWNER TO solarnet;

--
-- Name: _hyper_11_1830_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_11_1830_chunk (
    CONSTRAINT constraint_1830 CHECK (((ts_start >= '2011-05-26 12:00:00+12'::timestamp with time zone) AND (ts_start < '2012-05-20 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_11_1830_chunk OWNER TO solarnet;

--
-- Name: _hyper_11_1831_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_11_1831_chunk (
    CONSTRAINT constraint_1831 CHECK (((ts_start >= '2009-06-05 12:00:00+12'::timestamp with time zone) AND (ts_start < '2010-05-31 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_11_1831_chunk OWNER TO solarnet;

--
-- Name: _hyper_11_1832_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_11_1832_chunk (
    CONSTRAINT constraint_1832 CHECK (((ts_start >= '2012-05-20 12:00:00+12'::timestamp with time zone) AND (ts_start < '2013-05-15 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_11_1832_chunk OWNER TO solarnet;

--
-- Name: _hyper_11_1833_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_11_1833_chunk (
    CONSTRAINT constraint_1833 CHECK (((ts_start >= '2013-05-15 12:00:00+12'::timestamp with time zone) AND (ts_start < '2014-05-10 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_11_1833_chunk OWNER TO solarnet;

--
-- Name: _hyper_11_1834_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_11_1834_chunk (
    CONSTRAINT constraint_1834 CHECK (((ts_start >= '2014-05-10 12:00:00+12'::timestamp with time zone) AND (ts_start < '2015-05-05 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_11_1834_chunk OWNER TO solarnet;

--
-- Name: _hyper_11_1835_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_11_1835_chunk (
    CONSTRAINT constraint_1835 CHECK (((ts_start >= '2015-05-05 12:00:00+12'::timestamp with time zone) AND (ts_start < '2016-04-29 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_11_1835_chunk OWNER TO solarnet;

--
-- Name: _hyper_11_1836_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_11_1836_chunk (
    CONSTRAINT constraint_1836 CHECK (((ts_start >= '2017-04-24 12:00:00+12'::timestamp with time zone) AND (ts_start < '2018-04-19 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_11_1836_chunk OWNER TO solarnet;

--
-- Name: _hyper_11_1837_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_11_1837_chunk (
    CONSTRAINT constraint_1837 CHECK (((ts_start >= '2008-06-10 12:00:00+12'::timestamp with time zone) AND (ts_start < '2009-06-05 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_11_1837_chunk OWNER TO solarnet;

--
-- Name: aud_datum_monthly; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.aud_datum_monthly (
    ts_start timestamp with time zone NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    prop_count bigint DEFAULT 0 NOT NULL,
    datum_q_count bigint DEFAULT 0 NOT NULL,
    datum_count integer DEFAULT 0 NOT NULL,
    datum_hourly_count smallint DEFAULT 0 NOT NULL,
    datum_daily_count smallint DEFAULT 0 NOT NULL,
    datum_monthly_pres boolean DEFAULT false NOT NULL,
    processed timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE solaragg.aud_datum_monthly OWNER TO solarnet;

--
-- Name: _hyper_12_1828_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_12_1828_chunk (
    CONSTRAINT constraint_1828 CHECK (((ts_start >= '2014-05-10 12:00:00+12'::timestamp with time zone) AND (ts_start < '2019-04-14 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_monthly);


ALTER TABLE _timescaledb_internal._hyper_12_1828_chunk OWNER TO solarnet;

--
-- Name: _hyper_12_1838_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_12_1838_chunk (
    CONSTRAINT constraint_1838 CHECK (((ts_start >= '2009-06-05 12:00:00+12'::timestamp with time zone) AND (ts_start < '2014-05-10 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_monthly);


ALTER TABLE _timescaledb_internal._hyper_12_1838_chunk OWNER TO solarnet;

--
-- Name: _hyper_12_1839_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_12_1839_chunk (
    CONSTRAINT constraint_1839 CHECK (((ts_start >= '2004-07-01 12:00:00+12'::timestamp with time zone) AND (ts_start < '2009-06-05 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_monthly);


ALTER TABLE _timescaledb_internal._hyper_12_1839_chunk OWNER TO solarnet;

--
-- Name: aud_acc_datum_daily; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.aud_acc_datum_daily (
    ts_start timestamp with time zone NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    datum_count integer DEFAULT 0 NOT NULL,
    datum_hourly_count integer DEFAULT 0 NOT NULL,
    datum_daily_count integer DEFAULT 0 NOT NULL,
    datum_monthly_count integer DEFAULT 0 NOT NULL,
    processed timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE solaragg.aud_acc_datum_daily OWNER TO solarnet;

--
-- Name: _hyper_13_1840_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_13_1840_chunk (
    CONSTRAINT constraint_1840 CHECK (((ts_start >= '2018-04-19 12:00:00+12'::timestamp with time zone) AND (ts_start < '2019-04-14 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_acc_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_13_1840_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_10_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_10_chunk (
    CONSTRAINT constraint_10 CHECK (((ts >= '2010-05-31 12:00:00+12'::timestamp with time zone) AND (ts < '2010-11-27 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_10_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_11_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_11_chunk (
    CONSTRAINT constraint_11 CHECK (((ts >= '2010-11-27 13:00:00+13'::timestamp with time zone) AND (ts < '2011-05-26 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_11_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_12_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_12_chunk (
    CONSTRAINT constraint_12 CHECK (((ts >= '2011-05-26 12:00:00+12'::timestamp with time zone) AND (ts < '2011-11-22 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_12_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_13_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_13_chunk (
    CONSTRAINT constraint_13 CHECK (((ts >= '2011-11-22 13:00:00+13'::timestamp with time zone) AND (ts < '2012-05-20 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_13_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_14_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_14_chunk (
    CONSTRAINT constraint_14 CHECK (((ts >= '2012-05-20 12:00:00+12'::timestamp with time zone) AND (ts < '2012-11-16 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_14_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_15_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_15_chunk (
    CONSTRAINT constraint_15 CHECK (((ts >= '2015-05-05 12:00:00+12'::timestamp with time zone) AND (ts < '2015-11-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_15_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_16_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_16_chunk (
    CONSTRAINT constraint_16 CHECK (((ts >= '2015-11-01 13:00:00+13'::timestamp with time zone) AND (ts < '2016-04-29 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_16_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_17_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_17_chunk (
    CONSTRAINT constraint_17 CHECK (((ts >= '2016-04-29 12:00:00+12'::timestamp with time zone) AND (ts < '2016-10-26 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_17_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_1803_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_1803_chunk (
    CONSTRAINT constraint_1803 CHECK (((ts >= '2018-04-19 12:00:00+12'::timestamp with time zone) AND (ts < '2018-04-19 14:09:36+12'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_1803_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_1825_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_1825_chunk (
    CONSTRAINT constraint_1825 CHECK (((ts >= '2018-04-19 14:09:36+12'::timestamp with time zone) AND (ts < '2018-07-18 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_1825_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_1858_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_1858_chunk (
    CONSTRAINT constraint_1858 CHECK (((ts >= '2018-07-18 12:00:00+12'::timestamp with time zone) AND (ts < '2018-10-16 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_1858_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_1859_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_1859_chunk (
    CONSTRAINT constraint_1859 CHECK (((ts >= '2018-10-16 13:00:00+13'::timestamp with time zone) AND (ts < '2019-01-14 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_1859_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_1866_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_1866_chunk (
    CONSTRAINT constraint_1866 CHECK (((ts >= '2019-01-14 13:00:00+13'::timestamp with time zone) AND (ts < '2019-04-14 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_1866_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_18_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_18_chunk (
    CONSTRAINT constraint_18 CHECK (((ts >= '2016-10-26 13:00:00+13'::timestamp with time zone) AND (ts < '2017-04-24 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_18_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_19_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_19_chunk (
    CONSTRAINT constraint_19 CHECK (((ts >= '2017-04-24 12:00:00+12'::timestamp with time zone) AND (ts < '2017-10-21 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_19_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_1_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_1_chunk (
    CONSTRAINT constraint_1 CHECK (((ts >= '2013-05-15 12:00:00+12'::timestamp with time zone) AND (ts < '2013-11-11 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_1_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_20_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_20_chunk (
    CONSTRAINT constraint_20 CHECK (((ts >= '2017-10-21 13:00:00+13'::timestamp with time zone) AND (ts < '2018-04-19 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_20_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_2_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_2_chunk (
    CONSTRAINT constraint_2 CHECK (((ts >= '2012-11-16 13:00:00+13'::timestamp with time zone) AND (ts < '2013-05-15 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_2_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_3_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_3_chunk (
    CONSTRAINT constraint_3 CHECK (((ts >= '2013-11-11 13:00:00+13'::timestamp with time zone) AND (ts < '2014-05-10 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_3_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_4_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_4_chunk (
    CONSTRAINT constraint_4 CHECK (((ts >= '2014-05-10 12:00:00+12'::timestamp with time zone) AND (ts < '2014-11-06 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_4_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_5_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_5_chunk (
    CONSTRAINT constraint_5 CHECK (((ts >= '2014-11-06 13:00:00+13'::timestamp with time zone) AND (ts < '2015-05-05 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_5_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_6_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_6_chunk (
    CONSTRAINT constraint_6 CHECK (((ts >= '2008-06-10 12:00:00+12'::timestamp with time zone) AND (ts < '2008-12-07 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_6_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_7_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_7_chunk (
    CONSTRAINT constraint_7 CHECK (((ts >= '2008-12-07 13:00:00+13'::timestamp with time zone) AND (ts < '2009-06-05 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_7_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_8_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_8_chunk (
    CONSTRAINT constraint_8 CHECK (((ts >= '2009-06-05 12:00:00+12'::timestamp with time zone) AND (ts < '2009-12-02 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_8_chunk OWNER TO solarnet;

--
-- Name: _hyper_1_9_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_1_9_chunk (
    CONSTRAINT constraint_9 CHECK (((ts >= '2009-12-02 13:00:00+13'::timestamp with time zone) AND (ts < '2010-05-31 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solardatum.da_datum);


ALTER TABLE _timescaledb_internal._hyper_1_9_chunk OWNER TO solarnet;

--
-- Name: _hyper_2_1862_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_2_1862_chunk (
    CONSTRAINT constraint_1862 CHECK (((ts >= '2019-01-01 19:00:00+13'::timestamp with time zone) AND (ts < '2020-01-02 01:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_loc_datum);


ALTER TABLE _timescaledb_internal._hyper_2_1862_chunk OWNER TO solarnet;

--
-- Name: _hyper_2_21_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_2_21_chunk (
    CONSTRAINT constraint_21 CHECK (((ts >= '2013-01-01 07:00:00+13'::timestamp with time zone) AND (ts < '2014-01-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_loc_datum);


ALTER TABLE _timescaledb_internal._hyper_2_21_chunk OWNER TO solarnet;

--
-- Name: _hyper_2_22_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_2_22_chunk (
    CONSTRAINT constraint_22 CHECK (((ts >= '2012-01-02 01:00:00+13'::timestamp with time zone) AND (ts < '2013-01-01 07:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_loc_datum);


ALTER TABLE _timescaledb_internal._hyper_2_22_chunk OWNER TO solarnet;

--
-- Name: _hyper_2_23_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_2_23_chunk (
    CONSTRAINT constraint_23 CHECK (((ts >= '2014-01-01 13:00:00+13'::timestamp with time zone) AND (ts < '2015-01-01 19:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_loc_datum);


ALTER TABLE _timescaledb_internal._hyper_2_23_chunk OWNER TO solarnet;

--
-- Name: _hyper_2_24_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_2_24_chunk (
    CONSTRAINT constraint_24 CHECK (((ts >= '2015-01-01 19:00:00+13'::timestamp with time zone) AND (ts < '2016-01-02 01:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_loc_datum);


ALTER TABLE _timescaledb_internal._hyper_2_24_chunk OWNER TO solarnet;

--
-- Name: _hyper_2_25_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_2_25_chunk (
    CONSTRAINT constraint_25 CHECK (((ts >= '2008-01-02 01:00:00+13'::timestamp with time zone) AND (ts < '2009-01-01 07:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_loc_datum);


ALTER TABLE _timescaledb_internal._hyper_2_25_chunk OWNER TO solarnet;

--
-- Name: _hyper_2_26_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_2_26_chunk (
    CONSTRAINT constraint_26 CHECK (((ts >= '2009-01-01 07:00:00+13'::timestamp with time zone) AND (ts < '2010-01-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_loc_datum);


ALTER TABLE _timescaledb_internal._hyper_2_26_chunk OWNER TO solarnet;

--
-- Name: _hyper_2_27_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_2_27_chunk (
    CONSTRAINT constraint_27 CHECK (((ts >= '2010-01-01 13:00:00+13'::timestamp with time zone) AND (ts < '2011-01-01 19:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_loc_datum);


ALTER TABLE _timescaledb_internal._hyper_2_27_chunk OWNER TO solarnet;

--
-- Name: _hyper_2_28_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_2_28_chunk (
    CONSTRAINT constraint_28 CHECK (((ts >= '2011-01-01 19:00:00+13'::timestamp with time zone) AND (ts < '2012-01-02 01:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_loc_datum);


ALTER TABLE _timescaledb_internal._hyper_2_28_chunk OWNER TO solarnet;

--
-- Name: _hyper_2_29_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_2_29_chunk (
    CONSTRAINT constraint_29 CHECK (((ts >= '2016-01-02 01:00:00+13'::timestamp with time zone) AND (ts < '2017-01-01 07:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_loc_datum);


ALTER TABLE _timescaledb_internal._hyper_2_29_chunk OWNER TO solarnet;

--
-- Name: _hyper_2_30_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_2_30_chunk (
    CONSTRAINT constraint_30 CHECK (((ts >= '2017-01-01 07:00:00+13'::timestamp with time zone) AND (ts < '2018-01-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_loc_datum);


ALTER TABLE _timescaledb_internal._hyper_2_30_chunk OWNER TO solarnet;

--
-- Name: _hyper_2_83_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_2_83_chunk (
    CONSTRAINT constraint_83 CHECK (((ts >= '2018-01-01 13:00:00+13'::timestamp with time zone) AND (ts < '2019-01-01 19:00:00+13'::timestamp with time zone)))
)
INHERITS (solardatum.da_loc_datum);


ALTER TABLE _timescaledb_internal._hyper_2_83_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_1804_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_1804_chunk (
    CONSTRAINT constraint_1804 CHECK (((ts_start >= '2018-04-19 12:00:00+12'::timestamp with time zone) AND (ts_start < '2018-10-16 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_1804_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_1860_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_1860_chunk (
    CONSTRAINT constraint_1860 CHECK (((ts_start >= '2018-10-16 13:00:00+13'::timestamp with time zone) AND (ts_start < '2019-04-14 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_1860_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_31_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_31_chunk (
    CONSTRAINT constraint_31 CHECK (((ts_start >= '2008-06-10 12:00:00+12'::timestamp with time zone) AND (ts_start < '2008-12-07 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_31_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_32_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_32_chunk (
    CONSTRAINT constraint_32 CHECK (((ts_start >= '2009-06-05 12:00:00+12'::timestamp with time zone) AND (ts_start < '2009-12-02 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_32_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_33_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_33_chunk (
    CONSTRAINT constraint_33 CHECK (((ts_start >= '2008-12-07 13:00:00+13'::timestamp with time zone) AND (ts_start < '2009-06-05 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_33_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_34_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_34_chunk (
    CONSTRAINT constraint_34 CHECK (((ts_start >= '2009-12-02 13:00:00+13'::timestamp with time zone) AND (ts_start < '2010-05-31 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_34_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_35_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_35_chunk (
    CONSTRAINT constraint_35 CHECK (((ts_start >= '2011-11-22 13:00:00+13'::timestamp with time zone) AND (ts_start < '2012-05-20 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_35_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_36_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_36_chunk (
    CONSTRAINT constraint_36 CHECK (((ts_start >= '2012-05-20 12:00:00+12'::timestamp with time zone) AND (ts_start < '2012-11-16 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_36_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_37_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_37_chunk (
    CONSTRAINT constraint_37 CHECK (((ts_start >= '2012-11-16 13:00:00+13'::timestamp with time zone) AND (ts_start < '2013-05-15 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_37_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_38_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_38_chunk (
    CONSTRAINT constraint_38 CHECK (((ts_start >= '2013-05-15 12:00:00+12'::timestamp with time zone) AND (ts_start < '2013-11-11 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_38_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_39_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_39_chunk (
    CONSTRAINT constraint_39 CHECK (((ts_start >= '2013-11-11 13:00:00+13'::timestamp with time zone) AND (ts_start < '2014-05-10 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_39_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_40_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_40_chunk (
    CONSTRAINT constraint_40 CHECK (((ts_start >= '2014-05-10 12:00:00+12'::timestamp with time zone) AND (ts_start < '2014-11-06 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_40_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_41_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_41_chunk (
    CONSTRAINT constraint_41 CHECK (((ts_start >= '2014-11-06 13:00:00+13'::timestamp with time zone) AND (ts_start < '2015-05-05 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_41_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_42_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_42_chunk (
    CONSTRAINT constraint_42 CHECK (((ts_start >= '2010-05-31 12:00:00+12'::timestamp with time zone) AND (ts_start < '2010-11-27 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_42_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_43_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_43_chunk (
    CONSTRAINT constraint_43 CHECK (((ts_start >= '2010-11-27 13:00:00+13'::timestamp with time zone) AND (ts_start < '2011-05-26 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_43_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_44_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_44_chunk (
    CONSTRAINT constraint_44 CHECK (((ts_start >= '2011-05-26 12:00:00+12'::timestamp with time zone) AND (ts_start < '2011-11-22 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_44_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_45_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_45_chunk (
    CONSTRAINT constraint_45 CHECK (((ts_start >= '2015-05-05 12:00:00+12'::timestamp with time zone) AND (ts_start < '2015-11-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_45_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_46_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_46_chunk (
    CONSTRAINT constraint_46 CHECK (((ts_start >= '2017-10-21 13:00:00+13'::timestamp with time zone) AND (ts_start < '2018-04-19 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_46_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_47_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_47_chunk (
    CONSTRAINT constraint_47 CHECK (((ts_start >= '2016-04-29 12:00:00+12'::timestamp with time zone) AND (ts_start < '2016-10-26 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_47_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_48_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_48_chunk (
    CONSTRAINT constraint_48 CHECK (((ts_start >= '2015-11-01 13:00:00+13'::timestamp with time zone) AND (ts_start < '2016-04-29 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_48_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_49_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_49_chunk (
    CONSTRAINT constraint_49 CHECK (((ts_start >= '2016-10-26 13:00:00+13'::timestamp with time zone) AND (ts_start < '2017-04-24 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_49_chunk OWNER TO solarnet;

--
-- Name: _hyper_3_50_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_3_50_chunk (
    CONSTRAINT constraint_50 CHECK (((ts_start >= '2017-04-24 12:00:00+12'::timestamp with time zone) AND (ts_start < '2017-10-21 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_3_50_chunk OWNER TO solarnet;

--
-- Name: _hyper_4_1865_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_4_1865_chunk (
    CONSTRAINT constraint_1865 CHECK (((ts_start >= '2019-01-01 19:00:00+13'::timestamp with time zone) AND (ts_start < '2020-01-02 01:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_4_1865_chunk OWNER TO solarnet;

--
-- Name: _hyper_4_51_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_4_51_chunk (
    CONSTRAINT constraint_51 CHECK (((ts_start >= '2008-01-02 01:00:00+13'::timestamp with time zone) AND (ts_start < '2009-01-01 07:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_4_51_chunk OWNER TO solarnet;

--
-- Name: _hyper_4_52_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_4_52_chunk (
    CONSTRAINT constraint_52 CHECK (((ts_start >= '2014-01-01 13:00:00+13'::timestamp with time zone) AND (ts_start < '2015-01-01 19:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_4_52_chunk OWNER TO solarnet;

--
-- Name: _hyper_4_53_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_4_53_chunk (
    CONSTRAINT constraint_53 CHECK (((ts_start >= '2009-01-01 07:00:00+13'::timestamp with time zone) AND (ts_start < '2010-01-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_4_53_chunk OWNER TO solarnet;

--
-- Name: _hyper_4_54_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_4_54_chunk (
    CONSTRAINT constraint_54 CHECK (((ts_start >= '2010-01-01 13:00:00+13'::timestamp with time zone) AND (ts_start < '2011-01-01 19:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_4_54_chunk OWNER TO solarnet;

--
-- Name: _hyper_4_55_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_4_55_chunk (
    CONSTRAINT constraint_55 CHECK (((ts_start >= '2011-01-01 19:00:00+13'::timestamp with time zone) AND (ts_start < '2012-01-02 01:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_4_55_chunk OWNER TO solarnet;

--
-- Name: _hyper_4_56_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_4_56_chunk (
    CONSTRAINT constraint_56 CHECK (((ts_start >= '2013-01-01 07:00:00+13'::timestamp with time zone) AND (ts_start < '2014-01-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_4_56_chunk OWNER TO solarnet;

--
-- Name: _hyper_4_57_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_4_57_chunk (
    CONSTRAINT constraint_57 CHECK (((ts_start >= '2015-01-01 19:00:00+13'::timestamp with time zone) AND (ts_start < '2016-01-02 01:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_4_57_chunk OWNER TO solarnet;

--
-- Name: _hyper_4_58_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_4_58_chunk (
    CONSTRAINT constraint_58 CHECK (((ts_start >= '2016-01-02 01:00:00+13'::timestamp with time zone) AND (ts_start < '2017-01-01 07:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_4_58_chunk OWNER TO solarnet;

--
-- Name: _hyper_4_59_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_4_59_chunk (
    CONSTRAINT constraint_59 CHECK (((ts_start >= '2012-01-02 01:00:00+13'::timestamp with time zone) AND (ts_start < '2013-01-01 07:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_4_59_chunk OWNER TO solarnet;

--
-- Name: _hyper_4_60_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_4_60_chunk (
    CONSTRAINT constraint_60 CHECK (((ts_start >= '2017-01-01 07:00:00+13'::timestamp with time zone) AND (ts_start < '2018-01-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_4_60_chunk OWNER TO solarnet;

--
-- Name: _hyper_4_86_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_4_86_chunk (
    CONSTRAINT constraint_86 CHECK (((ts_start >= '2018-01-01 13:00:00+13'::timestamp with time zone) AND (ts_start < '2019-01-01 19:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_4_86_chunk OWNER TO solarnet;

--
-- Name: _hyper_5_61_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_5_61_chunk (
    CONSTRAINT constraint_61 CHECK (((ts_start >= '2005-01-01 07:00:00+13'::timestamp with time zone) AND (ts_start < '2010-01-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_monthly);


ALTER TABLE _timescaledb_internal._hyper_5_61_chunk OWNER TO solarnet;

--
-- Name: _hyper_5_62_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_5_62_chunk (
    CONSTRAINT constraint_62 CHECK (((ts_start >= '2010-01-01 13:00:00+13'::timestamp with time zone) AND (ts_start < '2015-01-01 19:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_monthly);


ALTER TABLE _timescaledb_internal._hyper_5_62_chunk OWNER TO solarnet;

--
-- Name: _hyper_5_63_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_5_63_chunk (
    CONSTRAINT constraint_63 CHECK (((ts_start >= '2015-01-01 19:00:00+13'::timestamp with time zone) AND (ts_start < '2020-01-02 01:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_datum_monthly);


ALTER TABLE _timescaledb_internal._hyper_5_63_chunk OWNER TO solarnet;

--
-- Name: _hyper_6_1863_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_6_1863_chunk (
    CONSTRAINT constraint_1863 CHECK (((ts_start >= '2019-01-01 19:00:00+13'::timestamp with time zone) AND (ts_start < '2020-01-02 01:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_6_1863_chunk OWNER TO solarnet;

--
-- Name: _hyper_6_64_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_6_64_chunk (
    CONSTRAINT constraint_64 CHECK (((ts_start >= '2008-01-02 01:00:00+13'::timestamp with time zone) AND (ts_start < '2009-01-01 07:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_6_64_chunk OWNER TO solarnet;

--
-- Name: _hyper_6_65_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_6_65_chunk (
    CONSTRAINT constraint_65 CHECK (((ts_start >= '2014-01-01 13:00:00+13'::timestamp with time zone) AND (ts_start < '2015-01-01 19:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_6_65_chunk OWNER TO solarnet;

--
-- Name: _hyper_6_66_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_6_66_chunk (
    CONSTRAINT constraint_66 CHECK (((ts_start >= '2009-01-01 07:00:00+13'::timestamp with time zone) AND (ts_start < '2010-01-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_6_66_chunk OWNER TO solarnet;

--
-- Name: _hyper_6_67_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_6_67_chunk (
    CONSTRAINT constraint_67 CHECK (((ts_start >= '2010-01-01 13:00:00+13'::timestamp with time zone) AND (ts_start < '2011-01-01 19:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_6_67_chunk OWNER TO solarnet;

--
-- Name: _hyper_6_68_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_6_68_chunk (
    CONSTRAINT constraint_68 CHECK (((ts_start >= '2011-01-01 19:00:00+13'::timestamp with time zone) AND (ts_start < '2012-01-02 01:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_6_68_chunk OWNER TO solarnet;

--
-- Name: _hyper_6_69_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_6_69_chunk (
    CONSTRAINT constraint_69 CHECK (((ts_start >= '2012-01-02 01:00:00+13'::timestamp with time zone) AND (ts_start < '2013-01-01 07:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_6_69_chunk OWNER TO solarnet;

--
-- Name: _hyper_6_70_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_6_70_chunk (
    CONSTRAINT constraint_70 CHECK (((ts_start >= '2013-01-01 07:00:00+13'::timestamp with time zone) AND (ts_start < '2014-01-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_6_70_chunk OWNER TO solarnet;

--
-- Name: _hyper_6_71_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_6_71_chunk (
    CONSTRAINT constraint_71 CHECK (((ts_start >= '2015-01-01 19:00:00+13'::timestamp with time zone) AND (ts_start < '2016-01-02 01:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_6_71_chunk OWNER TO solarnet;

--
-- Name: _hyper_6_72_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_6_72_chunk (
    CONSTRAINT constraint_72 CHECK (((ts_start >= '2016-01-02 01:00:00+13'::timestamp with time zone) AND (ts_start < '2017-01-01 07:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_6_72_chunk OWNER TO solarnet;

--
-- Name: _hyper_6_73_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_6_73_chunk (
    CONSTRAINT constraint_73 CHECK (((ts_start >= '2017-01-01 07:00:00+13'::timestamp with time zone) AND (ts_start < '2018-01-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_6_73_chunk OWNER TO solarnet;

--
-- Name: _hyper_6_84_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_6_84_chunk (
    CONSTRAINT constraint_84 CHECK (((ts_start >= '2018-01-01 13:00:00+13'::timestamp with time zone) AND (ts_start < '2019-01-01 19:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_6_84_chunk OWNER TO solarnet;

--
-- Name: _hyper_7_74_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_7_74_chunk (
    CONSTRAINT constraint_74 CHECK (((ts_start >= '2005-01-01 07:00:00+13'::timestamp with time zone) AND (ts_start < '2010-01-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_7_74_chunk OWNER TO solarnet;

--
-- Name: _hyper_7_75_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_7_75_chunk (
    CONSTRAINT constraint_75 CHECK (((ts_start >= '2010-01-01 13:00:00+13'::timestamp with time zone) AND (ts_start < '2015-01-01 19:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_7_75_chunk OWNER TO solarnet;

--
-- Name: _hyper_7_76_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_7_76_chunk (
    CONSTRAINT constraint_76 CHECK (((ts_start >= '2015-01-01 19:00:00+13'::timestamp with time zone) AND (ts_start < '2020-01-02 01:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_daily);


ALTER TABLE _timescaledb_internal._hyper_7_76_chunk OWNER TO solarnet;

--
-- Name: _hyper_8_77_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_8_77_chunk (
    CONSTRAINT constraint_77 CHECK (((ts_start >= '2000-01-02 01:00:00+13'::timestamp with time zone) AND (ts_start < '2010-01-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_monthly);


ALTER TABLE _timescaledb_internal._hyper_8_77_chunk OWNER TO solarnet;

--
-- Name: _hyper_8_78_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_8_78_chunk (
    CONSTRAINT constraint_78 CHECK (((ts_start >= '2010-01-01 13:00:00+13'::timestamp with time zone) AND (ts_start < '2020-01-02 01:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.agg_loc_datum_monthly);


ALTER TABLE _timescaledb_internal._hyper_8_78_chunk OWNER TO solarnet;

--
-- Name: aud_datum_hourly; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.aud_datum_hourly (
    ts_start timestamp with time zone NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    prop_count integer DEFAULT 0 NOT NULL,
    datum_q_count integer DEFAULT 0 NOT NULL,
    datum_count integer DEFAULT 0 NOT NULL
);


ALTER TABLE solaragg.aud_datum_hourly OWNER TO solarnet;

--
-- Name: _hyper_9_147_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_147_chunk (
    CONSTRAINT constraint_147 CHECK (((ts_start >= '2018-04-19 12:00:00+12'::timestamp with time zone) AND (ts_start < '2018-10-16 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_147_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1841_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1841_chunk (
    CONSTRAINT constraint_1841 CHECK (((ts_start >= '2010-11-27 13:00:00+13'::timestamp with time zone) AND (ts_start < '2011-05-26 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1841_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1842_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1842_chunk (
    CONSTRAINT constraint_1842 CHECK (((ts_start >= '2011-05-26 12:00:00+12'::timestamp with time zone) AND (ts_start < '2011-11-22 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1842_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1843_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1843_chunk (
    CONSTRAINT constraint_1843 CHECK (((ts_start >= '2011-11-22 13:00:00+13'::timestamp with time zone) AND (ts_start < '2012-05-20 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1843_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1844_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1844_chunk (
    CONSTRAINT constraint_1844 CHECK (((ts_start >= '2009-06-05 12:00:00+12'::timestamp with time zone) AND (ts_start < '2009-12-02 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1844_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1845_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1845_chunk (
    CONSTRAINT constraint_1845 CHECK (((ts_start >= '2009-12-02 13:00:00+13'::timestamp with time zone) AND (ts_start < '2010-05-31 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1845_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1846_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1846_chunk (
    CONSTRAINT constraint_1846 CHECK (((ts_start >= '2010-05-31 12:00:00+12'::timestamp with time zone) AND (ts_start < '2010-11-27 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1846_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1847_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1847_chunk (
    CONSTRAINT constraint_1847 CHECK (((ts_start >= '2012-05-20 12:00:00+12'::timestamp with time zone) AND (ts_start < '2012-11-16 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1847_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1848_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1848_chunk (
    CONSTRAINT constraint_1848 CHECK (((ts_start >= '2012-11-16 13:00:00+13'::timestamp with time zone) AND (ts_start < '2013-05-15 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1848_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1849_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1849_chunk (
    CONSTRAINT constraint_1849 CHECK (((ts_start >= '2013-05-15 12:00:00+12'::timestamp with time zone) AND (ts_start < '2013-11-11 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1849_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1850_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1850_chunk (
    CONSTRAINT constraint_1850 CHECK (((ts_start >= '2013-11-11 13:00:00+13'::timestamp with time zone) AND (ts_start < '2014-05-10 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1850_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1851_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1851_chunk (
    CONSTRAINT constraint_1851 CHECK (((ts_start >= '2014-05-10 12:00:00+12'::timestamp with time zone) AND (ts_start < '2014-11-06 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1851_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1852_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1852_chunk (
    CONSTRAINT constraint_1852 CHECK (((ts_start >= '2014-11-06 13:00:00+13'::timestamp with time zone) AND (ts_start < '2015-05-05 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1852_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1853_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1853_chunk (
    CONSTRAINT constraint_1853 CHECK (((ts_start >= '2015-05-05 12:00:00+12'::timestamp with time zone) AND (ts_start < '2015-11-01 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1853_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1854_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1854_chunk (
    CONSTRAINT constraint_1854 CHECK (((ts_start >= '2015-11-01 13:00:00+13'::timestamp with time zone) AND (ts_start < '2016-04-29 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1854_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1855_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1855_chunk (
    CONSTRAINT constraint_1855 CHECK (((ts_start >= '2016-04-29 12:00:00+12'::timestamp with time zone) AND (ts_start < '2016-10-26 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1855_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1856_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1856_chunk (
    CONSTRAINT constraint_1856 CHECK (((ts_start >= '2008-06-10 12:00:00+12'::timestamp with time zone) AND (ts_start < '2008-12-07 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1856_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1857_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1857_chunk (
    CONSTRAINT constraint_1857 CHECK (((ts_start >= '2008-12-07 13:00:00+13'::timestamp with time zone) AND (ts_start < '2009-06-05 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1857_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_1861_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_1861_chunk (
    CONSTRAINT constraint_1861 CHECK (((ts_start >= '2018-10-16 13:00:00+13'::timestamp with time zone) AND (ts_start < '2019-04-14 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_1861_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_79_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_79_chunk (
    CONSTRAINT constraint_79 CHECK (((ts_start >= '2017-04-24 12:00:00+12'::timestamp with time zone) AND (ts_start < '2017-10-21 13:00:00+13'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_79_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_80_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_80_chunk (
    CONSTRAINT constraint_80 CHECK (((ts_start >= '2016-10-26 13:00:00+13'::timestamp with time zone) AND (ts_start < '2017-04-24 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_80_chunk OWNER TO solarnet;

--
-- Name: _hyper_9_81_chunk; Type: TABLE; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TABLE _timescaledb_internal._hyper_9_81_chunk (
    CONSTRAINT constraint_81 CHECK (((ts_start >= '2017-10-21 13:00:00+13'::timestamp with time zone) AND (ts_start < '2018-04-19 12:00:00+12'::timestamp with time zone)))
)
INHERITS (solaragg.aud_datum_hourly);


ALTER TABLE _timescaledb_internal._hyper_9_81_chunk OWNER TO solarnet;

--
-- Name: chunk_time_index_maint; Type: VIEW; Schema: _timescaledb_solarnetwork; Owner: solarnet
--

CREATE VIEW _timescaledb_solarnetwork.chunk_time_index_maint AS
 SELECT ht.id AS hypertable_id,
    ht.schema_name AS hypertable_schema_name,
    ht.table_name AS hypertable_table_name,
    ch.id AS chunk_id,
    ch.schema_name AS chunk_schema_name,
    ch.table_name AS chunk_table_name,
    to_timestamp(((dims.range_start)::double precision / (1000000)::double precision)) AS chunk_lower_range,
    to_timestamp(((dims.range_end)::double precision / (1000000)::double precision)) AS chunk_upper_range,
    chi.index_name AS chunk_index_name,
    chm.last_reindex AS chunk_index_last_reindex,
    chm.last_cluster AS chunk_index_last_cluster,
    pgi.indexdef AS chunk_index_def,
    pgi.tablespace AS chunk_index_tablespace,
    pgs.n_tup_ins,
    pgs.n_tup_upd,
    pgs.n_tup_del,
    pgs.n_dead_tup,
    pgs.n_live_tup,
    ((((pgs.n_dead_tup)::double precision / (pgs.n_live_tup)::double precision) * (100)::double precision))::integer AS dead_tup_percent,
    ((((((pgs.n_tup_ins + pgs.n_tup_upd) + pgs.n_tup_del))::double precision / (pgs.n_live_tup)::double precision) * (100)::double precision))::integer AS mod_tup_percent
   FROM ((((((((_timescaledb_catalog.chunk ch
     JOIN _timescaledb_catalog.chunk_constraint chs ON ((chs.chunk_id = ch.id)))
     JOIN _timescaledb_catalog.dimension dim ON ((ch.hypertable_id = dim.hypertable_id)))
     JOIN _timescaledb_catalog.dimension_slice dims ON (((dims.dimension_id = dim.id) AND (dims.id = chs.dimension_slice_id))))
     JOIN pg_stat_user_tables pgs ON (((pgs.schemaname = ch.schema_name) AND (pgs.relname = ch.table_name))))
     JOIN _timescaledb_catalog.hypertable ht ON ((ht.id = ch.hypertable_id)))
     JOIN _timescaledb_catalog.chunk_index chi ON ((chi.chunk_id = ch.id)))
     JOIN pg_indexes pgi ON (((pgi.schemaname = ch.schema_name) AND (pgi.tablename = ch.table_name) AND (pgi.indexname = chi.index_name))))
     LEFT JOIN _timescaledb_solarnetwork.chunk_index_maint chm ON (((chm.chunk_id = ch.id) AND (chm.index_name = chi.index_name))))
  WHERE ((dim.column_type)::oid = ('timestamp with time zone'::regtype)::oid);


ALTER TABLE _timescaledb_solarnetwork.chunk_time_index_maint OWNER TO solarnet;

--
-- Name: av_needed; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.av_needed AS
 SELECT av.nspname,
    av.relname,
    av.n_tup_ins,
    av.n_tup_upd,
    av.n_tup_del,
    av.hot_update_ratio,
    av.n_live_tup,
    av.n_dead_tup,
    av.reltuples,
    av.av_threshold,
    av.last_vacuum,
    av.last_analyze,
    ((av.n_dead_tup)::double precision > av.av_threshold) AS av_needed,
        CASE
            WHEN (av.reltuples > (0)::double precision) THEN round((((100.0 * (av.n_dead_tup)::numeric))::double precision / av.reltuples))
            ELSE (0)::double precision
        END AS pct_dead
   FROM ( SELECT n.nspname,
            c.relname,
            pg_stat_get_tuples_inserted(c.oid) AS n_tup_ins,
            pg_stat_get_tuples_updated(c.oid) AS n_tup_upd,
            pg_stat_get_tuples_deleted(c.oid) AS n_tup_del,
                CASE
                    WHEN (pg_stat_get_tuples_updated(c.oid) = 0) THEN (0)::double precision
                    ELSE ((pg_stat_get_tuples_hot_updated(c.oid))::real / (pg_stat_get_tuples_updated(c.oid))::double precision)
                END AS hot_update_ratio,
            pg_stat_get_live_tuples(c.oid) AS n_live_tup,
            pg_stat_get_dead_tuples(c.oid) AS n_dead_tup,
            c.reltuples,
            round((((current_setting('autovacuum_vacuum_threshold'::text))::integer)::double precision + (((current_setting('autovacuum_vacuum_scale_factor'::text))::numeric)::double precision * c.reltuples))) AS av_threshold,
            date_trunc('minute'::text, GREATEST(pg_stat_get_last_vacuum_time(c.oid), pg_stat_get_last_autovacuum_time(c.oid))) AS last_vacuum,
            date_trunc('minute'::text, GREATEST(pg_stat_get_last_analyze_time(c.oid), pg_stat_get_last_analyze_time(c.oid))) AS last_analyze
           FROM ((pg_class c
             LEFT JOIN pg_index i ON ((c.oid = i.indrelid)))
             LEFT JOIN pg_namespace n ON ((n.oid = c.relnamespace)))
          WHERE ((c.relkind = ANY (ARRAY['r'::"char", 't'::"char"])) AND (n.nspname <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name])) AND (n.nspname !~ '^pg_toast'::text))) av
  ORDER BY ((av.n_dead_tup)::double precision > av.av_threshold) DESC, av.n_dead_tup DESC;


ALTER TABLE public.av_needed OWNER TO postgres;

--
-- Name: index_size; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.index_size AS
 SELECT n.nspname AS schemaname,
    c.relname AS indexrelname,
    (round((((100 * pg_relation_size((i.indexrelid)::regclass)) / pg_relation_size((i.indrelid)::regclass)))::double precision) / (100)::double precision) AS index_ratio,
    pg_relation_size((i.indexrelid)::regclass) AS index_size,
    pg_relation_size((i.indrelid)::regclass) AS table_size,
    pg_size_pretty(pg_relation_size((i.indexrelid)::regclass)) AS index_size_pretty,
    pg_size_pretty(pg_relation_size((i.indrelid)::regclass)) AS table_size_pretty,
    sui.idx_scan
   FROM (((pg_index i
     LEFT JOIN pg_class c ON ((c.oid = i.indexrelid)))
     LEFT JOIN pg_namespace n ON ((n.oid = c.relnamespace)))
     LEFT JOIN pg_stat_user_indexes sui ON (((sui.schemaname = n.nspname) AND (sui.indexrelname = c.relname))))
  WHERE ((n.nspname <> ALL (ARRAY['pg_catalog'::name, 'information_schema'::name, 'pg_toast'::name])) AND (c.relkind = 'i'::"char") AND (pg_relation_size((i.indrelid)::regclass) > 0))
  ORDER BY (pg_relation_size((i.indexrelid)::regclass)) DESC;


ALTER TABLE public.index_size OWNER TO postgres;

--
-- Name: plv8_modules; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.plv8_modules (
    module character varying(256) NOT NULL,
    autoload boolean DEFAULT false NOT NULL,
    source text NOT NULL
);


ALTER TABLE public.plv8_modules OWNER TO postgres;

--
-- Name: blob_triggers; Type: TABLE; Schema: quartz; Owner: solarnet
--

CREATE TABLE quartz.blob_triggers (
    trigger_name character varying(200) NOT NULL,
    trigger_group character varying(200) NOT NULL,
    blob_data bytea,
    sched_name character varying(120) DEFAULT 'TestScheduler'::character varying NOT NULL
);


ALTER TABLE quartz.blob_triggers OWNER TO solarnet;

--
-- Name: calendars; Type: TABLE; Schema: quartz; Owner: solarnet
--

CREATE TABLE quartz.calendars (
    calendar_name character varying(200) NOT NULL,
    calendar bytea NOT NULL,
    sched_name character varying(120) DEFAULT 'TestScheduler'::character varying NOT NULL
);


ALTER TABLE quartz.calendars OWNER TO solarnet;

--
-- Name: cron_triggers; Type: TABLE; Schema: quartz; Owner: solarnet
--

CREATE TABLE quartz.cron_triggers (
    trigger_name character varying(200) NOT NULL,
    trigger_group character varying(200) NOT NULL,
    cron_expression character varying(120) NOT NULL,
    time_zone_id character varying(80),
    sched_name character varying(120) DEFAULT 'TestScheduler'::character varying NOT NULL
);


ALTER TABLE quartz.cron_triggers OWNER TO solarnet;

--
-- Name: triggers; Type: TABLE; Schema: quartz; Owner: solarnet
--

CREATE TABLE quartz.triggers (
    trigger_name character varying(200) NOT NULL,
    trigger_group character varying(200) NOT NULL,
    job_name character varying(200) NOT NULL,
    job_group character varying(200) NOT NULL,
    description character varying(250),
    next_fire_time bigint,
    prev_fire_time bigint,
    priority integer,
    trigger_state character varying(16) NOT NULL,
    trigger_type character varying(8) NOT NULL,
    start_time bigint NOT NULL,
    end_time bigint,
    calendar_name character varying(200),
    misfire_instr smallint,
    job_data bytea,
    sched_name character varying(120) DEFAULT 'TestScheduler'::character varying NOT NULL
);


ALTER TABLE quartz.triggers OWNER TO solarnet;

--
-- Name: cron_trigger_view; Type: VIEW; Schema: quartz; Owner: solarnet
--

CREATE VIEW quartz.cron_trigger_view AS
 SELECT t.trigger_name,
    t.trigger_group,
    t.job_name,
    t.job_group,
    c.cron_expression,
    to_timestamp(((t.next_fire_time / 1000))::double precision) AS next_fire_time,
    to_timestamp(((t.prev_fire_time / 1000))::double precision) AS prev_fire_time,
    t.priority,
    t.trigger_state,
        CASE t.start_time
            WHEN 0 THEN NULL::timestamp with time zone
            ELSE to_timestamp(((t.start_time / 1000))::double precision)
        END AS start_time,
        CASE t.end_time
            WHEN 0 THEN NULL::timestamp with time zone
            ELSE to_timestamp(((t.end_time / 1000))::double precision)
        END AS end_time,
    t.sched_name
   FROM (quartz.triggers t
     JOIN quartz.cron_triggers c ON ((((c.trigger_name)::text = (t.trigger_name)::text) AND ((c.trigger_group)::text = (t.trigger_group)::text) AND ((c.sched_name)::text = (t.sched_name)::text))))
  ORDER BY t.sched_name, t.trigger_group, t.trigger_name, t.job_group, t.job_name;


ALTER TABLE quartz.cron_trigger_view OWNER TO solarnet;

--
-- Name: fired_triggers; Type: TABLE; Schema: quartz; Owner: solarnet
--

CREATE TABLE quartz.fired_triggers (
    entry_id character varying(95) NOT NULL,
    trigger_name character varying(200) NOT NULL,
    trigger_group character varying(200) NOT NULL,
    instance_name character varying(200) NOT NULL,
    fired_time bigint NOT NULL,
    priority integer NOT NULL,
    state character varying(16) NOT NULL,
    job_name character varying(200),
    job_group character varying(200),
    requests_recovery boolean,
    is_nonconcurrent boolean,
    is_update_data boolean,
    sched_name character varying(120) DEFAULT 'TestScheduler'::character varying NOT NULL,
    sched_time bigint DEFAULT 0 NOT NULL
);


ALTER TABLE quartz.fired_triggers OWNER TO solarnet;

--
-- Name: job_details; Type: TABLE; Schema: quartz; Owner: solarnet
--

CREATE TABLE quartz.job_details (
    job_name character varying(200) NOT NULL,
    job_group character varying(200) NOT NULL,
    description character varying(250),
    job_class_name character varying(250) NOT NULL,
    is_durable boolean NOT NULL,
    requests_recovery boolean NOT NULL,
    job_data bytea,
    is_nonconcurrent boolean,
    is_update_data boolean,
    sched_name character varying(120) DEFAULT 'TestScheduler'::character varying NOT NULL
);


ALTER TABLE quartz.job_details OWNER TO solarnet;

--
-- Name: locks; Type: TABLE; Schema: quartz; Owner: solarnet
--

CREATE TABLE quartz.locks (
    lock_name character varying(40) NOT NULL,
    sched_name character varying(120) DEFAULT 'TestScheduler'::character varying NOT NULL
);


ALTER TABLE quartz.locks OWNER TO solarnet;

--
-- Name: paused_trigger_grps; Type: TABLE; Schema: quartz; Owner: solarnet
--

CREATE TABLE quartz.paused_trigger_grps (
    trigger_group character varying(200) NOT NULL,
    sched_name character varying(120) DEFAULT 'TestScheduler'::character varying NOT NULL
);


ALTER TABLE quartz.paused_trigger_grps OWNER TO solarnet;

--
-- Name: scheduler_state; Type: TABLE; Schema: quartz; Owner: solarnet
--

CREATE TABLE quartz.scheduler_state (
    instance_name character varying(200) NOT NULL,
    last_checkin_time bigint NOT NULL,
    checkin_interval bigint NOT NULL,
    sched_name character varying(120) DEFAULT 'TestScheduler'::character varying NOT NULL
);


ALTER TABLE quartz.scheduler_state OWNER TO solarnet;

--
-- Name: simple_triggers; Type: TABLE; Schema: quartz; Owner: solarnet
--

CREATE TABLE quartz.simple_triggers (
    trigger_name character varying(200) NOT NULL,
    trigger_group character varying(200) NOT NULL,
    repeat_count bigint NOT NULL,
    repeat_interval bigint NOT NULL,
    times_triggered bigint NOT NULL,
    sched_name character varying(120) DEFAULT 'TestScheduler'::character varying NOT NULL
);


ALTER TABLE quartz.simple_triggers OWNER TO solarnet;

--
-- Name: simprop_triggers; Type: TABLE; Schema: quartz; Owner: solarnet
--

CREATE TABLE quartz.simprop_triggers (
    sched_name character varying(120) NOT NULL,
    trigger_name character varying(200) NOT NULL,
    trigger_group character varying(200) NOT NULL,
    str_prop_1 character varying(512),
    str_prop_2 character varying(512),
    str_prop_3 character varying(512),
    int_prop_1 integer,
    int_prop_2 integer,
    long_prop_1 bigint,
    long_prop_2 bigint,
    dec_prop_1 numeric(13,4),
    dec_prop_2 numeric(13,4),
    bool_prop_1 boolean,
    bool_prop_2 boolean
);


ALTER TABLE quartz.simprop_triggers OWNER TO solarnet;

--
-- Name: agg_loc_datum_daily_data; Type: VIEW; Schema: solaragg; Owner: solarnet
--

CREATE VIEW solaragg.agg_loc_datum_daily_data AS
 SELECT d.ts_start,
    d.local_date,
    d.loc_id,
    d.source_id,
    solaragg.jdata_from_datum(d.*) AS jdata
   FROM solaragg.agg_loc_datum_daily d;


ALTER TABLE solaragg.agg_loc_datum_daily_data OWNER TO solarnet;

--
-- Name: agg_loc_datum_hourly_data; Type: VIEW; Schema: solaragg; Owner: solarnet
--

CREATE VIEW solaragg.agg_loc_datum_hourly_data AS
 SELECT d.ts_start,
    d.local_date,
    d.loc_id,
    d.source_id,
    solaragg.jdata_from_datum(d.*) AS jdata
   FROM solaragg.agg_loc_datum_hourly d;


ALTER TABLE solaragg.agg_loc_datum_hourly_data OWNER TO solarnet;

--
-- Name: agg_loc_datum_monthly_data; Type: VIEW; Schema: solaragg; Owner: solarnet
--

CREATE VIEW solaragg.agg_loc_datum_monthly_data AS
 SELECT d.ts_start,
    d.local_date,
    d.loc_id,
    d.source_id,
    solaragg.jdata_from_datum(d.*) AS jdata
   FROM solaragg.agg_loc_datum_monthly d;


ALTER TABLE solaragg.agg_loc_datum_monthly_data OWNER TO solarnet;

--
-- Name: agg_loc_messages; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.agg_loc_messages (
    created timestamp with time zone DEFAULT now() NOT NULL,
    loc_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    ts timestamp with time zone NOT NULL,
    msg text NOT NULL
);


ALTER TABLE solaragg.agg_loc_messages OWNER TO solarnet;

--
-- Name: agg_messages; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.agg_messages (
    created timestamp with time zone DEFAULT now() NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    ts timestamp with time zone NOT NULL,
    msg text NOT NULL
);


ALTER TABLE solaragg.agg_messages OWNER TO solarnet;

--
-- Name: agg_stale_datum; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.agg_stale_datum (
    ts_start timestamp with time zone NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    agg_kind character(1) NOT NULL,
    created timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE solaragg.agg_stale_datum OWNER TO solarnet;

--
-- Name: agg_stale_loc_datum; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.agg_stale_loc_datum (
    ts_start timestamp with time zone NOT NULL,
    loc_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    agg_kind character(1) NOT NULL,
    created timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE solaragg.agg_stale_loc_datum OWNER TO solarnet;

--
-- Name: aud_datum_daily_stale; Type: TABLE; Schema: solaragg; Owner: solarnet
--

CREATE TABLE solaragg.aud_datum_daily_stale (
    ts_start timestamp with time zone NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    aud_kind character(1) NOT NULL,
    created timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE solaragg.aud_datum_daily_stale OWNER TO solarnet;

--
-- Name: da_datum_range; Type: TABLE; Schema: solardatum; Owner: solarnet
--

CREATE TABLE solardatum.da_datum_range (
    ts_min timestamp with time zone NOT NULL,
    ts_max timestamp with time zone NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL
);


ALTER TABLE solardatum.da_datum_range OWNER TO solarnet;

--
-- Name: da_loc_meta; Type: TABLE; Schema: solardatum; Owner: solarnet
--

CREATE TABLE solardatum.da_loc_meta (
    loc_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    created timestamp with time zone NOT NULL,
    updated timestamp with time zone NOT NULL,
    jdata jsonb NOT NULL
);


ALTER TABLE solardatum.da_loc_meta OWNER TO solarnet;

--
-- Name: da_meta; Type: TABLE; Schema: solardatum; Owner: solarnet
--

CREATE TABLE solardatum.da_meta (
    node_id bigint NOT NULL,
    source_id character varying(64) NOT NULL,
    created timestamp with time zone NOT NULL,
    updated timestamp with time zone NOT NULL,
    jdata jsonb NOT NULL
);


ALTER TABLE solardatum.da_meta OWNER TO solarnet;

--
-- Name: instruction_seq; Type: SEQUENCE; Schema: solarnet; Owner: solarnet
--

CREATE SEQUENCE solarnet.instruction_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE solarnet.instruction_seq OWNER TO solarnet;

--
-- Name: node_local_time; Type: VIEW; Schema: solarnet; Owner: solarnet
--

CREATE VIEW solarnet.node_local_time AS
 SELECT n.node_id,
    COALESCE(l.time_zone, 'UTC'::character varying(64)) AS time_zone,
    timezone((COALESCE(l.time_zone, 'UTC'::character varying))::text, now()) AS local_ts,
    (date_part('hour'::text, timezone((COALESCE(l.time_zone, 'UTC'::character varying))::text, now())))::integer AS local_hour_of_day
   FROM (solarnet.sn_node n
     LEFT JOIN solarnet.sn_loc l ON ((l.id = n.loc_id)));


ALTER TABLE solarnet.node_local_time OWNER TO solarnet;

--
-- Name: sn_hardware; Type: TABLE; Schema: solarnet; Owner: solarnet
--

CREATE TABLE solarnet.sn_hardware (
    id bigint DEFAULT nextval('solarnet.solarnet_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    manufact character varying(256) NOT NULL,
    model character varying(256) NOT NULL,
    revision integer DEFAULT 0 NOT NULL,
    fts_default tsvector
);


ALTER TABLE solarnet.sn_hardware OWNER TO solarnet;

--
-- Name: sn_hardware_control; Type: TABLE; Schema: solarnet; Owner: solarnet
--

CREATE TABLE solarnet.sn_hardware_control (
    id bigint DEFAULT nextval('solarnet.solarnet_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    hw_id bigint NOT NULL,
    ctl_name character varying(128) NOT NULL,
    unit character varying(16)
);


ALTER TABLE solarnet.sn_hardware_control OWNER TO solarnet;

--
-- Name: sn_node_instruction; Type: TABLE; Schema: solarnet; Owner: solarnet
--

CREATE TABLE solarnet.sn_node_instruction (
    id bigint DEFAULT nextval('solarnet.instruction_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    node_id bigint NOT NULL,
    topic character varying(128) NOT NULL,
    instr_date timestamp with time zone NOT NULL,
    deliver_state solarnet.instruction_delivery_state NOT NULL,
    jresult_params json
);


ALTER TABLE solarnet.sn_node_instruction OWNER TO solarnet;

--
-- Name: sn_node_instruction_param; Type: TABLE; Schema: solarnet; Owner: solarnet
--

CREATE TABLE solarnet.sn_node_instruction_param (
    instr_id bigint NOT NULL,
    idx integer NOT NULL,
    pname character varying(256) NOT NULL,
    pvalue character varying(256) NOT NULL
);


ALTER TABLE solarnet.sn_node_instruction_param OWNER TO solarnet;

--
-- Name: sn_node_meta; Type: TABLE; Schema: solarnet; Owner: solarnet
--

CREATE TABLE solarnet.sn_node_meta (
    node_id bigint NOT NULL,
    created timestamp with time zone NOT NULL,
    updated timestamp with time zone NOT NULL,
    jdata jsonb NOT NULL
);


ALTER TABLE solarnet.sn_node_meta OWNER TO solarnet;

--
-- Name: sn_price_loc; Type: TABLE; Schema: solarnet; Owner: solarnet
--

CREATE TABLE solarnet.sn_price_loc (
    id bigint DEFAULT nextval('solarnet.solarnet_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    loc_name character varying(128) NOT NULL,
    source_id bigint NOT NULL,
    source_data character varying(128),
    currency character varying(10) NOT NULL,
    unit character varying(20) NOT NULL,
    fts_default tsvector,
    loc_id bigint NOT NULL
);


ALTER TABLE solarnet.sn_price_loc OWNER TO solarnet;

--
-- Name: sn_price_source; Type: TABLE; Schema: solarnet; Owner: solarnet
--

CREATE TABLE solarnet.sn_price_source (
    id bigint DEFAULT nextval('solarnet.solarnet_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    sname character varying(128) NOT NULL,
    fts_default tsvector
);


ALTER TABLE solarnet.sn_price_source OWNER TO solarnet;

--
-- Name: sn_weather_loc; Type: TABLE; Schema: solarnet; Owner: solarnet
--

CREATE TABLE solarnet.sn_weather_loc (
    id bigint DEFAULT nextval('solarnet.solarnet_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    loc_id bigint NOT NULL,
    source_id bigint NOT NULL,
    source_data character varying(128),
    fts_default tsvector
);


ALTER TABLE solarnet.sn_weather_loc OWNER TO solarnet;

--
-- Name: sn_weather_source; Type: TABLE; Schema: solarnet; Owner: solarnet
--

CREATE TABLE solarnet.sn_weather_source (
    id bigint DEFAULT nextval('solarnet.solarnet_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    sname character varying(128) NOT NULL,
    fts_default tsvector
);


ALTER TABLE solarnet.sn_weather_source OWNER TO solarnet;

--
-- Name: solaruser_seq; Type: SEQUENCE; Schema: solaruser; Owner: solarnet
--

CREATE SEQUENCE solaruser.solaruser_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE solaruser.solaruser_seq OWNER TO solarnet;

--
-- Name: user_node; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_node (
    node_id bigint NOT NULL,
    user_id bigint NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    disp_name character varying(128),
    description character varying(512),
    private boolean DEFAULT false NOT NULL,
    archived boolean DEFAULT false NOT NULL
);


ALTER TABLE solaruser.user_node OWNER TO solarnet;

--
-- Name: user_user; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_user (
    id bigint DEFAULT nextval('solaruser.solaruser_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    disp_name character varying(128) NOT NULL,
    email public.citext NOT NULL,
    password character varying(128) NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    loc_id bigint,
    jdata jsonb
);


ALTER TABLE solaruser.user_user OWNER TO solarnet;

--
-- Name: million_metric_avg_hour_costs; Type: VIEW; Schema: solaruser; Owner: solarnet
--

CREATE VIEW solaruser.million_metric_avg_hour_costs AS
 SELECT a.node_id,
    public.max(u.email) AS owner,
    (round(avg(a.prop_count)))::integer AS avg_hourly_prop_count,
    (((((avg(a.prop_count) * (24)::numeric) * (30)::numeric) / (1000000)::numeric) * (7)::numeric))::numeric(6,2) AS month_cost7,
    (((((avg(a.prop_count) * (24)::numeric) * (30)::numeric) / (1000000)::numeric) * (10)::numeric))::numeric(6,2) AS month_cost10
   FROM ((solaragg.aud_datum_hourly a
     JOIN solaruser.user_node un ON ((un.node_id = a.node_id)))
     JOIN solaruser.user_user u ON ((u.id = un.user_id)))
  GROUP BY a.node_id
  ORDER BY ((round(avg(a.prop_count)))::integer) DESC;


ALTER TABLE solaruser.million_metric_avg_hour_costs OWNER TO solarnet;

--
-- Name: million_metric_monthly_costs; Type: VIEW; Schema: solaruser; Owner: solarnet
--

CREATE VIEW solaruser.million_metric_monthly_costs AS
 SELECT (date_trunc('month'::text, timezone('UTC'::text, a.ts_start)))::date AS month,
    u.email AS owner,
    a.node_id AS node,
    sum(a.prop_count) AS total_prop_count,
    sum(a.datum_q_count) AS total_datum_q_count,
    (round(((sum(a.prop_count))::double precision / (date_part('epoch'::text, (((date_trunc('month'::text, timezone('UTC'::text, a.ts_start)))::date + '1 mon'::interval) - ((date_trunc('month'::text, timezone('UTC'::text, a.ts_start)))::date)::timestamp without time zone)) / (3600)::double precision))))::integer AS avg_hourly_prop_count,
    ((((sum(a.prop_count))::numeric / (1000000)::numeric) * (10)::numeric))::numeric(6,2) AS cost
   FROM ((solaragg.aud_datum_hourly a
     JOIN solaruser.user_node un ON ((un.node_id = a.node_id)))
     JOIN solaruser.user_user u ON ((u.id = un.user_id)))
  GROUP BY ROLLUP(u.email, ((date_trunc('month'::text, timezone('UTC'::text, a.ts_start)))::date), a.node_id)
  ORDER BY u.email, ((date_trunc('month'::text, timezone('UTC'::text, a.ts_start)))::date), a.node_id;


ALTER TABLE solaruser.million_metric_monthly_costs OWNER TO solarnet;

--
-- Name: user_node_conf; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_node_conf (
    id bigint DEFAULT nextval('solaruser.solaruser_seq'::regclass) NOT NULL,
    user_id bigint NOT NULL,
    node_id bigint,
    created timestamp with time zone DEFAULT now() NOT NULL,
    conf_key character varying(1024) NOT NULL,
    conf_date timestamp with time zone,
    sec_phrase character varying(128) NOT NULL,
    country character(2) DEFAULT 'NZ'::bpchar NOT NULL,
    time_zone character varying(64) DEFAULT 'Pacific/Auckland'::character varying NOT NULL
);


ALTER TABLE solaruser.user_node_conf OWNER TO solarnet;

--
-- Name: network_association; Type: VIEW; Schema: solaruser; Owner: solarnet
--

CREATE VIEW solaruser.network_association AS
 SELECT (u.email)::text AS username,
    unc.conf_key,
    unc.sec_phrase
   FROM (solaruser.user_node_conf unc
     JOIN solaruser.user_user u ON ((u.id = unc.user_id)));


ALTER TABLE solaruser.network_association OWNER TO solarnet;

--
-- Name: user_adhoc_export_task; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_adhoc_export_task (
    created timestamp with time zone DEFAULT now() NOT NULL,
    user_id bigint NOT NULL,
    schedule character(1) NOT NULL,
    task_id uuid NOT NULL
);


ALTER TABLE solaruser.user_adhoc_export_task OWNER TO solarnet;

--
-- Name: user_alert_seq; Type: SEQUENCE; Schema: solaruser; Owner: solarnet
--

CREATE SEQUENCE solaruser.user_alert_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE solaruser.user_alert_seq OWNER TO solarnet;

--
-- Name: user_alert; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_alert (
    id bigint DEFAULT nextval('solaruser.user_alert_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    user_id bigint NOT NULL,
    node_id bigint,
    valid_to timestamp with time zone DEFAULT now() NOT NULL,
    alert_type solaruser.user_alert_type NOT NULL,
    status solaruser.user_alert_status NOT NULL,
    alert_opt json
);


ALTER TABLE solaruser.user_alert OWNER TO solarnet;

--
-- Name: user_alert_info; Type: VIEW; Schema: solaruser; Owner: solarnet
--

CREATE VIEW solaruser.user_alert_info AS
 SELECT al.id AS alert_id,
    al.user_id,
    al.node_id,
    al.alert_type,
    al.status AS alert_status,
    al.alert_opt,
    un.disp_name AS node_name,
    l.time_zone AS node_tz,
    u.disp_name AS user_name,
    u.email
   FROM ((((solaruser.user_alert al
     JOIN solaruser.user_user u ON ((al.user_id = u.id)))
     LEFT JOIN solaruser.user_node un ON (((un.user_id = al.user_id) AND (un.node_id = al.node_id))))
     LEFT JOIN solarnet.sn_node n ON ((al.node_id = n.node_id)))
     LEFT JOIN solarnet.sn_loc l ON ((l.id = n.loc_id)))
  ORDER BY al.user_id, al.node_id;


ALTER TABLE solaruser.user_alert_info OWNER TO solarnet;

--
-- Name: user_alert_sit; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_alert_sit (
    id bigint DEFAULT nextval('solaruser.user_alert_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    alert_id bigint NOT NULL,
    status solaruser.user_alert_sit_status NOT NULL,
    notified timestamp with time zone,
    info json
);


ALTER TABLE solaruser.user_alert_sit OWNER TO solarnet;

--
-- Name: user_auth_token; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_auth_token (
    auth_token character(20) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    user_id bigint NOT NULL,
    auth_secret character varying(32) NOT NULL,
    status solaruser.user_auth_token_status NOT NULL,
    token_type solaruser.user_auth_token_type NOT NULL,
    jpolicy jsonb
);


ALTER TABLE solaruser.user_auth_token OWNER TO solarnet;

--
-- Name: user_auth_token_login; Type: VIEW; Schema: solaruser; Owner: solarnet
--

CREATE VIEW solaruser.user_auth_token_login AS
 SELECT t.auth_token AS username,
    t.auth_secret AS password,
    u.enabled,
    u.id AS user_id,
    u.disp_name AS display_name,
    (t.token_type)::character varying AS token_type,
    t.jpolicy
   FROM (solaruser.user_auth_token t
     JOIN solaruser.user_user u ON ((u.id = t.user_id)))
  WHERE (t.status = 'Active'::solaruser.user_auth_token_status);


ALTER TABLE solaruser.user_auth_token_login OWNER TO solarnet;

--
-- Name: user_auth_token_node_ids; Type: VIEW; Schema: solaruser; Owner: solarnet
--

CREATE VIEW solaruser.user_auth_token_node_ids AS
SELECT
    NULL::character(20) AS auth_token,
    NULL::bigint AS user_id,
    NULL::solaruser.user_auth_token_type AS token_type,
    NULL::jsonb AS jpolicy,
    NULL::bigint[] AS node_ids;


ALTER TABLE solaruser.user_auth_token_node_ids OWNER TO solarnet;

--
-- Name: user_auth_token_nodes; Type: VIEW; Schema: solaruser; Owner: solarnet
--

CREATE VIEW solaruser.user_auth_token_nodes AS
 SELECT t.auth_token,
    un.node_id
   FROM (solaruser.user_auth_token t
     JOIN solaruser.user_node un ON ((un.user_id = t.user_id)))
  WHERE ((un.archived = false) AND (t.status = 'Active'::solaruser.user_auth_token_status) AND (((t.jpolicy -> 'nodeIds'::text) IS NULL) OR ((t.jpolicy -> 'nodeIds'::text) @> ((un.node_id)::text)::jsonb)));


ALTER TABLE solaruser.user_auth_token_nodes OWNER TO solarnet;

--
-- Name: user_role; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_role (
    user_id bigint NOT NULL,
    role_name character varying(128) NOT NULL
);


ALTER TABLE solaruser.user_role OWNER TO solarnet;

--
-- Name: user_auth_token_role; Type: VIEW; Schema: solaruser; Owner: solarnet
--

CREATE VIEW solaruser.user_auth_token_role AS
 SELECT t.auth_token AS username,
    ('ROLE_'::text || upper(((t.token_type)::character varying)::text)) AS authority
   FROM solaruser.user_auth_token t
UNION
 SELECT t.auth_token AS username,
    r.role_name AS authority
   FROM (solaruser.user_auth_token t
     JOIN solaruser.user_role r ON (((r.user_id = t.user_id) AND (t.token_type = 'User'::solaruser.user_auth_token_type))));


ALTER TABLE solaruser.user_auth_token_role OWNER TO solarnet;

--
-- Name: user_auth_token_sources; Type: VIEW; Schema: solaruser; Owner: solarnet
--

CREATE VIEW solaruser.user_auth_token_sources AS
 SELECT t.auth_token,
    un.node_id,
    (d.source_id)::text AS source_id,
    d.ts_start AS ts
   FROM (((solaruser.user_auth_token t
     JOIN solaruser.user_node un ON ((un.user_id = t.user_id)))
     JOIN solaragg.agg_datum_daily d ON ((d.node_id = un.node_id)))
     LEFT JOIN LATERAL ( SELECT solarcommon.ant_pattern_to_regexp(jsonb_array_elements_text((t.jpolicy -> 'sourceIds'::text))) AS regex) s_regex ON (true))
  WHERE ((un.archived = false) AND (t.status = 'Active'::solaruser.user_auth_token_status) AND (((t.jpolicy -> 'nodeIds'::text) IS NULL) OR ((t.jpolicy -> 'nodeIds'::text) @> ((un.node_id)::text)::jsonb)) AND (((t.jpolicy -> 'sourceIds'::text) IS NULL) OR ((d.source_id)::text ~ s_regex.regex)));


ALTER TABLE solaruser.user_auth_token_sources OWNER TO solarnet;

--
-- Name: user_expire_seq; Type: SEQUENCE; Schema: solaruser; Owner: solarnet
--

CREATE SEQUENCE solaruser.user_expire_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE solaruser.user_expire_seq OWNER TO solarnet;

--
-- Name: user_expire_data_conf; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_expire_data_conf (
    id bigint DEFAULT nextval('solaruser.user_expire_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    user_id bigint NOT NULL,
    cname character varying(64) NOT NULL,
    sident character varying(128) NOT NULL,
    expire_days integer NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    sprops jsonb,
    filter jsonb
);


ALTER TABLE solaruser.user_expire_data_conf OWNER TO solarnet;

--
-- Name: user_export_seq; Type: SEQUENCE; Schema: solaruser; Owner: solarnet
--

CREATE SEQUENCE solaruser.user_export_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE solaruser.user_export_seq OWNER TO solarnet;

--
-- Name: user_export_data_conf; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_export_data_conf (
    id bigint DEFAULT nextval('solaruser.user_export_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    user_id bigint NOT NULL,
    cname character varying(64) NOT NULL,
    sident character varying(128) NOT NULL,
    sprops jsonb,
    filter jsonb
);


ALTER TABLE solaruser.user_export_data_conf OWNER TO solarnet;

--
-- Name: user_export_datum_conf; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_export_datum_conf (
    id bigint DEFAULT nextval('solaruser.user_export_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    user_id bigint NOT NULL,
    cname character varying(64) NOT NULL,
    delay_mins integer NOT NULL,
    schedule character(1) NOT NULL,
    min_export_date timestamp with time zone DEFAULT now() NOT NULL,
    data_conf_id bigint,
    dest_conf_id bigint,
    outp_conf_id bigint
);


ALTER TABLE solaruser.user_export_datum_conf OWNER TO solarnet;

--
-- Name: user_export_dest_conf; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_export_dest_conf (
    id bigint DEFAULT nextval('solaruser.user_export_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    user_id bigint NOT NULL,
    cname character varying(64) NOT NULL,
    sident character varying(128) NOT NULL,
    sprops jsonb
);


ALTER TABLE solaruser.user_export_dest_conf OWNER TO solarnet;

--
-- Name: user_export_outp_conf; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_export_outp_conf (
    id bigint DEFAULT nextval('solaruser.user_export_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    user_id bigint NOT NULL,
    cname character varying(64) NOT NULL,
    sident character varying(128) NOT NULL,
    sprops jsonb,
    compression character(1) NOT NULL
);


ALTER TABLE solaruser.user_export_outp_conf OWNER TO solarnet;

--
-- Name: user_export_task; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_export_task (
    created timestamp with time zone DEFAULT now() NOT NULL,
    user_id bigint NOT NULL,
    schedule character(1) NOT NULL,
    export_date timestamp with time zone NOT NULL,
    task_id uuid NOT NULL,
    conf_id bigint NOT NULL
);


ALTER TABLE solaruser.user_export_task OWNER TO solarnet;

--
-- Name: user_login; Type: VIEW; Schema: solaruser; Owner: solarnet
--

CREATE VIEW solaruser.user_login AS
 SELECT (user_user.email)::text AS username,
    user_user.password,
    user_user.enabled,
    user_user.id AS user_id,
    user_user.disp_name AS display_name
   FROM solaruser.user_user;


ALTER TABLE solaruser.user_login OWNER TO solarnet;

--
-- Name: user_login_role; Type: VIEW; Schema: solaruser; Owner: solarnet
--

CREATE VIEW solaruser.user_login_role AS
 SELECT (u.email)::text AS username,
    r.role_name AS authority
   FROM (solaruser.user_user u
     JOIN solaruser.user_role r ON ((r.user_id = u.id)));


ALTER TABLE solaruser.user_login_role OWNER TO solarnet;

--
-- Name: user_meta; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_meta (
    user_id bigint NOT NULL,
    created timestamp with time zone NOT NULL,
    updated timestamp with time zone NOT NULL,
    jdata jsonb NOT NULL
);


ALTER TABLE solaruser.user_meta OWNER TO solarnet;

--
-- Name: user_node_cert; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_node_cert (
    created timestamp with time zone DEFAULT now() NOT NULL,
    user_id bigint NOT NULL,
    node_id bigint NOT NULL,
    status character(1) NOT NULL,
    keystore bytea NOT NULL,
    request_id character varying(32) NOT NULL
);


ALTER TABLE solaruser.user_node_cert OWNER TO solarnet;

--
-- Name: user_node_hardware_control; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_node_hardware_control (
    id bigint DEFAULT nextval('solaruser.solaruser_seq'::regclass) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL,
    node_id bigint NOT NULL,
    source_id character varying(128) NOT NULL,
    hwc_id bigint NOT NULL,
    disp_name character varying(128)
);


ALTER TABLE solaruser.user_node_hardware_control OWNER TO solarnet;

--
-- Name: user_node_info; Type: VIEW; Schema: solaruser; Owner: solarnet
--

CREATE VIEW solaruser.user_node_info AS
 SELECT un.node_id,
    un.disp_name AS node_name,
    l.time_zone AS node_tz,
    u.disp_name AS user_name,
    u.email,
    un.user_id
   FROM (((solaruser.user_node un
     JOIN solaruser.user_user u ON ((u.id = un.user_id)))
     JOIN solarnet.sn_node n ON ((un.node_id = n.node_id)))
     LEFT JOIN solarnet.sn_loc l ON ((l.id = n.loc_id)))
  ORDER BY un.node_id;


ALTER TABLE solaruser.user_node_info OWNER TO solarnet;

--
-- Name: user_node_tiers; Type: VIEW; Schema: solaruser; Owner: solarnet
--

CREATE VIEW solaruser.user_node_tiers AS
 WITH tiers AS (
         SELECT un.user_id,
            un.created,
            rank() OVER usr AS num,
                CASE
                    WHEN (rank() OVER usr < 6) THEN 1
                    WHEN (rank() OVER usr < 21) THEN 2
                    WHEN (rank() OVER usr < 51) THEN 3
                    ELSE 4
                END AS tier
           FROM solaruser.user_node un
          WINDOW usr AS (PARTITION BY un.user_id ORDER BY un.created)
        )
 SELECT g.user_id,
    min(g.start_date) AS start_date,
    g.tier,
    count(*) AS num
   FROM ( SELECT tiers.user_id,
            (first_value(tiers.created) OVER t)::date AS start_date,
            tiers.tier
           FROM tiers
          WINDOW t AS (PARTITION BY tiers.user_id, tiers.tier ORDER BY tiers.created)) g
  GROUP BY g.user_id, g.tier;


ALTER TABLE solaruser.user_node_tiers OWNER TO solarnet;

--
-- Name: user_node_tiers_info; Type: VIEW; Schema: solaruser; Owner: solarnet
--

CREATE VIEW solaruser.user_node_tiers_info AS
 SELECT t.user_id,
    u.email,
    t.start_date,
    ((t.start_date + '3 mons'::interval))::date AS invoice_date,
    t.num,
    t.tier,
        CASE t.tier
            WHEN 1 THEN 40
            WHEN 2 THEN 140
            WHEN 3 THEN 300
            ELSE 500
        END AS price
   FROM (solaruser.user_node_tiers t
     JOIN solaruser.user_user u ON ((u.id = t.user_id)));


ALTER TABLE solaruser.user_node_tiers_info OWNER TO solarnet;

--
-- Name: user_node_xfer; Type: TABLE; Schema: solaruser; Owner: solarnet
--

CREATE TABLE solaruser.user_node_xfer (
    created timestamp with time zone DEFAULT now() NOT NULL,
    user_id bigint NOT NULL,
    node_id bigint NOT NULL,
    recipient public.citext NOT NULL
);


ALTER TABLE solaruser.user_node_xfer OWNER TO solarnet;

--
-- Name: _hyper_11_1826_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1826_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_11_1826_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1826_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_11_1826_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1826_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_11_1826_chunk datum_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1826_chunk ALTER COLUMN datum_hourly_count SET DEFAULT 0;


--
-- Name: _hyper_11_1826_chunk datum_daily_pres; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1826_chunk ALTER COLUMN datum_daily_pres SET DEFAULT false;


--
-- Name: _hyper_11_1826_chunk processed_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1826_chunk ALTER COLUMN processed_count SET DEFAULT now();


--
-- Name: _hyper_11_1826_chunk processed_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1826_chunk ALTER COLUMN processed_hourly_count SET DEFAULT now();


--
-- Name: _hyper_11_1826_chunk processed_io_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1826_chunk ALTER COLUMN processed_io_count SET DEFAULT now();


--
-- Name: _hyper_11_1827_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1827_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_11_1827_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1827_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_11_1827_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1827_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_11_1827_chunk datum_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1827_chunk ALTER COLUMN datum_hourly_count SET DEFAULT 0;


--
-- Name: _hyper_11_1827_chunk datum_daily_pres; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1827_chunk ALTER COLUMN datum_daily_pres SET DEFAULT false;


--
-- Name: _hyper_11_1827_chunk processed_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1827_chunk ALTER COLUMN processed_count SET DEFAULT now();


--
-- Name: _hyper_11_1827_chunk processed_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1827_chunk ALTER COLUMN processed_hourly_count SET DEFAULT now();


--
-- Name: _hyper_11_1827_chunk processed_io_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1827_chunk ALTER COLUMN processed_io_count SET DEFAULT now();


--
-- Name: _hyper_11_1829_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1829_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_11_1829_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1829_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_11_1829_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1829_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_11_1829_chunk datum_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1829_chunk ALTER COLUMN datum_hourly_count SET DEFAULT 0;


--
-- Name: _hyper_11_1829_chunk datum_daily_pres; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1829_chunk ALTER COLUMN datum_daily_pres SET DEFAULT false;


--
-- Name: _hyper_11_1829_chunk processed_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1829_chunk ALTER COLUMN processed_count SET DEFAULT now();


--
-- Name: _hyper_11_1829_chunk processed_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1829_chunk ALTER COLUMN processed_hourly_count SET DEFAULT now();


--
-- Name: _hyper_11_1829_chunk processed_io_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1829_chunk ALTER COLUMN processed_io_count SET DEFAULT now();


--
-- Name: _hyper_11_1830_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1830_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_11_1830_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1830_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_11_1830_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1830_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_11_1830_chunk datum_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1830_chunk ALTER COLUMN datum_hourly_count SET DEFAULT 0;


--
-- Name: _hyper_11_1830_chunk datum_daily_pres; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1830_chunk ALTER COLUMN datum_daily_pres SET DEFAULT false;


--
-- Name: _hyper_11_1830_chunk processed_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1830_chunk ALTER COLUMN processed_count SET DEFAULT now();


--
-- Name: _hyper_11_1830_chunk processed_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1830_chunk ALTER COLUMN processed_hourly_count SET DEFAULT now();


--
-- Name: _hyper_11_1830_chunk processed_io_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1830_chunk ALTER COLUMN processed_io_count SET DEFAULT now();


--
-- Name: _hyper_11_1831_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1831_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_11_1831_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1831_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_11_1831_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1831_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_11_1831_chunk datum_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1831_chunk ALTER COLUMN datum_hourly_count SET DEFAULT 0;


--
-- Name: _hyper_11_1831_chunk datum_daily_pres; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1831_chunk ALTER COLUMN datum_daily_pres SET DEFAULT false;


--
-- Name: _hyper_11_1831_chunk processed_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1831_chunk ALTER COLUMN processed_count SET DEFAULT now();


--
-- Name: _hyper_11_1831_chunk processed_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1831_chunk ALTER COLUMN processed_hourly_count SET DEFAULT now();


--
-- Name: _hyper_11_1831_chunk processed_io_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1831_chunk ALTER COLUMN processed_io_count SET DEFAULT now();


--
-- Name: _hyper_11_1832_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1832_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_11_1832_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1832_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_11_1832_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1832_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_11_1832_chunk datum_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1832_chunk ALTER COLUMN datum_hourly_count SET DEFAULT 0;


--
-- Name: _hyper_11_1832_chunk datum_daily_pres; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1832_chunk ALTER COLUMN datum_daily_pres SET DEFAULT false;


--
-- Name: _hyper_11_1832_chunk processed_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1832_chunk ALTER COLUMN processed_count SET DEFAULT now();


--
-- Name: _hyper_11_1832_chunk processed_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1832_chunk ALTER COLUMN processed_hourly_count SET DEFAULT now();


--
-- Name: _hyper_11_1832_chunk processed_io_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1832_chunk ALTER COLUMN processed_io_count SET DEFAULT now();


--
-- Name: _hyper_11_1833_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1833_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_11_1833_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1833_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_11_1833_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1833_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_11_1833_chunk datum_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1833_chunk ALTER COLUMN datum_hourly_count SET DEFAULT 0;


--
-- Name: _hyper_11_1833_chunk datum_daily_pres; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1833_chunk ALTER COLUMN datum_daily_pres SET DEFAULT false;


--
-- Name: _hyper_11_1833_chunk processed_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1833_chunk ALTER COLUMN processed_count SET DEFAULT now();


--
-- Name: _hyper_11_1833_chunk processed_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1833_chunk ALTER COLUMN processed_hourly_count SET DEFAULT now();


--
-- Name: _hyper_11_1833_chunk processed_io_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1833_chunk ALTER COLUMN processed_io_count SET DEFAULT now();


--
-- Name: _hyper_11_1834_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1834_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_11_1834_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1834_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_11_1834_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1834_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_11_1834_chunk datum_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1834_chunk ALTER COLUMN datum_hourly_count SET DEFAULT 0;


--
-- Name: _hyper_11_1834_chunk datum_daily_pres; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1834_chunk ALTER COLUMN datum_daily_pres SET DEFAULT false;


--
-- Name: _hyper_11_1834_chunk processed_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1834_chunk ALTER COLUMN processed_count SET DEFAULT now();


--
-- Name: _hyper_11_1834_chunk processed_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1834_chunk ALTER COLUMN processed_hourly_count SET DEFAULT now();


--
-- Name: _hyper_11_1834_chunk processed_io_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1834_chunk ALTER COLUMN processed_io_count SET DEFAULT now();


--
-- Name: _hyper_11_1835_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1835_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_11_1835_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1835_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_11_1835_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1835_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_11_1835_chunk datum_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1835_chunk ALTER COLUMN datum_hourly_count SET DEFAULT 0;


--
-- Name: _hyper_11_1835_chunk datum_daily_pres; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1835_chunk ALTER COLUMN datum_daily_pres SET DEFAULT false;


--
-- Name: _hyper_11_1835_chunk processed_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1835_chunk ALTER COLUMN processed_count SET DEFAULT now();


--
-- Name: _hyper_11_1835_chunk processed_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1835_chunk ALTER COLUMN processed_hourly_count SET DEFAULT now();


--
-- Name: _hyper_11_1835_chunk processed_io_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1835_chunk ALTER COLUMN processed_io_count SET DEFAULT now();


--
-- Name: _hyper_11_1836_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1836_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_11_1836_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1836_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_11_1836_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1836_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_11_1836_chunk datum_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1836_chunk ALTER COLUMN datum_hourly_count SET DEFAULT 0;


--
-- Name: _hyper_11_1836_chunk datum_daily_pres; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1836_chunk ALTER COLUMN datum_daily_pres SET DEFAULT false;


--
-- Name: _hyper_11_1836_chunk processed_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1836_chunk ALTER COLUMN processed_count SET DEFAULT now();


--
-- Name: _hyper_11_1836_chunk processed_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1836_chunk ALTER COLUMN processed_hourly_count SET DEFAULT now();


--
-- Name: _hyper_11_1836_chunk processed_io_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1836_chunk ALTER COLUMN processed_io_count SET DEFAULT now();


--
-- Name: _hyper_11_1837_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1837_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_11_1837_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1837_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_11_1837_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1837_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_11_1837_chunk datum_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1837_chunk ALTER COLUMN datum_hourly_count SET DEFAULT 0;


--
-- Name: _hyper_11_1837_chunk datum_daily_pres; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1837_chunk ALTER COLUMN datum_daily_pres SET DEFAULT false;


--
-- Name: _hyper_11_1837_chunk processed_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1837_chunk ALTER COLUMN processed_count SET DEFAULT now();


--
-- Name: _hyper_11_1837_chunk processed_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1837_chunk ALTER COLUMN processed_hourly_count SET DEFAULT now();


--
-- Name: _hyper_11_1837_chunk processed_io_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_11_1837_chunk ALTER COLUMN processed_io_count SET DEFAULT now();


--
-- Name: _hyper_12_1828_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1828_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_12_1828_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1828_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_12_1828_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1828_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_12_1828_chunk datum_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1828_chunk ALTER COLUMN datum_hourly_count SET DEFAULT 0;


--
-- Name: _hyper_12_1828_chunk datum_daily_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1828_chunk ALTER COLUMN datum_daily_count SET DEFAULT 0;


--
-- Name: _hyper_12_1828_chunk datum_monthly_pres; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1828_chunk ALTER COLUMN datum_monthly_pres SET DEFAULT false;


--
-- Name: _hyper_12_1828_chunk processed; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1828_chunk ALTER COLUMN processed SET DEFAULT now();


--
-- Name: _hyper_12_1838_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1838_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_12_1838_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1838_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_12_1838_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1838_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_12_1838_chunk datum_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1838_chunk ALTER COLUMN datum_hourly_count SET DEFAULT 0;


--
-- Name: _hyper_12_1838_chunk datum_daily_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1838_chunk ALTER COLUMN datum_daily_count SET DEFAULT 0;


--
-- Name: _hyper_12_1838_chunk datum_monthly_pres; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1838_chunk ALTER COLUMN datum_monthly_pres SET DEFAULT false;


--
-- Name: _hyper_12_1838_chunk processed; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1838_chunk ALTER COLUMN processed SET DEFAULT now();


--
-- Name: _hyper_12_1839_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1839_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_12_1839_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1839_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_12_1839_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1839_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_12_1839_chunk datum_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1839_chunk ALTER COLUMN datum_hourly_count SET DEFAULT 0;


--
-- Name: _hyper_12_1839_chunk datum_daily_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1839_chunk ALTER COLUMN datum_daily_count SET DEFAULT 0;


--
-- Name: _hyper_12_1839_chunk datum_monthly_pres; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1839_chunk ALTER COLUMN datum_monthly_pres SET DEFAULT false;


--
-- Name: _hyper_12_1839_chunk processed; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_12_1839_chunk ALTER COLUMN processed SET DEFAULT now();


--
-- Name: _hyper_13_1840_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_1840_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_13_1840_chunk datum_hourly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_1840_chunk ALTER COLUMN datum_hourly_count SET DEFAULT 0;


--
-- Name: _hyper_13_1840_chunk datum_daily_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_1840_chunk ALTER COLUMN datum_daily_count SET DEFAULT 0;


--
-- Name: _hyper_13_1840_chunk datum_monthly_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_1840_chunk ALTER COLUMN datum_monthly_count SET DEFAULT 0;


--
-- Name: _hyper_13_1840_chunk processed; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_13_1840_chunk ALTER COLUMN processed SET DEFAULT now();


--
-- Name: _hyper_9_147_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_147_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_147_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_147_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_147_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_147_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1841_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1841_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1841_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1841_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1841_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1841_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1842_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1842_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1842_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1842_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1842_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1842_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1843_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1843_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1843_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1843_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1843_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1843_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1844_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1844_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1844_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1844_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1844_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1844_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1845_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1845_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1845_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1845_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1845_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1845_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1846_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1846_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1846_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1846_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1846_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1846_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1847_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1847_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1847_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1847_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1847_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1847_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1848_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1848_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1848_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1848_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1848_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1848_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1849_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1849_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1849_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1849_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1849_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1849_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1850_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1850_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1850_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1850_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1850_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1850_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1851_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1851_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1851_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1851_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1851_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1851_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1852_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1852_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1852_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1852_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1852_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1852_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1853_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1853_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1853_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1853_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1853_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1853_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1854_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1854_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1854_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1854_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1854_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1854_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1855_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1855_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1855_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1855_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1855_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1855_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1856_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1856_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1856_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1856_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1856_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1856_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1857_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1857_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1857_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1857_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1857_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1857_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_1861_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1861_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_1861_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1861_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_1861_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_1861_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_79_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_79_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_79_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_79_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_79_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_79_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_80_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_80_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_80_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_80_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_80_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_80_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: _hyper_9_81_chunk prop_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_81_chunk ALTER COLUMN prop_count SET DEFAULT 0;


--
-- Name: _hyper_9_81_chunk datum_q_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_81_chunk ALTER COLUMN datum_q_count SET DEFAULT 0;


--
-- Name: _hyper_9_81_chunk datum_count; Type: DEFAULT; Schema: _timescaledb_internal; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_internal._hyper_9_81_chunk ALTER COLUMN datum_count SET DEFAULT 0;


--
-- Name: chunk_index_maint chunk_index_maint_pkey; Type: CONSTRAINT; Schema: _timescaledb_solarnetwork; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_solarnetwork.chunk_index_maint
    ADD CONSTRAINT chunk_index_maint_pkey PRIMARY KEY (chunk_id, index_name);


--
-- Name: plv8_modules plv8_modules_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.plv8_modules
    ADD CONSTRAINT plv8_modules_pkey PRIMARY KEY (module);


--
-- Name: blob_triggers blob_triggers_pkey; Type: CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.blob_triggers
    ADD CONSTRAINT blob_triggers_pkey PRIMARY KEY (sched_name, trigger_name, trigger_group);


--
-- Name: calendars calendars_pkey; Type: CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.calendars
    ADD CONSTRAINT calendars_pkey PRIMARY KEY (sched_name, calendar_name);


--
-- Name: cron_triggers cron_triggers_pkey; Type: CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.cron_triggers
    ADD CONSTRAINT cron_triggers_pkey PRIMARY KEY (sched_name, trigger_name, trigger_group);


--
-- Name: fired_triggers fired_triggers_pkey; Type: CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.fired_triggers
    ADD CONSTRAINT fired_triggers_pkey PRIMARY KEY (sched_name, entry_id);


--
-- Name: job_details job_details_pkey; Type: CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.job_details
    ADD CONSTRAINT job_details_pkey PRIMARY KEY (sched_name, job_name, job_group);


--
-- Name: locks locks_pkey; Type: CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.locks
    ADD CONSTRAINT locks_pkey PRIMARY KEY (sched_name, lock_name);


--
-- Name: paused_trigger_grps paused_trigger_grps_pkey; Type: CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.paused_trigger_grps
    ADD CONSTRAINT paused_trigger_grps_pkey PRIMARY KEY (sched_name, trigger_group);


--
-- Name: scheduler_state scheduler_state_pkey; Type: CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.scheduler_state
    ADD CONSTRAINT scheduler_state_pkey PRIMARY KEY (sched_name, instance_name);


--
-- Name: simple_triggers simple_triggers_pkey; Type: CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.simple_triggers
    ADD CONSTRAINT simple_triggers_pkey PRIMARY KEY (sched_name, trigger_name, trigger_group);


--
-- Name: simprop_triggers simprop_triggers_pkey; Type: CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.simprop_triggers
    ADD CONSTRAINT simprop_triggers_pkey PRIMARY KEY (sched_name, trigger_name, trigger_group);


--
-- Name: triggers triggers_pkey; Type: CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.triggers
    ADD CONSTRAINT triggers_pkey PRIMARY KEY (sched_name, trigger_name, trigger_group);


--
-- Name: agg_stale_datum agg_stale_datum_pkey; Type: CONSTRAINT; Schema: solaragg; Owner: solarnet
--

ALTER TABLE ONLY solaragg.agg_stale_datum
    ADD CONSTRAINT agg_stale_datum_pkey PRIMARY KEY (agg_kind, ts_start, node_id, source_id);


--
-- Name: agg_stale_loc_datum agg_stale_loc_datum_pkey; Type: CONSTRAINT; Schema: solaragg; Owner: solarnet
--

ALTER TABLE ONLY solaragg.agg_stale_loc_datum
    ADD CONSTRAINT agg_stale_loc_datum_pkey PRIMARY KEY (agg_kind, ts_start, loc_id, source_id);


SET default_tablespace = solarindex;

--
-- Name: aud_datum_daily_stale aud_datum_daily_stale_pkey; Type: CONSTRAINT; Schema: solaragg; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solaragg.aud_datum_daily_stale
    ADD CONSTRAINT aud_datum_daily_stale_pkey PRIMARY KEY (aud_kind, ts_start, node_id, source_id);


SET default_tablespace = '';

--
-- Name: da_datum_aux da_datum_aux_pkey; Type: CONSTRAINT; Schema: solardatum; Owner: solarnet
--

ALTER TABLE ONLY solardatum.da_datum_aux
    ADD CONSTRAINT da_datum_aux_pkey PRIMARY KEY (node_id, ts, source_id, atype);


--
-- Name: da_datum_range da_datum_range_pkey; Type: CONSTRAINT; Schema: solardatum; Owner: solarnet
--

ALTER TABLE ONLY solardatum.da_datum_range
    ADD CONSTRAINT da_datum_range_pkey PRIMARY KEY (node_id, source_id);


--
-- Name: da_loc_meta da_loc_meta_pkey; Type: CONSTRAINT; Schema: solardatum; Owner: solarnet
--

ALTER TABLE ONLY solardatum.da_loc_meta
    ADD CONSTRAINT da_loc_meta_pkey PRIMARY KEY (loc_id, source_id);


--
-- Name: da_meta da_meta_pkey; Type: CONSTRAINT; Schema: solardatum; Owner: solarnet
--

ALTER TABLE ONLY solardatum.da_meta
    ADD CONSTRAINT da_meta_pkey PRIMARY KEY (node_id, source_id);


--
-- Name: sn_datum_export_task datum_export_task_pkey; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet
--

ALTER TABLE ONLY solarnet.sn_datum_export_task
    ADD CONSTRAINT datum_export_task_pkey PRIMARY KEY (id);


--
-- Name: sn_datum_import_job datum_import_job_pkey; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet
--

ALTER TABLE ONLY solarnet.sn_datum_import_job
    ADD CONSTRAINT datum_import_job_pkey PRIMARY KEY (user_id, id);


SET default_tablespace = solarindex;

--
-- Name: sn_hardware_control sn_hardware_control_pkey; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solarnet.sn_hardware_control
    ADD CONSTRAINT sn_hardware_control_pkey PRIMARY KEY (id);


--
-- Name: sn_hardware_control sn_hardware_control_unq; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solarnet.sn_hardware_control
    ADD CONSTRAINT sn_hardware_control_unq UNIQUE (hw_id, ctl_name);


--
-- Name: sn_hardware sn_hardware_pkey; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solarnet.sn_hardware
    ADD CONSTRAINT sn_hardware_pkey PRIMARY KEY (id);


--
-- Name: sn_hardware sn_hardware_unq; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solarnet.sn_hardware
    ADD CONSTRAINT sn_hardware_unq UNIQUE (manufact, model, revision);


--
-- Name: sn_loc sn_loc_pkey; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solarnet.sn_loc
    ADD CONSTRAINT sn_loc_pkey PRIMARY KEY (id);


--
-- Name: sn_node_instruction_param sn_node_instruction_param_pkey; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solarnet.sn_node_instruction_param
    ADD CONSTRAINT sn_node_instruction_param_pkey PRIMARY KEY (instr_id, idx);


--
-- Name: sn_node_instruction sn_node_instruction_pkey; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solarnet.sn_node_instruction
    ADD CONSTRAINT sn_node_instruction_pkey PRIMARY KEY (id);


SET default_tablespace = '';

--
-- Name: sn_node_meta sn_node_meta_pkey; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet
--

ALTER TABLE ONLY solarnet.sn_node_meta
    ADD CONSTRAINT sn_node_meta_pkey PRIMARY KEY (node_id);


SET default_tablespace = solarindex;

--
-- Name: sn_node sn_node_pkey; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solarnet.sn_node
    ADD CONSTRAINT sn_node_pkey PRIMARY KEY (node_id);


--
-- Name: sn_price_loc sn_price_loc_loc_name_key; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solarnet.sn_price_loc
    ADD CONSTRAINT sn_price_loc_loc_name_key UNIQUE (loc_name);


--
-- Name: sn_price_loc sn_price_loc_pkey; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solarnet.sn_price_loc
    ADD CONSTRAINT sn_price_loc_pkey PRIMARY KEY (id);


--
-- Name: sn_price_source sn_price_source_pkey; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solarnet.sn_price_source
    ADD CONSTRAINT sn_price_source_pkey PRIMARY KEY (id);


--
-- Name: sn_weather_loc sn_weather_loc_pkey; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solarnet.sn_weather_loc
    ADD CONSTRAINT sn_weather_loc_pkey PRIMARY KEY (id);


--
-- Name: sn_weather_source sn_weather_source_pkey; Type: CONSTRAINT; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solarnet.sn_weather_source
    ADD CONSTRAINT sn_weather_source_pkey PRIMARY KEY (id);


SET default_tablespace = '';

--
-- Name: user_adhoc_export_task user_adhoc_export_task_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_adhoc_export_task
    ADD CONSTRAINT user_adhoc_export_task_pkey PRIMARY KEY (user_id, task_id);


SET default_tablespace = solarindex;

--
-- Name: user_alert user_alert_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solaruser.user_alert
    ADD CONSTRAINT user_alert_pkey PRIMARY KEY (id);


--
-- Name: user_alert_sit user_alert_sit_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solaruser.user_alert_sit
    ADD CONSTRAINT user_alert_sit_pkey PRIMARY KEY (id);


--
-- Name: user_auth_token user_auth_token_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solaruser.user_auth_token
    ADD CONSTRAINT user_auth_token_pkey PRIMARY KEY (auth_token);


SET default_tablespace = '';

--
-- Name: user_datum_delete_job user_datum_delete_job_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_datum_delete_job
    ADD CONSTRAINT user_datum_delete_job_pkey PRIMARY KEY (user_id, id);


--
-- Name: user_expire_data_conf user_expire_data_conf_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_expire_data_conf
    ADD CONSTRAINT user_expire_data_conf_pkey PRIMARY KEY (id);


--
-- Name: user_export_data_conf user_export_data_conf_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_export_data_conf
    ADD CONSTRAINT user_export_data_conf_pkey PRIMARY KEY (id);


--
-- Name: user_export_datum_conf user_export_datum_conf_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_export_datum_conf
    ADD CONSTRAINT user_export_datum_conf_pkey PRIMARY KEY (id);


--
-- Name: user_export_dest_conf user_export_dest_conf_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_export_dest_conf
    ADD CONSTRAINT user_export_dest_conf_pkey PRIMARY KEY (id);


--
-- Name: user_export_outp_conf user_export_outp_conf_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_export_outp_conf
    ADD CONSTRAINT user_export_outp_conf_pkey PRIMARY KEY (id);


--
-- Name: user_export_task user_export_task_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_export_task
    ADD CONSTRAINT user_export_task_pkey PRIMARY KEY (user_id, schedule, export_date);


--
-- Name: user_meta user_meta_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_meta
    ADD CONSTRAINT user_meta_pkey PRIMARY KEY (user_id);


--
-- Name: user_node_cert user_node_cert_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_node_cert
    ADD CONSTRAINT user_node_cert_pkey PRIMARY KEY (user_id, node_id);


SET default_tablespace = solarindex;

--
-- Name: user_node_conf user_node_conf_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solaruser.user_node_conf
    ADD CONSTRAINT user_node_conf_pkey PRIMARY KEY (id);


--
-- Name: user_node_conf user_node_conf_unq; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solaruser.user_node_conf
    ADD CONSTRAINT user_node_conf_unq UNIQUE (user_id, conf_key);


--
-- Name: user_node_hardware_control user_node_hardware_control_node_unq; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solaruser.user_node_hardware_control
    ADD CONSTRAINT user_node_hardware_control_node_unq UNIQUE (node_id, source_id);


--
-- Name: user_node_hardware_control user_node_hardware_control_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solaruser.user_node_hardware_control
    ADD CONSTRAINT user_node_hardware_control_pkey PRIMARY KEY (id);


--
-- Name: user_node user_node_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solaruser.user_node
    ADD CONSTRAINT user_node_pkey PRIMARY KEY (node_id);


--
-- Name: user_node_xfer user_node_xfer_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solaruser.user_node_xfer
    ADD CONSTRAINT user_node_xfer_pkey PRIMARY KEY (user_id, node_id);


--
-- Name: user_role user_role_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solaruser.user_role
    ADD CONSTRAINT user_role_pkey PRIMARY KEY (user_id, role_name);


SET default_tablespace = '';

--
-- Name: user_user user_user_email_unq; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_user
    ADD CONSTRAINT user_user_email_unq UNIQUE (email);


SET default_tablespace = solarindex;

--
-- Name: user_user user_user_pkey; Type: CONSTRAINT; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

ALTER TABLE ONLY solaruser.user_user
    ADD CONSTRAINT user_user_pkey PRIMARY KEY (id);


--
-- Name: _hyper_10_1864_chunk_aud_loc_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_10_1864_chunk_aud_loc_datum_hourly_pkey ON _timescaledb_internal._hyper_10_1864_chunk USING btree (loc_id, ts_start, source_id);


--
-- Name: _hyper_10_82_chunk_aud_loc_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_10_82_chunk_aud_loc_datum_hourly_pkey ON _timescaledb_internal._hyper_10_82_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_10_82_chunk CLUSTER ON _hyper_10_82_chunk_aud_loc_datum_hourly_pkey;


--
-- Name: _hyper_10_85_chunk_aud_loc_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_10_85_chunk_aud_loc_datum_hourly_pkey ON _timescaledb_internal._hyper_10_85_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_10_85_chunk CLUSTER ON _hyper_10_85_chunk_aud_loc_datum_hourly_pkey;


--
-- Name: _hyper_11_1826_chunk_aud_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_11_1826_chunk_aud_datum_daily_pkey ON _timescaledb_internal._hyper_11_1826_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_11_1826_chunk CLUSTER ON _hyper_11_1826_chunk_aud_datum_daily_pkey;


--
-- Name: _hyper_11_1827_chunk_aud_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_11_1827_chunk_aud_datum_daily_pkey ON _timescaledb_internal._hyper_11_1827_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_11_1829_chunk_aud_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_11_1829_chunk_aud_datum_daily_pkey ON _timescaledb_internal._hyper_11_1829_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_11_1829_chunk CLUSTER ON _hyper_11_1829_chunk_aud_datum_daily_pkey;


--
-- Name: _hyper_11_1830_chunk_aud_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_11_1830_chunk_aud_datum_daily_pkey ON _timescaledb_internal._hyper_11_1830_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_11_1830_chunk CLUSTER ON _hyper_11_1830_chunk_aud_datum_daily_pkey;


--
-- Name: _hyper_11_1831_chunk_aud_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_11_1831_chunk_aud_datum_daily_pkey ON _timescaledb_internal._hyper_11_1831_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_11_1831_chunk CLUSTER ON _hyper_11_1831_chunk_aud_datum_daily_pkey;


--
-- Name: _hyper_11_1832_chunk_aud_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_11_1832_chunk_aud_datum_daily_pkey ON _timescaledb_internal._hyper_11_1832_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_11_1832_chunk CLUSTER ON _hyper_11_1832_chunk_aud_datum_daily_pkey;


--
-- Name: _hyper_11_1833_chunk_aud_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_11_1833_chunk_aud_datum_daily_pkey ON _timescaledb_internal._hyper_11_1833_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_11_1833_chunk CLUSTER ON _hyper_11_1833_chunk_aud_datum_daily_pkey;


--
-- Name: _hyper_11_1834_chunk_aud_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_11_1834_chunk_aud_datum_daily_pkey ON _timescaledb_internal._hyper_11_1834_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_11_1834_chunk CLUSTER ON _hyper_11_1834_chunk_aud_datum_daily_pkey;


--
-- Name: _hyper_11_1835_chunk_aud_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_11_1835_chunk_aud_datum_daily_pkey ON _timescaledb_internal._hyper_11_1835_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_11_1835_chunk CLUSTER ON _hyper_11_1835_chunk_aud_datum_daily_pkey;


--
-- Name: _hyper_11_1836_chunk_aud_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_11_1836_chunk_aud_datum_daily_pkey ON _timescaledb_internal._hyper_11_1836_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_11_1836_chunk CLUSTER ON _hyper_11_1836_chunk_aud_datum_daily_pkey;


--
-- Name: _hyper_11_1837_chunk_aud_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_11_1837_chunk_aud_datum_daily_pkey ON _timescaledb_internal._hyper_11_1837_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_12_1828_chunk_aud_datum_monthly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_12_1828_chunk_aud_datum_monthly_pkey ON _timescaledb_internal._hyper_12_1828_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_12_1838_chunk_aud_datum_monthly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_12_1838_chunk_aud_datum_monthly_pkey ON _timescaledb_internal._hyper_12_1838_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_12_1838_chunk CLUSTER ON _hyper_12_1838_chunk_aud_datum_monthly_pkey;


--
-- Name: _hyper_12_1839_chunk_aud_datum_monthly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_12_1839_chunk_aud_datum_monthly_pkey ON _timescaledb_internal._hyper_12_1839_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_13_1840_chunk_aud_acc_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_13_1840_chunk_aud_acc_datum_daily_pkey ON _timescaledb_internal._hyper_13_1840_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_1_10_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_10_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_10_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_10_chunk CLUSTER ON _hyper_1_10_chunk_da_datum_pkey;


--
-- Name: _hyper_1_10_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_10_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_10_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_11_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_11_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_11_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_11_chunk CLUSTER ON _hyper_1_11_chunk_da_datum_pkey;


--
-- Name: _hyper_1_11_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_11_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_11_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_12_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_12_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_12_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_12_chunk CLUSTER ON _hyper_1_12_chunk_da_datum_pkey;


--
-- Name: _hyper_1_12_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_12_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_12_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_13_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_13_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_13_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_13_chunk CLUSTER ON _hyper_1_13_chunk_da_datum_pkey;


--
-- Name: _hyper_1_13_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_13_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_13_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_14_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_14_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_14_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_14_chunk CLUSTER ON _hyper_1_14_chunk_da_datum_pkey;


--
-- Name: _hyper_1_14_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_14_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_14_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_15_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_15_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_15_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_15_chunk CLUSTER ON _hyper_1_15_chunk_da_datum_pkey;


--
-- Name: _hyper_1_15_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_15_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_15_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_16_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_16_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_16_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_16_chunk CLUSTER ON _hyper_1_16_chunk_da_datum_pkey;


--
-- Name: _hyper_1_16_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_16_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_16_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_17_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_17_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_17_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_17_chunk CLUSTER ON _hyper_1_17_chunk_da_datum_pkey;


--
-- Name: _hyper_1_17_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_17_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_17_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_1803_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_1803_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_1803_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_1803_chunk CLUSTER ON _hyper_1_1803_chunk_da_datum_pkey;


--
-- Name: _hyper_1_1803_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_1803_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_1803_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_1825_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_1825_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_1825_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_1825_chunk CLUSTER ON _hyper_1_1825_chunk_da_datum_pkey;


--
-- Name: _hyper_1_1825_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_1825_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_1825_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_1858_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_1858_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_1858_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_1858_chunk CLUSTER ON _hyper_1_1858_chunk_da_datum_pkey;


--
-- Name: _hyper_1_1858_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_1858_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_1858_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_1859_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_1859_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_1859_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_1859_chunk CLUSTER ON _hyper_1_1859_chunk_da_datum_pkey;


--
-- Name: _hyper_1_1859_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_1859_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_1859_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_1866_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_1866_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_1866_chunk USING btree (node_id, ts, source_id);


--
-- Name: _hyper_1_1866_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_1866_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_1866_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_18_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_18_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_18_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_18_chunk CLUSTER ON _hyper_1_18_chunk_da_datum_pkey;


--
-- Name: _hyper_1_18_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_18_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_18_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_19_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_19_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_19_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_19_chunk CLUSTER ON _hyper_1_19_chunk_da_datum_pkey;


--
-- Name: _hyper_1_19_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_19_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_19_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_1_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_1_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_1_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_1_chunk CLUSTER ON _hyper_1_1_chunk_da_datum_pkey;


--
-- Name: _hyper_1_1_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_1_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_1_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_20_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_20_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_20_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_20_chunk CLUSTER ON _hyper_1_20_chunk_da_datum_pkey;


--
-- Name: _hyper_1_20_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_20_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_20_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_2_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_2_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_2_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_2_chunk CLUSTER ON _hyper_1_2_chunk_da_datum_pkey;


--
-- Name: _hyper_1_2_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_2_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_2_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_3_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_3_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_3_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_3_chunk CLUSTER ON _hyper_1_3_chunk_da_datum_pkey;


--
-- Name: _hyper_1_3_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_3_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_3_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_4_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_4_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_4_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_4_chunk CLUSTER ON _hyper_1_4_chunk_da_datum_pkey;


--
-- Name: _hyper_1_4_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_4_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_4_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_5_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_5_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_5_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_5_chunk CLUSTER ON _hyper_1_5_chunk_da_datum_pkey;


--
-- Name: _hyper_1_5_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_5_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_5_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_6_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_6_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_6_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_6_chunk CLUSTER ON _hyper_1_6_chunk_da_datum_pkey;


--
-- Name: _hyper_1_6_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_6_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_6_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_7_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_7_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_7_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_7_chunk CLUSTER ON _hyper_1_7_chunk_da_datum_pkey;


--
-- Name: _hyper_1_7_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_7_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_7_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_8_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_8_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_8_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_8_chunk CLUSTER ON _hyper_1_8_chunk_da_datum_pkey;


--
-- Name: _hyper_1_8_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_8_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_8_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_1_9_chunk_da_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_9_chunk_da_datum_pkey ON _timescaledb_internal._hyper_1_9_chunk USING btree (node_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_1_9_chunk CLUSTER ON _hyper_1_9_chunk_da_datum_pkey;


--
-- Name: _hyper_1_9_chunk_da_datum_reverse_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_1_9_chunk_da_datum_reverse_pkey ON _timescaledb_internal._hyper_1_9_chunk USING btree (node_id, ts DESC, source_id);


--
-- Name: _hyper_2_1862_chunk_da_loc_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_2_1862_chunk_da_loc_datum_pkey ON _timescaledb_internal._hyper_2_1862_chunk USING btree (loc_id, ts, source_id);


--
-- Name: _hyper_2_21_chunk_da_loc_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_2_21_chunk_da_loc_datum_pkey ON _timescaledb_internal._hyper_2_21_chunk USING btree (loc_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_2_21_chunk CLUSTER ON _hyper_2_21_chunk_da_loc_datum_pkey;


--
-- Name: _hyper_2_22_chunk_da_loc_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_2_22_chunk_da_loc_datum_pkey ON _timescaledb_internal._hyper_2_22_chunk USING btree (loc_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_2_22_chunk CLUSTER ON _hyper_2_22_chunk_da_loc_datum_pkey;


--
-- Name: _hyper_2_23_chunk_da_loc_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_2_23_chunk_da_loc_datum_pkey ON _timescaledb_internal._hyper_2_23_chunk USING btree (loc_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_2_23_chunk CLUSTER ON _hyper_2_23_chunk_da_loc_datum_pkey;


--
-- Name: _hyper_2_24_chunk_da_loc_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_2_24_chunk_da_loc_datum_pkey ON _timescaledb_internal._hyper_2_24_chunk USING btree (loc_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_2_24_chunk CLUSTER ON _hyper_2_24_chunk_da_loc_datum_pkey;


--
-- Name: _hyper_2_25_chunk_da_loc_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_2_25_chunk_da_loc_datum_pkey ON _timescaledb_internal._hyper_2_25_chunk USING btree (loc_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_2_25_chunk CLUSTER ON _hyper_2_25_chunk_da_loc_datum_pkey;


--
-- Name: _hyper_2_26_chunk_da_loc_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_2_26_chunk_da_loc_datum_pkey ON _timescaledb_internal._hyper_2_26_chunk USING btree (loc_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_2_26_chunk CLUSTER ON _hyper_2_26_chunk_da_loc_datum_pkey;


--
-- Name: _hyper_2_27_chunk_da_loc_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_2_27_chunk_da_loc_datum_pkey ON _timescaledb_internal._hyper_2_27_chunk USING btree (loc_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_2_27_chunk CLUSTER ON _hyper_2_27_chunk_da_loc_datum_pkey;


--
-- Name: _hyper_2_28_chunk_da_loc_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_2_28_chunk_da_loc_datum_pkey ON _timescaledb_internal._hyper_2_28_chunk USING btree (loc_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_2_28_chunk CLUSTER ON _hyper_2_28_chunk_da_loc_datum_pkey;


--
-- Name: _hyper_2_29_chunk_da_loc_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_2_29_chunk_da_loc_datum_pkey ON _timescaledb_internal._hyper_2_29_chunk USING btree (loc_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_2_29_chunk CLUSTER ON _hyper_2_29_chunk_da_loc_datum_pkey;


--
-- Name: _hyper_2_30_chunk_da_loc_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_2_30_chunk_da_loc_datum_pkey ON _timescaledb_internal._hyper_2_30_chunk USING btree (loc_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_2_30_chunk CLUSTER ON _hyper_2_30_chunk_da_loc_datum_pkey;


--
-- Name: _hyper_2_83_chunk_da_loc_datum_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_2_83_chunk_da_loc_datum_pkey ON _timescaledb_internal._hyper_2_83_chunk USING btree (loc_id, ts, source_id);

ALTER TABLE _timescaledb_internal._hyper_2_83_chunk CLUSTER ON _hyper_2_83_chunk_da_loc_datum_pkey;


--
-- Name: _hyper_3_1804_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_1804_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_1804_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_1804_chunk CLUSTER ON _hyper_3_1804_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_1860_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_1860_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_1860_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_3_31_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_31_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_31_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_31_chunk CLUSTER ON _hyper_3_31_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_32_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_32_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_32_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_32_chunk CLUSTER ON _hyper_3_32_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_33_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_33_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_33_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_33_chunk CLUSTER ON _hyper_3_33_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_34_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_34_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_34_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_34_chunk CLUSTER ON _hyper_3_34_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_35_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_35_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_35_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_35_chunk CLUSTER ON _hyper_3_35_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_36_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_36_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_36_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_36_chunk CLUSTER ON _hyper_3_36_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_37_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_37_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_37_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_37_chunk CLUSTER ON _hyper_3_37_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_38_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_38_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_38_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_38_chunk CLUSTER ON _hyper_3_38_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_39_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_39_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_39_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_39_chunk CLUSTER ON _hyper_3_39_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_40_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_40_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_40_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_40_chunk CLUSTER ON _hyper_3_40_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_41_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_41_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_41_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_41_chunk CLUSTER ON _hyper_3_41_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_42_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_42_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_42_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_42_chunk CLUSTER ON _hyper_3_42_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_43_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_43_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_43_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_43_chunk CLUSTER ON _hyper_3_43_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_44_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_44_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_44_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_44_chunk CLUSTER ON _hyper_3_44_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_45_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_45_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_45_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_45_chunk CLUSTER ON _hyper_3_45_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_46_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_46_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_46_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_46_chunk CLUSTER ON _hyper_3_46_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_47_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_47_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_47_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_47_chunk CLUSTER ON _hyper_3_47_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_48_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_48_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_48_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_48_chunk CLUSTER ON _hyper_3_48_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_49_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_49_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_49_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_49_chunk CLUSTER ON _hyper_3_49_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_3_50_chunk_agg_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_3_50_chunk_agg_datum_hourly_pkey ON _timescaledb_internal._hyper_3_50_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_3_50_chunk CLUSTER ON _hyper_3_50_chunk_agg_datum_hourly_pkey;


--
-- Name: _hyper_4_1865_chunk_agg_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_4_1865_chunk_agg_datum_daily_pkey ON _timescaledb_internal._hyper_4_1865_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_4_51_chunk_agg_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_4_51_chunk_agg_datum_daily_pkey ON _timescaledb_internal._hyper_4_51_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_4_51_chunk CLUSTER ON _hyper_4_51_chunk_agg_datum_daily_pkey;


--
-- Name: _hyper_4_52_chunk_agg_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_4_52_chunk_agg_datum_daily_pkey ON _timescaledb_internal._hyper_4_52_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_4_52_chunk CLUSTER ON _hyper_4_52_chunk_agg_datum_daily_pkey;


--
-- Name: _hyper_4_53_chunk_agg_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_4_53_chunk_agg_datum_daily_pkey ON _timescaledb_internal._hyper_4_53_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_4_53_chunk CLUSTER ON _hyper_4_53_chunk_agg_datum_daily_pkey;


--
-- Name: _hyper_4_54_chunk_agg_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_4_54_chunk_agg_datum_daily_pkey ON _timescaledb_internal._hyper_4_54_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_4_54_chunk CLUSTER ON _hyper_4_54_chunk_agg_datum_daily_pkey;


--
-- Name: _hyper_4_55_chunk_agg_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_4_55_chunk_agg_datum_daily_pkey ON _timescaledb_internal._hyper_4_55_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_4_55_chunk CLUSTER ON _hyper_4_55_chunk_agg_datum_daily_pkey;


--
-- Name: _hyper_4_56_chunk_agg_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_4_56_chunk_agg_datum_daily_pkey ON _timescaledb_internal._hyper_4_56_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_4_56_chunk CLUSTER ON _hyper_4_56_chunk_agg_datum_daily_pkey;


--
-- Name: _hyper_4_57_chunk_agg_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_4_57_chunk_agg_datum_daily_pkey ON _timescaledb_internal._hyper_4_57_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_4_57_chunk CLUSTER ON _hyper_4_57_chunk_agg_datum_daily_pkey;


--
-- Name: _hyper_4_58_chunk_agg_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_4_58_chunk_agg_datum_daily_pkey ON _timescaledb_internal._hyper_4_58_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_4_58_chunk CLUSTER ON _hyper_4_58_chunk_agg_datum_daily_pkey;


--
-- Name: _hyper_4_59_chunk_agg_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_4_59_chunk_agg_datum_daily_pkey ON _timescaledb_internal._hyper_4_59_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_4_59_chunk CLUSTER ON _hyper_4_59_chunk_agg_datum_daily_pkey;


--
-- Name: _hyper_4_60_chunk_agg_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_4_60_chunk_agg_datum_daily_pkey ON _timescaledb_internal._hyper_4_60_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_4_60_chunk CLUSTER ON _hyper_4_60_chunk_agg_datum_daily_pkey;


--
-- Name: _hyper_4_86_chunk_agg_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_4_86_chunk_agg_datum_daily_pkey ON _timescaledb_internal._hyper_4_86_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_4_86_chunk CLUSTER ON _hyper_4_86_chunk_agg_datum_daily_pkey;


--
-- Name: _hyper_5_61_chunk_agg_datum_monthly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_5_61_chunk_agg_datum_monthly_pkey ON _timescaledb_internal._hyper_5_61_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_5_61_chunk CLUSTER ON _hyper_5_61_chunk_agg_datum_monthly_pkey;


--
-- Name: _hyper_5_62_chunk_agg_datum_monthly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_5_62_chunk_agg_datum_monthly_pkey ON _timescaledb_internal._hyper_5_62_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_5_62_chunk CLUSTER ON _hyper_5_62_chunk_agg_datum_monthly_pkey;


--
-- Name: _hyper_5_63_chunk_agg_datum_monthly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_5_63_chunk_agg_datum_monthly_pkey ON _timescaledb_internal._hyper_5_63_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_5_63_chunk CLUSTER ON _hyper_5_63_chunk_agg_datum_monthly_pkey;


--
-- Name: _hyper_6_1863_chunk_agg_loc_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_6_1863_chunk_agg_loc_datum_hourly_pkey ON _timescaledb_internal._hyper_6_1863_chunk USING btree (loc_id, ts_start, source_id);


--
-- Name: _hyper_6_64_chunk_agg_loc_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_6_64_chunk_agg_loc_datum_hourly_pkey ON _timescaledb_internal._hyper_6_64_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_6_64_chunk CLUSTER ON _hyper_6_64_chunk_agg_loc_datum_hourly_pkey;


--
-- Name: _hyper_6_65_chunk_agg_loc_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_6_65_chunk_agg_loc_datum_hourly_pkey ON _timescaledb_internal._hyper_6_65_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_6_65_chunk CLUSTER ON _hyper_6_65_chunk_agg_loc_datum_hourly_pkey;


--
-- Name: _hyper_6_66_chunk_agg_loc_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_6_66_chunk_agg_loc_datum_hourly_pkey ON _timescaledb_internal._hyper_6_66_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_6_66_chunk CLUSTER ON _hyper_6_66_chunk_agg_loc_datum_hourly_pkey;


--
-- Name: _hyper_6_67_chunk_agg_loc_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_6_67_chunk_agg_loc_datum_hourly_pkey ON _timescaledb_internal._hyper_6_67_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_6_67_chunk CLUSTER ON _hyper_6_67_chunk_agg_loc_datum_hourly_pkey;


--
-- Name: _hyper_6_68_chunk_agg_loc_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_6_68_chunk_agg_loc_datum_hourly_pkey ON _timescaledb_internal._hyper_6_68_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_6_68_chunk CLUSTER ON _hyper_6_68_chunk_agg_loc_datum_hourly_pkey;


--
-- Name: _hyper_6_69_chunk_agg_loc_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_6_69_chunk_agg_loc_datum_hourly_pkey ON _timescaledb_internal._hyper_6_69_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_6_69_chunk CLUSTER ON _hyper_6_69_chunk_agg_loc_datum_hourly_pkey;


--
-- Name: _hyper_6_70_chunk_agg_loc_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_6_70_chunk_agg_loc_datum_hourly_pkey ON _timescaledb_internal._hyper_6_70_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_6_70_chunk CLUSTER ON _hyper_6_70_chunk_agg_loc_datum_hourly_pkey;


--
-- Name: _hyper_6_71_chunk_agg_loc_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_6_71_chunk_agg_loc_datum_hourly_pkey ON _timescaledb_internal._hyper_6_71_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_6_71_chunk CLUSTER ON _hyper_6_71_chunk_agg_loc_datum_hourly_pkey;


--
-- Name: _hyper_6_72_chunk_agg_loc_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_6_72_chunk_agg_loc_datum_hourly_pkey ON _timescaledb_internal._hyper_6_72_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_6_72_chunk CLUSTER ON _hyper_6_72_chunk_agg_loc_datum_hourly_pkey;


--
-- Name: _hyper_6_73_chunk_agg_loc_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_6_73_chunk_agg_loc_datum_hourly_pkey ON _timescaledb_internal._hyper_6_73_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_6_73_chunk CLUSTER ON _hyper_6_73_chunk_agg_loc_datum_hourly_pkey;


--
-- Name: _hyper_6_84_chunk_agg_loc_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_6_84_chunk_agg_loc_datum_hourly_pkey ON _timescaledb_internal._hyper_6_84_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_6_84_chunk CLUSTER ON _hyper_6_84_chunk_agg_loc_datum_hourly_pkey;


--
-- Name: _hyper_7_74_chunk_agg_loc_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_7_74_chunk_agg_loc_datum_daily_pkey ON _timescaledb_internal._hyper_7_74_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_7_74_chunk CLUSTER ON _hyper_7_74_chunk_agg_loc_datum_daily_pkey;


--
-- Name: _hyper_7_75_chunk_agg_loc_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_7_75_chunk_agg_loc_datum_daily_pkey ON _timescaledb_internal._hyper_7_75_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_7_75_chunk CLUSTER ON _hyper_7_75_chunk_agg_loc_datum_daily_pkey;


--
-- Name: _hyper_7_76_chunk_agg_loc_datum_daily_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_7_76_chunk_agg_loc_datum_daily_pkey ON _timescaledb_internal._hyper_7_76_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_7_76_chunk CLUSTER ON _hyper_7_76_chunk_agg_loc_datum_daily_pkey;


--
-- Name: _hyper_8_77_chunk_agg_loc_datum_monthly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_8_77_chunk_agg_loc_datum_monthly_pkey ON _timescaledb_internal._hyper_8_77_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_8_77_chunk CLUSTER ON _hyper_8_77_chunk_agg_loc_datum_monthly_pkey;


--
-- Name: _hyper_8_78_chunk_agg_loc_datum_monthly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_8_78_chunk_agg_loc_datum_monthly_pkey ON _timescaledb_internal._hyper_8_78_chunk USING btree (loc_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_8_78_chunk CLUSTER ON _hyper_8_78_chunk_agg_loc_datum_monthly_pkey;


--
-- Name: _hyper_9_147_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_147_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_147_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_9_147_chunk CLUSTER ON _hyper_9_147_chunk_aud_datum_hourly_pkey;


--
-- Name: _hyper_9_1841_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1841_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1841_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1842_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1842_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1842_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1843_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1843_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1843_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1844_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1844_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1844_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1845_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1845_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1845_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1846_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1846_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1846_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1847_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1847_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1847_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1848_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1848_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1848_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1849_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1849_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1849_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1850_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1850_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1850_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1851_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1851_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1851_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1852_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1852_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1852_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1853_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1853_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1853_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1854_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1854_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1854_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1855_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1855_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1855_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1856_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1856_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1856_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1857_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1857_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1857_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_1861_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_1861_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_1861_chunk USING btree (node_id, ts_start, source_id);


--
-- Name: _hyper_9_79_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_79_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_79_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_9_79_chunk CLUSTER ON _hyper_9_79_chunk_aud_datum_hourly_pkey;


--
-- Name: _hyper_9_80_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_80_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_80_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_9_80_chunk CLUSTER ON _hyper_9_80_chunk_aud_datum_hourly_pkey;


--
-- Name: _hyper_9_81_chunk_aud_datum_hourly_pkey; Type: INDEX; Schema: _timescaledb_internal; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX _hyper_9_81_chunk_aud_datum_hourly_pkey ON _timescaledb_internal._hyper_9_81_chunk USING btree (node_id, ts_start, source_id);

ALTER TABLE _timescaledb_internal._hyper_9_81_chunk CLUSTER ON _hyper_9_81_chunk_aud_datum_hourly_pkey;


SET default_tablespace = '';

--
-- Name: idx_qrtz_ft_inst_job_req_rcvry; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_ft_inst_job_req_rcvry ON quartz.fired_triggers USING btree (sched_name, instance_name, requests_recovery);


--
-- Name: idx_qrtz_ft_j_g; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_ft_j_g ON quartz.fired_triggers USING btree (sched_name, job_name, job_group);


--
-- Name: idx_qrtz_ft_jg; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_ft_jg ON quartz.fired_triggers USING btree (sched_name, job_group);


--
-- Name: idx_qrtz_ft_t_g; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_ft_t_g ON quartz.fired_triggers USING btree (sched_name, trigger_name, trigger_group);


--
-- Name: idx_qrtz_ft_tg; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_ft_tg ON quartz.fired_triggers USING btree (sched_name, trigger_group);


--
-- Name: idx_qrtz_ft_trig_inst_name; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_ft_trig_inst_name ON quartz.fired_triggers USING btree (sched_name, instance_name);


--
-- Name: idx_qrtz_j_grp; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_j_grp ON quartz.job_details USING btree (sched_name, job_group);


--
-- Name: idx_qrtz_j_req_recovery; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_j_req_recovery ON quartz.job_details USING btree (sched_name, requests_recovery);


--
-- Name: idx_qrtz_t_c; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_t_c ON quartz.triggers USING btree (sched_name, calendar_name);


--
-- Name: idx_qrtz_t_g; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_t_g ON quartz.triggers USING btree (sched_name, trigger_group);


--
-- Name: idx_qrtz_t_j; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_t_j ON quartz.triggers USING btree (sched_name, job_name, job_group);


--
-- Name: idx_qrtz_t_jg; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_t_jg ON quartz.triggers USING btree (sched_name, job_group);


--
-- Name: idx_qrtz_t_n_g_state; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_t_n_g_state ON quartz.triggers USING btree (sched_name, trigger_group, trigger_state);


--
-- Name: idx_qrtz_t_n_state; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_t_n_state ON quartz.triggers USING btree (sched_name, trigger_name, trigger_group, trigger_state);


--
-- Name: idx_qrtz_t_next_fire_time; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_t_next_fire_time ON quartz.triggers USING btree (sched_name, next_fire_time);


--
-- Name: idx_qrtz_t_nft_misfire; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_t_nft_misfire ON quartz.triggers USING btree (sched_name, misfire_instr, next_fire_time);


--
-- Name: idx_qrtz_t_nft_st; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_t_nft_st ON quartz.triggers USING btree (sched_name, trigger_state, next_fire_time);


--
-- Name: idx_qrtz_t_nft_st_misfire; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_t_nft_st_misfire ON quartz.triggers USING btree (sched_name, misfire_instr, next_fire_time, trigger_state);


--
-- Name: idx_qrtz_t_nft_st_misfire_grp; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_t_nft_st_misfire_grp ON quartz.triggers USING btree (sched_name, misfire_instr, next_fire_time, trigger_group, trigger_state);


--
-- Name: idx_qrtz_t_state; Type: INDEX; Schema: quartz; Owner: solarnet
--

CREATE INDEX idx_qrtz_t_state ON quartz.triggers USING btree (sched_name, trigger_state);


SET default_tablespace = solarindex;

--
-- Name: agg_datum_daily_pkey; Type: INDEX; Schema: solaragg; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX agg_datum_daily_pkey ON solaragg.agg_datum_daily USING btree (node_id, ts_start, source_id);

ALTER TABLE solaragg.agg_datum_daily CLUSTER ON agg_datum_daily_pkey;


--
-- Name: agg_datum_hourly_pkey; Type: INDEX; Schema: solaragg; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX agg_datum_hourly_pkey ON solaragg.agg_datum_hourly USING btree (node_id, ts_start, source_id);

ALTER TABLE solaragg.agg_datum_hourly CLUSTER ON agg_datum_hourly_pkey;


--
-- Name: agg_datum_monthly_pkey; Type: INDEX; Schema: solaragg; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX agg_datum_monthly_pkey ON solaragg.agg_datum_monthly USING btree (node_id, ts_start, source_id);

ALTER TABLE solaragg.agg_datum_monthly CLUSTER ON agg_datum_monthly_pkey;


--
-- Name: agg_loc_datum_daily_pkey; Type: INDEX; Schema: solaragg; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX agg_loc_datum_daily_pkey ON solaragg.agg_loc_datum_daily USING btree (loc_id, ts_start, source_id);

ALTER TABLE solaragg.agg_loc_datum_daily CLUSTER ON agg_loc_datum_daily_pkey;


--
-- Name: agg_loc_datum_hourly_pkey; Type: INDEX; Schema: solaragg; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX agg_loc_datum_hourly_pkey ON solaragg.agg_loc_datum_hourly USING btree (loc_id, ts_start, source_id);

ALTER TABLE solaragg.agg_loc_datum_hourly CLUSTER ON agg_loc_datum_hourly_pkey;


--
-- Name: agg_loc_datum_monthly_pkey; Type: INDEX; Schema: solaragg; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX agg_loc_datum_monthly_pkey ON solaragg.agg_loc_datum_monthly USING btree (loc_id, ts_start, source_id);

ALTER TABLE solaragg.agg_loc_datum_monthly CLUSTER ON agg_loc_datum_monthly_pkey;


SET default_tablespace = '';

--
-- Name: agg_loc_messages_ts_loc_idx; Type: INDEX; Schema: solaragg; Owner: solarnet
--

CREATE INDEX agg_loc_messages_ts_loc_idx ON solaragg.agg_loc_messages USING btree (ts, loc_id);


SET default_tablespace = solarindex;

--
-- Name: agg_messages_ts_node_idx; Type: INDEX; Schema: solaragg; Owner: solarnet; Tablespace: solarindex
--

CREATE INDEX agg_messages_ts_node_idx ON solaragg.agg_messages USING btree (ts, node_id);


--
-- Name: aud_acc_datum_daily_pkey; Type: INDEX; Schema: solaragg; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX aud_acc_datum_daily_pkey ON solaragg.aud_acc_datum_daily USING btree (node_id, ts_start, source_id);


--
-- Name: aud_datum_daily_pkey; Type: INDEX; Schema: solaragg; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX aud_datum_daily_pkey ON solaragg.aud_datum_daily USING btree (node_id, ts_start, source_id);


--
-- Name: aud_datum_hourly_pkey; Type: INDEX; Schema: solaragg; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX aud_datum_hourly_pkey ON solaragg.aud_datum_hourly USING btree (node_id, ts_start, source_id);

ALTER TABLE solaragg.aud_datum_hourly CLUSTER ON aud_datum_hourly_pkey;


--
-- Name: aud_datum_monthly_pkey; Type: INDEX; Schema: solaragg; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX aud_datum_monthly_pkey ON solaragg.aud_datum_monthly USING btree (node_id, ts_start, source_id);


--
-- Name: aud_loc_datum_hourly_pkey; Type: INDEX; Schema: solaragg; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX aud_loc_datum_hourly_pkey ON solaragg.aud_loc_datum_hourly USING btree (loc_id, ts_start, source_id);

ALTER TABLE solaragg.aud_loc_datum_hourly CLUSTER ON aud_loc_datum_hourly_pkey;


--
-- Name: da_datum_pkey; Type: INDEX; Schema: solardatum; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX da_datum_pkey ON solardatum.da_datum USING btree (node_id, ts, source_id);

ALTER TABLE solardatum.da_datum CLUSTER ON da_datum_pkey;


--
-- Name: da_datum_reverse_pkey; Type: INDEX; Schema: solardatum; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX da_datum_reverse_pkey ON solardatum.da_datum USING btree (node_id, ts DESC, source_id);


--
-- Name: da_loc_datum_pkey; Type: INDEX; Schema: solardatum; Owner: solarnet; Tablespace: solarindex
--

CREATE UNIQUE INDEX da_loc_datum_pkey ON solardatum.da_loc_datum USING btree (loc_id, ts, source_id);

ALTER TABLE solardatum.da_loc_datum CLUSTER ON da_loc_datum_pkey;


--
-- Name: sn_hardware_fts_default_idx; Type: INDEX; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

CREATE INDEX sn_hardware_fts_default_idx ON solarnet.sn_hardware USING gin (fts_default);


--
-- Name: sn_loc_fts_default_idx; Type: INDEX; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

CREATE INDEX sn_loc_fts_default_idx ON solarnet.sn_loc USING gin (fts_default);


--
-- Name: sn_node_instruction_node_idx; Type: INDEX; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

CREATE INDEX sn_node_instruction_node_idx ON solarnet.sn_node_instruction USING btree (node_id, deliver_state, instr_date);


--
-- Name: sn_price_loc_fts_default_idx; Type: INDEX; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

CREATE INDEX sn_price_loc_fts_default_idx ON solarnet.sn_price_loc USING gin (fts_default);


--
-- Name: sn_price_source_fts_default_idx; Type: INDEX; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

CREATE INDEX sn_price_source_fts_default_idx ON solarnet.sn_price_source USING gin (fts_default);


--
-- Name: sn_weather_loc_fts_default_idx; Type: INDEX; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

CREATE INDEX sn_weather_loc_fts_default_idx ON solarnet.sn_weather_loc USING gin (fts_default);


--
-- Name: sn_weather_source_fts_default_idx; Type: INDEX; Schema: solarnet; Owner: solarnet; Tablespace: solarindex
--

CREATE INDEX sn_weather_source_fts_default_idx ON solarnet.sn_weather_source USING gin (fts_default);


--
-- Name: user_alert_node_idx; Type: INDEX; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

CREATE INDEX user_alert_node_idx ON solaruser.user_alert USING btree (node_id);


--
-- Name: user_alert_sit_alert_created_idx; Type: INDEX; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

CREATE INDEX user_alert_sit_alert_created_idx ON solaruser.user_alert_sit USING btree (alert_id, created DESC);


--
-- Name: user_alert_sit_notified_idx; Type: INDEX; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

CREATE INDEX user_alert_sit_notified_idx ON solaruser.user_alert_sit USING btree (notified) WHERE (notified IS NOT NULL);


--
-- Name: user_alert_user_idx; Type: INDEX; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

CREATE INDEX user_alert_user_idx ON solaruser.user_alert USING btree (user_id);


--
-- Name: user_alert_valid_idx; Type: INDEX; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

CREATE INDEX user_alert_valid_idx ON solaruser.user_alert USING btree (valid_to);


SET default_tablespace = '';

--
-- Name: user_expire_data_conf_user_idx; Type: INDEX; Schema: solaruser; Owner: solarnet
--

CREATE INDEX user_expire_data_conf_user_idx ON solaruser.user_expire_data_conf USING btree (user_id);


--
-- Name: user_export_data_conf_user_idx; Type: INDEX; Schema: solaruser; Owner: solarnet
--

CREATE INDEX user_export_data_conf_user_idx ON solaruser.user_export_data_conf USING btree (user_id);


--
-- Name: user_export_datum_conf_user_idx; Type: INDEX; Schema: solaruser; Owner: solarnet
--

CREATE INDEX user_export_datum_conf_user_idx ON solaruser.user_export_datum_conf USING btree (user_id);


--
-- Name: user_export_dest_conf_user_idx; Type: INDEX; Schema: solaruser; Owner: solarnet
--

CREATE INDEX user_export_dest_conf_user_idx ON solaruser.user_export_dest_conf USING btree (user_id);


--
-- Name: user_export_outp_conf_user_idx; Type: INDEX; Schema: solaruser; Owner: solarnet
--

CREATE INDEX user_export_outp_conf_user_idx ON solaruser.user_export_outp_conf USING btree (user_id);


SET default_tablespace = solarindex;

--
-- Name: user_node_user_idx; Type: INDEX; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

CREATE INDEX user_node_user_idx ON solaruser.user_node USING btree (user_id);


--
-- Name: user_node_xfer_recipient_idx; Type: INDEX; Schema: solaruser; Owner: solarnet; Tablespace: solarindex
--

CREATE INDEX user_node_xfer_recipient_idx ON solaruser.user_node_xfer USING btree (recipient);


SET default_tablespace = '';

--
-- Name: user_user_jdata_idx; Type: INDEX; Schema: solaruser; Owner: solarnet
--

CREATE INDEX user_user_jdata_idx ON solaruser.user_user USING gin (jdata jsonb_path_ops);


--
-- Name: user_auth_token_node_ids _RETURN; Type: RULE; Schema: solaruser; Owner: solarnet
--

CREATE OR REPLACE VIEW solaruser.user_auth_token_node_ids AS
 SELECT t.auth_token,
    t.user_id,
    t.token_type,
    t.jpolicy,
    array_agg(un.node_id) AS node_ids
   FROM (solaruser.user_auth_token t
     JOIN solaruser.user_node un ON ((un.user_id = t.user_id)))
  WHERE ((un.archived = false) AND (t.status = 'Active'::solaruser.user_auth_token_status) AND (((t.jpolicy -> 'nodeIds'::text) IS NULL) OR ((t.jpolicy -> 'nodeIds'::text) @> ((un.node_id)::text)::jsonb)))
  GROUP BY t.auth_token, t.user_id;


--
-- Name: _hyper_1_1_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_1_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_2_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_2_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_3_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_3_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_4_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_4_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_5_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_5_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_6_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_6_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_7_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_7_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_8_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_8_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_9_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_9_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_10_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_10_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_11_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_11_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_12_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_12_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_13_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_13_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_14_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_14_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_15_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_15_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_16_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_16_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_17_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_17_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_18_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_18_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_19_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_19_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_20_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_20_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_1803_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_1803_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_1825_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_1825_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_1858_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_1858_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_1859_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_1859_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_1_1866_chunk aa_agg_stale_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_1_1866_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: _hyper_2_21_chunk aa_agg_stale_loc_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_loc_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_2_21_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_loc_datum();


--
-- Name: _hyper_2_22_chunk aa_agg_stale_loc_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_loc_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_2_22_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_loc_datum();


--
-- Name: _hyper_2_23_chunk aa_agg_stale_loc_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_loc_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_2_23_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_loc_datum();


--
-- Name: _hyper_2_24_chunk aa_agg_stale_loc_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_loc_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_2_24_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_loc_datum();


--
-- Name: _hyper_2_25_chunk aa_agg_stale_loc_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_loc_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_2_25_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_loc_datum();


--
-- Name: _hyper_2_26_chunk aa_agg_stale_loc_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_loc_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_2_26_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_loc_datum();


--
-- Name: _hyper_2_27_chunk aa_agg_stale_loc_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_loc_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_2_27_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_loc_datum();


--
-- Name: _hyper_2_28_chunk aa_agg_stale_loc_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_loc_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_2_28_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_loc_datum();


--
-- Name: _hyper_2_29_chunk aa_agg_stale_loc_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_loc_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_2_29_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_loc_datum();


--
-- Name: _hyper_2_30_chunk aa_agg_stale_loc_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_loc_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_2_30_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_loc_datum();


--
-- Name: _hyper_2_83_chunk aa_agg_stale_loc_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_loc_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_2_83_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_loc_datum();


--
-- Name: _hyper_2_1862_chunk aa_agg_stale_loc_datum; Type: TRIGGER; Schema: _timescaledb_internal; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_loc_datum BEFORE INSERT OR DELETE OR UPDATE ON _timescaledb_internal._hyper_2_1862_chunk FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_loc_datum();


--
-- Name: agg_datum_hourly ts_insert_blocker; Type: TRIGGER; Schema: solaragg; Owner: solarnet
--

CREATE TRIGGER ts_insert_blocker BEFORE INSERT ON solaragg.agg_datum_hourly FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.insert_blocker();


--
-- Name: agg_datum_daily ts_insert_blocker; Type: TRIGGER; Schema: solaragg; Owner: solarnet
--

CREATE TRIGGER ts_insert_blocker BEFORE INSERT ON solaragg.agg_datum_daily FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.insert_blocker();


--
-- Name: agg_datum_monthly ts_insert_blocker; Type: TRIGGER; Schema: solaragg; Owner: solarnet
--

CREATE TRIGGER ts_insert_blocker BEFORE INSERT ON solaragg.agg_datum_monthly FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.insert_blocker();


--
-- Name: agg_loc_datum_hourly ts_insert_blocker; Type: TRIGGER; Schema: solaragg; Owner: solarnet
--

CREATE TRIGGER ts_insert_blocker BEFORE INSERT ON solaragg.agg_loc_datum_hourly FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.insert_blocker();


--
-- Name: agg_loc_datum_daily ts_insert_blocker; Type: TRIGGER; Schema: solaragg; Owner: solarnet
--

CREATE TRIGGER ts_insert_blocker BEFORE INSERT ON solaragg.agg_loc_datum_daily FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.insert_blocker();


--
-- Name: agg_loc_datum_monthly ts_insert_blocker; Type: TRIGGER; Schema: solaragg; Owner: solarnet
--

CREATE TRIGGER ts_insert_blocker BEFORE INSERT ON solaragg.agg_loc_datum_monthly FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.insert_blocker();


--
-- Name: aud_datum_hourly ts_insert_blocker; Type: TRIGGER; Schema: solaragg; Owner: solarnet
--

CREATE TRIGGER ts_insert_blocker BEFORE INSERT ON solaragg.aud_datum_hourly FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.insert_blocker();


--
-- Name: aud_loc_datum_hourly ts_insert_blocker; Type: TRIGGER; Schema: solaragg; Owner: solarnet
--

CREATE TRIGGER ts_insert_blocker BEFORE INSERT ON solaragg.aud_loc_datum_hourly FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.insert_blocker();


--
-- Name: aud_datum_daily ts_insert_blocker; Type: TRIGGER; Schema: solaragg; Owner: solarnet
--

CREATE TRIGGER ts_insert_blocker BEFORE INSERT ON solaragg.aud_datum_daily FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.insert_blocker();


--
-- Name: aud_datum_monthly ts_insert_blocker; Type: TRIGGER; Schema: solaragg; Owner: solarnet
--

CREATE TRIGGER ts_insert_blocker BEFORE INSERT ON solaragg.aud_datum_monthly FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.insert_blocker();


--
-- Name: aud_acc_datum_daily ts_insert_blocker; Type: TRIGGER; Schema: solaragg; Owner: solarnet
--

CREATE TRIGGER ts_insert_blocker BEFORE INSERT ON solaragg.aud_acc_datum_daily FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.insert_blocker();


--
-- Name: da_datum aa_agg_stale_datum; Type: TRIGGER; Schema: solardatum; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum BEFORE INSERT OR DELETE OR UPDATE ON solardatum.da_datum FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: da_datum_aux aa_agg_stale_datum_aux; Type: TRIGGER; Schema: solardatum; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_datum_aux BEFORE INSERT OR DELETE OR UPDATE ON solardatum.da_datum_aux FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_datum();


--
-- Name: da_loc_datum aa_agg_stale_loc_datum; Type: TRIGGER; Schema: solardatum; Owner: solarnet
--

CREATE TRIGGER aa_agg_stale_loc_datum BEFORE INSERT OR DELETE OR UPDATE ON solardatum.da_loc_datum FOR EACH ROW EXECUTE PROCEDURE solardatum.trigger_agg_stale_loc_datum();


--
-- Name: da_meta populate_updated; Type: TRIGGER; Schema: solardatum; Owner: solarnet
--

CREATE TRIGGER populate_updated BEFORE INSERT OR UPDATE ON solardatum.da_meta FOR EACH ROW EXECUTE PROCEDURE solardatum.populate_updated();


--
-- Name: da_loc_meta populate_updated; Type: TRIGGER; Schema: solardatum; Owner: solarnet
--

CREATE TRIGGER populate_updated BEFORE INSERT OR UPDATE ON solardatum.da_loc_meta FOR EACH ROW EXECUTE PROCEDURE solardatum.populate_updated();


--
-- Name: da_datum ts_insert_blocker; Type: TRIGGER; Schema: solardatum; Owner: solarnet
--

CREATE TRIGGER ts_insert_blocker BEFORE INSERT ON solardatum.da_datum FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.insert_blocker();


--
-- Name: da_loc_datum ts_insert_blocker; Type: TRIGGER; Schema: solardatum; Owner: solarnet
--

CREATE TRIGGER ts_insert_blocker BEFORE INSERT ON solardatum.da_loc_datum FOR EACH ROW EXECUTE PROCEDURE _timescaledb_internal.insert_blocker();


--
-- Name: sn_hardware maintain_fts; Type: TRIGGER; Schema: solarnet; Owner: solarnet
--

CREATE TRIGGER maintain_fts BEFORE INSERT OR UPDATE ON solarnet.sn_hardware FOR EACH ROW EXECUTE PROCEDURE tsvector_update_trigger('fts_default', 'pg_catalog.english', 'manufact', 'model');


--
-- Name: sn_weather_source maintain_fts; Type: TRIGGER; Schema: solarnet; Owner: solarnet
--

CREATE TRIGGER maintain_fts BEFORE INSERT OR UPDATE ON solarnet.sn_weather_source FOR EACH ROW EXECUTE PROCEDURE tsvector_update_trigger('fts_default', 'pg_catalog.english', 'sname');


--
-- Name: sn_weather_loc maintain_fts; Type: TRIGGER; Schema: solarnet; Owner: solarnet
--

CREATE TRIGGER maintain_fts BEFORE INSERT OR UPDATE ON solarnet.sn_weather_loc FOR EACH ROW EXECUTE PROCEDURE tsvector_update_trigger('fts_default', 'pg_catalog.english', 'source_data');


--
-- Name: sn_price_source maintain_fts; Type: TRIGGER; Schema: solarnet; Owner: solarnet
--

CREATE TRIGGER maintain_fts BEFORE INSERT OR UPDATE ON solarnet.sn_price_source FOR EACH ROW EXECUTE PROCEDURE tsvector_update_trigger('fts_default', 'pg_catalog.english', 'sname');


--
-- Name: sn_price_loc maintain_fts; Type: TRIGGER; Schema: solarnet; Owner: solarnet
--

CREATE TRIGGER maintain_fts BEFORE INSERT OR UPDATE ON solarnet.sn_price_loc FOR EACH ROW EXECUTE PROCEDURE tsvector_update_trigger('fts_default', 'pg_catalog.english', 'loc_name', 'source_data', 'currency');


--
-- Name: sn_loc maintain_fts; Type: TRIGGER; Schema: solarnet; Owner: solarnet
--

CREATE TRIGGER maintain_fts BEFORE INSERT OR UPDATE ON solarnet.sn_loc FOR EACH ROW EXECUTE PROCEDURE tsvector_update_trigger('fts_default', 'pg_catalog.english', 'country', 'region', 'state_prov', 'locality', 'postal_code', 'address');


--
-- Name: user_node node_ownership_transfer; Type: TRIGGER; Schema: solaruser; Owner: solarnet
--

CREATE TRIGGER node_ownership_transfer BEFORE UPDATE ON solaruser.user_node FOR EACH ROW WHEN ((old.user_id IS DISTINCT FROM new.user_id)) EXECUTE PROCEDURE solaruser.node_ownership_transfer();


--
-- Name: chunk_index_maint chunk_index_maint_chunk_id_fk; Type: FK CONSTRAINT; Schema: _timescaledb_solarnetwork; Owner: solarnet
--

ALTER TABLE ONLY _timescaledb_solarnetwork.chunk_index_maint
    ADD CONSTRAINT chunk_index_maint_chunk_id_fk FOREIGN KEY (chunk_id) REFERENCES _timescaledb_catalog.chunk(id) ON DELETE CASCADE;


--
-- Name: blob_triggers blob_triggers_sched_name_fkey; Type: FK CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.blob_triggers
    ADD CONSTRAINT blob_triggers_sched_name_fkey FOREIGN KEY (sched_name, trigger_name, trigger_group) REFERENCES quartz.triggers(sched_name, trigger_name, trigger_group);


--
-- Name: cron_triggers cron_triggers_sched_name_fkey; Type: FK CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.cron_triggers
    ADD CONSTRAINT cron_triggers_sched_name_fkey FOREIGN KEY (sched_name, trigger_name, trigger_group) REFERENCES quartz.triggers(sched_name, trigger_name, trigger_group);


--
-- Name: simple_triggers simple_triggers_sched_name_fkey; Type: FK CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.simple_triggers
    ADD CONSTRAINT simple_triggers_sched_name_fkey FOREIGN KEY (sched_name, trigger_name, trigger_group) REFERENCES quartz.triggers(sched_name, trigger_name, trigger_group);


--
-- Name: simprop_triggers simprop_triggers_sched_name_fkey; Type: FK CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.simprop_triggers
    ADD CONSTRAINT simprop_triggers_sched_name_fkey FOREIGN KEY (sched_name, trigger_name, trigger_group) REFERENCES quartz.triggers(sched_name, trigger_name, trigger_group);


--
-- Name: triggers triggers_sched_name_fkey; Type: FK CONSTRAINT; Schema: quartz; Owner: solarnet
--

ALTER TABLE ONLY quartz.triggers
    ADD CONSTRAINT triggers_sched_name_fkey FOREIGN KEY (sched_name, job_name, job_group) REFERENCES quartz.job_details(sched_name, job_name, job_group);


--
-- Name: sn_datum_import_job datum_import_user_fk; Type: FK CONSTRAINT; Schema: solarnet; Owner: solarnet
--

ALTER TABLE ONLY solarnet.sn_datum_import_job
    ADD CONSTRAINT datum_import_user_fk FOREIGN KEY (user_id) REFERENCES solaruser.user_user(id) ON DELETE CASCADE;


--
-- Name: sn_hardware_control sn_hardware_control_hardware_fk; Type: FK CONSTRAINT; Schema: solarnet; Owner: solarnet
--

ALTER TABLE ONLY solarnet.sn_hardware_control
    ADD CONSTRAINT sn_hardware_control_hardware_fk FOREIGN KEY (hw_id) REFERENCES solarnet.sn_hardware(id);


--
-- Name: sn_node_instruction sn_node_instruction_node_fk; Type: FK CONSTRAINT; Schema: solarnet; Owner: solarnet
--

ALTER TABLE ONLY solarnet.sn_node_instruction
    ADD CONSTRAINT sn_node_instruction_node_fk FOREIGN KEY (node_id) REFERENCES solarnet.sn_node(node_id);


--
-- Name: sn_node_instruction_param sn_node_instruction_param_sn_node_instruction_fk; Type: FK CONSTRAINT; Schema: solarnet; Owner: solarnet
--

ALTER TABLE ONLY solarnet.sn_node_instruction_param
    ADD CONSTRAINT sn_node_instruction_param_sn_node_instruction_fk FOREIGN KEY (instr_id) REFERENCES solarnet.sn_node_instruction(id) ON DELETE CASCADE;


--
-- Name: sn_node sn_node_loc_fk; Type: FK CONSTRAINT; Schema: solarnet; Owner: solarnet
--

ALTER TABLE ONLY solarnet.sn_node
    ADD CONSTRAINT sn_node_loc_fk FOREIGN KEY (loc_id) REFERENCES solarnet.sn_loc(id);


--
-- Name: sn_node_meta sn_node_meta_node_fk; Type: FK CONSTRAINT; Schema: solarnet; Owner: solarnet
--

ALTER TABLE ONLY solarnet.sn_node_meta
    ADD CONSTRAINT sn_node_meta_node_fk FOREIGN KEY (node_id) REFERENCES solarnet.sn_node(node_id) ON DELETE CASCADE;


--
-- Name: sn_node sn_node_weather_loc_fk; Type: FK CONSTRAINT; Schema: solarnet; Owner: solarnet
--

ALTER TABLE ONLY solarnet.sn_node
    ADD CONSTRAINT sn_node_weather_loc_fk FOREIGN KEY (wloc_id) REFERENCES solarnet.sn_weather_loc(id);


--
-- Name: sn_price_loc sn_price_loc_loc_fk; Type: FK CONSTRAINT; Schema: solarnet; Owner: solarnet
--

ALTER TABLE ONLY solarnet.sn_price_loc
    ADD CONSTRAINT sn_price_loc_loc_fk FOREIGN KEY (loc_id) REFERENCES solarnet.sn_loc(id);


--
-- Name: sn_price_loc sn_price_loc_sn_price_source_fk; Type: FK CONSTRAINT; Schema: solarnet; Owner: solarnet
--

ALTER TABLE ONLY solarnet.sn_price_loc
    ADD CONSTRAINT sn_price_loc_sn_price_source_fk FOREIGN KEY (source_id) REFERENCES solarnet.sn_price_source(id);


--
-- Name: sn_weather_loc sn_weather_location_sn_loc_fk; Type: FK CONSTRAINT; Schema: solarnet; Owner: solarnet
--

ALTER TABLE ONLY solarnet.sn_weather_loc
    ADD CONSTRAINT sn_weather_location_sn_loc_fk FOREIGN KEY (loc_id) REFERENCES solarnet.sn_loc(id);


--
-- Name: sn_weather_loc sn_weather_location_sn_weather_source_fk; Type: FK CONSTRAINT; Schema: solarnet; Owner: solarnet
--

ALTER TABLE ONLY solarnet.sn_weather_loc
    ADD CONSTRAINT sn_weather_location_sn_weather_source_fk FOREIGN KEY (source_id) REFERENCES solarnet.sn_weather_source(id);


--
-- Name: user_role fk_user_role_user_id; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_role
    ADD CONSTRAINT fk_user_role_user_id FOREIGN KEY (user_id) REFERENCES solaruser.user_user(id) ON DELETE CASCADE;


--
-- Name: user_adhoc_export_task user_adhoc_export_task_datum_export_task_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_adhoc_export_task
    ADD CONSTRAINT user_adhoc_export_task_datum_export_task_fk FOREIGN KEY (task_id) REFERENCES solarnet.sn_datum_export_task(id) ON DELETE CASCADE;


--
-- Name: user_alert user_alert_node_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_alert
    ADD CONSTRAINT user_alert_node_fk FOREIGN KEY (node_id) REFERENCES solarnet.sn_node(node_id);


--
-- Name: user_alert_sit user_alert_sit_alert_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_alert_sit
    ADD CONSTRAINT user_alert_sit_alert_fk FOREIGN KEY (alert_id) REFERENCES solaruser.user_alert(id) ON DELETE CASCADE;


--
-- Name: user_alert user_alert_user_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_alert
    ADD CONSTRAINT user_alert_user_fk FOREIGN KEY (user_id) REFERENCES solaruser.user_user(id) ON DELETE CASCADE;


--
-- Name: user_auth_token user_auth_token_user_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_auth_token
    ADD CONSTRAINT user_auth_token_user_fk FOREIGN KEY (user_id) REFERENCES solaruser.user_user(id) ON DELETE CASCADE;


--
-- Name: user_node_cert user_cert_user_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_node_cert
    ADD CONSTRAINT user_cert_user_fk FOREIGN KEY (user_id) REFERENCES solaruser.user_user(id) ON DELETE CASCADE;


--
-- Name: user_datum_delete_job user_datum_delete_user_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_datum_delete_job
    ADD CONSTRAINT user_datum_delete_user_fk FOREIGN KEY (user_id) REFERENCES solaruser.user_user(id) ON DELETE CASCADE;


--
-- Name: user_expire_data_conf user_expire_data_conf_user_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_expire_data_conf
    ADD CONSTRAINT user_expire_data_conf_user_fk FOREIGN KEY (user_id) REFERENCES solaruser.user_user(id) ON DELETE CASCADE;


--
-- Name: user_export_data_conf user_export_data_conf_user_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_export_data_conf
    ADD CONSTRAINT user_export_data_conf_user_fk FOREIGN KEY (user_id) REFERENCES solaruser.user_user(id) ON DELETE CASCADE;


--
-- Name: user_export_datum_conf user_export_datum_conf_data_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_export_datum_conf
    ADD CONSTRAINT user_export_datum_conf_data_fk FOREIGN KEY (data_conf_id) REFERENCES solaruser.user_export_data_conf(id);


--
-- Name: user_export_datum_conf user_export_datum_conf_dest_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_export_datum_conf
    ADD CONSTRAINT user_export_datum_conf_dest_fk FOREIGN KEY (dest_conf_id) REFERENCES solaruser.user_export_dest_conf(id);


--
-- Name: user_export_datum_conf user_export_datum_conf_outp_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_export_datum_conf
    ADD CONSTRAINT user_export_datum_conf_outp_fk FOREIGN KEY (outp_conf_id) REFERENCES solaruser.user_export_outp_conf(id);


--
-- Name: user_export_datum_conf user_export_datum_conf_user_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_export_datum_conf
    ADD CONSTRAINT user_export_datum_conf_user_fk FOREIGN KEY (user_id) REFERENCES solaruser.user_user(id) ON DELETE CASCADE;


--
-- Name: user_export_dest_conf user_export_dest_conf_user_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_export_dest_conf
    ADD CONSTRAINT user_export_dest_conf_user_fk FOREIGN KEY (user_id) REFERENCES solaruser.user_user(id) ON DELETE CASCADE;


--
-- Name: user_export_outp_conf user_export_outp_conf_user_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_export_outp_conf
    ADD CONSTRAINT user_export_outp_conf_user_fk FOREIGN KEY (user_id) REFERENCES solaruser.user_user(id) ON DELETE CASCADE;


--
-- Name: user_export_task user_export_task_datum_export_task_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_export_task
    ADD CONSTRAINT user_export_task_datum_export_task_fk FOREIGN KEY (task_id) REFERENCES solarnet.sn_datum_export_task(id);


--
-- Name: user_export_task user_export_task_user_export_datum_conf_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_export_task
    ADD CONSTRAINT user_export_task_user_export_datum_conf_fk FOREIGN KEY (conf_id) REFERENCES solaruser.user_export_datum_conf(id);


--
-- Name: user_meta user_meta_user_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_meta
    ADD CONSTRAINT user_meta_user_fk FOREIGN KEY (user_id) REFERENCES solaruser.user_user(id) ON DELETE CASCADE;


--
-- Name: user_node_conf user_node_conf_user_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_node_conf
    ADD CONSTRAINT user_node_conf_user_fk FOREIGN KEY (user_id) REFERENCES solaruser.user_user(id);


--
-- Name: user_node_hardware_control user_node_hardware_control_hardware_control_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_node_hardware_control
    ADD CONSTRAINT user_node_hardware_control_hardware_control_fk FOREIGN KEY (hwc_id) REFERENCES solarnet.sn_hardware_control(id);


--
-- Name: user_node_hardware_control user_node_hardware_control_node_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_node_hardware_control
    ADD CONSTRAINT user_node_hardware_control_node_fk FOREIGN KEY (node_id) REFERENCES solarnet.sn_node(node_id);


--
-- Name: user_node user_node_node_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_node
    ADD CONSTRAINT user_node_node_fk FOREIGN KEY (node_id) REFERENCES solarnet.sn_node(node_id);


--
-- Name: user_node user_node_user_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_node
    ADD CONSTRAINT user_node_user_fk FOREIGN KEY (user_id) REFERENCES solaruser.user_user(id);


--
-- Name: user_node_xfer user_node_xfer_user_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_node_xfer
    ADD CONSTRAINT user_node_xfer_user_fk FOREIGN KEY (user_id) REFERENCES solaruser.user_user(id) ON DELETE CASCADE;


--
-- Name: user_user user_user_loc_fk; Type: FK CONSTRAINT; Schema: solaruser; Owner: solarnet
--

ALTER TABLE ONLY solaruser.user_user
    ADD CONSTRAINT user_user_loc_fk FOREIGN KEY (loc_id) REFERENCES solarnet.sn_loc(id);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pgsql
--

GRANT USAGE ON SCHEMA public TO solarauth;


--
-- Name: SCHEMA _timescaledb_catalog; Type: ACL; Schema: -; Owner: postgres
--

GRANT ALL ON SCHEMA _timescaledb_catalog TO solarinput;


--
-- Name: SCHEMA quartz; Type: ACL; Schema: -; Owner: solarnet
--

GRANT ALL ON SCHEMA quartz TO solar;


--
-- Name: SCHEMA solaragg; Type: ACL; Schema: -; Owner: solarnet
--

GRANT ALL ON SCHEMA solaragg TO solar;


--
-- Name: SCHEMA solarcommon; Type: ACL; Schema: -; Owner: solarnet
--

GRANT ALL ON SCHEMA solarcommon TO solar;


--
-- Name: SCHEMA solardatum; Type: ACL; Schema: -; Owner: solarnet
--

GRANT ALL ON SCHEMA solardatum TO solar;


--
-- Name: SCHEMA solarnet; Type: ACL; Schema: -; Owner: solarnet
--

GRANT ALL ON SCHEMA solarnet TO solar;


--
-- Name: SCHEMA solaruser; Type: ACL; Schema: -; Owner: solarnet
--

GRANT ALL ON SCHEMA solaruser TO solar;
GRANT USAGE ON SCHEMA solaruser TO solarauth;


--
-- Name: TYPE created; Type: ACL; Schema: solarnet; Owner: solarnet
--

REVOKE ALL ON TYPE solarnet.created FROM solarnet;


--
-- Name: TYPE instruction_delivery_state; Type: ACL; Schema: solarnet; Owner: solarnet
--

REVOKE ALL ON TYPE solarnet.instruction_delivery_state FROM solarnet;


--
-- Name: SEQUENCE solarnet_seq; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT,USAGE ON SEQUENCE solarnet.solarnet_seq TO solar;
GRANT ALL ON SEQUENCE solarnet.solarnet_seq TO solarinput;


--
-- Name: TYPE pk_i; Type: ACL; Schema: solarnet; Owner: solarnet
--

REVOKE ALL ON TYPE solarnet.pk_i FROM solarnet;


--
-- Name: TYPE user_auth_token_status; Type: ACL; Schema: solaruser; Owner: solarnet
--

REVOKE ALL ON TYPE solaruser.user_auth_token_status FROM solarnet;


--
-- Name: TYPE user_auth_token_type; Type: ACL; Schema: solaruser; Owner: solarnet
--

REVOKE ALL ON TYPE solaruser.user_auth_token_type FROM solarnet;


--
-- Name: FUNCTION aud_inc_datum_query_count(qdate timestamp with time zone, node bigint, source text, dcount integer); Type: ACL; Schema: solaragg; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaragg.aud_inc_datum_query_count(qdate timestamp with time zone, node bigint, source text, dcount integer) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.aud_inc_datum_query_count(qdate timestamp with time zone, node bigint, source text, dcount integer) TO solar;


--
-- Name: FUNCTION calc_agg_datum_agg(node bigint, sources text[], start_ts timestamp with time zone, end_ts timestamp with time zone, kind character); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.calc_agg_datum_agg(node bigint, sources text[], start_ts timestamp with time zone, end_ts timestamp with time zone, kind character) TO solar;


--
-- Name: FUNCTION calc_agg_loc_datum_agg(loc bigint, sources text[], start_ts timestamp with time zone, end_ts timestamp with time zone, kind character); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.calc_agg_loc_datum_agg(loc bigint, sources text[], start_ts timestamp with time zone, end_ts timestamp with time zone, kind character) TO solar;


--
-- Name: FUNCTION calc_datum_time_slots(node bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer, tolerance interval); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.calc_datum_time_slots(node bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer, tolerance interval) TO solar;


--
-- Name: FUNCTION calc_datum_time_slots_test(node bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer, tolerance interval); Type: ACL; Schema: solaragg; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaragg.calc_datum_time_slots_test(node bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer, tolerance interval) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.calc_datum_time_slots_test(node bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer, tolerance interval) TO solar;


--
-- Name: FUNCTION calc_loc_datum_time_slots(loc bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer, tolerance interval); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.calc_loc_datum_time_slots(loc bigint, sources text[], start_ts timestamp with time zone, span interval, slotsecs integer, tolerance interval) TO solar;


--
-- Name: FUNCTION calc_running_datum_total(nodes bigint[], sources text[], end_ts timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.calc_running_datum_total(nodes bigint[], sources text[], end_ts timestamp with time zone) TO solar;


--
-- Name: FUNCTION calc_running_datum_total(node bigint, sources text[], end_ts timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.calc_running_datum_total(node bigint, sources text[], end_ts timestamp with time zone) TO solar;


--
-- Name: FUNCTION calc_running_loc_datum_total(locs bigint[], sources text[], end_ts timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.calc_running_loc_datum_total(locs bigint[], sources text[], end_ts timestamp with time zone) TO solar;


--
-- Name: FUNCTION calc_running_loc_datum_total(loc bigint, sources text[], end_ts timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.calc_running_loc_datum_total(loc bigint, sources text[], end_ts timestamp with time zone) TO solar;


--
-- Name: FUNCTION calc_running_total(pk bigint, sources text[], end_ts timestamp with time zone, loc_mode boolean); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.calc_running_total(pk bigint, sources text[], end_ts timestamp with time zone, loc_mode boolean) TO solar;


--
-- Name: FUNCTION find_agg_datum_dow(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_agg_datum_dow(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;


--
-- Name: FUNCTION find_agg_datum_hod(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_agg_datum_hod(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;


--
-- Name: FUNCTION find_agg_datum_minute(node bigint, source text[], start_ts timestamp with time zone, end_ts timestamp with time zone, slotsecs integer, tolerance interval); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_agg_datum_minute(node bigint, source text[], start_ts timestamp with time zone, end_ts timestamp with time zone, slotsecs integer, tolerance interval) TO solar;


--
-- Name: FUNCTION find_agg_datum_seasonal_dow(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_agg_datum_seasonal_dow(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;


--
-- Name: FUNCTION find_agg_datum_seasonal_hod(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_agg_datum_seasonal_hod(node bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;


--
-- Name: FUNCTION find_agg_loc_datum_dow(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_agg_loc_datum_dow(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;


--
-- Name: FUNCTION find_agg_loc_datum_hod(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_agg_loc_datum_hod(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;


--
-- Name: FUNCTION find_agg_loc_datum_minute(loc bigint, source text[], start_ts timestamp with time zone, end_ts timestamp with time zone, slotsecs integer, tolerance interval); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_agg_loc_datum_minute(loc bigint, source text[], start_ts timestamp with time zone, end_ts timestamp with time zone, slotsecs integer, tolerance interval) TO solar;


--
-- Name: FUNCTION find_agg_loc_datum_seasonal_dow(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_agg_loc_datum_seasonal_dow(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;


--
-- Name: FUNCTION find_agg_loc_datum_seasonal_hod(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_agg_loc_datum_seasonal_hod(loc bigint, source text[], path text[], start_ts timestamp with time zone, end_ts timestamp with time zone) TO solar;


--
-- Name: FUNCTION find_audit_acc_datum_daily(node bigint, source text); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_audit_acc_datum_daily(node bigint, source text) TO solar;


--
-- Name: FUNCTION find_available_sources(nodes bigint[]); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_available_sources(nodes bigint[]) TO solar;


--
-- Name: FUNCTION find_available_sources(nodes bigint[], sdate timestamp with time zone, edate timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_available_sources(nodes bigint[], sdate timestamp with time zone, edate timestamp with time zone) TO solar;


--
-- Name: FUNCTION find_available_sources_before(nodes bigint[], edate timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_available_sources_before(nodes bigint[], edate timestamp with time zone) TO solar;


--
-- Name: FUNCTION find_available_sources_since(nodes bigint[], sdate timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_available_sources_since(nodes bigint[], sdate timestamp with time zone) TO solar;


--
-- Name: FUNCTION find_datum_for_time_span(node bigint, sources text[], start_ts timestamp with time zone, span interval, tolerance interval); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_datum_for_time_span(node bigint, sources text[], start_ts timestamp with time zone, span interval, tolerance interval) TO solar;


--
-- Name: FUNCTION find_loc_datum_for_time_span(loc bigint, sources text[], start_ts timestamp with time zone, span interval, tolerance interval); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_loc_datum_for_time_span(loc bigint, sources text[], start_ts timestamp with time zone, span interval, tolerance interval) TO solar;


--
-- Name: TABLE agg_datum_daily; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.agg_datum_daily TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_datum_daily TO solar;


--
-- Name: FUNCTION jdata_from_datum(datum solaragg.agg_datum_daily); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_datum_daily) TO solar;


--
-- Name: TABLE agg_datum_daily_data; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.agg_datum_daily_data TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_datum_daily_data TO solar;


--
-- Name: FUNCTION find_most_recent_daily(node bigint, sources text[]); Type: ACL; Schema: solaragg; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaragg.find_most_recent_daily(node bigint, sources text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.find_most_recent_daily(node bigint, sources text[]) TO solar;


--
-- Name: TABLE agg_datum_hourly; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.agg_datum_hourly TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_datum_hourly TO solar;


--
-- Name: FUNCTION jdata_from_datum(datum solaragg.agg_datum_hourly); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_datum_hourly) TO solar;


--
-- Name: TABLE agg_datum_hourly_data; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.agg_datum_hourly_data TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_datum_hourly_data TO solar;


--
-- Name: FUNCTION find_most_recent_hourly(node bigint, sources text[]); Type: ACL; Schema: solaragg; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaragg.find_most_recent_hourly(node bigint, sources text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.find_most_recent_hourly(node bigint, sources text[]) TO solar;


--
-- Name: TABLE agg_datum_monthly; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.agg_datum_monthly TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_datum_monthly TO solar;


--
-- Name: FUNCTION jdata_from_datum(datum solaragg.agg_datum_monthly); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_datum_monthly) TO solar;


--
-- Name: TABLE agg_datum_monthly_data; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.agg_datum_monthly_data TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_datum_monthly_data TO solar;


--
-- Name: FUNCTION find_most_recent_monthly(node bigint, sources text[]); Type: ACL; Schema: solaragg; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaragg.find_most_recent_monthly(node bigint, sources text[]) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.find_most_recent_monthly(node bigint, sources text[]) TO solar;


--
-- Name: FUNCTION find_running_datum(node bigint, sources text[], end_ts timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_running_datum(node bigint, sources text[], end_ts timestamp with time zone) TO solar;


--
-- Name: FUNCTION find_running_loc_datum(loc bigint, sources text[], end_ts timestamp with time zone); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.find_running_loc_datum(loc bigint, sources text[], end_ts timestamp with time zone) TO solar;


--
-- Name: TABLE agg_loc_datum_daily; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.agg_loc_datum_daily TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_loc_datum_daily TO solar;


--
-- Name: FUNCTION jdata_from_datum(datum solaragg.agg_loc_datum_daily); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_loc_datum_daily) TO solar;


--
-- Name: TABLE agg_loc_datum_hourly; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.agg_loc_datum_hourly TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_loc_datum_hourly TO solar;


--
-- Name: FUNCTION jdata_from_datum(datum solaragg.agg_loc_datum_hourly); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_loc_datum_hourly) TO solar;


--
-- Name: TABLE agg_loc_datum_monthly; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.agg_loc_datum_monthly TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_loc_datum_monthly TO solar;


--
-- Name: FUNCTION jdata_from_datum(datum solaragg.agg_loc_datum_monthly); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.jdata_from_datum(datum solaragg.agg_loc_datum_monthly) TO solar;


--
-- Name: FUNCTION minute_time_slot(ts timestamp with time zone, sec integer); Type: ACL; Schema: solaragg; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaragg.minute_time_slot(ts timestamp with time zone, sec integer) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.minute_time_slot(ts timestamp with time zone, sec integer) TO solar;


--
-- Name: FUNCTION populate_audit_acc_datum_daily(node bigint, source text); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.populate_audit_acc_datum_daily(node bigint, source text) TO solarinput;


--
-- Name: FUNCTION process_agg_stale_datum(kind character, max integer); Type: ACL; Schema: solaragg; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaragg.process_agg_stale_datum(kind character, max integer) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.process_agg_stale_datum(kind character, max integer) TO solar;


--
-- Name: FUNCTION process_agg_stale_loc_datum(kind character, max integer); Type: ACL; Schema: solaragg; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaragg.process_agg_stale_loc_datum(kind character, max integer) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.process_agg_stale_loc_datum(kind character, max integer) TO solar;


--
-- Name: FUNCTION process_one_agg_stale_datum(kind character); Type: ACL; Schema: solaragg; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaragg.process_one_agg_stale_datum(kind character) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.process_one_agg_stale_datum(kind character) TO solar;


--
-- Name: FUNCTION process_one_agg_stale_loc_datum(kind character); Type: ACL; Schema: solaragg; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaragg.process_one_agg_stale_loc_datum(kind character) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.process_one_agg_stale_loc_datum(kind character) TO solar;


--
-- Name: FUNCTION process_one_aud_datum_daily_stale(kind character); Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON FUNCTION solaragg.process_one_aud_datum_daily_stale(kind character) TO solar;


--
-- Name: FUNCTION slot_seconds(secs integer); Type: ACL; Schema: solaragg; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaragg.slot_seconds(secs integer) FROM PUBLIC;
GRANT ALL ON FUNCTION solaragg.slot_seconds(secs integer) TO solar;


--
-- Name: FUNCTION ant_pattern_to_regexp(pat text); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.ant_pattern_to_regexp(pat text) TO solar;


--
-- Name: FUNCTION components_from_jdata(jdata jsonb, OUT jdata_i jsonb, OUT jdata_a jsonb, OUT jdata_s jsonb, OUT jdata_t text[]); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.components_from_jdata(jdata jsonb, OUT jdata_i jsonb, OUT jdata_a jsonb, OUT jdata_s jsonb, OUT jdata_t text[]) TO solar;


--
-- Name: FUNCTION first_sfunc(anyelement, anyelement); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.first_sfunc(anyelement, anyelement) TO solar;


--
-- Name: FUNCTION jdata_from_components(jdata_i jsonb, jdata_a jsonb, jdata_s jsonb, jdata_t text[]); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.jdata_from_components(jdata_i jsonb, jdata_a jsonb, jdata_s jsonb, jdata_t text[]) TO solar;


--
-- Name: FUNCTION json_array_to_text_array(jdata json); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.json_array_to_text_array(jdata json) TO solar;


--
-- Name: FUNCTION json_array_to_text_array(jdata jsonb); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.json_array_to_text_array(jdata jsonb) TO solar;


--
-- Name: FUNCTION jsonb_avg_finalfunc(agg_state jsonb); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.jsonb_avg_finalfunc(agg_state jsonb) TO solar;


--
-- Name: FUNCTION jsonb_avg_object_finalfunc(agg_state jsonb); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.jsonb_avg_object_finalfunc(agg_state jsonb) TO solar;


--
-- Name: FUNCTION jsonb_avg_object_sfunc(agg_state jsonb, el jsonb); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.jsonb_avg_object_sfunc(agg_state jsonb, el jsonb) TO solar;


--
-- Name: FUNCTION jsonb_avg_sfunc(agg_state jsonb, el jsonb); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.jsonb_avg_sfunc(agg_state jsonb, el jsonb) TO solar;


--
-- Name: FUNCTION jsonb_diff_object_finalfunc(agg_state jsonb); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.jsonb_diff_object_finalfunc(agg_state jsonb) TO solar;


--
-- Name: FUNCTION jsonb_diff_object_sfunc(agg_state jsonb, el jsonb); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.jsonb_diff_object_sfunc(agg_state jsonb, el jsonb) TO solar;


--
-- Name: FUNCTION jsonb_diffsum_jdata_finalfunc(agg_state jsonb); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.jsonb_diffsum_jdata_finalfunc(agg_state jsonb) TO solar;


--
-- Name: FUNCTION jsonb_diffsum_object_finalfunc(agg_state jsonb); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.jsonb_diffsum_object_finalfunc(agg_state jsonb) TO solar;


--
-- Name: FUNCTION jsonb_diffsum_object_sfunc(agg_state jsonb, el jsonb); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.jsonb_diffsum_object_sfunc(agg_state jsonb, el jsonb) TO solar;


--
-- Name: FUNCTION jsonb_sum_object_sfunc(agg_state jsonb, el jsonb); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.jsonb_sum_object_sfunc(agg_state jsonb, el jsonb) TO solar;


--
-- Name: FUNCTION jsonb_sum_sfunc(agg_state jsonb, el jsonb); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.jsonb_sum_sfunc(agg_state jsonb, el jsonb) TO solar;


--
-- Name: FUNCTION jsonb_weighted_proj_object_finalfunc(agg_state jsonb); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.jsonb_weighted_proj_object_finalfunc(agg_state jsonb) TO solar;


--
-- Name: FUNCTION jsonb_weighted_proj_object_sfunc(agg_state jsonb, el jsonb, weight double precision); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.jsonb_weighted_proj_object_sfunc(agg_state jsonb, el jsonb, weight double precision) TO solar;


--
-- Name: FUNCTION plainto_prefix_tsquery(qtext text); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.plainto_prefix_tsquery(qtext text) TO solar;


--
-- Name: FUNCTION plainto_prefix_tsquery(config regconfig, qtext text); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.plainto_prefix_tsquery(config regconfig, qtext text) TO solar;


--
-- Name: FUNCTION reduce_dim(anyarray); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.reduce_dim(anyarray) TO solar;


--
-- Name: FUNCTION to_rfc1123_utc(d timestamp with time zone); Type: ACL; Schema: solarcommon; Owner: solarnet
--

GRANT ALL ON FUNCTION solarcommon.to_rfc1123_utc(d timestamp with time zone) TO solar;


--
-- Name: FUNCTION calculate_datum_at(nodes bigint[], sources text[], reading_ts timestamp with time zone, span interval); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.calculate_datum_at(nodes bigint[], sources text[], reading_ts timestamp with time zone, span interval) TO solar;


--
-- Name: FUNCTION calculate_datum_at_local(nodes bigint[], sources text[], reading_ts timestamp without time zone, span interval); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.calculate_datum_at_local(nodes bigint[], sources text[], reading_ts timestamp without time zone, span interval) TO solar;


--
-- Name: FUNCTION calculate_datum_diff(nodes bigint[], sources text[], ts_min timestamp with time zone, ts_max timestamp with time zone, tolerance interval); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.calculate_datum_diff(nodes bigint[], sources text[], ts_min timestamp with time zone, ts_max timestamp with time zone, tolerance interval) TO solar;


--
-- Name: FUNCTION calculate_datum_diff_local(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone, tolerance interval); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.calculate_datum_diff_local(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone, tolerance interval) TO solar;


--
-- Name: FUNCTION calculate_datum_diff_over(nodes bigint[], sources text[], ts_min timestamp with time zone, ts_max timestamp with time zone); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.calculate_datum_diff_over(nodes bigint[], sources text[], ts_min timestamp with time zone, ts_max timestamp with time zone) TO solar;


--
-- Name: FUNCTION calculate_datum_diff_over(node bigint, source text, ts_min timestamp with time zone, ts_max timestamp with time zone, tolerance interval); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.calculate_datum_diff_over(node bigint, source text, ts_min timestamp with time zone, ts_max timestamp with time zone, tolerance interval) TO solar;


--
-- Name: FUNCTION calculate_datum_diff_over_local(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.calculate_datum_diff_over_local(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) TO solar;


--
-- Name: FUNCTION datum_prop_count(jdata jsonb); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.datum_prop_count(jdata jsonb) TO solar;


--
-- Name: FUNCTION datum_record_counts(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.datum_record_counts(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) TO solar;


--
-- Name: FUNCTION datum_record_counts_for_filter(jfilter jsonb); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.datum_record_counts_for_filter(jfilter jsonb) TO solar;


--
-- Name: FUNCTION delete_datum(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.delete_datum(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) TO solar;


--
-- Name: FUNCTION delete_datum_for_filter(jfilter jsonb); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.delete_datum_for_filter(jfilter jsonb) TO solar;


--
-- Name: FUNCTION find_available_sources(nodes bigint[]); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_available_sources(nodes bigint[]) TO solar;


--
-- Name: FUNCTION find_available_sources(node bigint, st timestamp with time zone, en timestamp with time zone); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_available_sources(node bigint, st timestamp with time zone, en timestamp with time zone) TO solar;


--
-- Name: TABLE da_datum; Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON TABLE solardatum.da_datum TO solarinput;
GRANT SELECT ON TABLE solardatum.da_datum TO solar;


--
-- Name: FUNCTION find_earliest_after(nodes bigint[], sources text[], ts_min timestamp with time zone); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_earliest_after(nodes bigint[], sources text[], ts_min timestamp with time zone) TO solar;


--
-- Name: FUNCTION find_latest_before(nodes bigint[], sources text[], ts_max timestamp with time zone); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_latest_before(nodes bigint[], sources text[], ts_max timestamp with time zone) TO solar;


--
-- Name: SEQUENCE node_seq; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT,USAGE ON SEQUENCE solarnet.node_seq TO solar;
GRANT ALL ON SEQUENCE solarnet.node_seq TO solarinput;


--
-- Name: TABLE sn_loc; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT ON TABLE solarnet.sn_loc TO solar;
GRANT ALL ON TABLE solarnet.sn_loc TO solarinput;


--
-- Name: TABLE sn_node; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT ON TABLE solarnet.sn_node TO solar;
GRANT ALL ON TABLE solarnet.sn_node TO solarinput;


--
-- Name: TABLE da_datum_data; Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT SELECT ON TABLE solardatum.da_datum_data TO solar;


--
-- Name: FUNCTION find_least_recent_direct(node bigint); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_least_recent_direct(node bigint) TO solar;


--
-- Name: FUNCTION find_loc_available_sources(loc bigint, st timestamp with time zone, en timestamp with time zone); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_loc_available_sources(loc bigint, st timestamp with time zone, en timestamp with time zone) TO solar;


--
-- Name: TABLE da_loc_datum; Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON TABLE solardatum.da_loc_datum TO solarinput;
GRANT SELECT ON TABLE solardatum.da_loc_datum TO solar;


--
-- Name: TABLE da_loc_datum_data; Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT SELECT ON TABLE solardatum.da_loc_datum_data TO solar;


--
-- Name: FUNCTION find_loc_reportable_interval(loc bigint, src text, OUT ts_start timestamp with time zone, OUT ts_end timestamp with time zone, OUT loc_tz text, OUT loc_tz_offset integer); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_loc_reportable_interval(loc bigint, src text, OUT ts_start timestamp with time zone, OUT ts_end timestamp with time zone, OUT loc_tz text, OUT loc_tz_offset integer) TO solar;


--
-- Name: FUNCTION find_most_recent(nodes bigint[]); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_most_recent(nodes bigint[]) TO solar;


--
-- Name: FUNCTION find_most_recent(node bigint); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_most_recent(node bigint) TO solar;


--
-- Name: FUNCTION find_most_recent(node bigint, sources text[]); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_most_recent(node bigint, sources text[]) TO solar;


--
-- Name: FUNCTION find_most_recent_direct(nodes bigint[]); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_most_recent_direct(nodes bigint[]) TO solar;


--
-- Name: FUNCTION find_most_recent_direct(node bigint); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_most_recent_direct(node bigint) TO solar;


--
-- Name: FUNCTION find_most_recent_direct(node bigint, sources text[]); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_most_recent_direct(node bigint, sources text[]) TO solar;


--
-- Name: FUNCTION find_reportable_interval(node bigint, src text, OUT ts_start timestamp with time zone, OUT ts_end timestamp with time zone, OUT node_tz text, OUT node_tz_offset integer); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_reportable_interval(node bigint, src text, OUT ts_start timestamp with time zone, OUT ts_end timestamp with time zone, OUT node_tz text, OUT node_tz_offset integer) TO solar;


--
-- Name: FUNCTION find_reportable_intervals(nodes bigint[]); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_reportable_intervals(nodes bigint[]) TO solar;


--
-- Name: FUNCTION find_reportable_intervals(nodes bigint[], sources text[]); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_reportable_intervals(nodes bigint[], sources text[]) TO solar;


--
-- Name: FUNCTION find_sources_for_loc_meta(locs bigint[], criteria text); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_sources_for_loc_meta(locs bigint[], criteria text) TO solar;


--
-- Name: FUNCTION find_sources_for_meta(nodes bigint[], criteria text); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.find_sources_for_meta(nodes bigint[], criteria text) TO solar;


--
-- Name: TABLE da_datum_aux; Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT SELECT ON TABLE solardatum.da_datum_aux TO solar;
GRANT ALL ON TABLE solardatum.da_datum_aux TO solarinput;


--
-- Name: FUNCTION jdata_from_datum_aux_final(datum solardatum.da_datum_aux); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.jdata_from_datum_aux_final(datum solardatum.da_datum_aux) TO solar;


--
-- Name: FUNCTION jdata_from_datum_aux_start(datum solardatum.da_datum_aux); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.jdata_from_datum_aux_start(datum solardatum.da_datum_aux) TO solar;


--
-- Name: FUNCTION move_datum_aux(cdate_from timestamp with time zone, node_from bigint, src_from character varying, aux_type_from solardatum.da_datum_aux_type, cdate timestamp with time zone, node bigint, src character varying, aux_type solardatum.da_datum_aux_type, aux_notes text, jdata_final text, jdata_start text, meta_json text); Type: ACL; Schema: solardatum; Owner: solarnet
--

REVOKE ALL ON FUNCTION solardatum.move_datum_aux(cdate_from timestamp with time zone, node_from bigint, src_from character varying, aux_type_from solardatum.da_datum_aux_type, cdate timestamp with time zone, node bigint, src character varying, aux_type solardatum.da_datum_aux_type, aux_notes text, jdata_final text, jdata_start text, meta_json text) FROM PUBLIC;
GRANT ALL ON FUNCTION solardatum.move_datum_aux(cdate_from timestamp with time zone, node_from bigint, src_from character varying, aux_type_from solardatum.da_datum_aux_type, cdate timestamp with time zone, node bigint, src character varying, aux_type solardatum.da_datum_aux_type, aux_notes text, jdata_final text, jdata_start text, meta_json text) TO solar;


--
-- Name: FUNCTION store_datum(cdate timestamp with time zone, node bigint, src text, pdate timestamp with time zone, jdata text, track_recent boolean); Type: ACL; Schema: solardatum; Owner: solarnet
--

REVOKE ALL ON FUNCTION solardatum.store_datum(cdate timestamp with time zone, node bigint, src text, pdate timestamp with time zone, jdata text, track_recent boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION solardatum.store_datum(cdate timestamp with time zone, node bigint, src text, pdate timestamp with time zone, jdata text, track_recent boolean) TO solarin;


--
-- Name: FUNCTION store_datum_aux(cdate timestamp with time zone, node bigint, src character varying, aux_type solardatum.da_datum_aux_type, aux_notes text, jdata_final text, jdata_start text, jmeta text); Type: ACL; Schema: solardatum; Owner: solarnet
--

REVOKE ALL ON FUNCTION solardatum.store_datum_aux(cdate timestamp with time zone, node bigint, src character varying, aux_type solardatum.da_datum_aux_type, aux_notes text, jdata_final text, jdata_start text, jmeta text) FROM PUBLIC;
GRANT ALL ON FUNCTION solardatum.store_datum_aux(cdate timestamp with time zone, node bigint, src character varying, aux_type solardatum.da_datum_aux_type, aux_notes text, jdata_final text, jdata_start text, jmeta text) TO solarin;


--
-- Name: FUNCTION store_loc_datum(cdate timestamp with time zone, loc bigint, src text, pdate timestamp with time zone, jdata text); Type: ACL; Schema: solardatum; Owner: solarnet
--

REVOKE ALL ON FUNCTION solardatum.store_loc_datum(cdate timestamp with time zone, loc bigint, src text, pdate timestamp with time zone, jdata text) FROM PUBLIC;
GRANT ALL ON FUNCTION solardatum.store_loc_datum(cdate timestamp with time zone, loc bigint, src text, pdate timestamp with time zone, jdata text) TO solar;


--
-- Name: FUNCTION store_loc_meta(cdate timestamp with time zone, loc bigint, src text, jdata text); Type: ACL; Schema: solardatum; Owner: solarnet
--

REVOKE ALL ON FUNCTION solardatum.store_loc_meta(cdate timestamp with time zone, loc bigint, src text, jdata text) FROM PUBLIC;
GRANT ALL ON FUNCTION solardatum.store_loc_meta(cdate timestamp with time zone, loc bigint, src text, jdata text) TO solar;


--
-- Name: FUNCTION store_meta(cdate timestamp with time zone, node bigint, src text, jdata text); Type: ACL; Schema: solardatum; Owner: solarnet
--

REVOKE ALL ON FUNCTION solardatum.store_meta(cdate timestamp with time zone, node bigint, src text, jdata text) FROM PUBLIC;
GRANT ALL ON FUNCTION solardatum.store_meta(cdate timestamp with time zone, node bigint, src text, jdata text) TO solar;


--
-- Name: FUNCTION update_datum_range_dates(node bigint, source character varying, rdate timestamp with time zone); Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT ALL ON FUNCTION solardatum.update_datum_range_dates(node bigint, source character varying, rdate timestamp with time zone) TO solar;


--
-- Name: FUNCTION add_datum_export_task(uid uuid, ex_date timestamp with time zone, cfg text); Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT ALL ON FUNCTION solarnet.add_datum_export_task(uid uuid, ex_date timestamp with time zone, cfg text) TO solar;


--
-- Name: TABLE sn_datum_export_task; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT ON TABLE solarnet.sn_datum_export_task TO solar;
GRANT ALL ON TABLE solarnet.sn_datum_export_task TO solarinput;


--
-- Name: FUNCTION claim_datum_export_task(); Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT ALL ON FUNCTION solarnet.claim_datum_export_task() TO solar;


--
-- Name: TABLE sn_datum_import_job; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT ON TABLE solarnet.sn_datum_import_job TO solar;
GRANT ALL ON TABLE solarnet.sn_datum_import_job TO solarinput;


--
-- Name: FUNCTION claim_datum_import_job(); Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT ALL ON FUNCTION solarnet.claim_datum_import_job() TO solar;


--
-- Name: FUNCTION get_node_local_timestamp(timestamp with time zone, bigint); Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT ALL ON FUNCTION solarnet.get_node_local_timestamp(timestamp with time zone, bigint) TO solar;
GRANT ALL ON FUNCTION solarnet.get_node_local_timestamp(timestamp with time zone, bigint) TO solarinput;


--
-- Name: FUNCTION get_node_timezone(bigint); Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT ALL ON FUNCTION solarnet.get_node_timezone(bigint) TO solar;


--
-- Name: FUNCTION get_season(date); Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT ALL ON FUNCTION solarnet.get_season(date) TO solar;


--
-- Name: FUNCTION get_season_monday_start(date); Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT ALL ON FUNCTION solarnet.get_season_monday_start(date) TO solar;


--
-- Name: FUNCTION node_source_time_ranges_local(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone); Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT ALL ON FUNCTION solarnet.node_source_time_ranges_local(nodes bigint[], sources text[], ts_min timestamp without time zone, ts_max timestamp without time zone) TO solar;


--
-- Name: FUNCTION purge_completed_datum_export_tasks(older_date timestamp with time zone); Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT ALL ON FUNCTION solarnet.purge_completed_datum_export_tasks(older_date timestamp with time zone) TO solar;


--
-- Name: FUNCTION purge_completed_datum_import_jobs(older_date timestamp with time zone); Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT ALL ON FUNCTION solarnet.purge_completed_datum_import_jobs(older_date timestamp with time zone) TO solar;


--
-- Name: FUNCTION purge_completed_instructions(older_date timestamp with time zone); Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT ALL ON FUNCTION solarnet.purge_completed_instructions(older_date timestamp with time zone) TO solar;


--
-- Name: FUNCTION store_node_meta(cdate timestamp with time zone, node bigint, jdata text); Type: ACL; Schema: solarnet; Owner: solarnet
--

REVOKE ALL ON FUNCTION solarnet.store_node_meta(cdate timestamp with time zone, node bigint, jdata text) FROM PUBLIC;
GRANT ALL ON FUNCTION solarnet.store_node_meta(cdate timestamp with time zone, node bigint, jdata text) TO solarinput;


--
-- Name: TABLE user_datum_delete_job; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_datum_delete_job TO solar;
GRANT ALL ON TABLE solaruser.user_datum_delete_job TO solarinput;


--
-- Name: FUNCTION claim_datum_delete_job(); Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON FUNCTION solaruser.claim_datum_delete_job() TO solar;


--
-- Name: FUNCTION expire_datum_for_policy(userid bigint, jpolicy jsonb, age interval); Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON FUNCTION solaruser.expire_datum_for_policy(userid bigint, jpolicy jsonb, age interval) TO solar;


--
-- Name: FUNCTION find_most_recent_datum_for_user(users bigint[]); Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON FUNCTION solaruser.find_most_recent_datum_for_user(users bigint[]) TO solar;


--
-- Name: FUNCTION find_most_recent_datum_for_user_direct(users bigint[]); Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON FUNCTION solaruser.find_most_recent_datum_for_user_direct(users bigint[]) TO solar;


--
-- Name: FUNCTION preview_expire_datum_for_policy(userid bigint, jpolicy jsonb, age interval); Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON FUNCTION solaruser.preview_expire_datum_for_policy(userid bigint, jpolicy jsonb, age interval) TO solar;


--
-- Name: FUNCTION purge_completed_datum_delete_jobs(older_date timestamp with time zone); Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON FUNCTION solaruser.purge_completed_datum_delete_jobs(older_date timestamp with time zone) TO solar;


--
-- Name: FUNCTION purge_completed_user_adhoc_export_tasks(older_date timestamp with time zone); Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON FUNCTION solaruser.purge_completed_user_adhoc_export_tasks(older_date timestamp with time zone) TO solar;


--
-- Name: FUNCTION purge_completed_user_export_tasks(older_date timestamp with time zone); Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON FUNCTION solaruser.purge_completed_user_export_tasks(older_date timestamp with time zone) TO solar;


--
-- Name: FUNCTION purge_resolved_situations(older_date timestamp with time zone); Type: ACL; Schema: solaruser; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaruser.purge_resolved_situations(older_date timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION solaruser.purge_resolved_situations(older_date timestamp with time zone) TO solarinput;


--
-- Name: FUNCTION snws2_canon_request_data(req_date timestamp with time zone, host text, path text); Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON FUNCTION solaruser.snws2_canon_request_data(req_date timestamp with time zone, host text, path text) TO solar;


--
-- Name: FUNCTION snws2_find_verified_token_details(token_id text, req_date timestamp with time zone, host text, path text, signature text); Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON FUNCTION solaruser.snws2_find_verified_token_details(token_id text, req_date timestamp with time zone, host text, path text, signature text) TO solar;
GRANT ALL ON FUNCTION solaruser.snws2_find_verified_token_details(token_id text, req_date timestamp with time zone, host text, path text, signature text) TO solarauth;


--
-- Name: FUNCTION snws2_signature(signature_data text, sign_key bytea); Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON FUNCTION solaruser.snws2_signature(signature_data text, sign_key bytea) TO solar;


--
-- Name: FUNCTION snws2_signature_data(req_date timestamp with time zone, canon_request_data text); Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON FUNCTION solaruser.snws2_signature_data(req_date timestamp with time zone, canon_request_data text) TO solar;


--
-- Name: FUNCTION snws2_signing_key(sign_date date, secret text); Type: ACL; Schema: solaruser; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaruser.snws2_signing_key(sign_date date, secret text) FROM PUBLIC;
GRANT ALL ON FUNCTION solaruser.snws2_signing_key(sign_date date, secret text) TO solar;


--
-- Name: FUNCTION snws2_signing_key_hex(sign_date date, secret text); Type: ACL; Schema: solaruser; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaruser.snws2_signing_key_hex(sign_date date, secret text) FROM PUBLIC;
GRANT ALL ON FUNCTION solaruser.snws2_signing_key_hex(sign_date date, secret text) TO solar;


--
-- Name: FUNCTION snws2_validated_request_date(req_date timestamp with time zone, tolerance interval); Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON FUNCTION solaruser.snws2_validated_request_date(req_date timestamp with time zone, tolerance interval) TO solar;


--
-- Name: FUNCTION store_adhoc_export_task(usr bigint, sched character, ex_date timestamp with time zone, cfg text); Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON FUNCTION solaruser.store_adhoc_export_task(usr bigint, sched character, ex_date timestamp with time zone, cfg text) TO solar;


--
-- Name: FUNCTION store_export_task(usr bigint, sched character, ex_date timestamp with time zone, cfg_id bigint, cfg text); Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON FUNCTION solaruser.store_export_task(usr bigint, sched character, ex_date timestamp with time zone, cfg_id bigint, cfg text) TO solar;


--
-- Name: FUNCTION store_user_data(user_id bigint, json_obj jsonb); Type: ACL; Schema: solaruser; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaruser.store_user_data(user_id bigint, json_obj jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION solaruser.store_user_data(user_id bigint, json_obj jsonb) TO solarinput;


--
-- Name: FUNCTION store_user_meta(cdate timestamp with time zone, userid bigint, jdata text); Type: ACL; Schema: solaruser; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaruser.store_user_meta(cdate timestamp with time zone, userid bigint, jdata text) FROM PUBLIC;
GRANT ALL ON FUNCTION solaruser.store_user_meta(cdate timestamp with time zone, userid bigint, jdata text) TO solarinput;


--
-- Name: FUNCTION store_user_node_cert(created timestamp with time zone, node bigint, userid bigint, stat character, request text, keydata bytea); Type: ACL; Schema: solaruser; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaruser.store_user_node_cert(created timestamp with time zone, node bigint, userid bigint, stat character, request text, keydata bytea) FROM PUBLIC;
GRANT ALL ON FUNCTION solaruser.store_user_node_cert(created timestamp with time zone, node bigint, userid bigint, stat character, request text, keydata bytea) TO solar;


--
-- Name: FUNCTION store_user_node_xfer(node bigint, userid bigint, recip character varying); Type: ACL; Schema: solaruser; Owner: solarnet
--

REVOKE ALL ON FUNCTION solaruser.store_user_node_xfer(node bigint, userid bigint, recip character varying) FROM PUBLIC;
GRANT ALL ON FUNCTION solaruser.store_user_node_xfer(node bigint, userid bigint, recip character varying) TO solarinput;


--
-- Name: TABLE aud_loc_datum_hourly; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.aud_loc_datum_hourly TO solarinput;


--
-- Name: TABLE aud_datum_daily; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT SELECT ON TABLE solaragg.aud_datum_daily TO solar;
GRANT ALL ON TABLE solaragg.aud_datum_daily TO solarinput;


--
-- Name: TABLE aud_datum_monthly; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT SELECT ON TABLE solaragg.aud_datum_monthly TO solar;
GRANT ALL ON TABLE solaragg.aud_datum_monthly TO solarinput;


--
-- Name: TABLE aud_acc_datum_daily; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT SELECT ON TABLE solaragg.aud_acc_datum_daily TO solar;
GRANT ALL ON TABLE solaragg.aud_acc_datum_daily TO solarinput;


--
-- Name: TABLE aud_datum_hourly; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.aud_datum_hourly TO solarinput;


--
-- Name: TABLE plv8_modules; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT ON TABLE public.plv8_modules TO solar;


--
-- Name: TABLE blob_triggers; Type: ACL; Schema: quartz; Owner: solarnet
--

GRANT SELECT ON TABLE quartz.blob_triggers TO solar;
GRANT ALL ON TABLE quartz.blob_triggers TO solarinput;


--
-- Name: TABLE calendars; Type: ACL; Schema: quartz; Owner: solarnet
--

GRANT SELECT ON TABLE quartz.calendars TO solar;
GRANT ALL ON TABLE quartz.calendars TO solarinput;


--
-- Name: TABLE cron_triggers; Type: ACL; Schema: quartz; Owner: solarnet
--

GRANT SELECT ON TABLE quartz.cron_triggers TO solar;
GRANT ALL ON TABLE quartz.cron_triggers TO solarinput;


--
-- Name: TABLE triggers; Type: ACL; Schema: quartz; Owner: solarnet
--

GRANT SELECT ON TABLE quartz.triggers TO solar;
GRANT ALL ON TABLE quartz.triggers TO solarinput;


--
-- Name: TABLE fired_triggers; Type: ACL; Schema: quartz; Owner: solarnet
--

GRANT SELECT ON TABLE quartz.fired_triggers TO solar;
GRANT ALL ON TABLE quartz.fired_triggers TO solarinput;


--
-- Name: TABLE job_details; Type: ACL; Schema: quartz; Owner: solarnet
--

GRANT SELECT ON TABLE quartz.job_details TO solar;
GRANT ALL ON TABLE quartz.job_details TO solarinput;


--
-- Name: TABLE locks; Type: ACL; Schema: quartz; Owner: solarnet
--

GRANT SELECT ON TABLE quartz.locks TO solar;
GRANT ALL ON TABLE quartz.locks TO solarinput;


--
-- Name: TABLE paused_trigger_grps; Type: ACL; Schema: quartz; Owner: solarnet
--

GRANT SELECT ON TABLE quartz.paused_trigger_grps TO solar;
GRANT ALL ON TABLE quartz.paused_trigger_grps TO solarinput;


--
-- Name: TABLE scheduler_state; Type: ACL; Schema: quartz; Owner: solarnet
--

GRANT SELECT ON TABLE quartz.scheduler_state TO solar;
GRANT ALL ON TABLE quartz.scheduler_state TO solarinput;


--
-- Name: TABLE simple_triggers; Type: ACL; Schema: quartz; Owner: solarnet
--

GRANT SELECT ON TABLE quartz.simple_triggers TO solar;
GRANT ALL ON TABLE quartz.simple_triggers TO solarinput;


--
-- Name: TABLE agg_loc_datum_daily_data; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.agg_loc_datum_daily_data TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_loc_datum_daily_data TO solar;


--
-- Name: TABLE agg_loc_datum_hourly_data; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.agg_loc_datum_hourly_data TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_loc_datum_hourly_data TO solar;


--
-- Name: TABLE agg_loc_datum_monthly_data; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.agg_loc_datum_monthly_data TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_loc_datum_monthly_data TO solar;


--
-- Name: TABLE agg_loc_messages; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT SELECT ON TABLE solaragg.agg_loc_messages TO solar;
GRANT ALL ON TABLE solaragg.agg_loc_messages TO solarinput;


--
-- Name: TABLE agg_messages; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.agg_messages TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_messages TO solar;


--
-- Name: TABLE agg_stale_datum; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT ALL ON TABLE solaragg.agg_stale_datum TO solarinput;
GRANT SELECT ON TABLE solaragg.agg_stale_datum TO solar;


--
-- Name: TABLE agg_stale_loc_datum; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT SELECT ON TABLE solaragg.agg_stale_loc_datum TO solar;
GRANT ALL ON TABLE solaragg.agg_stale_loc_datum TO solarinput;


--
-- Name: TABLE aud_datum_daily_stale; Type: ACL; Schema: solaragg; Owner: solarnet
--

GRANT SELECT ON TABLE solaragg.aud_datum_daily_stale TO solar;
GRANT ALL ON TABLE solaragg.aud_datum_daily_stale TO solarinput;


--
-- Name: TABLE da_datum_range; Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT SELECT ON TABLE solardatum.da_datum_range TO solar;
GRANT ALL ON TABLE solardatum.da_datum_range TO solarinput;


--
-- Name: TABLE da_loc_meta; Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT SELECT ON TABLE solardatum.da_loc_meta TO solar;
GRANT ALL ON TABLE solardatum.da_loc_meta TO solarinput;


--
-- Name: TABLE da_meta; Type: ACL; Schema: solardatum; Owner: solarnet
--

GRANT SELECT ON TABLE solardatum.da_meta TO solar;
GRANT ALL ON TABLE solardatum.da_meta TO solarinput;


--
-- Name: SEQUENCE instruction_seq; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT,USAGE ON SEQUENCE solarnet.instruction_seq TO solar;
GRANT ALL ON SEQUENCE solarnet.instruction_seq TO solarinput;


--
-- Name: TABLE node_local_time; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT ON TABLE solarnet.node_local_time TO solar;


--
-- Name: TABLE sn_hardware; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT ON TABLE solarnet.sn_hardware TO solar;
GRANT ALL ON TABLE solarnet.sn_hardware TO solarinput;


--
-- Name: TABLE sn_hardware_control; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT ON TABLE solarnet.sn_hardware_control TO solar;
GRANT ALL ON TABLE solarnet.sn_hardware_control TO solarinput;


--
-- Name: TABLE sn_node_instruction; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT ON TABLE solarnet.sn_node_instruction TO solar;
GRANT ALL ON TABLE solarnet.sn_node_instruction TO solarinput;


--
-- Name: TABLE sn_node_instruction_param; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT ON TABLE solarnet.sn_node_instruction_param TO solar;
GRANT ALL ON TABLE solarnet.sn_node_instruction_param TO solarinput;


--
-- Name: TABLE sn_node_meta; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT ON TABLE solarnet.sn_node_meta TO solar;
GRANT ALL ON TABLE solarnet.sn_node_meta TO solarinput;


--
-- Name: TABLE sn_price_loc; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT ON TABLE solarnet.sn_price_loc TO solar;
GRANT ALL ON TABLE solarnet.sn_price_loc TO solarinput;


--
-- Name: TABLE sn_price_source; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT ON TABLE solarnet.sn_price_source TO solar;
GRANT ALL ON TABLE solarnet.sn_price_source TO solarinput;


--
-- Name: TABLE sn_weather_loc; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT ON TABLE solarnet.sn_weather_loc TO solar;
GRANT ALL ON TABLE solarnet.sn_weather_loc TO solarinput;


--
-- Name: TABLE sn_weather_source; Type: ACL; Schema: solarnet; Owner: solarnet
--

GRANT SELECT ON TABLE solarnet.sn_weather_source TO solar;
GRANT ALL ON TABLE solarnet.sn_weather_source TO solarinput;


--
-- Name: SEQUENCE solaruser_seq; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT,USAGE ON SEQUENCE solaruser.solaruser_seq TO solar;
GRANT ALL ON SEQUENCE solaruser.solaruser_seq TO solarinput;


--
-- Name: TABLE user_node; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_node TO solar;
GRANT ALL ON TABLE solaruser.user_node TO solarinput;


--
-- Name: COLUMN user_node.node_id; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT(node_id) ON TABLE solaruser.user_node TO solarauth;


--
-- Name: COLUMN user_node.user_id; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT(user_id) ON TABLE solaruser.user_node TO solarauth;


--
-- Name: COLUMN user_node.archived; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT(archived) ON TABLE solaruser.user_node TO solarauth;


--
-- Name: TABLE user_user; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_user TO solar;
GRANT ALL ON TABLE solaruser.user_user TO solarinput;


--
-- Name: TABLE user_node_conf; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_node_conf TO solar;
GRANT ALL ON TABLE solaruser.user_node_conf TO solarinput;


--
-- Name: TABLE network_association; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.network_association TO solar;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,UPDATE ON TABLE solaruser.network_association TO solarinput;


--
-- Name: TABLE user_adhoc_export_task; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_adhoc_export_task TO solar;
GRANT ALL ON TABLE solaruser.user_adhoc_export_task TO solarinput;


--
-- Name: SEQUENCE user_alert_seq; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT,USAGE ON SEQUENCE solaruser.user_alert_seq TO solar;
GRANT ALL ON SEQUENCE solaruser.user_alert_seq TO solarinput;


--
-- Name: TABLE user_alert; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_alert TO solar;
GRANT ALL ON TABLE solaruser.user_alert TO solarinput;


--
-- Name: TABLE user_alert_info; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_alert_info TO solar;


--
-- Name: TABLE user_alert_sit; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_alert_sit TO solar;
GRANT ALL ON TABLE solaruser.user_alert_sit TO solarinput;


--
-- Name: TABLE user_auth_token; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_auth_token TO solar;
GRANT ALL ON TABLE solaruser.user_auth_token TO solarinput;


--
-- Name: COLUMN user_auth_token.auth_token; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT(auth_token) ON TABLE solaruser.user_auth_token TO solarauth;


--
-- Name: COLUMN user_auth_token.user_id; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT(user_id) ON TABLE solaruser.user_auth_token TO solarauth;


--
-- Name: COLUMN user_auth_token.status; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT(status) ON TABLE solaruser.user_auth_token TO solarauth;


--
-- Name: COLUMN user_auth_token.token_type; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT(token_type) ON TABLE solaruser.user_auth_token TO solarauth;


--
-- Name: COLUMN user_auth_token.jpolicy; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT(jpolicy) ON TABLE solaruser.user_auth_token TO solarauth;


--
-- Name: TABLE user_auth_token_login; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_auth_token_login TO solar;
GRANT ALL ON TABLE solaruser.user_auth_token_login TO solarinput;


--
-- Name: TABLE user_auth_token_node_ids; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_auth_token_node_ids TO solar;
GRANT ALL ON TABLE solaruser.user_auth_token_node_ids TO solarinput;
GRANT SELECT ON TABLE solaruser.user_auth_token_node_ids TO solarauth;


--
-- Name: TABLE user_auth_token_nodes; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_auth_token_nodes TO solar;


--
-- Name: TABLE user_role; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_role TO solar;
GRANT ALL ON TABLE solaruser.user_role TO solarinput;


--
-- Name: TABLE user_auth_token_role; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_auth_token_role TO solar;
GRANT ALL ON TABLE solaruser.user_auth_token_role TO solarinput;


--
-- Name: TABLE user_auth_token_sources; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_auth_token_sources TO solar;


--
-- Name: SEQUENCE user_expire_seq; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT,USAGE ON SEQUENCE solaruser.user_expire_seq TO solar;
GRANT ALL ON SEQUENCE solaruser.user_expire_seq TO solarinput;


--
-- Name: TABLE user_expire_data_conf; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT ALL ON TABLE solaruser.user_expire_data_conf TO solar;


--
-- Name: SEQUENCE user_export_seq; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT,USAGE ON SEQUENCE solaruser.user_export_seq TO solar;
GRANT ALL ON SEQUENCE solaruser.user_export_seq TO solarinput;


--
-- Name: TABLE user_export_data_conf; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_export_data_conf TO solar;
GRANT ALL ON TABLE solaruser.user_export_data_conf TO solarinput;


--
-- Name: TABLE user_export_datum_conf; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_export_datum_conf TO solar;
GRANT ALL ON TABLE solaruser.user_export_datum_conf TO solarinput;


--
-- Name: TABLE user_export_dest_conf; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_export_dest_conf TO solar;
GRANT ALL ON TABLE solaruser.user_export_dest_conf TO solarinput;


--
-- Name: TABLE user_export_outp_conf; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_export_outp_conf TO solar;
GRANT ALL ON TABLE solaruser.user_export_outp_conf TO solarinput;


--
-- Name: TABLE user_export_task; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_export_task TO solar;
GRANT ALL ON TABLE solaruser.user_export_task TO solarinput;


--
-- Name: TABLE user_login; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_login TO solar;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,UPDATE ON TABLE solaruser.user_login TO solarinput;


--
-- Name: TABLE user_login_role; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_login_role TO solar;
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,UPDATE ON TABLE solaruser.user_login_role TO solarinput;


--
-- Name: TABLE user_meta; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_meta TO solar;
GRANT ALL ON TABLE solaruser.user_meta TO solarinput;


--
-- Name: TABLE user_node_cert; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_node_cert TO solar;
GRANT ALL ON TABLE solaruser.user_node_cert TO solarinput;


--
-- Name: TABLE user_node_hardware_control; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_node_hardware_control TO solar;
GRANT ALL ON TABLE solaruser.user_node_hardware_control TO solarinput;


--
-- Name: TABLE user_node_xfer; Type: ACL; Schema: solaruser; Owner: solarnet
--

GRANT SELECT ON TABLE solaruser.user_node_xfer TO solar;
GRANT ALL ON TABLE solaruser.user_node_xfer TO solarinput;


--
-- PostgreSQL database dump complete
--

