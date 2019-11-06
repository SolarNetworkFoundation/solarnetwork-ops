#!/usr/bin/env bash

do_cpu_temp () {
	local temp=""
	if [ -e /sys/class/thermal/thermal_zone0/temp ]; then
		# Using awk, rather than bc, so trailing zeros not generated
		temp=$(echo - |awk -v t=$(cat /sys/class/thermal/thermal_zone0/temp) '{print t / 1000}')
	elif [ -x /opt/vc/bin/vcgencmd ]; then
		temp=$(/opt/vc/bin/vcgencmd measure_temp 2>/dev/null |tr -cd 0123456789.-)
	fi
	if [ -n "$temp" ]; then
		echo 'i/cpu_temp'
		echo "$temp"
	fi
}
