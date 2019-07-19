# SolarIn: SolarNetwork data ingestion

# SSL Setup

The SolarIn application requires X.509 client certificates for SolarNodes, which are provisioned
via the SolarUser application. The `configuration/tomcat-server.xml` file contains the SSL setup.
It expects a `configuration/central.jks` keystore that
contains a `web` private key and associated signed certificate and a `ca` CA public certificate. 

In addition, it expects a `configuration/central-trust.jks` keystore that includes the `ca` CA public
certificate.

Both keystores are expected to have a password of `dev123`. This is the password used by the 
SolarNetwork Developer CA, which the reference *solaruser* application deploys. Thus by starting
up the solaruser reference application, it will create the `central.jks` and `central-trust.jks` 
files and you can simply copy them into the `configuration` directory here.
