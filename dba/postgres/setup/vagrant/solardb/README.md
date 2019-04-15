# SolarDB Virtual Machine - Postgres

# Custom setup arguments

To pass customized arguments to the `bin/setup-solardb-freebsd.sh` script, add them as a `setup_args`
variable in a `Vagrantfile.local` file. For example:

```ruby
setup_args="-B local/pg-conf.awk"
```

The `local` directory will be ignored by git, so you can place any local setup files in there.

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