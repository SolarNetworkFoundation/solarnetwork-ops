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

# ZFS configuration

The machine creates 3 extra drives that get initialised as ZFS pools:

 1. `snjournal` - for the Postgres WAL
 2. `sndata` - for the actual data
 3. `snindex` - for indexes
 
The location/size of these drives are controlled by the following properties, which you
can override in `Vagrantfile.local`:

| Property          | Default             | Description |
|-------------------|---------------------|-------------|
| `disk_journal`    | `disk/journal.vmdk` | Path to the `snjournal` drive. |
| `disk_journal_mb` | `512`               | Size, in MB, for the `snjournal` drive. |
| `disk_data`       | `disk/data.vmdk`    | Path to the `sndata` drive. |
| `disk_data_mb`    | `4096`              | Size, in MB, for the `sndata` drive. |
| `disk_index`      | `disk/index.vmdk`   | Path to the `snindex` drive. |
| `disk_index_mb`   | `4096`              | Size, in MB, for the `snindex` drive. |
