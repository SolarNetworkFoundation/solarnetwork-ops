# SolarNetwork Dogtag 10 Admin Guide

This guide describes useful information about the `ca.solarnetwork.net`
system, which is used to administer SolarNode certificates.

# EC2

The server is an EC2 instance. Connect via `ssh` like this:

	ssh -i ~/keys/matt-solarnetwork.pem fedora@ca.solarnetwork.net

# VNC

The server runs VNC, which you can tunnel over SSH like this:

	ssh -CL5901:localhost:5901 -i ~/keys/matt-solarnetwork.pem fedora@ca.solarnetwork.net

If VNC is not running or working, you can try restarting the service via

	systemctl restart vncserver@:1

# Restarting server

If the server ever restarts, ssh in and verify the Dogtag services like:

	systemctl status dirsrv\@ca.target
	systemctl status pki-tomcatd\@rootca.service

If anything is not running, start it by changing `status` to `start` in the
associated service command.

# Renewing Agent certificates

Agent certificates must be renewed before they expire. Find the certificate
ID of the agent certificate to renew, e.g. look in **Firefox > Preferences >
Advanced > Certificates**.

  1. Go to https://ca.solarnetwork.net:8443/, click on **End User Services**
  2. Click on **Renewal: Renew certificate to be manually approved by agents**
  3. Enter the certificate serial number to renew. _The serial number is listed
     in hex in Firefox: convert the hex value to decimal here._
  4. Note the resulting request ID. Go back to https://ca.solarnetwork.net:8443/
  5. Click on **Agent Services**
  6. Click on **Show renewal requests** and search for the request ID just created.
  7. The validity period defaults to 180 days. Manually modify this to **365 days**.
  8. Approve the request.
  9. Go back to https://ca.solarnetwork.net:8443/, click on **End User Services**.
  10. On **Check Request Status** enter the request ID, the click on the **Issued
      certificate** link.
  11. At the bottom, click on the **Import Certificate** button.

# 389 LDAP Server

From VNC as the `caadmin` user, can access admin UI like

```
389-console -u 'cn=Directory Manager' -a http://localhost:9830/
```


# System certificate command line utilities

## List certificates

```
certutil -L -d /var/lib/pki/rootca/alias

Certificate Nickname                                         Trust Attributes
                                                             SSL,S/MIME,JAR/XPI

Server-Cert cert-rootca                                      cu,cu,cu
subsystemCert cert-rootca CA                                 u,u,u
caSigningCert cert-rootca CA                                 CTu,Cu,Cu
ocspSigningCert cert-rootca CA                               cu,cu,cu
auditSigningCert cert-rootca CA                              u,u,Pu
```

## Modify trust attributes

If the certificates do not have the proper trust attributes, it will not function properly.
Update the attributes with `certutil`, for example:

```
certutil -M -d /var/lib/pki/rootca/alias -n 'auditSigningCert cert-rootca CA' -t 'u,u,Pu' 
```

The trust arguments, from the `certutil` man page, are:

```
-t trustargs
   Specify the trust attributes to modify in an existing certificate or to apply to a certificate when creating it or adding it to a database. There are three available
   trust categories for each certificate, expressed in the order SSL, email, object signing for each trust setting. In each category position, use none, any, or all of the
   attribute codes:

   ·   p - Valid peer

   ·   P - Trusted peer (implies p)

   ·   c - Valid CA

   ·   T - Trusted CA (implies c)

   ·   C - trusted CA for client authentication (ssl server only)

   ·   u - user

   The attribute codes for the categories are separated by commas, and the entire set of attributes enclosed by quotation marks. For example:

   -t "TCu,Cu,Tuw"
```

# Renewing CA System certificates

Before CA system certificates expire, such as the `CN=CA Signing Certificate`,
they must be renewed. Submit renewal requests and approve them using the web
GUI. Then renew via the command line **or** the console:

## List available system certificates

List the aliases (nicknames) for the system certificates (as `root` user):

