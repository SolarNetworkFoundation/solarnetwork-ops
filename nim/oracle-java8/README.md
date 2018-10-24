# SolarNode Oracle Java NIM Configuration

This directory contains the configuration source files for creating a SolarNode OS image
that updates to using the latest Oracle Java 8 JDK available from the Ubuntu webupd8team
PPA. Note this assumes the OS is Debian Stretch (9) based.

# NIM

The NIM image should be created by uploading these `dataFile` resources:

 * `oracle-java8.fish`
 * `pi-update-java8.firstboot`
