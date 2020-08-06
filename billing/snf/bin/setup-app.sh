#!/usr/bin/env sh

APP_NAME="solarapp"
CLEAN=""
ENV_NAME="dev"
APP_BUILD_HOME="example/apphome"
APP_BUILD_DIR="cli"
SRC_DIR="src"
APP_ARTIFACT_NAME="snf-accounting-cli"
APP_HOME=""
VERBOSE=""

do_help () {
	cat 1>&2 <<EOF
Usage: $0 -a <app name> -e <env name> -h <dest> -i <ivy conf> [-b <build home>] [-rtv]

If building from a reference template, overrides can be provided by placing files in a
local/<env name>/<app name> directory.

Arguments:

 -a <app name>       - the application to deploy; must be a directory in the apphome/ directory
 -b <app build home> - the path to the solarnetwork-build repository directory
 -b <app build dir>  - the path to the gradle build to execute
 -e <env name>       - the local build name; defaults to `dev`; allows creating different deployment
                       directory trees such as `stage` or `prod` with different configuration files
                       for different environments.
 -h <dest home>      - a directory to deploy the application to; a directory named <app name> will
                       be created here
 -r                  - clean and recreate the application from scratch; this deletes any existing
                       deployment directory <virgo home>/<app name> and then deploys a new copy
 -s                  - the application source dir; defaults to 'src'
 -v                  - verbose mode; print out more verbose messages
EOF
}

while getopts ":a:b:c:e:h:rs:v" opt; do
	case $opt in
		a) APP_NAME="${OPTARG}";;
		b) APP_BUILD_HOME="${OPTARG}";;
		c) APP_BUILD_DIR="${OPTARG}";;
		e) ENV_NAME="${OPTARG}";;
		h) APP_HOME="${OPTARG}";;
		r) CLEAN='TRUE';;
		s) SRC_DIR="${OPTARG}";;
		v) VERBOSE='TRUE';;
		*)
			echo "Unknown argument ${OPTARG}"
			do_help
			exit 1
	esac
done
shift $(($OPTIND - 1))

if [ -z "$APP_HOME" ]; then
	echo "App home not provided; pass the -h argument.";
	exit 1;
fi

SETUP_HOME=$(pwd)

if [ -n "$VERBOSE" ]; then
	echo "Deploying app to [$APP_BUILD_HOME/$APP_NAME]"
fi

#
# Clean
#
if [ -d "$APP_HOME/$APP_NAME" -a -n "$CLEAN" ]; then
	if [ -n "$VERBOSE" ]; then
		echo "Deleting existing app home [$APP_HOME/$APP_NAME]"
	fi
	rm -rf "$APP_HOME/$APP_NAME"
fi

#
# Sync apphome files
#
if [ -n "$VERBOSE" ]; then
	echo "Copying app build home [$APP_BUILD_HOME/$APP_NAME]"
fi
cp -pR "$APP_BUILD_HOME/$APP_NAME/" "$APP_HOME/$APP_NAME"
if [ -d "local/$ENV_NAME/$APP_NAME" ]; then
	if [ -n "$VERBOSE" ]; then
		echo "Copying app env [$ENV_NAME] build home [local/$ENV_NAME/$APP_NAME]"
	fi
	cp -pR "local/$ENV_NAME/$APP_NAME/" "$APP_HOME/$APP_NAME"
fi

#
# Build app
#
if [ -n "$VERBOSE" ]; then
	echo "Building app in [$SRC_DIR/$APP_BUILD_DIR]"
fi
"$SRC_DIR/gradlew" -b "$SRC_DIR/$APP_BUILD_DIR/build.gradle" clean build

#
# Copy built app
#
if [ -n "$VERBOSE" ]; then
	echo "Building app in [$SRC_DIR/$APP_BUILD_DIR]"
fi
cp -R "$SRC_DIR/$APP_BUILD_DIR/build/libs/$APP_ARTIFACT_NAME"* "$APP_HOME/$APP_NAME"

#
# Make sure executable
#
if [ -n "$VERBOSE" ]; then
	echo "Making binaries executable in [$APP_HOME/$APP_NAME/bin]"
fi
chmod 755 "$APP_HOME/$APP_NAME/bin"/*.sh

#
# Make symlink
#
cd "$APP_HOME/$APP_NAME"
artifact=`ls -1 ${APP_ARTIFACT_NAME}*`
if [ -n "$VERBOSE" ]; then
	echo "Making symlink from $artifact -> ${APP_ARTIFACT_NAME}.${artifact##*.}"
fi
ln -s $artifact "${APP_ARTIFACT_NAME}.${artifact##*.}"