```
$ pki-server subsystem-cert-find ca

-----------------
5 entries matched
-----------------
  Serial No: 65554
  Cert ID: signing
  Nickname: caSigningCert cert-rootca CA
  Token: internal

  Serial No: 65536
  Cert ID: ocsp_signing
  Nickname: ocspSigningCert cert-pki-tomcat CA
  Token: internal

  Serial No: 65537
  Cert ID: sslserver
  Nickname: Server-Cert cert-pki-tomcat
  Token: internal

  Serial No: 65538
  Cert ID: subsystem
  Nickname: subsystemCert cert-pki-tomcat
  Token: internal

  Serial No: 65539
  Cert ID: audit_signing
  Nickname: auditSigningCert cert-pki-tomcat CA
  Token: internal
```

Can then view certificate dates for a given nickname:

```
$ certutil -L -d /var/lib/pki/pki-tomcat/alias -n "caSigningCert cert-rootca CA" | egrep "Serial|Before|After"

        Serial Number: 65554 (0x10012)
            Not Before: Fri May 15 04:44:26 2020
            Not After : Tue May 15 04:44:26 2040

```

Here's a one-liner to print out the dates for all subsystem certificates:

```bash
pki-server subsystem-cert-find ca |grep Nickname |awk 'BEGIN { FS = ": " }; {print $2}' \
  |while read nick; do echo "$nick:"; \
  certutil -L -d /var/lib/pki/pki-tomcat/alias -n "$nick" |egrep "Serial|Before|After"; done
```

## Submit system certificate renewal requests 

As the `caadmin` user, for each expiring system certificate run:

```
[caadmin@ca ~]$ pki ca-cert-request-submit --profile caManualRenewal --serial 0x10000 --renewal
```

A typical result looks like this:

```
-----------------------------
Submitted certificate request
-----------------------------
  Request ID: 10139
  Type: renewal
  Request Status: pending
  Operation Result: success
```

Note the **Request ID** values. Then approve each request:

## Approve system certificate renewal requests

```
pki -n 'PKI Administrator for solarnetwork.net' ca-cert-request-approve 10137
```

A typical response looks like this:

```
----------------------------------
Approved certificate request 10137
----------------------------------
  Request ID: 10137
  Type: renewal
  Request Status: complete
  Operation Result: success
  Certificate ID: 0x1007e
```

Note the **Certificate ID** values. Then download each certificate to a file:

## Download renewed system certificates

```
[caadmin@ca ~]$ pki ca-cert-export 0x1007e --output-file ocspSigningCert-2020-0x1007e.crt
```

## Install renewed system certificates

Finally, as the `root` user, install the certificates.

```
[root ~caadmin]$ systemctl stop pki-tomcatd@pki-tomcat.service
[root ~caadmin]$ pki-server subsystem-cert-update ca ocsp_signing --cert ocspSigningCert-2020-0x1007e.crt
[root ~caadmin]$ pki-server subsystem-cert-update ca sslserver --cert Server-Cert-2020-0x1007f.crt
[root ~caadmin]$ pki-server subsystem-cert-update ca subsystem --cert subsystemCert-2020-0x10081.crt
[root ~caadmin]$ pki-server subsystem-cert-update ca audit_signing --cert auditSigningCert-2020-0x10080.crt
[root ~caadmin]$ systemctl start pki-tomcatd@pki-tomcat.service
```

# List users

As the `caadmin` OS user:

```
pki -d ~/.dogtag/nssdb -n 'PKI Administrator for solarnetwork.net' ca-user-find

-----------------
4 entries matched
-----------------
  User ID: CA-ca.solarnetwork.net-8443
  Full name: CA-ca.solarnetwork.net-8443

  User ID: caadmin
  Full name: caadmin

  User ID: pkidbuser
  Full name: pkidbuser

  User ID: suagent
  Full name: SolarUser Agent
```

> :warning: **Note** that the `-n` argument might be `caadmin` depending on the state of the NSS DB.
> Also note that the `-d` default is `~/.dogtag/nssdb` so that argument can be omitted.

# List user certificates

