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

#
# identify yourself when running under cygwin
#
cygwin=false
case "$(uname)" in
    CYGWIN*) cygwin=true ;;
esac
export cygwin

export JMX_PORT=9881
echo "Starting Virgo HTTP on port 9081, debug port 9981."
exec "$SCRIPT_DIR"/"$EXECUTABLE" start -debug 9981 "$@"
