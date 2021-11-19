# SolarNetwork Foundation Virgo Deployment Support

This directory contains scripts and configuration support for deploying Virgo based application
servers for the SolarNet could services.


# App setup script

The `bin/setup-virgo.sh` script helps to download Virgo and setup up a Virgo-based SolarNet
application. You can copy or link to the reference application configurations in `example/apphome`
to get started.

## Example

```sh
# Setup a SolarJobs application server in /home/solarnet/solarjobs
$ cp -a example/apphome/solarjobs apphome
$ ./bin/setup-virgo.sh -rv -h /home/solarnet -a solarjobs -i example/ivy-solarjobs.xml
```

## Local environment overrides

You can use the `example/apphome` reference configurations as a staring point and provide
customisations via an environment directory tree rooted in a `local/<env>/<app>` directory. Files
found there will be copied _after_ the base application configuration tree. Pass `-e <env>` to the
setup script with the name of your environment. For example, `-a solarjobs -e dev` would copy the
contents of a `local/dev/solarjobs` directory after copying `apphome/solarjobs`.


# Database connection

The main Postgres database connection settings are defined in the
`configuration/services/net.solarnetwork.jdbc.pool.hikari-central.cfg` file of each reference
application. They are configured to connect to a `solar-database` host on port `5432`. Thus the host
OS must be able to resolve that name to the IP address of the actual server. For development where
you run the database on the same machine, you can add an entry in `/etc/hosts` that maps that name.
For example:

```
127.0.0.1       solar-database localhost
```


# Docker image

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


# Virgo repository configuration

The setup script creates two repositories for the application:

| Repository | Description |
|------------|-------------|
| `etc`      | For configuration files. |
| `usr`      | For application bundles. |


# Application boot sequence

Virgo is configured to load a Virgo plan named `net.solarnetwork.{appname}.env` when started. The 
reference applications in `example/apphome` all place this in the `etc` repository, for example 
`solarin/repository/etc/net.solarnetwork.solarin.env-1.0.plan`. This plan should load all the 
necessary Configuration Admin properties files, for example database credentials.

The reference applications in `example/apphome` then deploy a plan into the `pickup` directory that
encompasses the entire application, so Virgo deploys this _after_ the environment settings are all
loaded. For example, the `solarin/pickup/net.solarnetwork.solarin-1.0.plan` plan defines the SolarIn
application.


# Dynamic configuration factories

The Felix FileInstall plugin is configured and will look for configuration factories in the 
`configuration/services` directory within the application. For example, you might need to include
a `net.solarnetwork.central.in.mqtt.MqttDataCollector-solarinstr.cfg` configuration to instantiate
a MQTT client to push instructions to nodes.


# ECS production build

Building to ECS for production involves:

 1. Running the `setup-virgo.sh` script to assemble the application.
 2. Building a Docker image out of the assembled application.
 3. Tagging the Docker image.
 4. Pushing the Docker image to ECR.
 5. Deploying the Docker image to ECS as a service.
 
Run the `setup-virgo.sh` script for the production environment tree. For example, for the SolarQuery
application:

```sh
./bin/setup-virgo.sh -rv -h /tmp/virgo-aws -a solarquery -e prod-aws -i example/ivy-solarquery.xml

docker build -t solarquery-prod /tmp/virgo-aws/solarquery

docker tag solarquery-prod:latest 151824139716.dkr.ecr.us-west-2.amazonaws.com/sn-apps:solarquery-20200504A

aws --profile snf ecr get-login-password --region us-west-2 | \
    docker login --username AWS --password-stdin 151824139716.dkr.ecr.us-west-2.amazonaws.com

docker push 151824139716.dkr.ecr.us-west-2.amazonaws.com/sn-apps:solarquery-20200504A
```

# Shell helper functions

To help automate these deployment steps, I've been using the following `zsh` shell functions, which
have been added to `~/.zshrc` to make available. The paths would need to be adjusted to another
developer's workstation. Using these functions the process of deploying a new build goes like this,
using SolarUser as the example here:

```sh
# create a new build, then open ksdiff to show diff with previous build
sn-virgo-ecs-newbuild solaruser

# After manually inspecting the changes in ksdiff, and everthing is OK, create new Docker image
# using the current date + build letter suffix as the tag:
sn-virgo-ecs-dockerize solaruser 20210928_A

# Finally push the Docker image up to the container repository:
sn-virgo-ecs-push solaruser 20210928_A
```

The functions are as follows:

```sh
# Use a separate Ivy cache/repo dir for SN prod builds, to keep development publications out
SN_PROD_IVY_DIR="/Users/matt/var/ivy2-sn-prod"

##################################
# SolarNetwork ECS app build
##################################

# pass app name, e.g. `sn-virgo-ecs-build solarjobs`
function sn-virgo-ecs-build () {
	if [ -z "$1" ]; then
		echo "Pass app name to build, e.g. solarjobs"
	else
		cd ~/Documents/SNF/Sysadmin/solarnetwork-ops/virgo
		ANT_OPTS="-Divy.default.ivy.user.dir=${SN_PROD_IVY_DIR}" ./bin/setup-virgo.sh -rv \
			-h ~/var/virgo-aws \
			-i example/ivy-$1.xml \
			-I ../../solarnetwork-osgi-lib/ivysettings-local-first.xml \
			-e prod-aws \
			-a "$1"
		popd
		
		# show a visual diff of the changes; using ksdiff here provided by Kaleidoscope macOS app
		ksdiff ~/var/virgo-aws/$1.prev ~/var/virgo-aws/$1
	fi
}

# pass app name, e.g. `sn-virgo-ecs-newbuild solarjobs`
function sn-virgo-ecs-newbuild () {
	if [ -z "$1" ]; then
		echo "Pass app name to build, e.g. solarjobs"
	else
		rsync -av --delete ~/var/virgo-aws/$1/ ~/var/virgo-aws/$1.prev/
		sn-virgo-ecs-build "$@"
	fi
}

# pass app name and tag, e.g. `sn-virgo-ecs-dockerize solarjobs 20200525_A`
function sn-virgo-ecs-dockerize () {
	if [ -z "$1" -o -z "$2" ]; then
		echo "Pass app name and tag name to build, e.g. solarjobs 20200525_A"
	else
		docker build -t "$1-prod" ~/var/virgo-aws/$1 \
			&& docker tag "$1-prod:latest" "151824139716.dkr.ecr.us-west-2.amazonaws.com/sn-apps:$1-$2" \
			&& echo "Push app with: docker push 151824139716.dkr.ecr.us-west-2.amazonaws.com/sn-apps:$1-$2" \
			&& echo "Or with: sn-virgo-ecs-push $1 $2"
	fi
}

# pass app name and tag, e.g. `sn-virgo-ecs-push solarjobs 20200525_A`
function sn-virgo-ecs-push () {
	if [ -z "$1" -o -z "$2" ]; then
		echo "Pass app name and tag name to build, e.g. solarjobs 20200525_A"
	else
		aws --profile snf ecr get-login-password --region us-west-2 \
			|docker login --username AWS --password-stdin 151824139716.dkr.ecr.us-west-2.amazonaws.com
		docker push "151824139716.dkr.ecr.us-west-2.amazonaws.com/sn-apps:$1-$2"
	fi
}
```
