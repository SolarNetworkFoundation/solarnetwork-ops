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
