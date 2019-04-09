#!/usr/bin/env bash

CA_CONF="example/ca.cfg"
CA_SEC_DOMAIN_NAME="SolarNetworkDev"
CA_SEC_DOMAIN_PASS="Secret.123"
CA_ADMIN_P12_PASS="Secret.123"
CA_AGENT_UID="suagent"
CA_AGENT_NAME="SolarUser Agent"
CA_AGENT_EMAIL="sugagent@solarnetworkdev.net"
CA_AGENT_P12_PASS="Secret.123"
DRY_RUN=""
DS_INST_NAME="ca"
DS_ROOT_PW="admin"
DS_SUFFIX="dc=solarnetworkdev,dc=net"
HOSTNAME="ca.solarnetworkdev.net"
SN_PROFILE_CONF="example/SolarNode.cfg"
SN_IN_DNS_NAME="in.solarnetworkdev.net"
UPDATE_PKGS=""
VERBOSE=""

do_help () {
	cat 1>&2 <<EOF
Usage: $0 [-nuv]

Arguments:
 -c <CA config path> - path to the Dogtag CA configuration file to use; defaults to example/ca.cfg
 -d <profile path>   - path to the Dogtag SolarNode profile configuration file to use; defaults to
                       example/SolarNode.cfg
 -e <admin p12 pw>   - the PKI Admin PKCS#12 password, i.e. from ca.cfg; defaults to Secret.123
 -F <sec domain pw>  - the PKI security domain name, i.e. from ca.cfg; defaults to SolarNetworkDev
 -f <sec domain pw>  - the PKI security domain password, i.e. from ca.cfg; defaults to Secret.123
 -h <host name>      - the FQDN for the machine; defaults to ca.solarnetworkdev.net
 -i <in DNS name>    - the SoalrIn DNS name; defaults to in.solarentworkdev.net
 -J <agent uid>      - the SolarUser agent UID; defaults to suagent
 -j <agent name>     - the SolarUser agent name; defaults to "SolarUser Agent"
 -K <agent email>    - the SolarUser agent email; defaults to "suagent@solarnetworkdev.net"
 -k <agent p12 pw>   - the SolarUser agent PKCS#12 password; defaults to Secret.123
 -n                  - dry run; do not make any actual changes
 -o <DS inst name>   - the Directory Server instance name; defaults to ca
 -p <DS root pw>     - the Directory Server root user password; defaults to admin
 -s <DN suffix>      - the Directory Server DN suffix to use; defaults to dc=solarnetworkdev,dc=net
 -u                  - update package cache
 -v                  - verbose mode; print out more verbose messages
EOF
}

while getopts ":c:d:e:F:f:h:i:J:j:K:k:no:p:s:uv" opt; do
	case $opt in
		
		c) CA_CONF="${OPTARG}";;
		d) SN_PROFILE_CONF="${OPTARG}";;
		e) CA_ADMIN_P12_PASS="${OPTARG}";;
		F) CA_SEC_DOMAIN_NAME="${OPTARG}";;
		f) CA_SEC_DOMAIN_PASS="${OPTARG}";;
		h) HOSTNAME="${OPTARG}";;
		i) HOSTNAME="${OPTARG}";;
		J) CA_AGENT_UID="${OPTARG}";;
		j) CA_AGENT_NAME="${OPTARG}";;
		K) CA_AGENT_EMAIL="${OPTARG}";;
		k) CA_AGENT_P12_PASS="${OPTARG}";;
		n) DRY_RUN='TRUE';;
		o) DS_INST_NAME="${OPTARG}";;
		p) DS_ROOT_PW="${OPTARG}";;
		s) DS_SUFFIX="${OPTARG}";;
		u) UPDATE_PKGS='TRUE';;
		v) VERBOSE='TRUE';;
		?)
			echo "Unknown argument ${OPTARG}"
			do_help
			exit 1
	esac
done
shift $(($OPTIND - 1))

did_pki=""

# install package if not already installed
pkg_install () {	
	if rpm -q $1 >/dev/null 2>&1; then
		echo "Package $1 already installed."
	else
		echo "Installing package $1 ..."
		if [ -z "$DRY_RUN" ]; then
			sudo yum -y install $1
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
			sudo yum -y groupinstall "$1"
		fi
	fi
}

setup_pkgs () {
	if [ -n "$UPDATE_PKGS" ]; then
		sudo yum upgrade -y
		sudo yum makecache
	fi
}

