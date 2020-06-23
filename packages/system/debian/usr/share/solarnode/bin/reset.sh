#!/usr/bin/env sh
#
# Helper script for SolarNodeOS reset support.
# 
# Executes executable scripts in /usr/share/solarnode/reset.d,
# passing -a if that is passed to this script.


APP_ONLY=""
HOOK_DIR="${HOOK_DIR:-/usr/share/solarnode/reset.d}"

while getopts ":a" opt; do
	case $opt in
		a) APP_ONLY="-a";;
		*)
			echo "Unknown option '$OPTARG'." 1>&2
			exit 1
	esac
done

find "${HOOK_DIR}" -type f -perm -500 -exec {} ${APP_ONLY} \;
