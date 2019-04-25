#!/usr/bin/env bash

CA_CONF="example/ca.cfg"
CA_SEC_DOMAIN_NAME="SolarNetworkDev"
CA_SEC_DOMAIN_PASS="Secret.123"
CA_ADMIN_LOGIN="caadmin"
CA_ADMIN_HOME="/home/caadmin"
CA_ADMIN_PASS="caadmin"
PKI_ADMIN_P12_PASS="Secret.123"
CA_AGENT_UID="suagent"
CA_AGENT_NAME="SolarUser Agent"
CA_AGENT_EMAIL="sugagent@solarnetworkdev.net"
CA_AGENT_P12_PASS="Secret.123"
CA_AGENT_JKS_PASS="dev123"
DRY_RUN=""
DS_INST_NAME="ca"
DS_ROOT_PASS="admin"
DS_SUFFIX="dc=solarnetworkdev,dc=net"
DS_IMPORT_LDIF=""
HOSTNAME="ca.solarnetworkdev.net"
SN_PROFILE_CONF="example/SolarNode.cfg"
SN_IN_DNS_NAME="solarnetworkdev.net"
SN_IN_JKS_PASS="dev123"
SN_TRUST_JKS_PASS="dev123"
UPDATE_PKGS=""
VERBOSE=""

if [ $(id -u) -ne 0 ]; then
	echo "This script must be run as root."
	exit 1
fi

do_help () {
	cat 1>&2 <<EOF
Usage: $0 [-nuv]

Arguments:
 -A <admin username>    - the CA Admin OS username; defaults to caadmin
 -a <admin home>        - the CA Admin OS home; defafults to $CA_ADMIN_HOME
 -c <PKI config path>   - path to the Dogtag CA configuration file to use; defaults to example/ca.cfg
 -d <profile path>      - path to the Dogtag SolarNode profile configuration file to use; defaults to
                          example/SolarNode.cfg
 -E <admin pw>          - the CA admin OS user password; defaults to caadmin
 -e <pki admin p12 pw>  - the PKI Admin PKCS#12 password, i.e. from ca.cfg; defaults to Secret.123
 -F <sec domain pw>     - the PKI security domain name, i.e. from ca.cfg; defaults to SolarNetworkDev
 -f <sec domain pw>     - the PKI security domain password, i.e. from ca.cfg; defaults to Secret.123
 -h <host name>         - the FQDN for the machine; defaults to ca.solarnetworkdev.net
 -I <in JKS pw>         - the SolarIn JKS keystore password; defaults to dev123
 -i <in DNS name>       - the SoalrIn DNS name; defaults to in.solarentworkdev.net
 -J <agent uid>         - the SolarUser agent UID; defaults to suagent
 -j <agent name>        - the SolarUser agent name; defaults to "SolarUser Agent"
 -K <agent email>       - the SolarUser agent email; defaults to "suagent@solarnetworkdev.net"
 -k <agent p12 pw>      - the SolarUser agent PKCS#12 password; defaults to Secret.123
 -L <agent jks pw>      - the SolarUser agent JKS password; defaults to dev123
 -l <trust jks pw>      - the SolarNet trust store JKS password; defaults to dev123
 -n                     - dry run; do not make any actual changes
 -o <DS inst name>      - the Directory Server instance name; defaults to ca
 -p <DS root pw>        - the Directory Server root user password; defaults to admin
 -s <DN suffix>         - the Directory Server DN suffix to use; defaults to dc=solarnetworkdev,dc=net
 -t <LDIF file>         - path to a LDIF file to import into the Directory Server after Dogtag
                          configured; this can be used to migrate data from another Dogtag instance
 -u                     - update package cache
 -v                     - verbose mode; print out more verbose messages
EOF
}

