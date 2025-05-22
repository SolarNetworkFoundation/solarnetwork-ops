# SolarSSH FreeBSD 14.2 Server Setup

# EFS mount

```sh
mkdir /mnt/cert-support
mount -t nfs -o nfsv4 `fetch -q -o - http://169.254.169.254/latest/meta-data/placement/availability-zone`.fs-2b965081.efs.us-west-2.amazonaws.com:/ /mnt/cert-support
```

# SNF Repo

Create `/usr/local/etc/ssl/certs/snf.cert` SNF package certificate then 
`/usr/local/etc/pkg/repos/snf.conf` repository configuration:

```
snf: {
        url: "http://snf-freebsd-repo.s3-website-us-west-2.amazonaws.com/solarssh_142x64-HEAD",
        mirror_type: "http",
        signature_type: "pubkey",
        pubkey: "/usr/local/etc/ssl/certs/snf.cert",
        enabled: yes,
        priority: 100
}
```

# Software setup

Installed Tomcat and Munin Node:

```sh
pkg install -r snf tomcat101 tomcat-native2 py311-certbot py311-certbot-dns-route53 munin-node
```

Created `/usr/local/etc/rc.d/cert_support`:

```sh
touch /usr/local/etc/rc.d/cert_support
vi /usr/local/etc/rc.d/cert_support # fill in content
chmod 755 /usr/local/etc/rc.d/cert_support
```

Configured `/etc/rc.conf`:

```
nfs_client_enable="YES"
cert_support_enable="YES"
munin_node_enable="YES"
tomcat101_enable="YES"
tomcat101_stdout="/dev/null"
tomcat101_java_opts="-Dsolarssh.logdir=/usr/local/solarssh/logs -Dorg.apache.tomcat.websocket.DISABLE_BUILTIN_EXTENSIONS=true"
```

The [DISABLE_BUILTIN_EXTENSIONS=true is added](https://stackoverflow.com/questions/28894316/tomcat-jsr356-websocket-disable-permessage-deflate-compression)
to work around a web socket issue.

Configured `/usr/local/etc/munin/munin-node.conf` with

```
# set host name
host_name ssh.solarnetwork.net

# add allow
allow ^10\.0\..*$
```

# Configure SolarSSH

Tomcat lives in `/usr/local/apache-tomcat-10.1`. Configure `conf/server.xml` and 
`conf/Catalina/localhost/ROOT.xml` as shown here (fill in actual password in `ROOT.xml`). Then

```sh
mkdir /usr/local/solarssh
chgrp www /usr/local/solarssh
chmod 750 /usr/local/solarssh
cd /usr/local/solarssh
ln -s ../apache-tomcat-10.1/logs
vi logback.xml # as provided
chmod 640 solarssh-1.1.0-plain.war
ln -s solarssh-1.1.0-plain.war solarssh.war
vi sshd-sever-key # secret
mkdir webapps
chmod 650 webapps
chgrp www *
```

# Configure Elastic IP

Set Elastic IP on VM.

# Let's Encrypt SSL certificate

Created `/etc/periodic.conf` with:

```
export CRYPTOGRAPHY_OPENSSL_NO_LEGACY=1
weekly_certbot_enable="YES"
```

Set up credentials for AWS:

```sh
mkdir ~/.aws
touch ~/.aws/config
chmod 600 ~/.aws/config
```

Then configured AWS credentials `~/.aws/config` like

```
[default]
aws_access_key_id=AKIAIOSFODNN7EXAMPLE
aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

Created initial certificate via:

```sh
certbot certonly --dns-route53 -d ssh.solarnetwork.net
```

Created renewal hook script `/usr/local/etc/letsencrypt/renewal-hooks/deploy/solarssh.sh`

```sh
#!/bin/sh

set -e

for domain in $RENEWED_DOMAINS; do
		daemon_cert_root=/mnt/cert-support/tls

		# Make sure the certificate and private key files are
		# never world readable, even just for an instant while
		# we're copying them into daemon_cert_root.
		umask 077

		cp -f "$RENEWED_LINEAGE/cert.pem" "$daemon_cert_root/$domain.cert"
		cp -f "$RENEWED_LINEAGE/chain.pem" "$daemon_cert_root/$domain.chain"
		cp -f "$RENEWED_LINEAGE/fullchain.pem" "$daemon_cert_root/$domain.fullchain"
		cp -f "$RENEWED_LINEAGE/privkey.pem" "$daemon_cert_root/$domain.key"

		# Apply the proper file ownership and permissions for
		# the daemon to read its certificate and key.
		chmod 440 "$daemon_cert_root/$domain.cert" \
				"$daemon_cert_root/$domain.chain" \
				"$daemon_cert_root/$domain.fullchain" \
				"$daemon_cert_root/$domain.key"
done
service tomcat101 reload >/dev/null
```

Ensure proper execute permissions set:

```sh
chmod 755 /usr/local/etc/letsencrypt/renewal-hooks/deploy/solarssh.sh
```

Run the renew post-hook manually (**note** command below is for `sh`, **not** `csh`):

```sh
CRYPTOGRAPHY_OPENSSL_NO_LEGACY=1 RENEWED_DOMAINS="ssh.solarnetwork.net" \
  RENEWED_LINEAGE="/usr/local/etc/letsencrypt/live/ssh.solarnetwork.net" \
  /usr/local/etc/letsencrypt/renewal-hooks/deploy/solarssh.sh
```
