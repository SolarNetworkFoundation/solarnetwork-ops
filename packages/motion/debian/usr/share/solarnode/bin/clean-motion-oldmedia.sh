#!/bin/sh

CONF_DIR="/etc/motion"
DEFAULTS="/etc/default/sn-motion"
HELPER="/usr/share/solarnode/bin/clean-oldfiles.sh"
MOTION_MEDIA_KEEP_DAYS="5"

if [ -e "$DEFAULTS" ]; then
	. "$DEFAULTS"
fi

if [ -d "$CONF_DIR" -a -x "$HELPER" ]; then
	# iterate over all possible target_dir directories that need cleaning
	egrep -r '^target_dir ' "$CONF_DIR" |cut -d' ' -f2 |uniq |while read dir; do
		echo "Cleaning motion media files older than $MOTION_MEDIA_KEEP_DAYS days from $dir."
		$HELPER -D "$MOTION_MEDIA_KEEP_DAYS" "$dir"
	done
fi