while getopts ":A:a:c:d:E:e:F:f:h:i:I:J:j:K:k:L:l:no:p:s:t:uv" opt; do
	case $opt in		
		A) CA_ADMIN_LOGIN="${OPTARG}";;
		a) CA_ADMIN_HOME="${OPTARG}";;
		c) CA_CONF="${OPTARG}";;
		d) SN_PROFILE_CONF="${OPTARG}";;
		E) CA_ADMIN_PASS="${OPTARG}";;
		e) PKI_ADMIN_P12_PASS="${OPTARG}";;
		F) CA_SEC_DOMAIN_NAME="${OPTARG}";;
		f) CA_SEC_DOMAIN_PASS="${OPTARG}";;
		h) HOSTNAME="${OPTARG}";;
		I) SN_IN_JKS_PASS="${OPTARG}";;
		i) SN_IN_DNS_NAME="${OPTARG}";;
		J) CA_AGENT_UID="${OPTARG}";;
		j) CA_AGENT_NAME="${OPTARG}";;
		K) CA_AGENT_EMAIL="${OPTARG}";;
		k) CA_AGENT_P12_PASS="${OPTARG}";;
		L) CA_AGENT_JKS_PASS="${OPTARG}";;
		l) SN_TRUST_JKS_PASS="${OPTARG}";;
		n) DRY_RUN='TRUE';;
		o) DS_INST_NAME="${OPTARG}";;
		p) DS_ROOT_PASS="${OPTARG}";;
		s) DS_SUFFIX="${OPTARG}";;
		t) DS_IMPORT_LDIF="${OPTARG}";;
		u) UPDATE_PKGS='TRUE';;
		v) VERBOSE='TRUE';;
		?)
			echo "Unknown argument ${OPTARG}"
			do_help
			exit 1
	esac
done
shift $(($OPTIND - 1))

did_ds_ldif_import=""
did_pki=""
did_vnc=""

# install package if not already installed
pkg_install () {	
	if rpm -q $1 >/dev/null 2>&1; then
		echo "Package $1 already installed."
	else
		echo "Installing package $1 ..."
		if [ -z "$DRY_RUN" ]; then
			yum -y install $1
		fi
	fi
}

# install package group if not already installed
yum_groupinstall () {
	local installed=$(yum -q grouplist installed |grep "$1")
	if [ -n "$installed" ]; then
		echo "Package group $1 already installed."
	else
		echo "Installing package group $1 ..."
		if [ -z "$DRY_RUN" ]; then
			yum -y groupinstall "$1"
		fi
	fi
}

setup_pkgs () {
	if [ -n "$UPDATE_PKGS" ]; then
		echo 'Upgrading OS packages...'
		if [ -z "$DRY_RUN" ]; then
			yum upgrade -y
			yum makecache
		fi
	fi
}

setup_hostname () {
	if hostnamectl status --static |grep -q "$HOSTNAME"; then
		echo "Hostname already set to $HOSTNAME."
	else
		echo "Setting hostname to $HOSTNAME..."
		hostnamectl set-hostname "$HOSTNAME"
	fi
}

setup_dns () {
	if grep -q "$HOSTNAME" /etc/hosts; then
		echo "/etc/hosts contains $HOSTNAME already."
	else
		echo "Setting up $HOSTNAME /etc/hosts entry"
		sed "s/^127.0.0.1[[:space:]]*localhost/127.0.0.1 $HOSTNAME localhost/" /etc/hosts >/tmp/hosts.new
		if [ -z "$(diff /etc/hosts /tmp/hosts.new)" ]; then
			# didn't change anything, try 127.0.1.0
			sed "s/^127.0.1.1.*/127.0.1.1 $HOSTNAME/" /etc/hosts >/tmp/hosts.new
		fi
		if [ "$(diff /etc/hosts /tmp/hosts.new)" ]; then
			chmod 644 /tmp/hosts.new
			chown root:root /tmp/hosts.new
			cp -a /etc/hosts /etc/hosts.bak
			mv -f /tmp/hosts.new /etc/hosts
		fi
	fi
}

