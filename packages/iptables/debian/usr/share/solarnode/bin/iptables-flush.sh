#!/bin/bash
#
# Usage: iptables-flush [6]
#
# If "6" is passed as an argument, then IPv6 rules are managed.

iptables="/sbin/ip$1tables"
tables_restore="/sbin/ip$1tables-restore"
if ! type -p "$iptables"; then
	echo "Error: invalid argument [$1]"
	exit 1
fi

while read -r table; do
	rules="/usr/share/solarnode/conf/ip$1tables-empty-$table.rules"
	if [ -e "$rules" ]; then
		echo "Restoring empty $table rules from $rules"
		tables+=("$rules")
	fi
done < "/proc/net/ip$1_tables_names"

if (( ${#tables[*]} )); then
  cat "${tables[@]}" | "$tables_restore"
fi

