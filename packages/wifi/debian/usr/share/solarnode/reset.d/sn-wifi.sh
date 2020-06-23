#!/usr/bin/env sh
#
# Helper script for SolarNodeOS reset support.
# 
# If -a is passed as an argument, this script does nothing. Otherwise
# it will delete the WiFi 
# Executes executable scripts in /usr/share/solarnode/reset.d,
# passing -a if that is passed to this script.

APP_ONLY=""
CONF_DIR="${CONF_DIR:-/etc/wpa_supplicant}"

while getopts ":a" opt; do
	case $opt in
		a) APP_ONLY="-a";;
		*)
			echo "Unknown option '$OPTARG'." 1>&2
			exit 1
	esac
done

if [ -n "${APP_ONLY}" ]; then
	exit 0
fi

if systemctl is-active sn-wifi-conf@wlan0.service >/dev/null; then
	echo 'Stopping sn-wifi-conf@wlan0.service...'
	systemctl stop sn-wifi-conf@wlan0.service || true
fi
if systemctl is-enabled sn-wifi-conf@wlan0.service >/dev/null; then
	echo 'Disabling sn-wifi-conf@wlan0.service...'
	systemctl disable sn-wifi-conf@wlan0.service || true
fi

echo 'Removing WiFi connection configuration...'
find "${CONF_DIR}" -type f -name 'wpa_supplicant-*.conf' -print -exec rm -f {} \;
