# SolarDB Virtual Machine - Postgres

# SSL configuration

Copy your certificate, private key, and optional CA certificate to a `tls` directory in this
directory. The setup script will copy this directory into the Postgres configuration directory. Then
use the `-E <cert> -e <key> -F <ca>` arguments to configure Postgres to use these files. By default,
the script looks for `tls/server.crt`, `tls/server.key`, and `tls/ca.crt`. For example:

```
tls
├── ca.crt
├── server.crt
└── server.key
```