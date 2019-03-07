#!/usr/bin/env sh

virgoVersion="3.7.2.RELEASE"
virgoDownloadUrl="https://www.eclipse.org/downloads/download.php?file=/virgo/release/VP/${virgoVersion}/virgo-tomcat-server-${virgoVersion}.zip&r=1"
virgoDownloadSha="f997cbdd9beed4fd953f5bf7a9cf3c5b3940a1d565f6722148ecdae5e21e84a7d414e7f0e1cd222172753956a3654f6959f74ccd216476de9f7beda6478c2ac6"

virgoDownloadPath="/var/tmp/virgo-tomcat-server-${virgoVersion}.zip"

APP_NAME="solarapp"
DRY_RUN=""
VIRGO_HOME=""
VERBOSE=""

while getopts ":a:h:tv" opt; do
	case $opt in
		a) APP_NAME="${OPTARG}";;
		h) VIRGO_HOME="${OPTARG}";;
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

if [ ! -L "$VIRGO_HOME/$APP_NAME" ]; then
	echo "Making link $VIRGO_HOME/$APP_NAME -> virgo-tomcat-server-${virgoVersion}"
	cd "$VIRGO_HOME"
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
	sed -i '' -E "s/^initialArtifacts=(.*)/initialArtifacts=\1,repository:plan\/net.solarnetwork.central.env.plan/" "$VIRGO_HOME/$APP_NAME/configuration/org.eclipse.virgo.kernel.userregion.properties"
fi

#
# Add Java8 support
#
if ! grep -q 'com.sun.org.apache.bcel.internal' "$VIRGO_HOME/$APP_NAME/configuration/java-server.profile"; then
	if [ -n "$VERBOSE" ]; then
		echo "Adding additional system packages from defs/sys-packages-add.txt"
	fi
	if [ ! -e defs/sys-packages-add.txt ]; then
		echo "Missing defs/sys-packages-add.txt file!"
		exit 1	
	fi
	sed -i '' -E '/org.osgi.framework.system.packages/r defs/sys-packages-add.txt' "$VIRGO_HOME/$APP_NAME/configuration/java-server.profile"
fi