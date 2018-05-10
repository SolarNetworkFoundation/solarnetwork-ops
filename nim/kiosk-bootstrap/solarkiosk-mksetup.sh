#!/usr/bin/env bash

SYS_HOME=solarkiosk-root

SYSTEM_FILE=solarkiosk-system-00001.tgz

GTAR_USER_MAP=solarkiosk-gtar-user.map
GTAR_GROUP_MAP=solarkiosk-gtar-user.map

SYS_FILE=`grealpath "$SYSTEM_FILE"`

TU_MAP=`grealpath "$GTAR_USER_MAP"`
TG_MAP=`grealpath "$GTAR_GROUP_MAP"`

ORIG_WD="$PWD"

# find files for system config
echo
echo "Creating the NIM archive $SYS_FILE..."
cd "$SYS_HOME"
find etc home usr var -type f -not -name ".DS_Store" -print0 |gtar cvzf "$SYS_FILE" --null -T - --owner-map "$TU_MAP" --group-map "$TG_MAP"
