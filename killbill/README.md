# SolarNetwork Foundation Killbill Support

SNF relies on a customized Killbill WAR that includes a  [custom invoice formatter][1]
that must be included in the application's classpath. To simplify deployment we've
constructed a customized WAR that includes the formatter's JAR.

Additionally, [a bug][2] has been discovered in version *0.18.20* that prevents invoices
from generating for some clients, and have deployed [a fix][3] that requires replacing
a JAR from the WAR with an updated version.

The `mk-sn-war.sh` script here can be used to customize the Killbill WAR. Download
the *killbill-profiles-killbill-X.Y.Z.war* to this directory, then run the script
to produce a *sn-killbill-profiles-killbill-X.Y.Z.war* version with the updates.

 [1]: https://github.com/SolarNetwork/killbill-invoice-formatter
 [2]: https://groups.google.com/d/msg/killbilling-users/of8TMBlzF7A/szSxkMUPCAAJ
 [3]: https://github.com/SolarNetwork/killbill/commit/fefb13bff5b105cc3411fb1625425013492fd130
