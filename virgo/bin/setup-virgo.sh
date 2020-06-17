#!/usr/bin/env sh

virgoVersion="3.7.2.RELEASE"
virgoDownloadUrl="https://www.eclipse.org/downloads/download.php?file=/virgo/release/VP/${virgoVersion}/virgo-tomcat-server-${virgoVersion}.zip&r=1"
# 3.7.0 virgoDownloadSha="7d95293d55cc51d0febc3a3feeff211305614fa9f7fb41ac6a1129220fc0810692c6cd765bd16cbb712874aff77e08d3fd3dc6c7b0a150f433d82fd7b8f9b873"
virgoDownloadSha="f997cbdd9beed4fd953f5bf7a9cf3c5b3940a1d565f6722148ecdae5e21e84a7d414e7f0e1cd222172753956a3654f6959f74ccd216476de9f7beda6478c2ac6"

virgoDownloadPath="/var/tmp/virgo-tomcat-server-${virgoVersion}.zip"

APP_NAME="solarapp"
CLEAN=""
DRY_RUN=""
ENV_NAME="dev"
IVY_FILE="example/ivy.xml"
IVY_SETTINGS_FILE="../../solarnetwork-osgi-lib/ivysettings.xml"
SN_BUILD_HOME="solarnetwork-build"
VIRGO_HOME=""
VERBOSE=""

do_help () {
	cat 1>&2 <<EOF
Usage: $0 -a <app name> -e <env name> -h <dest> -i <ivy conf> [-b <build home>] [-rtv]

The following helper programs are used by this script:

 * ant    - to resolve the SolarNet application dependencies
 * curl   - to download Virgo
 * unzip  - to extract the Virgo archive

If building from a reference template, overrides can be provided by placing files in a
local/<env name>/<app name> directory.

Arguments:

 -a <app name>       - the application to deploy; must be a directory in the apphome/ directory
 -b <sn build home>  - the path to the solarnetwork-build repository directory
 -e <env name>       - the local build name; defaults to `dev`; allows creating different deployment
                       directory trees such as `stage` or `prod` with different configuration files
                       for different environments.
 -h <dest home>      - a directory to deploy the application to; a directory named <app name> will
                       be created here
 -i <ivy path>       - the Ivy build file that defines all the application's dependencies; this is
                       relative to the -b <sn build home> directory
 -I <ivy set. path>  - the Ivy settings file that defines all the application's dependencies; this
                       is relative to the -b <sn build home> directory
 -r                  - clean and recreate the application from scratch; this deletes any existing
                       deployment directory <virgo home>/<app name> and then deploys a new copy
 -t                  - test mode; do not deploy the application
 -v                  - verbose mode; print out more verbose messages
EOF
}

while getopts ":a:b:e:h:i:I:rtv" opt; do
	case $opt in
		a) APP_NAME="${OPTARG}";;
		b) SN_BUILD_HOME="${OPTARG}";;
		e) ENV_NAME="${OPTARG}";;
		h) VIRGO_HOME="${OPTARG}";;
		i) IVY_FILE="${OPTARG}";;
		I) IVY_SETTINGS_FILE="${OPTARG}";;
		r) CLEAN='TRUE';;
		t) DRY_RUN='TRUE';;
		v) VERBOSE='TRUE';;
		*)
			echo "Unknown argument ${OPTARG}"
			do_help
			exit 1
	esac
done
shift $(($OPTIND - 1))

if [ -z "$VIRGO_HOME" ]; then
	echo "Virgo home not provided; pass the -h argument.";
	exit 1;
fi

SETUP_HOME=$(pwd)

shaFileHash=

sha512File () {
	echo "Verifying file $1..."
	shaFileHash=`openssl dgst -hex -sha512 -r $1 |cut -d' ' -f1`
}

