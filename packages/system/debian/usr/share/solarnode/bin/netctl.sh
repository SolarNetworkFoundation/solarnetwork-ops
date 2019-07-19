#!/bin/sh
#
# Manage systemd-networkd device up/down status. Designed to be used
# for things like the SolarNode HTTP Ping Control. Add this script
# to the sudoers config for the solarnode user, then it can restart
# network devices in response to ping failures.

# function() to list devices
do_list () {
	ip link list |awk '$1 ~ "^[0-9]+:" { sub(":", "", $2); print $2; }' |grep -v lo
}

# function(device) to check status
do_status () {
	ip addr show dev $1
}

# function(device) to check status
do_stop () {
	ip link set down $1
	ip addr flush dev $1
}

do_netrestart() {
	systemctl restart systemd-networkd
}

# Print help
do_help () {
	echo "Usage: $0 {list|status|start|stop|restart} [device]" 1>&2
}

# Verify command arguments
ACTION="$1"
IFACE="$2"

if [ -z "$ACTION" ]; then
	do_help
	exit 1
fi

# Parse command line parameters.
case $ACTION in
	list)
		do_list
		;;
		
	status)
		if [ -n "$IFACE" ]; then
			do_status $IFACE
		else
			for d in $(do_list); do
				do_status "$d"
			done
		fi
		;;

	start)
		do_netrestart
		;;

	stop)
		if [ -n "$IFACE" ]; then
			do_stop $IFACE
		else
			echo 'Device name argument required.'
		fi
		;;

	restart)
		if [ -n "$IFACE" ]; then
			do_stop $IFACE
		fi
		sleep 1
		do_netrestart
		;;

	*)
		do_help
		exit 1
		;;
esac

exit 0

