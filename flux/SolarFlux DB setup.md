# SolarFlux DB Setup

## Limited authentication role

Created a new `solarauth` DB role with limited privileges. See the `NET-169-production.sql` script.

## Certificate authentication setup

### Server

Created a server certificate signed by the SN CA  (note the `dev` references are for development,
the production server omits those):

```
$ openssl req -out db.solarnetworkdev.net.csr -new -sha256 -newkey rsa:2048 -nodes -keyout db.solarnetworkdev.net.key \
	-subj '/O=SolarNetworkDev/OU=DB/CN=db.solarnetworkdev.net'
$ chmod 600 db.solarnetworkdev.net.key
```

Submitted the CSR to the CA, using the _Other Certificate Enrollment_ profile, and then approved the request.

### Client

Created a client certificate for SolarFlux authentication (note the `dev` references are for development,
the production server omits those):

```
$ openssl req -out matt-auth-dev.csr -new -sha256 -newkey rsa:2048 -nodes -keyout matt-auth-dev.key \
	-subj '/O=SolarNetworkDev/OU=DB/emailAddress=matt@solarnetwork.net/CN=auth'
$ chmod 600 matt-auth-dev.key

# Also create DER encoded key, required by Java
$ openssl pkcs8 -topk8 -inform PEM -in matt-auth-dev.key -outform DER -nocrypt -out matt-auth-dev.key.der
$ chmod 600 matt-auth-dev.key.der
```

Submitted the CSR to the CA, using the _Other Certificate Enrollment_ profile, and then approved the request. **Note** that
the _Extended Key Usage_ attribute must include `1.3.6.1.5.5.7.3.2` for client-side authentication.


Updated `pg_ident.conf` to map the `CN=auth` in the client certificate to the `solarauth` role:

```
# MAPNAME       SYSTEM-USERNAME         PG-USERNAME
cert    auth    solarauth
```
