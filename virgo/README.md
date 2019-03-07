# SolarNetwork Foundation Virgo Deployment Support

This directory contains scripts and configuration support for deploying Virgo
based application servers for the SolarNet could services.

# App setup script

The `bin/setup-virgo.sh` script helps to download Virgo and setup up a Virgo-based SolarNet application.

## Example

```sh
# Setup a SolarJobs application server in /home/solarnet/solarjobs
./bin/setup-virgo.sh -rv -h /home/solarnet -a solarjobs -i example/ivy-solarjobs.xml
```
