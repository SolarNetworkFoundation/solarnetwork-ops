#!/usr/bin/env bash

SCRIPT="$0"

# SCRIPT may be an arbitrarily deep series of symlinks. Loop until we have the concrete path.
while [ -h "$SCRIPT" ] ; do
  ls=`ls -ld "$SCRIPT"`
  # Drop everything prior to ->
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    SCRIPT="$link"
  else
    SCRIPT=`dirname "$SCRIPT"`/"$link"
  fi
done

SCRIPT_DIR=`dirname $SCRIPT`
EXECUTABLE="dmk.sh"

export cygwin=false

env_jdbc () {
	local args=""
	
	if [ -n "$SN_JDBC_URL" ]; then
		args="$args --set jdbc.url=$SN_JDBC_URL"
	fi
	
	if [ -n "$SN_JDBC_USER" ]; then
		args="$args --set jdbc.user=$SN_JDBC_USER"
	fi
	
	if [ -n "$SN_JDBC_PASS" ]; then
		args="$args --set jdbc.pass=$SN_JDBC_PASS"
	fi
	
	java -jar "$SCRIPT_DIR"/sn-prop-util.jar modify --file "$SCRIPT_DIR"/../repository/etc/net.solarnetwork.central.dao.jdbc.properties $args
}

env_jdbc

export JMX_PORT=9880
echo "Starting Virgo HTTP on port 9080, debug port 9980."
exec "$SCRIPT_DIR"/"$EXECUTABLE" start -debug 9980 "$@"