setup_hostname () {
	if hostnamectl status --static |grep -q "$HOSTNAME"; then
		echo "Hostname already set to $HOSTNAME."
	else
		echo "Setting hostname to $HOSTNAME..."
		sudo hostnamectl set-hostname "$HOSTNAME"
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
			sudo chown root:root /tmp/hosts.new
			sudo cp -a /etc/hosts /etc/hosts.bak
			sudo mv -f /tmp/hosts.new /etc/hosts
		fi
	fi
}

setup_osuser () {
	if getent passwd caadmin >/dev/null; then
		echo 'caadmin user already exists.'
	else
		echo 'Adding caadmin user.'
		if [ -z "$DRY_RUN" ]; then
			sudo useradd -c 'CA Admin' -s /bin/bash -m -U caadmin
			sudo sh -c 'echo "caadmin:caadmin" |chpasswd'
		fi
	fi
}

setup_swap () {

	if grep -q '/swapfile' /etc/fstab; then
		echo 'Swapfile already configured.'
	else
		echo 'Creating swapfile...'
		if [ -z "$DRY_RUN" ]; then
			sudo fallocate -l 1G /swapfile
			sudo chmod 600 /swapfile
			sudo mkswap /swapfile
			sudo swapon /swapfile
			echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
		fi
	fi
}

