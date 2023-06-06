# SolarNetwork Postgres Deployment

SolarNetwork relies on a Postgres database. The main production deployment is modified
from a standard developer deployment to make use of Timescale "hypertables" for several
of the main time-series tables. Additionally the authentication and authorization is more
restrictive.

# Postgres TLS certificate authentication

Postgres is configured to use X.509 client certificates for authentication. The certificates
are issued by the SolarNetwork Foundation CA.

## Creating certificates

First create a CSR. The `CN` attribute must match a username configured on the server.
In the following example, a `foobar` user is assumed:

```
openssl req -out matt-sysadmin.csr -new -sha256 -newkey rsa:2048 -nodes -keyout matt-foobar.key \
	-subj '/O=SolarNetwork/OU=DB/emailAddress=matt@solarnetwork.net/CN=foobar'
```

This will generate a `matt-foobar.key` private key and a CSR `matt-foobar.csr`. Submit that CSR to
the SNF CA. Note this certificate must support client authentication, which is the extended key
usage ID `1.3.6.1.5.5.7.3.2`. Approve the CSR, and save the resulting certificate as
`matt-foobar.crt`.

## Server certificate authentication

On the Postgres server, certificate authentication is allowed via an identity map named `cert`.
The `pg_ident.conf` file must contain a proper mapping for the `CN` certificate username to
a database user. For example, the following line would map the `foobar` certificate user
 to the `solarauth` database user:
 
 ```
 cert foobar solarauth
 ```
