# SolarNetwork Dogtag 10 Admin Guide

This guide describes useful information about the `ca.solarnetwork.net`
system, which is used to administer SolarNode certificates.

# EC2

The server is an EC2 instance. Connect via `ssh` like this:

	ssh -i ~/keys/matt-solarnetwork.pem ec2-user@ca.solarnetwork.net

# VNC

The server runs VNC, which you can tunnel over SSH like this:

	ssh -CL5901:localhost:5901 -i ~/keys/matt-solarnetwork.pem ec2-user@ca.solarnetwork.net

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

## Renewing the suagent certificate

The certificate serial number can be obtained by printing out the certificate
details from the **configuration/dogtag-client.jks** keystore:

	keytool -list -v -keystore dogtag-client.jks -alias suagent

**Note** that the serial number will show in **hex** but must be entered in
**decimal** in Dogtag.

After renewing the **suagent** certificate, it must be installed for SolarNetwork
to use.

  1. Export the certificate in PEM format.
  2. The private key is stored in **configuration/dogtag-client.jks** in SolarNetwork.
     The password for this file can be found in
     **repository/local/net.solarnetwork.central.user.pki.dogtag.properties**.
     Import it with the `keytool -importcert` comment, noting the `-alias` should be the
     same as the existing entry. For example:

     	 keytool -importcert -keystore dogtag-client.jks -alias suagent -file suagent.crt

  3. Now the certificate must be imported into Dogtag. Connect to VNC as described
     earlier. Launch `pkiconsole` and log in as the `caadmin` user:

     	pkiconsole https://ca.solarnetwork.net:8443/ca

     Note that the **caadmin** OS user password is _different_ from the **caadmin**
     PKI user's password (`pki_admin_password`)!
  4. Select **Configuration > Users and Groups** and then select the **suagent** user.
  5. Click the **Certificates** button.
  6. Click the **Import** button.
  7. Import the new certificate. It will be added along with the old certificate.
  8. Restart SolarNetwork for the change to take effect.

## Renewing the caadmin certificate

The process is similar to that listed above for the **suagent** certificate, except
the certificate is not stored in any Java keychain. Once the certificate has been 
renewed, log into the PKI Console and import the the renewed certificate under the
**Configuration > Users and Groups** UI pane for the **caadmin** user.

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

## Renew via command line

	certutil -D -d /etc/pki/rootca/alias -n 'Server-Cert cert-rootca'
	certutil -A -d /etc/pki/rootca/alias -n 'Server-Cert cert-rootca' -t 'cu,cu,cu' -a -i ca.solarnetwork.net.crt

	certutil -D -d /etc/pki/rootca/alias -n 'ocspSigningCert cert-rootca CA'
	certutil -A -d /etc/pki/rootca/alias -n 'ocspSigningCert cert-rootca CA' -t 'u,u,u' -a -i SolarNetwork-Root-OCSP-Signing-Certificate.crt

	certutil -D -d /etc/pki/rootca/alias -n 'subsystemCert cert-rootca CA'
	certutil -A -d /etc/pki/rootca/alias -n 'subsystemCert cert-rootca CA' -t 'u,u,u' -a -i SolarNetwork-Root-CA-Subsystem-Certificate.crt

	certutil -D -d /etc/pki/rootca/alias -n 'auditSigningCert cert-rootca CA'
	certutil -A -d /etc/pki/rootca/alias -n 'auditSigningCert cert-rootca CA' -t 'u,u,Pu' -a -i SolarNetwork-Root-CA-Audit-Signing-Certificate.crt

## Or, renew via PKI console

Go to **System Keys and Certificates > Local Certificates** (via left-hand tree > tab).
For each cert, click **Add/Renew**, **Next**, **Install a certificate**, **Next**.

For **OCSP** or **Server** can choose that option from the menu, otherwise choose **Other**. Then **Next**.

Copy/paste in the certificate, then **Next**. If selected **Other**, enter in the exact nickname that matches
the older certificate, e.g. `subsystemCert cert-rootca CA`. Then **Next** to complete.
Finally, delete the expired/expiring certificate with the smaller serial number by
selecting that certificate in the **Local Certificates** list and clicking the **Delete**
button.

## Note on SolarNetwork Root CA Subsystem Certificate

The **pkidbuser** and **CA-ca.solarnetwork.net-8443** users need the renewed certificate for this user, in the PKI Console visit the
**Configuration > Users and Groups** UI pane for the **pkidbuser** user. Click the 
**Certificates** button, then **Import** and paste in the renewed certificate.