setup_vnc () {
	pkg_install tigervnc-server
	
	if sudo ls -d /home/caadmin/.vnc &>/dev/null; then
		echo 'caadmin VNC configuration dir already exists.'
	else
		if [ -z "$DRY_RUN" ]; then
			sudo -u caadmin mkdir /home/caadmin/.vnc
		fi
	fi
	
	if sudo ls /home/caadmin/.vnc/passwd &>/dev/null; then
		echo 'caadmin VNC password already exists.'
	else
		echo 'Setting up VNC password for caadmin...'
		if [ -z "$DRY_RUN" ]; then
			local conf=$(cat <<-EOF
				caadmin
				caadmin
				n
				EOF
				)
			echo "$conf" |sudo /sbin/runuser -u caadmin vncpasswd
		fi
	fi
	
	if sudo ls /home/caadmin/.vnc/config &>/dev/null; then
		echo 'caadmin VNC config already exists.'
	else
		echo 'Setting up VNC config for caadmin...'
		if [ -z "$DRY_RUN" ]; then
			local conf=$(cat <<-EOF
				localhost
				depth=24
				geometry=1280x1024
				EOF
				)
			echo "$conf" |sudo -u caadmin tee /home/caadmin/.vnc/config
		fi
	fi

	if sudo ls /home/caadmin/.vnc/xstartup &>/dev/null; then
		echo 'caadmin VNC xstartup already exists.'
	else
		echo 'Setting up VNC xstartup for caadmin...'
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
			echo "$conf" |sudo -u caadmin tee /home/caadmin/.vnc/xstartup
		
			sudo chmod 755 /home/caadmin/.vnc/xstartup
		fi
	fi
	
	if [ -e /etc/systemd/system/vncserver@:1.service ]; then
		echo 'caadmin VNC service already exists.'
	else
		echo 'Setting up caadmin VNC service...'
		if [ -z "$DRY_RUN" ]; then
			sudo cp /lib/systemd/system/vncserver@.service  /etc/systemd/system/vncserver@:1.service
			sudo sed -i \
				-e 's/<USER>/caadmin/' \
				-e '/^PIDFile=/d' \
				/etc/systemd/system/vncserver@\:1.service
			sudo systemctl daemon-reload
			sudo systemctl enable vncserver@:1
			sudo systemctl start vncserver@:1
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
					-e "s/;root_password = .*/root_password = $DS_ROOT_PW/" \
					ds.tmp >ds.inf
			fi
		fi
		if [ -e ds.inf ]; then
			echo 'Configuring DS from ds.inf...'
			if [ ! -e /usr/bin/systemctl ]; then
				echo 'Adding /usr/bin/systemctl -> /bin/systemctl to work around dscreate bug...'
				if [ -z "$DRY_RUN" ]; then
					sudo ln -s /bin/systemctl /usr/bin/systemctl
				fi
			fi
			if [ -z "$DRY_RUN" ]; then
				sudo dscreate from-file ds.inf
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
 				sudo pkispawn -s CA -f "/vagrant/$CA_CONF"
 				did_pki=1
			fi
		fi
	fi
	
	# the system is enabled via pki-tomcatd.target now
	if [ -z "$DRY_RUN" ]; then
		sudo systemctl enable pki-tomcatd.target
		sudo systemctl start pki-tomcatd.target
	fi
	
	# Give Dogtag chance to come up - -TODO: only if just started it
	sleep 5
	
	if sudo certutil -L -d /root/.dogtag/nssdb -n "CA Certificate" -a &>/dev/null; then
		echo "CA Root Certificate already imported into nssdb."
	else
		echo "Importing CA Root Certificate into nssdb..."
		if [ -z "$DRY_RUN" ]; then
			sudo pki client-cert-import "CA Certificate" --ca-server
		fi
	fi
	
	if [ -z "$DRY_RUN" ]; then
		echo "-----CA Root Certificate .dogtag/pki-tomcat/ca-root.crt-----"
		sudo certutil -L -d /root/.dogtag/nssdb -n "CA Certificate" -a |sudo tee /root/.dogtag/pki-tomcat/ca-root.crt
	fi
	
	# Import cert for caadmin's pkiconsole
	if sudo -u caadmin certutil -L -d /home/caadmin/.dogtag-idm-console -n "CA Certificate" -a &>/dev/null; then
		echo "CA Root Certificate already imported into caadmin's pkiconsole nssdb."
	else
		echo "Importing CA Root Certificate into caadmin's pkiconsole nssdb..."
		if [ -z "$DRY_RUN" ]; then
			sudo -u caadmin pki -d /home/caadmin/.dogtag-idm-console client-cert-import "CA Certificate" --ca-server
		fi
	fi
	
	local admin_nickname=$(sudo pki pkcs12-cert-find --pkcs12-file /root/.dogtag/pki-tomcat/ca_admin_cert.p12 --pkcs12-password "$CA_ADMIN_P12_PASS" |grep 'Friendly Name:' |cut -d : -f 2 |xargs)
	if [ -n "$admin_nickname" ]; then
		if sudo certutil -L -d /root/.dogtag/nssdb -n "$admin_nickname" -a &>/dev/null; then
			echo "CA Admin Certificate '$admin_nickname' already imported into nssdb."
		else
			echo "Importing CA Admin Certificate '$admin_nickname' into nssdb..."
			if [ -z "$DRY_RUN" ]; then
				sudo pki client-cert-import "$admin_nickname" --pkcs12 /root/.dogtag/pki-tomcat/ca_admin_cert.p12 --pkcs12-password "$CA_ADMIN_P12_PASS"
			fi
		fi
	
		if sudo pki -n "$admin_nickname" ca-profile-show SolarNode &>/dev/null; then
			echo "CA profile SolarNode already exists."
		else
			echo "Configuring CA profile SolarNode..."
			if [ -z "$DRY_RUN" ]; then
				sudo pki -n "$admin_nickname" ca-profile-add "/vagrant/$SN_PROFILE_CONF" --raw
				sudo pki -n "$admin_nickname" ca-profile-enable SolarNode
			fi
		fi
	fi
	
	# Copy entire pki nssdb to caadmin
	if sudo ls /home/caadmin/.dogtag &>/dev/null; then
		echo 'caadmin pki data exists.'
	else
		echo 'Setting up caadmin pki data...'
		if [ -z "$DRY_RUN" ]; then
			sudo rsync -a /root/.dogtag /home/caadmin
			sudo chown -R caadmin:caadmin /home/caadmin/.dogtag
		fi
	fi

	if sudo ls /home/caadmin/.dogtag/pki-tomcat/central-trust.jks &>/dev/null; then
		echo 'central-trust.jks keystore already exists.'
	else
		echo 'Setting up central-trust.jks keystore...'
		if [ -z "$DRY_RUN" ]; then
			sudo -u caadmin keytool -importcert -trustcacerts -alias ca \
				-keystore /home/caadmin/.dogtag/pki-tomcat/central-trust.jks -storetype jks -storepass dev123 \
				-file /home/caadmin/.dogtag/pki-tomcat/ca-root.crt -noprompt
		fi
	fi
	
	# SolarIn server certificate creation
	#
	# SolarIn requires a server certificate. The following block creates one based on the SN_IN_DNS_NAME
	# value. The certificate and private key will be exported as a PKCS#12 file at .dogtag/pki-tomcat/SN_IN_DNS_NAME.p12
	
	if sudo ls "/home/caadmin/.dogtag/pki-tomcat/$SN_IN_DNS_NAME.p12" &>/dev/null; then
		echo "$SN_IN_DNS_NAME certificate already exists."
	else
		echo "Creating $SN_IN_DNS_NAME certificate..."
		if [ -z "$DRY_RUN" ]; then
			local req_id=$(sudo -u caadmin pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" client-cert-request \
				"CN=$SN_IN_DNS_NAME,OU=SolarIn,O=$CA_SEC_DOMAIN_NAME" --profile caServerCert \
				|grep 'Request ID:' |cut -d : -f 2 |xargs)
			if [ -z "$req_id" ]; then
				echo "ERROR: unable to request $SN_IN_DNS_NAME certificate."
				exit 1
			else
				echo "Approving $SN_IN_DNS_NAME certificate request $req_id..."
				local cert_id=$(sudo -u caadmin pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" ca-cert-request-review "$req_id" --action approve \
					|grep 'Certificate ID:'|cut -d : -f 2 |xargs)
				if [ -z "$cert_id" ]; then
					echo "ERROR: unable to approve $SN_IN_DNS_NAME certificate."
					exit 1
				else
					echo "Saving approved $SN_IN_DNS_NAME certificate $cert_id to .dogtag/pki-tomcat/$SN_IN_DNS_NAME.crt"
					sudo -u caadmin pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" ca-cert-show $cert_id --encoded \
						--output "/home/caadmin/.dogtag/pki-tomcat/$SN_IN_DNS_NAME.crt"

					echo "Importing approved $SN_IN_DNS_NAME certificate $cert_id to nssdb..."
					sudo -u caadmin pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" client-cert-import "$SN_IN_DNS_NAME" --serial $cert_id
					
					echo "Exporting approved $SN_IN_DNS_NAME certificate and private key $cert_id to .dogtag/pki-tomcat/$SN_IN_DNS_NAME.nssdb.p12..."
					sudo -u caadmin pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" pkcs12-cert-import "$SN_IN_DNS_NAME" \
						--pkcs12-file "/home/caadmin/.dogtag/pki-tomcat/$SN_IN_DNS_NAME.p12" --pkcs12-password "$CA_ADMIN_P12_PASS"
					
					echo "Exporting approved $SN_IN_DNS_NAME certificate and private key $cert_id to .dogtag/pki-tomcat/$SN_IN_DNS_NAME.p12..."
					sudo -u caadmin pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" pkcs12-cert-import "$SN_IN_DNS_NAME" \
						--pkcs12-file "/home/caadmin/.dogtag/pki-tomcat/$SN_IN_DNS_NAME.p12" --pkcs12-password "$CA_ADMIN_P12_PASS" \
						--no-trust-flags --no-chain --key-encryption 'PBE/SHA1/DES3/CBC'
				fi
			fi	
		fi
	fi
	
	# SolarUser agent certificate creation
	#
	# SolarUser requires an "agent" user and associated client certificate to manage SolarNode certificates.
	# The following block creates a `suagent` PKI user, adds them to the `Certificate Manager Agents` group,
	# and then creates a certificate for the user. The certificate and private key will be exported as a 
	# PKCS#12 file at .dogtag/pki-tomcat/suagent.p12
	
	if sudo ls "/home/caadmin/.dogtag/pki-tomcat/$CA_AGENT_UID.p12" &>/dev/null; then
		echo "$CA_AGENT_UID certificate already exists."
	else
		echo "Creating SolarUser agent user $CA_AGENT_UID..."
		if [ -z "$DRY_RUN" ]; then
			sudo -u caadmin pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" ca-user-add "$CA_AGENT_UID" \
				--fullName "$CA_AGENT_NAME" --email "$CA_AGENT_EMAIL"
				
			echo "Adding $CA_AGENT_UID agent user to group..."
			sudo -u caadmin pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname"  ca-group-member-add \
				"Certificate Manager Agents" "$CA_AGENT_UID"
		fi
				
		echo "Creating $CA_AGENT_UID certificate..."
		if [ -z "$DRY_RUN" ]; then
			local req_id=$(sudo -u caadmin pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" client-cert-request \
				"UID=$CA_AGENT_UID,E=$CA_AGENT_EMAIL,CN=$CA_AGENT_NAME,OU=SolarUser,O=$CA_SEC_DOMAIN_NAME" --profile caUserCert \
				|grep 'Request ID:' |cut -d : -f 2 |xargs)
			if [ -z "$req_id" ]; then
				echo "ERROR: unable to request $CA_AGENT_UID certificate."
				exit 1
			else
				echo "Approving $CA_AGENT_UID certificate request $req_id..."
				local cert_id=$(sudo -u caadmin pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" ca-cert-request-review "$req_id" --action approve \
					|grep 'Certificate ID:'|cut -d : -f 2 |xargs)
				if [ -z "$cert_id" ]; then
					echo "ERROR: unable to approve $CA_AGENT_UID certificate."
					exit 1
				else
					echo "Adding $CA_AGENT_UID certificate to user..."
					sudo -u caadmin pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" ca-user-cert-add "$CA_AGENT_UID" --serial "$cert_id"
					
					echo "Importing approved $CA_AGENT_UID certificate $cert_id to nssdb..."
					sudo -u caadmin pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" client-cert-import "$CA_AGENT_UID" --serial $cert_id
					
					echo "Exporting approved $CA_AGENT_UID certificate and private key $cert_id to .dogtag/pki-tomcat/$CA_AGENT_UID.p12..."
					sudo -u caadmin pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" pkcs12-cert-import "$CA_AGENT_UID" \
						--pkcs12-file "/home/caadmin/.dogtag/pki-tomcat/$CA_AGENT_UID.p12" --pkcs12-password "$CA_AGENT_P12_PASS" \
						--no-trust-flags --no-chain --key-encryption 'PBE/SHA1/DES3/CBC'
				fi
			fi	
		fi
	fi

	if sudo ls /home/caadmin/.dogtag/pki-tomcat/dogtag-client.jks &>/dev/null; then
		echo 'dogtag-client.jks keystore already exists.'
	else
		echo 'Setting up dogtag-client.jks keystore...'
		if [ -z "$DRY_RUN" ]; then
			sudo -u caadmin keytool -importkeystore -srckeystore /home/caadmin/.dogtag/pki-tomcat/suagent.p12 \
				-srcstoretype pkcs12 -srcstorepass "$CA_AGENT_P12_PASS" \
				-destkeystore /home/caadmin/.dogtag/pki-tomcat/dogtag-client.jks \
				-deststoretype jks -deststorepass dev123 -noprompt
		fi
	fi
}

setup_firewall() {
	firewall-cmd --quiet --zone=public --add-port=8080/tcp --permanent
	firewall-cmd --quiet --zone=public --add-port=8080/tcp
	firewall-cmd --quiet --zone=public --add-port=8443/tcp --permanent
	firewall-cmd --quiet --zone=public --add-port=8443/tcp
}

setup_cockpit () {
	if systemctl status cockpit.socket |grep ' disabled;'; then
		echo 'Enabling cockpit service...'
		if [ -z "$DRY_RUN" ]; then
			sudo systemctl enable cockpit.socket
			sudo systemctl start cockpit.socket
		fi
	else
		echo 'Cockpit service already enabled.'
	fi
}

show_results () {
	if [ -n "$did_pki" ]; then
		cat <<-EOF
			
			Dogtag PKI has been setup at https://$HOSTNAME:8443/ca.
			You may need to add a hosts entry for $HOSTNAME from one of these IP addresses:
			
			  `hostname -I`
				
			The Dogtag root CA certificate has been saved to:
			
			  /home/caadmin/.dogtag/pki-tomcat/ca-root.crt
				
			You can import this certificate as a trusted CA. The certificate has been copied into
			a Java keystore for use by SolarNetwork applications, with a password 'dev123':
			
			  /home/caadmin/.dogtag/pki-tomcat/central-trust.jks

			You need an admin certificate to access Dogtag, which as been created as the PKCS#12 file

			  /home/caadmin/.dogtag/pki-tomcat/ca_admin_cert.p12
			
			that contains the private key and certificate you can import into your browser. The 
			password used was specified in the 'pki_client_pkcs12_password' property in the PKI
			configuration file $CA_CONF.
			
			A CA Agent user 'suagent' has been created for SolarUser to integrate with Dogtag. This
			user has been added to the 'Certificate Manager Agents' group. A PKCS#12 file for this
			user has been created as
			
			  /home/caadmin/.dogtag/pki-tomcat/suagent.p12
				
			The suagent.p12 file has been copied into a Java keystore for use by SolarNetwork
			applications, with a store password 'dev123':
			
			  /home/caadmin/.dogtag/pki-tomcat/dogtag-client.jks

			
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
setup_firewall

setup_cockpit

show_results