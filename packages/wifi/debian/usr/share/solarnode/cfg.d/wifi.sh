#!/usr/bin/env bash
#
# Helper script for SolarNode OS WiFi configuration support.

if [ $# -lt 1 ]; then
	echo "Must provide action argument."  1>&2
	exit 1
fi

CFG_SCRIPT="${CFG_SCRIPT:-/usr/share/solarnode/bin/wifi-cfg.sh}"
ACTION="$1"
shift 1

do_help () {
	cat 1>&2 <<EOF
Usage: wifi.sh action [args]

Actions:

 configure - Configure WiFi settings.
 settings  - View current WiFi settings.
 status    - Get current WiFi connection status.
 restart   - Restart the WiFi connection.
EOF
}

do_configure () {
	configure_help () {
		cat 1>&2 <<EOF
	Usage for configure action:

	 -c <country>  - The WiFi 2-character country code.
	 -s <ssid>     - The WiFi SSID to connect to.
	 -p <password> - The WiFi password to use.
EOF
	}

	local OPTIND opt country ssid password tmpfile
	while getopts ":c:p:s:" opt; do
		case $opt in
			c) country="${OPTARG}";;
			p) password="${OPTARG}";;
			s) ssid="${OPTARG}";;
			*)
				echo "Unknown configure option '$OPTARG'." 1>&2
				configure_help
				exit 1
		esac
	done
	shift $(($OPTIND - 1))
	echo "configure c = ${country}, s = ${ssid}, p = ${password}; $*"
	tmpfile=$(mktemp /tmp/sn-wifi.XXXXXX)
	if [ -n "${country}" ]; then
		echo "sn-wifi sn-wifi/country string $country" >>$tmpfile
	fi
	if [ -n "${ssid}" ]; then
		echo "sn-wifi sn-wifi/ssid string $ssid" >>$tmpfile
	fi
	if [ -n "${password}" ]; then
		echo "sn-wifi sn-wifi/pass password $password" >>$tmpfile
	fi
	if [ -s "$tmpfile" ]; then
		debconf-set-selections $tmpfile
		if [ -x "$CFG_SCRIPT" ]; then
			echo "$PASS" | $CFG_SCRIPT -c "$country" -s "$ssid"
		fi
	else
		configure_help
		exit 1
	fi
	rm $tmpfile
}

case $ACTION in
	configure) do_configure "$@";;

	*)
		echo "Action '${ACTION}' not supported." 1>&2
		echo 1>&2
		do_help
		exit 1
esac
