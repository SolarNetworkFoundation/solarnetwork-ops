#!/usr/bin/env bash

EXP_KEY=$(date +%Y%m%d)
EXP_DIR="/tmp/solarca-data-$EXP_KEY"
HOSTNAME="ca.solarnetwork.net"
PKI_P12_PASS="password.txt"
DEST_DB_INST_NAME="pki-tomcat-CA"

if [ $(id -u) -ne 0 ]; then
	echo "This script must be run as root."
	exit 1
fi

do_help () {
	cat 1>&2 <<EOF
Usage: $0 [arguments]

Arguments:
 -h <hostname>          - the CA hostname; defaults to ca.solarnetwork.net
 -i <dest db inst name> - the destination DB instance name; defaults to pki-tomcat-CA
 -w <p12 pw>            - the PKCS#12 password file to use; defaults to password.txt

EOF
}

while getopts ":h:i:w:" opt; do
	case $opt in
		h) HOSTNAME="${OPTARG}";;
		i) DEST_DB_INST_NAME="${OPTARG}";;
		w) PKI_P12_PASS="${OPTARG}";;
		*)
			echo "Unknown argument ${OPTARG}"
			do_help
			exit 1
	esac
done
shift $(($OPTIND - 1))

# create export dir
mkdir "$EXP_DIR"

if [ ! -e "$PKI_P12_PASS" ];then
	echo "P12 password file [$PKI_P12_PASS] not found. See -w argument."
	exit 1
fi
echo "Saving P12 password to $EXP_DIR/password.txt"
cp -a "$PKI_P12_PASS" "$EXP_DIR"

# get internal db password
echo "Saving internal DB password to $EXP_DIR/internal.txt"
grep internal= /var/lib/pki/rootca/conf/password.conf \
    |awk -F= '{print $2;}' >"$EXP_DIR/internal.txt"
chmod 600 "$EXP_DIR/internal.txt"

# export p12
echo "Exporting P12 to $EXP_DIR/ca.solarnetwork.net-ca-$EXP_KEY.p12"
PKCS12Export -d /var/lib/pki/rootca/alias -p "$EXP_DIR/internal.txt" \
    -o "$EXP_DIR/ca.solarnetwork.net-ca-$EXP_KEY.p12" -w "$PKI_P12_PASS"

# create CSR
echo "Exporting root CA CSR to $EXP_DIR/$HOSTNAME-ca-signing-$EXP_KEY.csr"
echo "-----BEGIN NEW CERTIFICATE REQUEST-----" >"$EXP_DIR/$HOSTNAME-ca-signing-$EXP_KEY.csr"
sed -n "/^ca.signing.certreq=/ s/^[^=]*=// p" </var/lib/pki/rootca/ca/conf/CS.cfg \
    >>"$EXP_DIR/$HOSTNAME-ca-signing-$EXP_KEY.csr"
echo "-----END NEW CERTIFICATE REQUEST-----" >>"$EXP_DIR/$HOSTNAME-ca-signing-$EXP_KEY.csr"

# get LDAP DB instance name
DB_INST_NAME=$(grep internaldb.database /etc/pki/rootca/ca/CS.cfg |awk -F= '{print $2;}')
if [ -z "$DB_INST_NAME" ]; then
	echo "DB instance name not found in /etc/pki/rootca/ca/CS.cfg"
	exit 1
fi
echo "DB instance name [$DB_INST_NAME] found in /etc/pki/rootca/ca/CS.cfg"

cd /lib/dirsrv/slapd-ca

# stop LDAP server
echo "Stopping directory server for data export"
systemctl stop dirsrv.target

# export entire DB
echo "Exporting director server complete data set to $EXP_DIR/$HOSTNAME-$EXP_KEY.ldif"
./db2ldif -n "$DB_INST_NAME" -a "/tmp/$HOSTNAME-$EXP_KEY.ldif"
mv -f "/tmp/$HOSTNAME-$EXP_KEY.ldif" "$EXP_DIR"
chown root:root "$EXP_DIR/$HOSTNAME-$EXP_KEY.ldif"

# export requests
echo "Exporting director server request data set to $EXP_DIR/$HOSTNAME-$EXP_KEY-requests.ldif"
./db2ldif -n "$DB_INST_NAME" -s "ou=ca,ou=requests,o=$DB_INST_NAME" -U \
    -a "/tmp/$HOSTNAME-$EXP_KEY-requests.ldif"
mv -f "/tmp/$HOSTNAME-$EXP_KEY-requests.ldif" "$EXP_DIR"
chown root:root "$EXP_DIR/$HOSTNAME-$EXP_KEY-requests.ldif"

# export certificates
echo "Exporting director server certificate data set to $EXP_DIR/$HOSTNAME-$EXP_KEY-certs.ldif"
./db2ldif -n "$DB_INST_NAME" -s "ou=certificateRepository,ou=ca,o=$DB_INST_NAME" -U \
    -a "/tmp/$HOSTNAME-$EXP_KEY-certs.ldif"
mv -f "/tmp/$HOSTNAME-$EXP_KEY-certs.ldif" "$EXP_DIR"
chown root:root "$EXP_DIR/$HOSTNAME-$EXP_KEY-certs.ldif"

# bring back up LDAP
echo "Starting directory server"
systemctl start dirsrv.target

# create migration import LDIF that renames rootca-CA to pki-tomcat-CA
echo "Creating migration import LDIF $EXP_DIR/$HOSTNAME-$EXP_KEY-migration.ldif"
cat "$EXP_DIR/$HOSTNAME-$EXP_KEY-requests.ldif" "$EXP_DIR/$HOSTNAME-$EXP_KEY-certs.ldif" \
    |sed -e "s/o=$DB_INST_NAME/o=$DEST_DB_INST_NAME/" \
    >"$EXP_DIR/$HOSTNAME-$EXP_KEY-migration.ldif"
chmod 600 "$EXP_DIR/$HOSTNAME-$EXP_KEY-migration.ldif"

# remove raw request/cert LDIF no longer needed
echo "Deleting temporary -requests and -certs LDIF files"
rm -f "$EXP_DIR/$HOSTNAME-$EXP_KEY-requests.ldif"
rm -f "$EXP_DIR/$HOSTNAME-$EXP_KEY-certs.ldif"
