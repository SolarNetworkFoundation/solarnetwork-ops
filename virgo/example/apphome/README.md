# Example SolarNet application templates

The directories here are reference implementations of SolarNet application configurations for
deploying with Eclipse Virgo. Copy these directories into the `../..` directory, modify the files
as needed, and run the `bin/setup-virgo.sh` script to genrerate the application. Or link to these
directories and run the script to generate the reference implementations.

# App startup

Each reference application includes a `bin/sn-start.sh` script that defines different JMX and Java
debugger ports to listen on. Thus you can start the application like

```sh
$ ./bin/sn-start.sh

Starting Virgo HTTP on port 9081, debug port 9981.
Listening for transport dt_socket at address: 9981
[2019-04-04 16:19:42.146] startup-tracker              <KE0001I> Kernel starting. 
...
[2019-04-04 16:20:12.519] start-signalling-1           <DE0005I> Started plan 'net.solarnetwork.solaruser.plan' version '1.0.0'. 
```
