# SolarFlux MQTT configuration

SolarFlux uses VerneMQ for the MQTT broker, with the `solarflux-vernemq-webhook` application
deployed on the same machine(s) to handle authorization and auditing tasks.

## systemd service

The `fluxhook.service` unit manages the solarflux-vernemq-webhook application, which relies on
Java 21. A Java 21 JRE is installed in `/opt/java-21` for this purpose.

> :warning: The `solarflux-vernemq-webhook.service` unit is an older version of the service,
> superseded by `fluxhook.service`.
 
