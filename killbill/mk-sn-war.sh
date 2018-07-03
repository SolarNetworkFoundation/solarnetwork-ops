#!/bin/sh

VER=0.18.20

cp -va killbill-profiles-killbill-$VER.war sn-killbill-profiles-killbill-$VER.war

# Replace invoice JAR with bugfix
zip -vd sn-killbill-profiles-killbill-$VER.war 'WEB-INF/lib/killbill-invoice-*.jar'

# Add custom JARs
cd sn-war-root
jar uvf ../sn-killbill-profiles-killbill-$VER.war WEB-INF/lib/*.jar
