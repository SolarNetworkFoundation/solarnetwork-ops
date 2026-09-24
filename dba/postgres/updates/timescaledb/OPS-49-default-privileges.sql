/* Move the solarnet and solaruser schema default privileges from the old postgres_ role to
 * solarnet.
 *
 * Every other schema already registers its defaults for solarnet, because they were created
 * by migrations, which run as solarnet. These two schemas predate that: their defaults were
 * registered by the superuser of the day, since renamed to postgres_. A pg_default_acl entry
 * belongs to the role that created it and cannot be reassigned, so the old entries are
 * revoked and equivalent ones created for solarnet.
 *
 * Until this runs, anything created in these two schemas by a migration inherits no ACLs at
 * all -- tables end up with no group access, and functions keep only the built-in PUBLIC
 * EXECUTE default that revoke_all_public() later strips.
 *
 * NOTE this script must be run by a SUPERUSER: only a superuser, or a member of postgres_,
 * may revoke that role's default privileges. Running it as solarnet fails with
 * "permission denied to change default privileges".
 *
 * Existing objects are not affected; this only changes what newly created objects inherit.
 *
 * The REVOKE ... FROM PUBLIC statements below mirror tsdb-init-core-schema.sql and
 * tsdb-init-user-schema.sql, but note they do not actually keep PUBLIC off newly created
 * functions and types: Postgres merges the built-in default (which grants EXECUTE on
 * functions to PUBLIC) back in at creation time, whatever the pg_default_acl entry says.
 * Stripping PUBLIC is done by the revoke_all_public() sweep in tsdb-init-permissions.sql,
 * which is why functions created since the last sweep still show a PUBLIC grant.
 *
 * Do NOT add FOR ROLE to the setup scripts to match this. Those run as the admin user, so
 * pinning them to the owner role leaves every object created during a fresh install with no
 * group access at all -- set_ownership() re-owns objects but does not re-apply defaults.
 */

-- remove the old role's entries: revoking the named grants empties each entry, which drops it
ALTER DEFAULT PRIVILEGES FOR ROLE postgres_ IN SCHEMA solarnet REVOKE ALL ON TABLES FROM solar, solarjobs, solaruser;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres_ IN SCHEMA solarnet REVOKE ALL ON SEQUENCES FROM solar, solarjobs, solaruser;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres_ IN SCHEMA solarnet REVOKE ALL ON FUNCTIONS FROM solar, solarjobs, solaruser;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres_ IN SCHEMA solarnet REVOKE ALL ON TYPES FROM solar, solarjobs, solaruser;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres_ IN SCHEMA solaruser REVOKE ALL ON TABLES FROM solarjobs, solaruser;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres_ IN SCHEMA solaruser REVOKE ALL ON SEQUENCES FROM solarjobs, solaruser;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres_ IN SCHEMA solaruser REVOKE ALL ON FUNCTIONS FROM solarjobs, solaruser;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres_ IN SCHEMA solaruser REVOKE ALL ON TYPES FROM solarjobs, solaruser;

-- recreate them for solarnet: same grants as tsdb-init-core-schema.sql
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet REVOKE ALL ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet REVOKE ALL ON TYPES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet GRANT SELECT ON TABLES TO solar;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet GRANT USAGE,SELECT ON SEQUENCES TO solar;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet GRANT EXECUTE ON FUNCTIONS TO solar;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet GRANT USAGE ON TYPES TO solar;

ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet GRANT ALL ON TABLES TO solarjobs;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet GRANT ALL ON SEQUENCES TO solarjobs;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet GRANT ALL ON FUNCTIONS TO solarjobs;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet GRANT ALL ON TYPES TO solarjobs;

ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet GRANT ALL ON TABLES TO solaruser;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet GRANT ALL ON SEQUENCES TO solaruser;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet GRANT ALL ON FUNCTIONS TO solaruser;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solarnet GRANT ALL ON TYPES TO solaruser;

-- and for solaruser: same grants as tsdb-init-user-schema.sql
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solaruser REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solaruser REVOKE ALL ON SEQUENCES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solaruser REVOKE ALL ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solaruser REVOKE ALL ON TYPES FROM PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solaruser GRANT ALL ON TABLES TO solaruser;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solaruser GRANT ALL ON SEQUENCES TO solaruser;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solaruser GRANT ALL ON FUNCTIONS TO solaruser;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solaruser GRANT ALL ON TYPES TO solaruser;

ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solaruser GRANT SELECT ON TABLES TO solarjobs;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solaruser GRANT SELECT ON SEQUENCES TO solarjobs;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solaruser GRANT EXECUTE ON FUNCTIONS TO solarjobs;
ALTER DEFAULT PRIVILEGES FOR ROLE solarnet IN SCHEMA solaruser GRANT USAGE ON TYPES TO solarjobs;

-- audit: this should return no rows
SELECT defaclrole::regrole AS role, defaclnamespace::regnamespace AS schema,
	defaclobjtype AS objtype, defaclacl AS acl
FROM pg_default_acl
WHERE defaclrole <> 'solarnet'::regrole
ORDER BY 2, 3;
