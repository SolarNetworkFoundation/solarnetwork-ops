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

	java -jar "$SCRIPT_DIR"/sn-prop-util.jar modify --file "$SCRIPT_DIR"/../configuration/services/net.solarnetwork.jdbc.pool.hikari-central.cfg $args
}

env_ssh () {
	if [ -n "$SSH_PUBLIC_KEY" ]; then
		if [ ! -d ~ ]; then
			mkdir -p ~
			chown virgo:virgo ~
		fi
		if [ ! -d ~/.ssh ]; then
			mkdir -p ~/.ssh
			chown virgo:virgo ~/.ssh
			chmod 700 ~/.ssh
		fi
		if [ ! -e ~/.ssh/authorized_keys ]; then
			touch ~/.ssh/authorized_keys
			chown virgo:virgo ~/.ssh/authorized_keys
			chmod 600 ~/.ssh/authorized_keys
		fi
		if ! fgrep "$SSH_PUBLIC_KEY" ~/.ssh/authorized_keys >/dev/null; then
			echo "$SSH_PUBLIC_KEY" >>~/.ssh/authorized_keys
		fi
	fi
}

env_jdbc
env_ssh

export JAVA_OPTS="-Xmx768m -Djava.awt.headless=true -Djdk.management.heapdump.allowAnyFileSuffix=true -Dsolarnetwork.pidfile=$SCRIPT_DIR/../work/solarnet.pid -Dfelix.fileinstall.dir=$SCRIPT_DIR/../configuration/services -Dfelix.fileinstall.filter=.*\.cfg -Dfelix.fileinstall.noInitialDelay=true -Dfelix.fileinstall.enableConfigSave=false"
export JMX_PORT=9881
echo "Starting Virgo HTTP @ 9081, AJP @ 9701, debug @ 9981."
exec "$SCRIPT_DIR"/"$EXECUTABLE" start -debug 9981 "$@"
