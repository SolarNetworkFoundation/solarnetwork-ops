/* No default privileges are needed in the solarcommon schema, to match production.
 *
 * Postgres already grants EXECUTE on functions and USAGE on types to PUBLIC by default, and
 * solarcommon is deliberately left out of the revoke_all_public() list in
 * tsdb-init-permissions.sql, so those grants survive. New solarcommon functions and types are
 * therefore usable by every role without any ACL DDL.
 *
 * This file previously restated those two built-in defaults with ALTER DEFAULT PRIVILEGES,
 * which had no effect: objects created with or without those entries come out identical.
 *
 * NOTE this does not extend to TABLES, which have no built-in PUBLIC default. A new
 * solarcommon table needs an explicit grant, as tsdb-init-permissions.sql does for
 * solarcommon.messages and tsdb-init-permissions-solarjobs.sql for solarcommon.app_setting.
 */
