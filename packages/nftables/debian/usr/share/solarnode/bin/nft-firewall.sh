#!/usr/bin/env sh
#
# Debian helper script for managing the nftables firewall.

CMD="/usr/sbin/nft"
CMD_OPTS="-ann"
NFT_FAMILY="ip"
NFT_TABLE="filter"
NFT_CHAIN="snManaged"

do_help () {
	h=$(cat <<-EOF
		Usage: $0 <action> [<args>]
		
		<action> is one of: close, list-open, open, rule-id

		close <port>        Close a port.
		is-open <port>      Test if a port is open; returnes yes|no.
		list-open           List the open ports.
		open <port>         Open a port.
		rule-id <port>      Show the nftables handle for the rule for a port.
		EOF
		)
	echo "$h" 1>&2
}

# do_list_open - list open ports
do_list_open () {
	$CMD $CMD_OPTS list chain $NFT_FAMILY $NFT_TABLE $NFT_CHAIN \
		|grep dport \
		|sed 's/.*dport \([0-9]*\).*/\1/' \
		|sort -u
}

# chec_restricted_port <port> - test if a port should not be managed, exit if so
check_restricted_port () {
	case $1 in
		22|80|8080)
			# not allowed
			echo "Port $1 is restricted." 1>&2
			exit 1
			;;
	esac
}

# find_rule_handle <port> - test if a port is open; returns the rule handle if found
find_rule_handle () {
	local awkcmd='NF > 3 && $(NF-1) == "handle" && $2 == "dport" && $3 == "'"$1"'" {print $NF}'
	# expecting output like: tcp dport X ... # handle Y
	# for which X is the port and Y should be returned
	$CMD -ann list chain $NFT_FAMILY $NFT_TABLE $NFT_CHAIN |awk "$awkcmd" |head -1
}

# get_rule_id <port> - get the rule ID for a port
get_rule_id () {
	local port="$1"
	if [ -z "$port" ]; then
		echo "Port to find is required." 1>&2
		exit 1
	fi
	find_rule_handle "$port"
}

do_is_open () {
	local port="$1"
	if [ -z "$port" ]; then
		echo "Port to test is required." 1>&2
		exit 1
	fi
	check_restricted_port "$port"
	local h=$(find_rule_handle $port)
	if [ -n "$h" ]; then
		echo yes
	else
		echo no
	fi
}

# do_open <port> - open a port
do_open () {
	local port="$1"
	if [ -z "$port" ]; then
		echo "Port to open is required." 1>&2
		exit 1
	fi
	check_restricted_port "$port"
	if [ -z $(find_rule_handle "$port") ]; then
		$CMD add rule $NFT_FAMILY $NFT_TABLE $NFT_CHAIN tcp dport $1 counter accept
	fi
}

# do_close <port> - close a port
do_close () {
	local port="$1"
	if [ -z "$port" ]; then
		echo "Port to close is required." 1>&2
		exit 1
	fi
	check_restricted_port "$port"
	local h=$(find_rule_handle $port)
	if [ -n "$h" ]; then
		$CMD delete rule $NFT_FAMILY $NFT_TABLE $NFT_CHAIN handle $h 
	fi
}


if [ -z "$1" ]; then
	echo "Must provide action (close, is-open, list-open, open, rule-id); use -? for help." 1>&2
	exit 1
fi

ACTION="$1"

shift 1

case $ACTION in
	close)
		do_close "$1"
		;;

	is-open)
		do_is_open "$1"
		;;

	list-open)
		do_list_open
		;;

	open)
		do_open "$1"
		;;

	rule-id)
		get_rule_id "$1"
		;;

	*)
		echo "Action '${ACTION}' not supported." 1>&2
		echo 1>&2
		do_help
		exit 1
		;;
esac