```
pki -d ~/.dogtag/nssdb -n 'PKI Administrator for solarnetwork.net' ca-user-cert-find suagent

  Cert ID: 2;65545;CN=SolarNetwork Root CA,OU=SolarNetwork Certification Authority,O=SolarNetwork;UID=suagent,E=suagent@solarnetwork.net,CN=suagent,OU=SolarUser,O=SolarNetwork
  Version: 2
  Serial Number: 0x10009
  Issuer: CN=SolarNetwork Root CA,OU=SolarNetwork Certification Authority,O=SolarNetwork
  Subject: UID=suagent,E=suagent@solarnetwork.net,CN=suagent,OU=SolarUser,O=SolarNetwork
```

# Show certificate details
```
pki ca-cert-show 0x100c7

  Serial Number: 0x100c7
  Subject DN: UID=suagent,E=suagent@solarnetwork.net,CN=suagent,OU=SolarUser,O=SolarNetwork
  Issuer DN: CN=SolarNetwork Root CA,OU=SolarNetwork Certification Authority,O=SolarNetwork
  Status: VALID
  Not Valid Before: Wed Apr 28 21:23:57 UTC 2021
  Not Valid After: Mon Oct 25 21:23:57 UTC 2021
```

# Renew user certificate

```
# request cert renew
pki -d ~/.dogtag/nssdb -n 'PKI Administrator for solarnetwork.net' ca-cert-request-submit \
    --profile caManualRenewal --renewal --serial 0x10009

-----------------------------
Submitted certificate request
-----------------------------
  Request ID: 10075
  Type: renewal
  Request Status: complete
  Operation Result: success
  Certificate ID: 0x10040

# NOTE if Status is pending, then approve else skip this step
# pki -d ~/.dogtag/nssdb -n 'PKI Administrator for solarnetwork.net' ca-cert-request-approve 10075

# export
pki -n 'PKI Administrator for solarnetwork.net' ca-cert-export 0x10040 --output-file pki-suagent-20201118.crt

# add to user
pki -n 'PKI Administrator for solarnetwork.net' ca-user-cert-add suagent --input pki-suagent-20201118.crt

# import cert to nssdb
pki -n 'PKI Administrator for solarnetwork.net' client-cert-import suagent --serial 0x10040

# export cert + key to p12
pki -n 'PKI Administrator for solarnetwork.net' pkcs12-cert-import suagent \
    --no-trust-flags --no-chain --key-encryption 'PBE/SHA1/DES3/CBC' \
    --pkcs12-file pki-suagent-20201118.p12 \
    --pkcs12-password Secret.123
```

# Create java keystore for client apps

Convert the `.p12` keystore into a `.jks` for the apps to use:

```
# convet keystore format to JKS
keytool -importkeystore -srckeystore \
	~/Documents/SNF/Sysadmin/CA/Certs/pki-2020/pki-suagent-202109-0x100dd.p12 \
	-srcstoretype pkcs12 \
	-srcstorepass 'PASSWORD' \
	-srckeypass 'PASSWORD' \
	-destkeystore dogtag-client-202109.jks \
	-deststoretype jks \
	-deststorepass 'PASSWORD' \
	-destkeypass 'PASSWORD' \
	-noprompt \
	-srcalias suagent \
	-destalias suagent

# import CA cert
keytool -importcert -keystore dogtag-client-202109.jks \
	-alias ca \
	-file ~/Documents/SNF/Sysadmin/CA/Certs/pki-2020/ca-root-2020.crt
```

Afterwards the `ca` and `suagent` certificates should be present:

```
keytool -list -keystore dogtag-client-202109.jks                                                                                  

Your keystore contains 2 entries

ca, 28/09/2021, trustedCertEntry, 
Certificate fingerprint (SHA-256): F6:1F:E9:CA:03:08:3F:C2:87:00:C0:0E:B7:07:11:3B:7E:44:85:77:65:DD:24:AC:8B:71:7B:6B:83:58:96:8A
suagent, 28/09/2021, PrivateKeyEntry, 
Certificate fingerprint (SHA-256): FD:2B:7E:8C:14:51:42:B9:34:78:3B:59:AC:4C:B3:E4:D5:67:3F:F6:DC:30:AF:90:7C:BB:E8:B7:22:D2:CE:29
```
