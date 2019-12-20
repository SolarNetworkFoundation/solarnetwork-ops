#!/usr/bin/env sh
#
# Debian helper script for managing the socket CAN configuration. 

do_help () {
	h=$(cat <<-EOF
		Usage: $0 [<flags>] <action> [<args>]
		
		<flags> include:
		
		-d <device name>       The name of the CAN bus device, e.g. `can0`.
		
		<action> is one of:

		baud <speed>           Get or set the baud for a device.
		extra <extra>          Configure extra options like FD support.
		listen-only (on|off)   Toggle read-only mode for a device.
		restart-ms <ms>        Get or set the bus restart, in milliseonds.
		EOF
		)
	echo "$h" 1>&2
}

DEVICE=""

while getopts ":d:" opt; do
	case $opt in
		d) DEVICE="${OPTARG}";;

		*) do_help; exit 1;;
	esac
done

shift $(($OPTIND - 1))

if [ $# -lt 1 ]; then
	echo "Must provide action, use -? for help."  1>&2
	exit 1
fi

ACTION="$1"

shift 1

SERVICE="/lib/systemd/system/sn-pi-seeed-socketcan@.service"
INSTANCE="sn-pi-seeed-socketcan@${DEVICE}"
OVERRIDE_DIR="/etc/solarnode/socketcan"
OVERRIDE="${OVERRIDE_DIR}/${DEVICE}.env"

get_env_value () {
	local key="$1"
	local val=""
	if [ -e "${OVERRIDE}" ]; then
		val=$(grep "${key}=" "${OVERRIDE}" |sed -e "s/${key}=\(.*\)/\1/")
	fi
	if [ -z "${val}" ]; then
		val=$(grep "${key}=" "${SERVICE}" |sed -e 's/.*'"${key}"'=\([0-9a-zA-Z_-]*\).*/\1/')
	fi
	echo "${val}"
}

set_env_value () {
	local key="$1"
	local val="$2"
	if [ ! -e "${OVERRIDE}" ];then
		if [ ! -d "${OVERRIDE_DIR}" ];then
			mkdir -p "${OVERRIDE_DIR}"
		fi
	fi
	if grep -q "${key}=" "${OVERRIDE}"; then
		# update
		sed -i -e "/${key}=/c ${key}=${val}" "${OVERRIDE}"
	else
		echo "${key}=${val}" >>"${OVERRIDE}"
	fi
	
	systemctl daemon-reload
	if systemctl --quiet is-active "${INSTANCE}"; then
		systemctl restart "${INSTANCE}"
	fi
}

check_device_opt () {
	if [ -z "${DEVICE}" ]; then
		echo "Must provide device with -d; see -? for help." 1>&2
		exit 1
	fi
}

do_baud () {
	check_device_opt
	if [ -z "$1" ]; then
		get_env_value 'SOCKETCAN_BAUD'
	else
		set_env_value 'SOCKETCAN_BAUD' "$1"
	fi
}

do_extra () {
	check_device_opt
	if [ -z "$1" ]; then
		get_env_value 'SOCKETCAN_OPTS'
	else
		set_env_value 'SOCKETCAN_OPTS' '"'"$1"'"'
	fi
}

do_listen_only () {
	check_device_opt
	if [ -z "$1" ]; then
		get_env_value 'SOCKETCAN_LISTEN_ONLY'
	else
		set_env_value 'SOCKETCAN_LISTEN_ONLY' "$1"
	fi
}

do_restart_ms () {
	check_device_opt
	if [ -z "$1" ]; then
		get_env_value 'SOCKETCAN_RESTART_MS'
	else
		set_env_value 'SOCKETCAN_RESTART_MS' "$1"
	fi
}

case $ACTION in
	baud) do_baud "$1" ;;
	extra) do_extra "$1" ;;
	listen-only) do_listen_only "$1" ;;
	restart-ms) do_restart_ms "$1" ;;
	*)
		echo "Action '${ACTION}' not supported." 1>&2
		echo 1>&2
		do_help
		exit 1
		;;
esac