setup_osuser () {
	if getent passwd $CA_ADMIN_LOGIN >/dev/null; then
		echo "$CA_ADMIN_LOGIN user already exists."
	else
		echo "Adding $CA_ADMIN_LOGIN user."
		if [ -z "$DRY_RUN" ]; then
			useradd -c 'CA Admin' -s /bin/bash -m -U "$CA_ADMIN_LOGIN" -d "$CA_ADMIN_HOME"
			echo "$CA_ADMIN_PASS:$CA_ADMIN_PASS" |chpasswd
		fi
	fi
}

setup_swap () {
	if grep -q '/swapfile' /etc/fstab; then
		echo 'Swapfile already configured.'
	else
		echo 'Creating swapfile...'
		if [ -z "$DRY_RUN" ]; then
			fallocate -l 1G /swapfile
			chmod 600 /swapfile
			mkswap /swapfile
			swapon /swapfile
			echo '/swapfile none swap sw 0 0' >>/etc/fstab
		fi
	fi
}

setup_vnc () {
	pkg_install tigervnc-server
	
	if  [ -d "$CA_ADMIN_HOME/.vnc" ]; then
		echo "$CA_ADMIN_LOGIN VNC configuration dir already exists."
	else
		if [ -z "$DRY_RUN" ]; then
			sudo -u $CA_ADMIN_LOGIN mkdir "$CA_ADMIN_HOME/.vnc"
		fi
	fi
	
	if [ -e "$CA_ADMIN_HOME/.vnc/passwd" ]; then
		echo "$CA_ADMIN_LOGIN VNC password already exists."
	else
		echo "Setting up VNC password for $CA_ADMIN_LOGIN..."
		if [ -z "$DRY_RUN" ]; then
			local conf=$(cat <<-EOF
				$CA_ADMIN_PASS
				$CA_ADMIN_PASS
				n
				EOF
				)
			echo "$conf" |/sbin/runuser -u $CA_ADMIN_LOGIN vncpasswd
		fi
	fi
	
	if [ -e "$CA_ADMIN_HOME/.vnc/config" ]; then
		echo "$CA_ADMIN_LOGIN VNC config already exists."
	else
		echo "Setting up VNC config for $CA_ADMIN_LOGIN..."
		if [ -z "$DRY_RUN" ]; then
			local conf=$(cat <<-EOF
				localhost
				depth=24
				geometry=1280x1024
				EOF
				)
			echo "$conf" |sudo -u $CA_ADMIN_LOGIN tee "$CA_ADMIN_HOME/.vnc/config"
		fi
	fi

	if [ -e "$CA_ADMIN_HOME/.vnc/xstartup" ]; then
		echo "$CA_ADMIN_LOGIN VNC xstartup already exists."
	else
		echo "Setting up VNC xstartup for $CA_ADMIN_LOGIN..."
		if [ -z "$DRY_RUN" ]; then
			local conf=$(cat <<-"EOF"
				#!/bin/sh

				if [ -x /usr/bin/startxfce4 ]; then
				  exec /usr/bin/startxfce4
				fi
				[ -r $HOME/.Xresources ] && xrdb $HOME/.Xresources
				xsetroot -solid grey
				xterm -geometry 80x24+10+10 -ls -title "$VNCDESKTOP Desktop" &
				twm &
			EOF
			)
			echo "$conf" |sudo -u $CA_ADMIN_LOGIN tee "$CA_ADMIN_HOME/.vnc/xstartup"
		
			chmod 755 "$CA_ADMIN_HOME/.vnc/xstartup"
		fi
	fi
	
	if [ -e /etc/systemd/system/vncserver@:1.service ]; then
		echo "$CA_ADMIN_LOGIN VNC service already exists."
	else
		echo "Setting up $CA_ADMIN_LOGIN VNC service..."
		if [ -z "$DRY_RUN" ]; then
			cp /lib/systemd/system/vncserver@.service  /etc/systemd/system/vncserver@:1.service
			sed -i \
				-e "s/<USER>/$CA_ADMIN_LOGIN/" \
				-e '/^PIDFile=/d' \
				/etc/systemd/system/vncserver@\:1.service
			systemctl daemon-reload
			systemctl enable vncserver@:1
			systemctl start vncserver@:1
			did_vnc="1"
		fi
	fi
}

