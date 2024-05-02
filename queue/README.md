# SolarIn Proxy, MQTT

This directory contains setup configuration for the SolarIn proxy server and SolarIn/MQTT server.

# SolarIn Proxy

The entire contents of the `freebsd/` directory is meant to be tarred up and extracted on a new EC2
instance to provide the initial configuration. Files ending in `.tmpl` are templates that need to be
integrated into the corresponding file whose name omits the `.tmpl` suffix.

## EFS mount

Setup EFS mount for certificate storage. The `cert-support` service will mount the filesystem at
boot:

```sh
mkdir /mnt/cert-support
```

## Packages

Initial package installation then:

```sh
pkg install --repository FreeBSD py39-certbot py39-certbot-dns-route53
pkg install --repository snf nginx postfix 
```

## Certbot config

Create the `~root/.aws/config` file like:

```
[default]
aws_access_key_id=TOKEN_ID
aws_secret_access_key=TOKEN_SECRET
```

