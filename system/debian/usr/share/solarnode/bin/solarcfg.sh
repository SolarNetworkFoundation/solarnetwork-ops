#!/usr/bin/env bash
#
# Helper script for SolarNode OS configuration support.

if [ $# -lt 2 ]; then
	echo "Must provide service and action arguments."  1>&2
	exit 1
fi

SERVICE="$1"
SCRIPT="$(find /usr/share/solarnode/cfg.d -name $SERVICE.\* -print -quit)"
shift 1

echo 
if [ ! -x "$SCRIPT" ]; then
	echo "Service '$SERVICE' not available." 1>&2
	exit 2
fi

sudo $SCRIPT "$@"