setup_desktop () {
	yum_groupinstall "Xfce Desktop"
	pkg_install firefox
}

setup_ds () {
	pkg_install 389-ds
	pkg_install cockpit-389-ds

	if dsctl -l |grep "slapd-$DS_INST_NAME"; then
		echo "DS $DS_INST_NAME exists already."
	else
		if [ -e ds.inf ]; then
			echo 'DS inf already exists.'
		else
			echo 'Configuring DS inf...'
			if [ -z "$DRY_RUN" ]; then
				dscreate create-template ds.tmp
				echo 'instance_name = ca' >>ds.tmp
				sed \
					-e "s/;instance_name = .*/instance_name = $DS_INST_NAME/" \
					-e "s/;full_machine_name = .*/full_machine_name = $HOSTNAME/" \
					-e "s/;suffix = .*/suffix = $DS_SUFFIX/" \
					-e "s/;root_password = .*/root_password = $DS_ROOT_PASS/" \
					ds.tmp >ds.inf
			fi
		fi
		if [ -e ds.inf ]; then
			echo 'Configuring DS from ds.inf...'
			if [ ! -e /usr/bin/systemctl ]; then
				echo 'Adding /usr/bin/systemctl -> /bin/systemctl to work around dscreate bug...'
				if [ -z "$DRY_RUN" ]; then
					ln -s /bin/systemctl /usr/bin/systemctl
				fi
			fi
			if [ -z "$DRY_RUN" ]; then
				dscreate from-file ds.inf
				mv ds.inf ds-ca.inf
			fi
		fi
	fi
}

