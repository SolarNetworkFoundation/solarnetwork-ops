# SolarNetwork Dogtag 10 Root CA Renewal Giude

This guide outlines how to renew the root CA signing certificate in Dogtag 10.8. See the
[Dogtag wiki][ref] for more information.

## Request renewal

```
$ sudo su -
$ pki ca-cert-request-submit --profile caManualRenewal --serial 0x1  --renewal

-----------------------------
Submitted certificate request
-----------------------------
  Request ID: 10018
  Type: renewal
  Request Status: pending
  Operation Result: success
```

## Approve request  

**NOTE** for non-CA, can use command line. For CA, must use _Bypass CA notAfter constraint_
option in web GUI. For non-CA only:

```
# NOTE the Request ID from before is used
$ pki -d ~/.dogtag/nssdb -n 'PKI Administrator for solarnetworkdev.net' -c Secret.123  \
    ca-cert-request-approve 10018
```

Keep note of approved certificate ID, e.g. `0x10011`.

## Download certificate

```sh
$ pki ca-cert-export 0x10011 --output-file ca_signing.crt
```

## Install system cert

```sh
$ systemctl stop pki-tomcatd@pki-tomcat.service

$ pki-server subsystem-cert-update ca signing --cert ca_signing.crt

# Get NSS password
$ grep internal= /var/lib/pki/pki-tomcat/conf/password.conf |awk -F= '{print $2;}'

# Fix trust attributes
$ certutil -M -d /var/lib/pki/pki-tomcat/alias -n 'caSigningCert cert-rootca CA' -t 'CT,C,C'

# Confirm by viewing
$ certutil -L -d /var/lib/pki/pki-tomcat/alias/ -n 'caSigningCert cert-rootca CA'

# Start PKI
$ systemctl start pki-tomcatd@pki-tomcat.service
```

## Renew other subsystem certificates

List serial numbers with

```sh
$ pki-server subsystem-cert-find ca
```

```
# request
$ pki ca-cert-request-submit --profile caManualRenewal --serial 65536 --renewal
$ pki ca-cert-request-submit --profile caManualRenewal --serial 65537 --renewal
$ pki ca-cert-request-submit --profile caManualRenewal --serial 65538 --renewal
$ pki ca-cert-request-submit --profile caManualRenewal --serial 65539 --renewal

# approve
$ pki -n 'PKI Administrator for solarnetworkdev.net' ca-cert-request-approve 10019
$ pki -n 'PKI Administrator for solarnetworkdev.net' ca-cert-request-approve 10020
$ pki -n 'PKI Administrator for solarnetworkdev.net' ca-cert-request-approve 10021
$ pki -n 'PKI Administrator for solarnetworkdev.net' ca-cert-request-approve 10022

# export
$ pki ca-cert-export 0x10012 --output-file ca_ocsp_signing.crt
$ pki ca-cert-export 0x10013 --output-file sslserver.crt
$ pki ca-cert-export 0x10014 --output-file subsystem.crt
$ pki ca-cert-export 0x10015 --output-file ca_audit_signing.crt
```

## Install other subsystem certs

```sh
$ systemctl stop pki-tomcatd@pki-tomcat.service

$ pki-server subsystem-cert-update ca ocsp_signing --cert ca_ocsp_signing.crt
$ pki-server subsystem-cert-update ca sslserver --cert sslserver.crt
$ pki-server subsystem-cert-update ca subsystem --cert subsystem.crt
$ pki-server subsystem-cert-update ca audit_signing --cert ca_audit_signing.crt


# Get NSS password
$ grep internal= /var/lib/pki/pki-tomcat/conf/password.conf |awk -F= '{print $2;}'

# Fix trust attributes (audit cert)
$ certutil -M -d /var/lib/pki/pki-tomcat/alias -n 'auditSigningCert cert-pki-tomcat CA' -t 'u,u,Pu'

# Confirm by viewing
$ certutil -L -d /var/lib/pki/pki-tomcat/alias -n 'caSigningCert cert-rootca CA'

# Start PKI
$ systemctl start pki-tomcatd@pki-tomcat.service
```


[ref]: https://www.dogtagpki.org/wiki/System_Certificate_Renewal
