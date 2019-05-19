#!/bin/bash

sn-netctl() {
	local action="$1"
	local device="$2"
	sudo /usr/share/solarnode/bin/netctl.sh "$1" "$2"
}
