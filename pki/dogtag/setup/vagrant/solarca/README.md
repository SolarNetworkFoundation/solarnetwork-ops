# SolarCA Virtual Machine - Dogtag PKI

This is a [Vagrant][vagrant] configuration for a virtual machine configured with the Dogtag PKI
Certification Authority (CA) system, suitable for use by SolarNetwork as its CA system for issuing
SolarNode certificates. The VM is configured as a full desktop system to facilitate ease of
administration via VNC.

![SolarCA Desktop](docs/solarca-vnc-demo.png)

# Quick Start

First, take a peek at the section on [tweaking the VM RAM/CPU settings](#tweaking-vm-ramcpu-settings).
Then to create a Dogtag instance with default (development focused) settings, run:

```sh
vagrant up
```

Then run out and grab a ☕️ or 🍩 (or both). Take your time, because it will take several minutes for
the VM to download/configure everything necessary. Once everything is ready, an installation report
will be printed to the screen that details everything you need to know about what was done.

# Tweaking VM RAM/CPU settings

The basic VM config allocates 1GB of RAM and 1 CPU. If you can afford the resources, you might allocate
a bit more by creating a `Vagrantfile.local` file with the following:

```
cpu_count=2
memory_size=2048
```

# Debugging Dogtag Server

You can create  a `/etc/tomcat/conf.d/debug.conf` file with JVM parameters to pass to the Tomcat
server, like

```
JAVA_OPTS="-Djavax.net.debug=ssl:handshake:verbose -Xdebug -Xnoagent -Xrunjdwp:server=y,transport=dt_socket,address=9000,suspend=n"
```

# Migrating existing server example

In `Vagrantfile.local` configure the `setup_args` value with all the necessary arguments. Copy any files referred to by the configuration
into the `local` directory, for example, if `ca-migrate.cfg` contains:

```
pki_pkcs12_path=/vagrant/local/existing-root-ca.p12
pki_pkcs12_password=Secret.123

pki_ca_signing_nickname=caSigningCert cert-rootca CA
pki_ca_signing_csr_path=/vagrant/local/existing-root-ca-signing.csr
```

 * `local/ca-migrate.cfg` - the CA configuration
 * `local/existing-data-migration.ldif` - the LDIF data to import, i.e. certificate requests, certificates, etc.
 * `local/existing-root-ca.p12` - the CA root key/certificate to import
 * `local/existing-root-ca-signing.csr` - the CA root CSR to import

Then the following arguments would be configured:

```
setup_args="-u -c local/ca-migrate.cfg -E Secret.1234 -h ca.solarnetwork.net -I Secret.1235 -i in.solarnetwork.net -K suagent@solarnetwork.net -k Secret.1236 -L Secret.1237 -l Secret.1238 -s dc=solarnetwork,dc=net -t local/existing-data-migration.ldif"
```

[vagrant]: https://www.vagrantup.com/