#
# Download/install Virgo
#
if [ -d "$VIRGO_HOME/$APP_NAME" -a -n "$CLEAN" ]; then
	if [ -n "$VERBOSE" ]; then
		echo "Deleting existing Virgo home [$VIRGO_HOME/$APP_NAME]"
	fi
	rm -rf "$VIRGO_HOME/$APP_NAME"
fi
if [ -d "$VIRGO_HOME/$APP_NAME" ]; then
	echo "Virgo already installed at [$VIRGO_HOME/virgo-tomcat-server-${virgoVersion}]"
else
	if [ -e "$virgoDownloadPath" ]; then
		sha512File "$virgoDownloadPath"
	fi

	if [ "$shaFileHash" != "$virgoDownloadSha" ]; then
		echo "\nDownloading Virgo $virgoVersion..."
		curl -L -s -S -o "$virgoDownloadPath" "$virgoDownloadUrl"
		if [ -e "$virgoDownloadPath" ]; then
			sha512File "$virgoDownloadPath"
			if [ "$shaFileHash" != "$virgoDownloadSha" ]; then
				echo "Error downloading Virgo: SHA mismatch"
				exit 1
			fi
		fi
	fi

	echo "Extracting $virgoDownloadPath -> $VIRGO_HOME"
	if [ -d "$VIRGO_HOME/virgo-tomcat-server-${virgoVersion}" ]; then
		rm -rf "$VIRGO_HOME/virgo-tomcat-server-${virgoVersion}"
	fi
	unzip -q -d "$VIRGO_HOME" "$virgoDownloadPath"
	mv "$VIRGO_HOME/virgo-tomcat-server-${virgoVersion}" "$VIRGO_HOME/$APP_NAME"
fi

#
# Remove splash webapp
#
if [ -e "$VIRGO_HOME/$APP_NAME/pickup/org.eclipse.virgo.apps.splash_${virgoVersion}.jar" ];then
	if [ -n "$VERBOSE" ]; then
		echo "Removing Virgo splash webapp pickup/org.eclipse.virgo.apps.splash_${virgoVersion}.jar"
	fi
	rm -f "$VIRGO_HOME/$APP_NAME/pickup/org.eclipse.virgo.apps.splash_${virgoVersion}.jar"
fi

#
# Remove Windows scripts
#
if [ -d "$VIRGO_HOME/$APP_NAME/bin" ];then
	if [ -n "$VERBOSE" ]; then
		echo "Removing Windows support..."
	fi
	find "$VIRGO_HOME/$APP_NAME/bin" -type f \( -name '*.bat' -o -name '*.vbs' \) -delete
fi

