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

export JAVA_OPTS="-Dsolarnetwork.pidfile=$SCRIPT_DIR/../work/solarnet.pid -Dfelix.fileinstall.dir=$SCRIPT_DIR/../configuration/services -Dfelix.fileinstall.filter=.*\.cfg -Dfelix.fileinstall.noInitialDelay=true"
export JMX_PORT=9882
echo "Starting Virgo HTTP @ 9082, AJP @ 9702, debug @ 9982."
exec "$SCRIPT_DIR"/"$EXECUTABLE" start -debug 9982 "$@"
