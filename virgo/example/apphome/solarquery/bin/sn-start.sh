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
JDBC_CONF="$SCRIPT_DIR/../configuration/services/net.solarnetwork.jdbc.pool.hikari-central.cfg"
JDBC_CONF_RW="$SCRIPT_DIR/../configuration/services/net.solarnetwork.jdbc.pool.hikari-central-readwrite.cfg"

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
	
	java -jar "$SCRIPT_DIR"/sn-prop-util.jar modify --file "$JDBC_CONF" $args
}

env_jdbc_rw () {
	local args=""
	
	if [ -n "$SN_JDBC_URL_RW" ]; then
		args="$args --set jdbc.url=$SN_JDBC_URL_RW"
	fi
	
	if [ -n "$SN_JDBC_USER" ]; then
		args="$args --set jdbc.user=$SN_JDBC_USER_RW"
	fi
	
	if [ -n "$SN_JDBC_PASS" ]; then
		args="$args --set jdbc.pass=$SN_JDBC_PASS_RW"
	fi
	
	java -jar "$SCRIPT_DIR"/sn-prop-util.jar modify --file "$JDBC_CONF_RW" $args
}

env_jdbc

if [ -e "$JDBC_CONF_RW" ]; then
	env_jdbc_rw
fi

export JAVA_OPTS="-Xmx768m -Djdk.management.heapdump.allowAnyFileSuffix=true -Dsolarnetwork.pidfile=$SCRIPT_DIR/../work/solarnet.pid -Dfelix.fileinstall.dir=$SCRIPT_DIR/../configuration/services -Dfelix.fileinstall.filter=.*\.cfg -Dfelix.fileinstall.noInitialDelay=true"
export JMX_PORT=9882
echo "Starting Virgo HTTP @ 9082, AJP @ 9702, debug @ 9982."
exec "$SCRIPT_DIR"/"$EXECUTABLE" start -debug 9982 "$@"
