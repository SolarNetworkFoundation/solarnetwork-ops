#!/bin/sh

VER=0.22.10

cp -va killbill-profiles-killbill-$VER.war sn-killbill-profiles-killbill-$VER.war

# Replace release JARs with custom versions
zip -vd sn-killbill-profiles-killbill-$VER.war \
    'WEB-INF/lib/killbill-subscription-*.jar' \
    'WEB-INF/lib/killbill-invoice-*.jar'

# Add custom JARs
cd sn-war-root
jar uvf ../sn-killbill-profiles-killbill-$VER.war WEB-INF/lib/*.jar
