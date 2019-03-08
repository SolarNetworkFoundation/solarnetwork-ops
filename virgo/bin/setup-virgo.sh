#!/usr/bin/env sh

virgoVersion="3.7.0.RELEASE"
virgoDownloadUrl="https://www.eclipse.org/downloads/download.php?file=/virgo/release/VP/${virgoVersion}/virgo-tomcat-server-${virgoVersion}.zip&r=1"
virgoDownloadSha="7d95293d55cc51d0febc3a3feeff211305614fa9f7fb41ac6a1129220fc0810692c6cd765bd16cbb712874aff77e08d3fd3dc6c7b0a150f433d82fd7b8f9b873"
# 3.7.2 virgoDownloadSha="f997cbdd9beed4fd953f5bf7a9cf3c5b3940a1d565f6722148ecdae5e21e84a7d414e7f0e1cd222172753956a3654f6959f74ccd216476de9f7beda6478c2ac6"

virgoDownloadPath="/var/tmp/virgo-tomcat-server-${virgoVersion}.zip"

APP_NAME="solarapp"
CLEAN=""
DRY_RUN=""
IVY_FILE="example/ivy.xml"
SN_BUILD_HOME="solarnetwork-build"
VIRGO_HOME=""
VERBOSE=""

while getopts ":a:b:h:i:rtv" opt; do
	case $opt in
		a) APP_NAME="${OPTARG}";;
		b) SN_BUILD_HOME="${OPTARG}";;
		h) VIRGO_HOME="${OPTARG}";;
		i) IVY_FILE="${OPTARG}";;
		r) CLEAN='TRUE';;
		t) DRY_RUN='TRUE';;
		v) VERBOSE='TRUE';;
		?)
			echo "Unknown argument ${OPTARG}"
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
if [ -d "$VIRGO_HOME/virgo-tomcat-server-${virgoVersion}" -a -n "$CLEAN" ]; then
	if [ -n "$VERBOSE" ]; then
		echo "Deleting existing Virgo home [$VIRGO_HOME/virgo-tomcat-server-${virgoVersion}]"
	fi
	rm -rf "$VIRGO_HOME/virgo-tomcat-server-${virgoVersion}"
fi
if [ -d "$VIRGO_HOME/virgo-tomcat-server-${virgoVersion}" ]; then
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
	unzip -q -d "$VIRGO_HOME" "$virgoDownloadPath"
fi

if [ "$(readlink $VIRGO_HOME/$APP_NAME)" != "virgo-tomcat-server-${virgoVersion}" ]; then
	echo "Making link $VIRGO_HOME/$APP_NAME -> virgo-tomcat-server-${virgoVersion}"
	cd "$VIRGO_HOME"
	if [ -L "$APP_NAME" ]; then
		rm 	"$APP_NAME"
	fi
	ln -s "virgo-tomcat-server-${virgoVersion}" "$APP_NAME"
fi

#
# Setup "env.plan" support
#
cd "$SETUP_HOME"
if ! grep -q 'net.solarnetwork.central.env.plan' "$VIRGO_HOME/$APP_NAME/configuration/org.eclipse.virgo.kernel.userregion.properties"; then
	if [ -n "$VERBOSE" ]; then
		echo "Adding net.solarnetwork.central.env.plan to initial artifacts"
	fi
	sed -i '' "s/^initialArtifacts=\(.*\)/initialArtifacts=\1,repository:plan\/net.solarnetwork.$APP_NAME.env/" "$VIRGO_HOME/$APP_NAME/configuration/org.eclipse.virgo.kernel.userregion.properties"
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
# Add local repository
#
if ! grep -q 'local.type' "$VIRGO_HOME/$APP_NAME/configuration/org.eclipse.virgo.repository.properties"; then
	if [ -n "$VERBOSE" ]; then
		echo "Adding 'local' respository to configuration/org.eclipse.virgo.repository.properties"
	fi
	sed -i '' -e '1 { s@^@local.type=external+local.searchPattern=repository/local/{artifact}++@; y/+/\n/; }' \
		-e 's/usr.type=watched/usr.type=external/' \
		-e 's@usr.watchDirectory=repository/usr@usr.searchPattern=repository/usr/{artifact}@' \
		-e 's/chain=ext,usr/chain=local,ext,usr/' \
		"$VIRGO_HOME/$APP_NAME/configuration/org.eclipse.virgo.repository.properties"
fi

#
# Sync apphome files
#
if [ -d "apphome/$APP_NAME" ]; then
	if [ -n "$VERBOSE" ]; then
		echo "Copying apphome/$APP_NAME contents -> $VIRGO_HOME/$APP_NAME"
	fi
	rsync -a "apphome/$APP_NAME/" "$VIRGO_HOME/$APP_NAME/"
fi

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
ant -buildfile "$SN_BUILD_HOME/solarnet-deploy/virgo/build.xml" -Divy.file="$IVY_FILE" \
	-Divy.resolve.refresh=true \
	-Divy.cache.ttl.default=1m \
	clean assemble
if [ -d "$SN_BUILD_HOME/solarnet-deploy/virgo/build/assemble/repository/usr" ]; then
	if [ -n "$VERBOSE" ]; then
		echo "Copying $SN_BUILD_HOME/solarnet-deploy/virgo/build/assemble/repository/usr contents -> $VIRGO_HOME/$APP_NAME/repository/usr"
	fi
	rsync -a "$SN_BUILD_HOME/solarnet-deploy/virgo/build/assemble/repository/usr" "$VIRGO_HOME/$APP_NAME/repository/"
fi