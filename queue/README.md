# SolarIn Proxy, MQTT

This directory contains setup configuration for the SolarIn proxy server and SolarIn/MQTT server.

# SolarIn Proxy

The entire contents of the `freebsd/` directory is meant to be tarred up and extracted on a new EC2
instance to provide the initial configuration. Files ending in `.tmpl` are templates that need to be
integrated into the corresponding file whose name omits the `.tmpl` suffix.


## Packages

Initial package installation:

```sh
pkg install --repository FreeBSD py39-certbot py39-certbot-dns-route53
pkg install --repository snf nginx postfix 
```


## Postfix MTA setup

The built-in Sendmail with FreeBSD does not support SASL which is required to use the SES smart host.
Installed Postfix instead. See
[the SES Postfix guide](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/postfix.html)	for
more details. To change Postfix to the default MTA, run:

```
mkdir -p /usr/local/etc/mail
install -m 0644 /usr/local/share/postfix/mailer.conf.postfix /usr/local/etc/mail/mailer.conf
```

Once the `/usr/local/etc/postfix/sasl_passwd` credentials have been configured, and 
`/etc/aliases` has been updated with `root: operations@solarnetwork.net`, be sure to run:

```
# create SASL database
postmap hash:/usr/local/etc/postfix/sasl_passwd

# update alias database
newaliases
```


## EFS mount

Setup EFS mount for certificate storage. The `cert-support` service will mount the filesystem at
boot:

```sh
mkdir /mnt/cert-support
```


## Certbot config

Create the `~root/.aws/config` file like:

```
[default]
aws_access_key_id=TOKEN_ID
aws_secret_access_key=TOKEN_SECRET
```

