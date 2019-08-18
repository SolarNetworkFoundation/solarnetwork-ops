# SolarNetwork Foundation Virgo Deployment Support

This directory contains scripts and configuration support for deploying Virgo based application
servers for the SolarNet could services.

## App setup script

The `bin/setup-virgo.sh` script helps to download Virgo and setup up a Virgo-based SolarNet
application. You can copy or link to the reference application configurations in `example/apphome`
to get started.

## Example

```sh
# Setup a SolarJobs application server in /home/solarnet/solarjobs
$ cp -a example/apphome/solarjobs .
$ ./bin/setup-virgo.sh -rv -h /home/solarnet -a solarjobs -i example/ivy-solarjobs.xml
```

## Database connection

The main Postgres database connection settings are defined in the
`configuration/services/net.solarnetwork.jdbc.pool.hikari-central.cfg` file of each reference
application. They are configured to connect to a `solar-database` host on port `5432`. Thus the host
OS must be able to resolve that name to the IP address of the actual server. For development where
you run the database on the same machine, you can add an entry in `/etc/hosts` that maps that name.
For example:

```
127.0.0.1       solar-database localhost
```

## Docker image

The reference applications each contain a `Dockerfile` to support building a Docker image.
For example, to build a SolarUser Docker image:

```sh
$ ./bin/setup-virgo.sh -rv -h /var/tmp -a solaruser -i example/ivy-solaruser.xml
$ docker build -t solaruser /var/tmp/solaruser
```

To run the application, pass in the IP address of the database via a `--add-host` argument. For 
example, if your host computer has the IP address `192.168.1.44`:

```sh
$ docker run -it --publish 9081:9081 --name solaruser --add-host solar-database:192.168.1.44 solaruser

Starting Virgo HTTP on port 9081, debug port 9981.
<KE0001I> Kernel starting. 
...
<WE0000I> Starting web bundle 'net.solarnetwork.central.user.web' version '1.40.0' with context path '/solaruser'.
<DE0005I> Started plan 'net.solarnetwork.solaruser.plan' version '1.0.0'.
```

From there, the SolarUser application will be available at http://localhost:9081/solaruser/. The other
applications can be built/run similarly, for example all the applications could be started like:

```sh
$ docker run --publish 9080:9080 --name solarjobs --add-host solar-database:192.168.1.44 solarjobs
$ docker run --publish 9081:9081 --name solaruser --add-host solar-database:192.168.1.44 solaruser
$ docker run --publish 9082:9082 --name solarquery --add-host solar-database:192.168.1.44 solarquery
$ docker run --publish 9083:9083 --name solarin --add-host solar-database:192.168.1.44 solarin
```

## Virgo repository configuration

The setup script creates two repositories for the application:

| Repository | Description |
|------------|-------------|
| `etc`      | For configuration files. |
| `usr`      | For application bundles. |

## Application boot sequence

Virgo is configured to load a Virgo plan named `net.solarnetwork.{appname}.env` when started. The 
reference applications in `example/apphome` all place this in the `etc` repository, for example 
`solarin/repository/etc/net.solarnetwork.solarin.env-1.0.plan`. This plan should load all the 
necessary Configuration Admin properties files, for example database credentials.

The reference applications in `example/apphome` then deploy a plan into the `pickup` directory that
encompasses the entire application, so Virgo deploys this _after_ the environment settings are all
loaded. For example, the `solarin/pickup/net.solarnetwork.solarin-1.0.plan` plan defines the SolarIn
application.

## Dynamic configuration factories

The Felix FileInstall plugin is configured and will look for configuration factories in the 
`configuration/services` directory within the application. For example, you might need to include
a `net.solarnetwork.central.in.mqtt.MqttDataCollector-solarinstr.cfg` configuration to instantiate
a MQTT client to push instructions to nodes.
