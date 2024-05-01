# SN DB Maintenance 2023-08-16

This maintenance is to add infrastructure to support SolarDNP3:

 * add dnp3.solarnetwork.net Let's Encrypt certificate
 
# Let's Encrypt certificate

Build on the SolarIn Proxy support for Let's Encrypt certificate management, with certificates
saved to EFS so the SolarDNP3 application has access to the certificate.

Created initial certificate via:

```sh
certbot certonly --dns-route53 -d dnp3.solarnetwork.net
```

Run the renew post-hook manually (**note** command below is for `sh`, **not** `csh`) to copy to EFS:

```sh
RENEWED_DOMAINS="dnp3.solarnetwork.net" \
  RENEWED_LINEAGE="/usr/local/etc/letsencrypt/live/dnp3.solarnetwork.net" \
  /usr/local/etc/letsencrypt/renewal-hooks/deploy/solarin.sh
```
