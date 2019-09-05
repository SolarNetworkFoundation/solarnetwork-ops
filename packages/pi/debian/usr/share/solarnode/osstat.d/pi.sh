#!/usr/bin/env bash

do_cpu_temp () {
	if [ -x /opt/vc/bin/vcgencmd ]; then
		local temp=$(/opt/vc/bin/vcgencmd measure_temp 2>/dev/null |tr -cd 0123456789.-)
		if [ -n "$temp" ]; then
			echo 'i/cpu_temp'
			echo "$temp"
		fi
	fi
}