setup_pki () {
	pkg_install pki-ca
	pkg_install dogtag-pki-server-theme
	
	# non-headless Java needed for console
	pkg_install java-1.8.0-openjdk
	pkg_install pki-console
	
	if [ -d /var/lib/pki/pki-tomcat ]; then
		echo 'Dogtag CA already present.'
	else
		echo "Creating Dogtag CA system using configuration $CA_CONF..."
		if [ -z "$DRY_RUN" ]; then
			if [ ! -e "/vagrant/$CA_CONF" ]; then
				echo "Dogtag CA config $CA_CONF not found; cannot create Dogtag CA system."
				exit 1
			else
 				pkispawn -s CA -f "/vagrant/$CA_CONF"
 				did_pki=1
			fi
		fi
	fi
	
	# the system is enabled via pki-tomcatd.target now
	if [ -z "$DRY_RUN" ]; then
		systemctl enable pki-tomcatd.target
		systemctl start pki-tomcatd.target
	fi
	
	# Give Dogtag chance to come up - -TODO: only if just started it
	sleep 5
	
	if certutil -L -d /root/.dogtag/nssdb -n "CA Certificate" -a &>/dev/null; then
		echo "CA Root Certificate already imported into nssdb."
	else
		echo "Importing CA Root Certificate into nssdb..."
		if [ -z "$DRY_RUN" ]; then
			pki client-cert-import "CA Certificate" --ca-server
		fi
	fi
	
	if [ -z "$DRY_RUN" ]; then
		echo "-----CA Root Certificate .dogtag/pki-tomcat/ca-root.crt-----"
		certutil -L -d /root/.dogtag/nssdb -n "CA Certificate" -a |tee /root/.dogtag/pki-tomcat/ca-root.crt
	fi
	
	# Import cert for admin's pkiconsole
	if sudo -u $CA_ADMIN_LOGIN certutil -L -d "$CA_ADMIN_HOME/.dogtag-idm-console" -n "CA Certificate" -a &>/dev/null; then
		echo "CA Root Certificate already imported into $CA_ADMIN_LOGIN's pkiconsole nssdb."
	else
		echo "Importing CA Root Certificate into $CA_ADMIN_LOGIN's pkiconsole nssdb..."
		if [ -z "$DRY_RUN" ]; then
			sudo -u $CA_ADMIN_LOGIN pki -d "$CA_ADMIN_HOME/.dogtag-idm-console" client-cert-import "CA Certificate" --ca-server
		fi
	fi
	
	local admin_nickname=$(pki pkcs12-cert-find --pkcs12-file /root/.dogtag/pki-tomcat/ca_admin_cert.p12 --pkcs12-password "$PKI_ADMIN_P12_PASS" |grep 'Friendly Name:' |cut -d : -f 2 |xargs)
	if [ -n "$admin_nickname" ]; then
		if certutil -L -d /root/.dogtag/nssdb -n "$admin_nickname" -a &>/dev/null; then
			echo "CA Admin Certificate '$admin_nickname' already imported into nssdb."
		else
			echo "Importing CA Admin Certificate '$admin_nickname' into nssdb..."
			if [ -z "$DRY_RUN" ]; then
				pki client-cert-import "$admin_nickname" --pkcs12 /root/.dogtag/pki-tomcat/ca_admin_cert.p12 --pkcs12-password "$PKI_ADMIN_P12_PASS"
			fi
		fi
	
		if pki -n "$admin_nickname" ca-profile-show SolarNode &>/dev/null; then
			echo "CA profile SolarNode already exists."
		else
			echo "Configuring CA profile SolarNode..."
			if [ -z "$DRY_RUN" ]; then
				pki -n "$admin_nickname" ca-profile-add "/vagrant/$SN_PROFILE_CONF" --raw
				pki -n "$admin_nickname" ca-profile-enable SolarNode
			fi
		fi
	fi
	
	# Sync entire pki nssdb to admin user
	echo "Syncing $CA_ADMIN_LOGIN pki data..."
	if [ -z "$DRY_RUN" ]; then
		rsync -a /root/.dogtag "$CA_ADMIN_HOME"
		chown -R "$CA_ADMIN_LOGIN:$CA_ADMIN_LOGIN" "$CA_ADMIN_HOME/.dogtag"
	fi

	if [ -e "$CA_ADMIN_HOME/.dogtag/pki-tomcat/central-trust.jks" ]; then
		echo 'central-trust.jks keystore already exists.'
	else
		echo 'Setting up central-trust.jks keystore...'
		if [ -z "$DRY_RUN" ]; then
			sudo -u $CA_ADMIN_LOGIN keytool -importcert -trustcacerts -alias ca \
				-keystore "$CA_ADMIN_HOME/.dogtag/pki-tomcat/central-trust.jks" -storetype jks \
				-storepass "$SN_TRUST_JKS_PASS" \
				-file "$CA_ADMIN_HOME/.dogtag/pki-tomcat/ca-root.crt" -noprompt
		fi
	fi
	
	# SolarIn server certificate creation
	#
	# SolarIn requires a server certificate. The following block creates one based on the SN_IN_DNS_NAME
	# value. The certificate and private key will be exported as a PKCS#12 file at .dogtag/pki-tomcat/SN_IN_DNS_NAME.p12
	
	if [ -e "$CA_ADMIN_HOME/.dogtag/pki-tomcat/$SN_IN_DNS_NAME.p12" ]; then
		echo "$SN_IN_DNS_NAME certificate already exists."
	else
		echo "Creating $SN_IN_DNS_NAME certificate..."
		if [ -z "$DRY_RUN" ]; then
			local req_id=$(sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" client-cert-request \
				"CN=$SN_IN_DNS_NAME,OU=SolarIn,O=$CA_SEC_DOMAIN_NAME" --profile caServerCert \
				|grep 'Request ID:' |cut -d : -f 2 |xargs)
			if [ -z "$req_id" ]; then
				echo "ERROR: unable to request $SN_IN_DNS_NAME certificate."
				exit 1
			else
				echo "Approving $SN_IN_DNS_NAME certificate request $req_id..."
				local cert_id=$(sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" ca-cert-request-review "$req_id" --action approve \
					|grep 'Certificate ID:'|cut -d : -f 2 |xargs)
				if [ -z "$cert_id" ]; then
					echo "ERROR: unable to approve $SN_IN_DNS_NAME certificate."
					exit 1
				else
					echo "Saving approved $SN_IN_DNS_NAME certificate $cert_id to .dogtag/pki-tomcat/$SN_IN_DNS_NAME.crt"
					sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" ca-cert-show $cert_id --encoded \
						--output "$CA_ADMIN_HOME/.dogtag/pki-tomcat/$SN_IN_DNS_NAME.crt"

					echo "Importing approved $SN_IN_DNS_NAME certificate $cert_id to nssdb..."
					sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" client-cert-import "$SN_IN_DNS_NAME" --serial $cert_id
					
					echo "Exporting approved $SN_IN_DNS_NAME certificate and private key $cert_id to .dogtag/pki-tomcat/$SN_IN_DNS_NAME.nssdb.p12..."
					sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" pkcs12-cert-import "$SN_IN_DNS_NAME" \
						--pkcs12-file "$CA_ADMIN_HOME/.dogtag/pki-tomcat/$SN_IN_DNS_NAME.p12" --pkcs12-password "$PKI_ADMIN_P12_PASS"
					
					echo "Exporting approved $SN_IN_DNS_NAME certificate and private key $cert_id to .dogtag/pki-tomcat/$SN_IN_DNS_NAME.p12..."
					sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" pkcs12-cert-import "$SN_IN_DNS_NAME" \
						--pkcs12-file "$CA_ADMIN_HOME/.dogtag/pki-tomcat/$SN_IN_DNS_NAME.p12" --pkcs12-password "$PKI_ADMIN_P12_PASS" \
						--no-trust-flags --no-chain --key-encryption 'PBE/SHA1/DES3/CBC'
				fi
			fi	
		fi
	fi

	if [ -e "$CA_ADMIN_HOME/.dogtag/pki-tomcat/central.jks" ]; then
		echo 'central.jks keystore already exists.'
	else
		echo 'Setting up central.jks keystore...'
		if [ -z "$DRY_RUN" ]; then
			sudo -u $CA_ADMIN_LOGIN keytool -importcert -trustcacerts -alias ca \
				-keystore "$CA_ADMIN_HOME/.dogtag/pki-tomcat/central.jks" -storetype jks \
				-storepass "$SN_IN_JKS_PASS" \
				-file "$CA_ADMIN_HOME/.dogtag/pki-tomcat/ca-root.crt" -noprompt
			sudo -u $CA_ADMIN_LOGIN keytool -importkeystore \
				-srckeystore "$CA_ADMIN_HOME/.dogtag/pki-tomcat/$SN_IN_DNS_NAME.p12" \
				-srcstoretype pkcs12 -srcstorepass "$CA_AGENT_P12_PASS" -srckeypass "$CA_AGENT_P12_PASS" \
				-destkeystore "$CA_ADMIN_HOME/.dogtag/pki-tomcat/central.jks" \
				-deststoretype jks -deststorepass "$SN_IN_JKS_PASS" -destkeypass "$SN_IN_JKS_PASS" \
				-noprompt -srcalias $SN_IN_DNS_NAME -destalias web
		fi
	fi
	
	# SolarUser agent certificate creation
	#
	# SolarUser requires an "agent" user and associated client certificate to manage SolarNode certificates.
	# The following block creates a `suagent` PKI user, adds them to the `Certificate Manager Agents` group,
	# and then creates a certificate for the user. The certificate and private key will be exported as a 
	# PKCS#12 file at .dogtag/pki-tomcat/suagent.p12
	
	if [ -e "$CA_ADMIN_HOME/.dogtag/pki-tomcat/$CA_AGENT_UID.p12" ]; then
		echo "$CA_AGENT_UID certificate already exists."
	else
		echo "Creating SolarUser agent user $CA_AGENT_UID..."
		if [ -z "$DRY_RUN" ]; then
			sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" ca-user-add "$CA_AGENT_UID" \
				--fullName "$CA_AGENT_NAME" --email "$CA_AGENT_EMAIL"
				
			echo "Adding $CA_AGENT_UID agent user to group..."
			sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname"  ca-group-member-add \
				"Certificate Manager Agents" "$CA_AGENT_UID"
		fi
				
		echo "Creating $CA_AGENT_UID certificate..."
		if [ -z "$DRY_RUN" ]; then
			local req_id=$(sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" client-cert-request \
				"UID=$CA_AGENT_UID,E=$CA_AGENT_EMAIL,CN=$CA_AGENT_NAME,OU=SolarUser,O=$CA_SEC_DOMAIN_NAME" --profile caUserCert \
				|grep 'Request ID:' |cut -d : -f 2 |xargs)
			if [ -z "$req_id" ]; then
				echo "ERROR: unable to request $CA_AGENT_UID certificate."
				exit 1
			else
				echo "Approving $CA_AGENT_UID certificate request $req_id..."
				local cert_id=$(sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" ca-cert-request-review "$req_id" --action approve \
					|grep 'Certificate ID:'|cut -d : -f 2 |xargs)
				if [ -z "$cert_id" ]; then
					echo "ERROR: unable to approve $CA_AGENT_UID certificate."
					exit 1
				else
					echo "Adding $CA_AGENT_UID certificate to user..."
					sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" ca-user-cert-add "$CA_AGENT_UID" --serial "$cert_id"
					
					echo "Importing approved $CA_AGENT_UID certificate $cert_id to nssdb..."
					sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" client-cert-import "$CA_AGENT_UID" --serial $cert_id
					
					echo "Exporting approved $CA_AGENT_UID certificate and private key $cert_id to .dogtag/pki-tomcat/$CA_AGENT_UID.p12..."
					sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" pkcs12-cert-import "$CA_AGENT_UID" \
						--pkcs12-file "$CA_ADMIN_HOME/.dogtag/pki-tomcat/$CA_AGENT_UID.p12" --pkcs12-password "$CA_AGENT_P12_PASS" \
						--no-trust-flags --no-chain --key-encryption 'PBE/SHA1/DES3/CBC'
				fi
			fi	
		fi
	fi

	if [ -e "$CA_ADMIN_HOME/.dogtag/pki-tomcat/dogtag-client.jks" ]; then
		echo 'dogtag-client.jks keystore already exists.'
	else
		echo 'Setting up dogtag-client.jks keystore...'
		if [ -z "$DRY_RUN" ]; then
			sudo -u $CA_ADMIN_LOGIN keytool -importcert -trustcacerts -alias ca \
				-keystore "$CA_ADMIN_HOME/.dogtag/pki-tomcat/dogtag-client.jks" -storetype jks \
				-storepass "$CA_AGENT_JKS_PASS" \
				-file "$CA_ADMIN_HOME/.dogtag/pki-tomcat/ca-root.crt" -noprompt
			sudo -u $CA_ADMIN_LOGIN keytool -importkeystore \
				-srckeystore "$CA_ADMIN_HOME/.dogtag/pki-tomcat/suagent.p12" \
				-srcstoretype pkcs12 -srcstorepass "$CA_AGENT_P12_PASS" -srckeypass "$CA_AGENT_P12_PASS" \
				-destkeystore "$CA_ADMIN_HOME/.dogtag/pki-tomcat/dogtag-client.jks" \
				-deststoretype jks -deststorepass "$CA_AGENT_JKS_PASS" -destkeypass "$CA_AGENT_JKS_PASS" \
				-noprompt
		fi
	fi
}

setup_ds_import () {
	if [ ! -e "/vagrant/$DS_IMPORT_LDIF" ]; then
		echo "Directory Server LDIF import file [$DS_IMPORT_LDIF] not found."
	else
		echo "Importing Directory Server LDIF file [$DS_IMPORT_LDIF]..."
		if [ -z "$DRY_RUN" ]; then
			systemctl stop pki-tomcatd.target
			db2bak
			ldapadd -x -w "$DS_ROOT_PASS" -D 'cn=Directory Manager' -c -f "/vagrant/$DS_IMPORT_LDIF" \
				>"$CA_ADMIN_HOME/.dogtag/pki-tomcat/ds-import-ldif.log" 2>&1
			systemctl start pki-tomcatd.target
			did_ds_ldif_import=1
		fi
	fi
}

setup_firewall () {
	firewall-cmd --quiet --zone=public --add-port=8080/tcp --permanent
	firewall-cmd --quiet --zone=public --add-port=8080/tcp
	firewall-cmd --quiet --zone=public --add-port=8443/tcp --permanent
	firewall-cmd --quiet --zone=public --add-port=8443/tcp
}

setup_cockpit () {
	if systemctl status cockpit.socket |grep ' disabled;'; then
		echo 'Enabling cockpit service...'
		if [ -z "$DRY_RUN" ]; then
			systemctl enable cockpit.socket
			systemctl start cockpit.socket
		fi
	else
		echo 'Cockpit service already enabled.'
	fi
}

show_results () {
	cat <<-EOF

		*******************************************************************************************
		INSTALLATION REPORT
		*******************************************************************************************
			
		To access services, you may need to add a hosts entry for $HOSTNAME
		from one of these IP addresses:
		
		  `hostname -I`
	
	EOF
	if [ -n "$did_vnc" ]; then
		cat <<-EOF
		
			A VNC server for the '$CA_ADMIN_LOGIN' user has been setup at localhost:1. You can access VNC
			by SSH forwarding a port to localhost:5901. For example
			
			  ssh -L5901:localhost:5901 $CA_ADMIN_LOGIN@$HOSTNAME
		EOF
	fi
	if [ -n "$did_pki" ]; then
		cat <<-EOF
			
			Dogtag PKI has been setup at https://$HOSTNAME:8443/ca.
				
			The Dogtag root CA certificate has been saved to:
			
			  $CA_ADMIN_HOME/.dogtag/pki-tomcat/ca-root.crt
				
			You can import this certificate as a trusted CA. The certificate has been copied for
			use by SolarNetwork applications with a password '$SN_TRUST_JKS_PASS' to:
			
			  $CA_ADMIN_HOME/.dogtag/pki-tomcat/central-trust.jks

			You need an admin certificate to access Dogtag, which as been created as the PKCS#12 file

			  $CA_ADMIN_HOME/.dogtag/pki-tomcat/ca_admin_cert.p12
			
			that contains the private key and certificate you can import into your browser. The 
			password used was specified in the 'pki_client_pkcs12_password' property in the PKI
			configuration file $CA_CONF.
			
			A SolarIn web server private key and certificate have been saved as a PKCS#12 file at
			
			  $CA_ADMIN_HOME/.dogtag/pki-tomcat/$SN_IN_DNS_NAME.p12
			  
			that uses the same password specified in the 'pki_client_pkcs12_password' property. A
			copy of that has been saved with the password '$SN_IN_JKS_PASS' to:
			
			  $CA_ADMIN_HOME/.dogtag/pki-tomcat/central.jks
			
			A CA Agent user 'suagent' has been created for SolarUser to integrate with Dogtag. This
			user has been added to the 'Certificate Manager Agents' group. A PKCS#12 file for this
			user has been created as
			
			  $CA_ADMIN_HOME/.dogtag/pki-tomcat/suagent.p12
				
			The CA Agent PKCS#12 file has been copied for use by SolarNetwork applications with a
			password '$CA_AGENT_JKS_PASS' to:
			
			  $CA_ADMIN_HOME/.dogtag/pki-tomcat/dogtag-client.jks

		EOF
	fi
	if [ -n "$did_ds_ldif_import" ]; then
		cat <<-EOF
		
			LDIF data has been imported from:
			
			  $DS_IMPORT_LDIF
			
			A log of the import results is saved to:
			
			  $CA_ADMIN_HOME/.dogtag/pki-tomcat/ds-import-ldif.log
		EOF
	fi
}

setup_pkgs
setup_hostname
setup_dns
setup_osuser
setup_swap
setup_desktop
setup_vnc
setup_ds
setup_pki
if [ -n "$DS_IMPORT_LDIF" ]; then
	setup_ds_import
fi
setup_firewall

setup_cockpit

show_results