#
# Remove docs, extras
#
if [ -e "$VIRGO_HOME/$APP_NAME/about_files" ]; then
	if [ -n "$VERBOSE" ]; then
		echo "Removing Virgo documentation..."
	fi
	rm -rf "$VIRGO_HOME/$APP_NAME/about_files"
	rm -rf "$VIRGO_HOME/$APP_NAME"/*.html
fi

#
# Remove hard-coded JAVA_OPTS="-Xmx1024m
#
if [ -e "$VIRGO_HOME/$APP_NAME/bin/dmk.sh" ]; then
	if [ -n "$VERBOSE" ]; then
		echo "Removing hard-coded JAVA_OPTS from $VIRGO_HOME/$APP_NAME/bin/dmk.sh"
	fi
	sed -i '' '/Xmx1024m/,/XX:MaxPermSize/d' "$VIRGO_HOME/$APP_NAME/bin/dmk.sh"
fi

#
# Setup "env.plan" support
#
cd "$SETUP_HOME"
if ! grep -q "net.solarnetwork.$APP_NAME.env.plan" "$VIRGO_HOME/$APP_NAME/configuration/org.eclipse.virgo.kernel.userregion.properties"; then
	if [ -n "$VERBOSE" ]; then
		echo "Adding net.solarnetwork.$APP_NAME.env.plan to initial artifacts"
	fi
	sed -i '' "s/^initialArtifacts=\(.*\)/initialArtifacts=\1,repository:plan\/net.solarnetwork.$APP_NAME.env.plan/" "$VIRGO_HOME/$APP_NAME/configuration/org.eclipse.virgo.kernel.userregion.properties"
fi

#
# Add Java8 support
#
if ! grep -q 'com.sun.org.apache.bcel.internal' "$VIRGO_HOME/$APP_NAME/configuration/java-server.profile"; then
	if [ -n "$VERBOSE" ]; then
		echo "Adding additional system packages from defs/sys-packages-add.txt to configuration/java-server.profile"
	fi
	if [ ! -e defs/sys-packages-add.txt ]; then
		echo "Missing defs/sys-packages-add.txt file!"
		exit 1	
	fi
	sed -i '' '/org.osgi.framework.system.packages/r defs/sys-packages-add.txt' "$VIRGO_HOME/$APP_NAME/configuration/java-server.profile"
fi
if ! grep -q 'JavaSE-1.8' "$VIRGO_HOME/$APP_NAME/configuration/java-server.profile"; then
	if [ -n "$VERBOSE" ]; then
		echo "Adding JavaSE-1.8 support to configuration/java-server.profile"
	fi
	sed -i '' -e '/JavaSE-1.7$/ { s/$/,\\+ JavaSE-1.8/; y/+/\n/; }' -e '/osgi.ee; osgi.ee="JavaSE"/ s/1.7"$/1.7, 1.8"/' "$VIRGO_HOME/$APP_NAME/configuration/java-server.profile"
fi

#
# Add env repository
#
if ! grep -q 'etc.type' "$VIRGO_HOME/$APP_NAME/configuration/org.eclipse.virgo.repository.properties"; then
	if [ -n "$VERBOSE" ]; then
		echo "Adding 'etc' respository to configuration/org.eclipse.virgo.repository.properties"
	fi
	sed -i '' -e '1 { s@^@etc.type=external+etc.searchPattern=repository/etc/{artifact}++@; y/+/\n/; }' \
		-e 's/usr.type=watched/usr.type=external/' \
		-e 's@usr.watchDirectory=repository/usr@usr.searchPattern=repository/usr/{artifact}@' \
		-e 's/chain=ext,usr/chain=etc,ext,usr/' \
		"$VIRGO_HOME/$APP_NAME/configuration/org.eclipse.virgo.repository.properties"
fi

#
# Sync apphome files
#
ant -buildfile build.xml -DVIRGO_HOME=$VIRGO_HOME -DAPP_NAME=$APP_NAME -DENV_NAME=$ENV_NAME

#
# Base usr repository contents
#
if [ ! -d "$SN_BUILD_HOME" ]; then
	echo "SolarNetwork build home [$SN_BUILD_HOME] not found."
	exit 1
fi
if [ -n "$VERBOSE" ]; then
	echo "Assembling base usr Virgo repository -> $VIRGO_HOME/$APP_NAME/repository/usr"
fi
ant -buildfile "$SN_BUILD_HOME/solarnet-deploy/virgo/build.xml" \
	-Divy.file="$IVY_FILE" \
	-Divy.settings="$IVY_SETTINGS_FILE" \
	-Divy.resolve.refresh=true \
	-Divy.cache.ttl.default=1m \
	clean assemble
if [ -d "$SN_BUILD_HOME/solarnet-deploy/virgo/build/assemble/repository/usr" ]; then
	if [ -n "$VERBOSE" ]; then
		echo "Copying $SN_BUILD_HOME/solarnet-deploy/virgo/build/assemble/repository/usr contents -> $VIRGO_HOME/$APP_NAME/repository/usr"
	fi
	cp -R "$SN_BUILD_HOME/solarnet-deploy/virgo/build/assemble/repository/usr" "$VIRGO_HOME/$APP_NAME/repository/"
fi