#!/bin/sh

DEFAULTS="/etc/default/sn-sixfab-3g-shield"
AUTO_RECONNECT_ENABLE=0
NET_INTERFACE="ppp0"
PING_HOST="1.1.1.1"

if [ -e "$DEFAULTS" ]; then
	. "$DEFAULTS"
fi

while getopts ":f" opt; do
	case $opt in
		f) AUTO_RECONNECT_ENABLE=1;;
		*)
			echo "Unknown argument: ${OPTARG}"
			exit 1
	esac
done
shift $(($OPTIND - 1))

if [ ${AUTO_RECONNECT_ENABLE} -eq 0 ]; then
	exit 0;
fi

# Get status of network neterface, e.g. UP, DOWN, UNKNOWN
iface_status=$(ip -br link show |grep '^ppp0' |awk '{print $2}')

if [ -z "${iface_status}" ]; then
	# interface not found
	echo "Network interface ${NET_INTERFACE} not found, will start now."
	systemctl restart sn-sixfab-3g-pppd
else
	echo "Pinging ${PING_HOST} on ${NET_INTERFACE}..." 1>&2

	if ! ping -q -I ${NET_INTERFACE} -c 1 ${PING_HOST} -s 0 >/dev/null; then
		echo "Unable to ping ${PING_HOST} on ${NET_INTERFACE}, will reconnect now."
		systemctl restart sn-sixfab-3g-pppd
	fi
fi
