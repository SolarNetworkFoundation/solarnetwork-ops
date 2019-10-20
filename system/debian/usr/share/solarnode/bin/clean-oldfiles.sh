#!/bin/sh
#
# Clean out old files based on modification date.

NUM_DAYS=1

while getopts ":D:" opt; do
	case $opt in
		D) NUM_DAYS=$OPTARG ;;
	esac
done

shift $(($OPTIND - 1))

if [ -z "$1" ]; then
	echo "Directories to clean from must be provided."
	exit 1
fi

find "$@" -mtime "+$NUM_DAYS" -delete
