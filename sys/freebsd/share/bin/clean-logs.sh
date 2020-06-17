#!/bin/sh

DAYS_OLD="21"
LOG_DIR="/var/log/tomcat"
TEST=""
VERBOSE=""
FIND_ARGS=""

while getopts ":d:f:tv" opt; do
        case $opt in
			d) DAYS_OLD="${OPTARG}" ;;
			f) FIND_ARGS="${OPTARG}" ;;
        	t) TEST="1" ;;
			v) VERBOSE="1" ;;
 			*)
				echo "Usage: [-t test]"
				exit 1
				;;
	esac
done

shift $((OPTIND - 1))

if [ $# -le 0 ]; then
	echo "Pass directories to look in as arguments."
	exit 1;
fi

if [ -n "$VERBOSE" ]; then
	echo "Looking for files in $@ more than $DAYS_OLD days old..."
	echo "find $@ -type f -mtime +${DAYS_OLD} ${FIND_ARGS}"
fi

for oldFile in $(eval find $@ -type f -mtime +${DAYS_OLD} ${FIND_ARGS}); do
	if [ -z "$TEST" ]; then
		if [ -n "$VERBOSE" ]; then
			echo "Removing old file ${oldFile}"
		fi
		rm -f ${oldFile}
	elif [ -n "$VERBOSE" ]; then
		echo "[TEST] Removing old file ${oldFile}"
	fi
done
