#!/bin/sh
#
# Pass application name(s) as arguments to clean their work/ directory bundle cache files.

VIRGO_HOME="/usr/local/opt/virgo"
for app in "$@"; do
	if [ -d "${VIRGO_HOME}/${app}/work" ]; then
		find ${VIRGO_HOME}/${app}/work ! -name work  -prune -type f -name '*.index' -exec rm -f {} \;
	fi
done
