#!/bin/bash
#
# Minimalist ssh brute force attack banning script for busybox-syslogd and nftables.
#
# Adapted from dropBrute.sh by robzr
#
# Installation steps:
#
# 1) Optionally edit the variables in the header of this script to customise
#    for your environment
#
# 2) Insert a reference for this rule in your firewall script before you
#    accept ssh, something like:
#
#    add chain ip filter dropBrute
#    add rule ip filter INPUT ct state new  tcp dport 22 counter jump dropBrute
#    add rule ip filter INPUT ct state new  tcp dport 22 limit rate 6/minute burst 6 packets counter accept
#
# 3) Run the script periodically out of cron:
#
#    */2 * * * * /usr/share/solarnode/bin/nftables-drop-brute.sh >/dev/null 2>&1
#
# To whitelist hosts or networks, simply add a manual entry to the lease
# file with a leasetime of -1.  This can be done with the following syntax:
#
#    echo "-1 192.168.1.0/24" >> /tmp/dropBrute.leases
#
# A static, or non-expiring blacklist of a host or network can also be
# added, just use a lease time of 0.  This can be done with the following syntax:
#
#    echo "0 1.2.3.0/24" >> /tmp/dropBrute.leases

# How many bad attempts before banning.
allowedAttempts=3

# How long IPs are banned for after the current day ends.
# default is 7 days
secondsToBan=$((7*60*60*24))

# the "lease" file - defaults to /tmp which does not persist across reboots
leaseFile=/tmp/dropBrute.leases

# This is the nftables chain that drop commands will go into.
# you will need to put a reference in your firewall rules for this
nftChain=dropBrute

# the path to nft
cmd='/usr/sbin/nft'

# End of user customizable variables (unless you know better :) )

[ `date +'%s'` -lt 1320000000 ] && echo 'System date not set, aborting.' && exit -1

now=`date +'%s'`
nowPlus=$((now + secondsToBan))

echo "Running dropBrute on $(date) ($now)"

# find new badIPs
for badIP in `logread | egrep -i 'Failed \w+ for'| sed 's/^.*from \(.*\) port.*/\1/' | sort -u` ; do
  found=$(logread |egrep -ci "Failed.*from $badIP")
  if [ $found -gt $allowedAttempts ] ; then
    # if there is not a lease, add it
    if [ $(egrep -c $badIP$ $leaseFile) -eq 0 ] ; then
       echo "$nowPlus $badIP" >> $leaseFile
    fi
  fi
done

find_rule_handle () {
  local ipaddr="$1"
  local rtype="$2"
  # expecting output like: ip saddr 22.33.44.55 return # handle 17
  # for which 17 should be returned
  local awkcmd='NF > 3 && $(NF-1) == "handle" && $2 == "saddr" && $3 == "'"$ipaddr"'" && $(NF-3) == "'"$rtype"'" {print $NF}'
  $cmd -a list chain ip filter $nftChain |awk "$awkcmd" |head -1
}

# now parse the leaseFile
while read lease ; do
  leaseTime=`echo $lease|cut -f1 -d\ `
  leaseIP=`echo $lease|cut -f2 -d\ `
  rhandle=""
  if [ $leaseTime -lt 0 ] ; then
    rhandle=$(find_rule_handle "$leaseIP" "return")
    if [ -z "$rhandle" ]; then
      echo "Adding new whitelist rule for $leaseIP"
      $cmd insert rule ip filter $nftChain ip saddr $leaseIP return
    fi
  else
    rhandle=$(find_rule_handle "$leaseIP" "drop")
    if [ $leaseTime -ge 1 -a $now -gt $leaseTime -a -n "$rhandle" ]; then
      echo "Expiring lease for $leaseIP (rule $rhandle)"
      $cmd delete rule ip filter dropBrute handle $rhandle
      sed -i /$leaseIP/d $leaseFile
    elif [ $leaseTime -ge 0 -a -z "$rhandle" ]; then
      echo "Adding new rule for $leaseIP"
      $cmd add rule ip filter $nftChain ip saddr $leaseIP drop
    fi
  fi
done < $leaseFile

