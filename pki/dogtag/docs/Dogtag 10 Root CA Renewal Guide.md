# SolarNetwork Dogtag 10 Root CA Renewal Giude

This guide outlines how to renew the root CA signing certificate in Dogtag 10.6. See the
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
option in web GUI.

```
# NOTE the Request ID from before is used
$ pki -d ~/.dogtag/nssdb -n 'PKI Administrator for solarnetworkdev.net' -c Secret.123  \
    ca-cert-request-review 10018 --action approve
```


[ref]: https://www.dogtagpki.org/wiki/System_Certificate_Renewal