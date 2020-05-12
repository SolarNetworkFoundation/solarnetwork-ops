# SolarNetwork Dogtag 10 Migration Giude

This guide outlines how to migrate from Dogtag 10.0 to a newer version. See the [Dogtag wiki][ref]
for more information.

# Export existing root cert from old CA

The first step is to export the existing data from the current (old) Dogtag CA.

```
sudo su -
mkdir /tmp/solarca-data
chgrp wheel /tmp/solarca-data
chmod 750 /tmp/solarca-data

echo Secret.123 >/tmp/solarca-data/password.txt

grep internal= /var/lib/pki/rootca/conf/password.conf \
    |awk -F= '{print $2;}' > /tmp/solarca-data/internal.txt

PKCS12Export -d /var/lib/pki/rootca/alias -p internal.txt \
    -o /tmp/solarca-data/ca.solarnetwork.net.p12 -w /tmp/solarca-data/password.txt

echo "-----BEGIN NEW CERTIFICATE REQUEST-----" >/tmp/solarca-data/ca.solarnetwork.net.csr
sed -n "/^ca.signing.certreq=/ s/^[^=]*=// p" </var/lib/pki/rootca/ca/conf/CS.cfg \
    >>/tmp/solarca-data/ca.solarnetwork.net.csr
echo "-----END NEW CERTIFICATE REQUEST-----" >>/tmp/solarca-data/ca.solarnetwork.net.csr
```

# Export existing LDAP data

Export the CA data from LDAP on the current Dogtag CA:

```sh
# get LDAP DB name, e.g. "rootca-CA"
grep internaldb.database /etc/pki/rootca/ca/CS.cfg

# stop LDAP server
systemctl stop dirsrv.target

cd /lib/dirsrv/slapd-ca

# export entire DB
./db2ldif -n "rootca-CA" -a /tmp/ca.solarnetwork.net-20190715.ldif
mv /tmp/ca.solarnetwork.net-20190715.ldif /tmp/solarca-data

# export requests
./db2ldif -n "rootca-CA" -s "ou=ca,ou=requests,o=rootca-CA" -U \
    -a /tmp/ca.solarnetwork.net-20190715-requests.ldif
mv /tmp/ca.solarnetwork.net-20190715-requests.ldif /tmp/solarca-data

# export certificates
./db2ldif -n "rootca-CA" -s "ou=certificateRepository,ou=ca,o=rootca-CA" -U \
    -a /tmp/ca.solarnetwork.net-20190715-certs.ldif
mv /tmp/ca.solarnetwork.net-20190715-certs.ldif /tmp/solarca-data

# bring back up LDAP (optional, if needed)
systemctl start dirsrv.target
```

Assuming that all goes well, you should end up with output like this:

```
Exported ldif file: /tmp/solarca-data/ca.solarnetwork.net-20190715.ldif
ldiffile: /tmp/solarca-data/ca.solarnetwork.net-20190715.ldif
[14/Jul/2019:20:31:20 -0400] - export rootca-CA: Processed 759 entries (100%).
[14/Jul/2019:20:31:21 -0400] - All database threads now stopped

Exported ldif file: /tmp/solarca-data/ca.solarnetwork.net-20190715-requests.ldif
ldiffile: /tmp/solarca-data/ca.solarnetwork.net-20190715-requests.ldif
[14/Jul/2019:20:32:28 -0400] - export rootca-CA: Processed 370 entries (100%).
[14/Jul/2019:20:32:28 -0400] - All database threads now stopped

Exported ldif file: /tmp/solarca-data/ca.solarnetwork.net-20190715-certs.ldif
ldiffile: /tmp/solarca-data/ca.solarnetwork.net-20190715-certs.ldif
[14/Jul/2019:20:33:12 -0400] - export rootca-CA: Processed 349 entries (100%).
[14/Jul/2019:20:33:12 -0400] - All database threads now stopped
```

# Migrate to new Dogtag DN

This last step merges the `-requests.ldif` and `-certs.ldif` files while renaming the DN from 
Dogtag 10.0 style to Dogtag >= 10.6 style:

```sh
cat /tmp/solarca-data/ca.solarnetwork.net-20190715-requests.ldif /tmp/solarca-data/ca.solarnetwork.net-20190715-certs.ldif \
    |sed -e 's/o=rootca-CA/o=pki-tomcat-CA/' \
    >/tmp/solarca-data/ca.solarnetworkdev.net-20190715-migration.ldif
```

# Setup production configuration

We'll use the `setup-solarca-fedora.sh` script in the **../setup/vagrant/solardb/bin** directory to
configure the new CA. Create a `../setup/vagrant/local/solarca-prod` configuration by copying the
`../setup/vagrant/solarca` directory:

```sh
cd ../setup/vagrant
cp -a solarca local/solarca-prod
cd local/solarca-prod/local
rsync -a 'ssh -i ~/keys/matt-solarnetwork.pem' ec2-user@ca.solarnetwork.net:/tmp/solarca-data/ ./
```

We'll place all our configuration into the `solarca-prod/local` directory. Of particular interest
will be the `local/ca-migrate.cfg` Dogtag setup configuration. This will include some absolute file
paths that must point to the files as they are uploaded on the server. This guide uses
`/vagrant/solarca-prod/local`. The `cfg` file also contains the password to use for the root P12
key store.

# Configure new CA

Then on new CA (`new-ca.solarnetwork.net` in the follow), run migration/setup, substituting
placeholders appropriately:

```sh
# cd back to vagrant/local dir
cd ../..

# sync solarca-prod conf to new server
rsync -a --copy-unsafe-links 'ssh -i ~/keys/matt-solarnetwork.pem' solarca-prod ec2-user@new-ca.solarnetwork.net:/tmp/

# ssh to new server
ssh -i  ~/keys/matt-solarnetwork.pem ec2-user@new-ca.solarnetwork.net

sudo su -

# Create symlink to dir so setup-solarca-fedora.sh script works
cd /
ln -s /tmp/solarca-prod /vagrant

# Fix permissions of cert/key in root keystore
#pki pkcs12-cert-mod "caSigningCert cert-rootca CA" \
#    --pkcs12-file /vagrant/local/ca.solarnetwork.net.p12 \
#    --pkcs12-password-file /vagrant/local/password.txt \
#    --trust-flags "CTu,Cu,Cu"

# Run setup script
cd /tmp/solarca-prod
./bin/setup-solarca-fedora.sh -u \
    -c local/ca-migrate.cfg \
    -E ${CA_ADMIN_PASS} \
    -h ca.solarnetwork.net \
    -I ${SN_IN_JKS_PASS} \
    -i in.solarnetwork.net \
    -K suagent@solarnetwork.net \
    -k ${CA_AGENT_P12_PASS} \
    -L ${CA_AGENT_JKS_PASS} \
    -l ${SN_TRUST_JKS_PASS} \
    -s dc=solarnetwork,dc=net \
    -t local/ca.solarnetwork.net-20190715-migration.ldif

```

[ref]: https://www.dogtagpki.org/wiki/PKI_10.5_Installing_CA_with_Existing_Certificates_using_PKCS12_File