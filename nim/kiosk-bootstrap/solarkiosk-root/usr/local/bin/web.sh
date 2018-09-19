#!/bin/sh
while true; do
	/usr/local/bin/web.py "$@" >/dev/null 2>&1
done

