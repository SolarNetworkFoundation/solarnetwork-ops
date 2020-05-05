#!/usr/bin/env bash

BASE_DIR="/vagrant"
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
DS_ROOT_PASS="admin.123"
DS_SUFFIX="dc=solarnetworkdev,dc=net"
DS_IMPORT_LDIF=""
HOSTNAME="ca.solarnetworkdev.net"
PKI_REPO_EXCLUDE="updates*"
SN_PROFILE_CONF="example/SolarNode.cfg"
SN_IN_DNS_NAME="in.solarnetworkdev.net"
SN_IN_JKS_PASS="dev123"
SN_SERVER_DNS_NAMES="DB:db.solarnetworkdev.net SolarFlux:influx.solarnetworkdev.net SolarIn:queue.solarnetworkdev.net"
SN_SERVER_P12_PASS="dev123"
SN_TRUST_JKS_PASS="dev123"
SN_USER_NAMES="DB:auth:operations@solarnetworkdev.net DB:in:operations@solarnetworkdev.net DB:jobs:operations@solarnetworkdev.net DB:query:operations@solarnetworkdev.net DB:user:operations@solarnetworkdev.net DB:sysadmin:operations@solarnetworkdev.net"
SN_USER_P12_PASS="dev123"
UPDATE_PKGS=""
VERBOSE=""

if [ $(id -u) -ne 0 ]; then
	echo "This script must be run as root."
	exit 1
fi

do_help () {
	cat 1>&2 <<EOF
Usage: $0 [-nuv]

Arguments that correspond to values in the PKI config file (-c) will be automatically set to the
value in that file and need not be passed.

Arguments:
 -A <admin username>    - the CA Admin OS username; defaults to caadmin
 -a <admin home>        - the CA Admin OS home; defafults to $CA_ADMIN_HOME
 -b <base dir>          - base dir for relative paths; defaults to /vagrant
 -c <PKI config path>   - path to the Dogtag CA configuration file to use; defaults to example/ca.cfg
 -d <profile path>      - path to the Dogtag SolarNode profile configuration file to use; defaults to
                          example/SolarNode.cfg
 -E <admin pw>          - the CA admin OS user password; defaults to caadmin
 -e <pki admin p12 pw>  - the PKI Admin PKCS#12 password, i.e. from ca.cfg; defaults to Secret.123
 -F <sec domain name>   - the PKI security domain name, i.e. from ca.cfg; defaults to SolarNetworkDev
 -f <sec domain pw>     - the PKI security domain password, i.e. from ca.cfg; defaults to Secret.123
 -H <repo glob>         - exclude package repositories matching this glob when installing PKI;
                          this is done to limit the version to match what is available in CentOS;
                          defaults to 'updates*'
 -h <host name>         - the FQDN for the machine; defaults to ca.solarnetworkdev.net
 -I <in JKS pw>         - the SolarIn JKS keystore password; defaults to dev123
 -i <in DNS name>       - the SoalrIn DNS name; defaults to in.solarentworkdev.net
 -J <agent uid>         - the SolarUser agent UID; defaults to suagent
 -j <agent name>        - the SolarUser agent name; defaults to "SolarUser Agent"
 -K <agent email>       - the SolarUser agent email; defaults to "suagent@solarnetworkdev.net"
 -k <agent p12 pw>      - the SolarUser agent PKCS#12 password; defaults to Secret.123
 -L <agent jks pw>      - the SolarUser agent JKS password; defaults to dev123
 -l <trust jks pw>      - the SolarNet trust store JKS password; defaults to dev123
 -M <server p12 pw>     - the DB servers PKCS#12 password; defaults to dev123
 -m <server DNS names>  - a space-delimited list of server DN organizational units and DNS name pairs
                          delimited by colons, to create certificates for; defaults to the following:

                         DB:db.solarnetworkdev.net SolarFlux:influx.solarnetworkdev.net SolarIn:queue.solarnetworkdev.net

 -n                     - dry run; do not make any actual changes
 -o <DS inst name>      - the Directory Server instance name; defaults to ca
 -p <DS root pw>        - the Directory Server root user password, i.e. from ca.cfg; defaults to admin
 -s <DN suffix>         - the Directory Server DN suffix to use; defaults to dc=solarnetworkdev,dc=net
 -t <LDIF file>         - path to a LDIF file to import into the Directory Server after Dogtag
                          configured; this can be used to migrate data from another Dogtag instance
 -u                     - update package cache
 -v                     - verbose mode; print out more verbose messages
 -W <user p12 pw>       - the user PKCS#12 password; defaults to dev123
 -w <user names>        - a space-delimited list of server DN organizational units, usernames, and
                          email address tuples delimited by colons, to create certificates for; 
                          defaults to the following:

                          DB:auth:operations@solarnetworkdev.net DB:in:operations@solarnetworkdev.net...
EOF
}

while getopts ":A:a:b:c:d:E:e:F:f:h:i:I:J:j:K:k:L:l:M:m:no:p:s:t:uvW:w:" opt; do
	case $opt in		
		A) CA_ADMIN_LOGIN="${OPTARG}";;
		a) CA_ADMIN_HOME="${OPTARG}";;
		b) BASE_DIR="${OPTARG}";;
		c) CA_CONF="${OPTARG}";;
		d) SN_PROFILE_CONF="${OPTARG}";;
		E) CA_ADMIN_PASS="${OPTARG}";;
		e) PKI_ADMIN_P12_PASS="${OPTARG}";;
		F) CA_SEC_DOMAIN_NAME="${OPTARG}";;
		f) CA_SEC_DOMAIN_PASS="${OPTARG}";;
		H) PKI_REPO_EXCLUDE="${OPTARG}";;
		h) HOSTNAME="${OPTARG}";;
		I) SN_IN_JKS_PASS="${OPTARG}";;
		i) SN_IN_DNS_NAME="${OPTARG}";;
		J) CA_AGENT_UID="${OPTARG}";;
		j) CA_AGENT_NAME="${OPTARG}";;
		K) CA_AGENT_EMAIL="${OPTARG}";;
		k) CA_AGENT_P12_PASS="${OPTARG}";;
		L) CA_AGENT_JKS_PASS="${OPTARG}";;
		l) SN_TRUST_JKS_PASS="${OPTARG}";;
		M) SN_SERVER_P12_PASS="${OPTARG}";;
		m) SN_SERVER_DNS_NAMES="${OPTARG}";;
		n) DRY_RUN='TRUE';;
		o) DS_INST_NAME="${OPTARG}";;
		p) DS_ROOT_PASS="${OPTARG}";;
		s) DS_SUFFIX="${OPTARG}";;
		t) DS_IMPORT_LDIF="${OPTARG}";;
		u) UPDATE_PKGS='TRUE';;
		v) VERBOSE='TRUE';;
		W) SN_USER_P12_PASS="${OPTARG}";;
		w) SN_USER_NAMES="${OPTARG}";;
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
os_type=""

if [ -e /etc/centos-release ]; then
	os_type="CENTOS"
elif [ -e /etc/fedora-release ]; then
	os_type="FEDORA"
fi

# install package if not already installed
pkg_install () {
	local pkg=$1
	local exrepo=$2
	if rpm -q $pkg >/dev/null 2>&1; then
		echo "Package $pkg already installed."
	else
		echo "Installing package $pkg ..."
		if [ -z "$DRY_RUN" ]; then
			if [ -n "$exrepo" ]; then
				yum -y --disablerepo=$exrepo install $pkg
			else
				yum -y install $pkg
			fi
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

setup_cfg_vars () {
	local tmp_val=$(grep '^pki_client_pkcs12_password=' "$BASE_DIR/$CA_CONF" 2>/dev/null |cut -d= -f2)
	PKI_ADMIN_P12_PASS="${tmp_val:-PKI_ADMIN_P12_PASS}"
	
	tmp_val=$(grep '^pki_security_domain_name=' "$BASE_DIR/$CA_CONF" 2>/dev/null |cut -d= -f2)
	CA_SEC_DOMAIN_NAME="${tmp_val:-CA_SEC_DOMAIN_NAME}"
	
	tmp_val=$(grep '^pki_security_domain_password=' "$BASE_DIR/$CA_CONF" 2>/dev/null |cut -d= -f2)
	CA_SEC_DOMAIN_PASS="${tmp_val:-CA_SEC_DOMAIN_PASS}"
	
	tmp_val=$(grep '^pki_ds_password=' "$BASE_DIR/$CA_CONF" 2>/dev/null |cut -d= -f2)
	DS_ROOT_PASS="${tmp_val:-DS_ROOT_PASS}"
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

setup_repos () {
	if [ "$os_type" = "CENTOS" ]; then
		pkg_install epel-release
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
			echo "$CA_ADMIN_LOGIN:$CA_ADMIN_PASS" |chpasswd
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
	
	local unit_tmpl='/lib/systemd/system/vncserver@.service'
	local unit_inst='/etc/systemd/system/vncserver@:1.service'
	if [ -e /usr/lib/systemd/user/vncserver@.service ]; then
		unit_tmpl='/usr/lib/systemd/user/vncserver@.service'
	fi
	if [ -e "$unit_inst" ]; then
		echo "$CA_ADMIN_LOGIN VNC service already exists."
	else
		echo "Setting up $CA_ADMIN_LOGIN VNC service..."
		if [ -z "$DRY_RUN" ]; then
			cp "$unit_tmpl"  "$unit_inst"
			if grep -q '^User=' "$unit_inst"; then
				sed -i \
					-e "s/<USER>/$CA_ADMIN_LOGIN/" \
					-e '/^PIDFile=/d' \
					"$unit_inst"
			else
				sed -i \
					-e '/Type=forking/a\' -e 'WorkingDirectory=/home/'"$CA_ADMIN_LOGIN"'\nUser='"$CA_ADMIN_LOGIN"'\nGroup='"$CA_ADMIN_LOGIN" \
					"$unit_inst"
			fi
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
	if dnf module list 389-ds >/dev/null; then
		if ! dnf module list --enabled 389-ds >/dev/null 2>&1; then
			dnf -y module enable 389-ds
		fi
	fi
	if ! pkg_install 389-ds; then
		if ! pkg_install 389-ds-base; then
			echo 'Failed to find 389-ds or 389-ds-base packages.'
			exit 1
		fi
	fi
	pkg_install cockpit-389-ds

	if dsctl -l 2>/dev/null |grep "slapd-$DS_INST_NAME"; then
		echo "DS $DS_INST_NAME exists already."
	else
		if [ -e ds.inf ]; then
			echo 'DS inf already exists.'
		else
			echo 'Configuring DS inf...'
			if [ -z "$DRY_RUN" ]; then
				if ! dscreate create-template ds.tmp; then
					echo 'Failed to create 389 configuration template.'
					exit 1
				fi
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
				if [ "$os_type" = "FEDORA" ]; then
					# work around F29 bug for missing environment file
					if [ ! -e "/etc/sysconfig/dirsrv-$DS_INST_NAME" ]; then
						echo "Creating /etc/sysconfig/dirsrv-$DS_INST_NAME environment file..."
						if [ -e /etc/sysconfig/dirsrv ]; then
							cp -a /etc/sysconfig/dirsrv "/etc/sysconfig/dirsrv-$DS_INST_NAME"
						else
							touch "/etc/sysconfig/dirsrv-$DS_INST_NAME"
						fi
					fi
				fi
				if ! dscreate from-file ds.inf; then
					echo 'Failed to create 389 instance from ds.inf'
					exit 1
				fi
				mv ds.inf "ds-$DS_INST_NAME.inf"
			fi
		fi
	fi
}

setup_pki_pkcs12 () {
	local p12_file=$(grep '^pki_pkcs12_path=' "$BASE_DIR/$CA_CONF" 2>/dev/null |cut -d= -f2)
	local p12_pw=$(grep '^pki_pkcs12_password=' "$BASE_DIR/$CA_CONF" 2>/dev/null |cut -d= -f2)
	local p12_nick=$(grep '^pki_ca_signing_nickname=' "$BASE_DIR/$CA_CONF" 2>/dev/null |cut -d= -f2)
	if [ -n "$p12_file" -a -n "$p12_pw"  -a -n "$p12_nick" ]; then
		if pki pkcs12-cert-find --pkcs12-file "$p12_file" --pkcs12-password "$p12_pw" |grep -A 3 "$p12_nick" |tail -1 |grep 'Trust Flags'; then
			echo "PKI PKCS#12 $p12_file nickname [$p12_nick] already has trust flags set."
		else
			echo "Setting PKI PKCS#12 $p12_file nickname [$p12_nick] trust flags..."
			if [ -z "$DRY_RUN" ]; then
				pki pkcs12-cert-mod "$p12_nick" --pkcs12-file "$p12_file" --pkcs12-password "$p12_pw" --trust-flags "CTu,Cu,Cu"
			fi
		fi
	fi
}

setup_pki_server_p12 () {
	local dns_name="$1"
	local dn_ou="$2"
	local p12_pass="$3"
	if [ -e "$CA_ADMIN_HOME/.dogtag/pki-tomcat/$dns_name.p12" ]; then
		echo "$dns_name certificate already exists."
	else
		echo "Creating $dns_name certificate..."
		if [ -z "$DRY_RUN" ]; then
			local req_id=$(sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" client-cert-request \
				"CN=$dns_name,OU=$dn_ou,O=$CA_SEC_DOMAIN_NAME" --profile caServerCert \
				|grep 'Request ID:' |cut -d : -f 2 |xargs)
			if [ -z "$req_id" ]; then
				echo "ERROR: unable to request $dns_name certificate."
				exit 1
			else
				echo "Approving $dns_name certificate request $req_id..."
				local cert_id=$(sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" ca-cert-request-review "$req_id" --action approve \
					|grep 'Certificate ID:'|cut -d : -f 2 |xargs)
				if [ -z "$cert_id" ]; then
					echo "ERROR: unable to approve $dns_name certificate."
					exit 1
				else
					echo "Saving approved $dns_name certificate $cert_id to .dogtag/pki-tomcat/$dns_name.crt"
					sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" ca-cert-show $cert_id --encoded \
						--output "$CA_ADMIN_HOME/.dogtag/pki-tomcat/$dns_name.crt"
						
					echo "Importing approved $dns_name certificate $cert_id to nssdb..."
					sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" client-cert-import "$dns_name" --serial $cert_id
				
					echo "Exporting approved $dns_name certificate and private key $cert_id to .dogtag/pki-tomcat/$dns_name.p12..."
					sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" pkcs12-cert-import "$dns_name" \
						--pkcs12-file "$CA_ADMIN_HOME/.dogtag/pki-tomcat/$dns_name.p12" --pkcs12-password "$p12_pass" \
						--no-trust-flags --no-chain --key-encryption 'PBE/SHA1/DES3/CBC'
				fi
			fi	
		fi
	fi
}

setup_pki_user_p12 () {
	local user_uid="$1"
	local user_email="$2"
	local dn_ou="$3"
	local p12_pass="$4"
	local ca_user="$5" # pass non-empty value to add certificate to CA user with same UID as $user_uid
	if [ -e "$CA_ADMIN_HOME/.dogtag/pki-tomcat/${dn_ou}-$user_uid.p12" ]; then
		echo "$dn_ou $user_uid certificate already exists."
	else
		echo "Creating $dn_ou $user_uid certificate..."
		if [ -z "$DRY_RUN" ]; then
			local req_id=$(sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" client-cert-request \
				"UID=$user_uid,E=$user_email,CN=$user_uid,OU=$dn_ou,O=$CA_SEC_DOMAIN_NAME" --profile caUserCert \
				|grep 'Request ID:' |cut -d : -f 2 |xargs)
			if [ -z "$req_id" ]; then
				echo "ERROR: unable to request $user_uid certificate."
				exit 1
			else
				echo "Approving $user_uid certificate request $req_id..."
				local cert_id=$(sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" ca-cert-request-review "$req_id" --action approve \
					|grep 'Certificate ID:'|cut -d : -f 2 |xargs)
				if [ -z "$cert_id" ]; then
					echo "ERROR: unable to approve $user_uid certificate."
					exit 1
				else
					if [ -n "$ca_user" ]; then
						echo "Adding $user_uid certificate to user..."
						sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" ca-user-cert-add "$user_uid" --serial "$cert_id"
					fi
										
					echo "Importing approved $user_uid certificate $cert_id to nssdb..."
					sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" client-cert-import "$user_uid" --serial $cert_id
					
					echo "Exporting approved $user_uid certificate and private key $cert_id to .dogtag/pki-tomcat/${dn_ou}-$user_uid.p12..."
					sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" pkcs12-cert-import "$user_uid" \
						--pkcs12-file "$CA_ADMIN_HOME/.dogtag/pki-tomcat/${dn_ou}-$user_uid.p12" --pkcs12-password "$p12_pass" \
						--no-trust-flags --no-chain --key-encryption 'PBE/SHA1/DES3/CBC'
				fi
			fi	
		fi
	fi
}

setup_pki () {
	if dnf module list pki-core >/dev/null; then
		if ! dnf module list --enabled pki-core >/dev/null 2>&1; then
			dnf -y module enable pki-core
		fi
	fi

	if [ "$os_type" = "FEDORA" ]; then
		pkg_install pki-ca "$PKI_REPO_EXCLUDE"
		pkg_install dogtag-pki-server-theme "$PKI_REPO_EXCLUDE"

		# non-headless Java needed for console
		pkg_install java-1.8.0-openjdk
		pkg_install pki-console "$PKI_REPO_EXCLUDE"
	else
		pkg_install pki-ca
	fi
	
	
	setup_pki_pkcs12
	
	if [ -d /var/lib/pki/pki-tomcat ]; then
		echo 'Dogtag CA already present.'
	else
		echo "Creating Dogtag CA system using configuration $CA_CONF..."
		if [ -z "$DRY_RUN" ]; then
			if [ ! -e "$BASE_DIR/$CA_CONF" ]; then
				echo "Dogtag CA config $CA_CONF not found; cannot create Dogtag CA system."
				exit 1
			else
 				pkispawn -s CA -f "$BASE_DIR/$CA_CONF"
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
				pki -n "$admin_nickname" ca-profile-add "$BASE_DIR/$SN_PROFILE_CONF" --raw
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
	# using the SN_IN_JKS_PASS.
	setup_pki_server_p12 "$SN_IN_DNS_NAME" "SolarIn" "$SN_IN_JKS_PASS"

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
				-srcstoretype pkcs12 -srcstorepass "$SN_IN_JKS_PASS" -srckeypass "$SN_IN_JKS_PASS" \
				-destkeystore "$CA_ADMIN_HOME/.dogtag/pki-tomcat/central.jks" \
				-deststoretype jks -deststorepass "$SN_IN_JKS_PASS" -destkeypass "$SN_IN_JKS_PASS" \
				-noprompt -srcalias $SN_IN_DNS_NAME -destalias web
		fi
	fi
	
	# Solar server certificates creation
	#
	# The following block iterates over SN_SERVER_DNS_NAMES and creates certificate and PKCS#12 archives for each. The
	# certificates and private keys named after the DNS name, saved to .dogtag/pki-tomcat using the 
	# SN_SERVER_P12_PASS password.
	for pair in $SN_SERVER_DNS_NAMES; do
		setup_pki_server_p12 "${pair#*:}" "${pair%:*}" "$SN_SERVER_P12_PASS"
	done

	# SolarUser agent certificate creation
	#
	# SolarUser requires an "agent" user and associated client certificate to manage SolarNode certificates.
	# The following block creates a `suagent` PKI user, adds them to the `Certificate Manager Agents` group,
	# and then creates a certificate for the user. The certificate and private key will be exported as a 
	# PKCS#12 file at .dogtag/pki-tomcat/suagent.p12
	
	if [ -e "$CA_ADMIN_HOME/.dogtag/pki-tomcat/SolarUser-$CA_AGENT_UID.p12" ]; then
		echo "SolarUser $CA_AGENT_UID certificate already exists."
	else
		echo "Creating SolarUser agent user $CA_AGENT_UID..."
		if [ -z "$DRY_RUN" ]; then
			sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname" ca-user-add "$CA_AGENT_UID" \
				--fullName "$CA_AGENT_NAME" --email "$CA_AGENT_EMAIL"
				
			echo "Adding $CA_AGENT_UID agent user to group..."
			sudo -u $CA_ADMIN_LOGIN pki -c "$CA_SEC_DOMAIN_PASS" -n "$admin_nickname"  ca-group-member-add \
				"Certificate Manager Agents" "$CA_AGENT_UID"
		fi
		
		setup_pki_user_p12 "$CA_AGENT_UID" "$CA_AGENT_EMAIL" "SolarUser" "$CA_AGENT_P12_PASS" "1"
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
				-srckeystore "$CA_ADMIN_HOME/.dogtag/pki-tomcat/SolarUser-$CA_AGENT_UID.p12" \
				-srcstoretype pkcs12 -srcstorepass "$CA_AGENT_P12_PASS" -srckeypass "$CA_AGENT_P12_PASS" \
				-destkeystore "$CA_ADMIN_HOME/.dogtag/pki-tomcat/dogtag-client.jks" \
				-deststoretype jks -deststorepass "$CA_AGENT_JKS_PASS" -destkeypass "$CA_AGENT_JKS_PASS" \
				-noprompt -srcalias $CA_AGENT_UID -destalias $CA_AGENT_UID
		fi
	fi

	# Useragent certificate creation
	#
	# Other certificates are created (for non-CA users), such as database users
	
	for tuple in $SN_USER_NAMES; do
		setup_pki_user_p12 "$(echo $tuple |cut -d: -f2)" "$(echo $tuple |cut -d: -f3)" "$(echo $tuple |cut -d: -f1)" "$SN_USER_P12_PASS"
	done
}

setup_ds_import () {
	if [ ! -e "$BASE_DIR/$DS_IMPORT_LDIF" ]; then
		echo "Directory Server LDIF import file [$DS_IMPORT_LDIF] not found."
	else
		echo "Importing Directory Server LDIF file [$DS_IMPORT_LDIF]..."
		if [ -z "$DRY_RUN" ]; then
			systemctl stop pki-tomcatd.target
			db2bak
			ldapadd -x -w "$DS_ROOT_PASS" -D 'cn=Directory Manager' -c -f "$BASE_DIR/$DS_IMPORT_LDIF" \
				>"$CA_ADMIN_HOME/.dogtag/pki-tomcat/ds-import-ldif.log" 2>&1
			systemctl start pki-tomcatd.target
			did_ds_ldif_import=1
		fi
	fi
}

setup_firewall () {
	echo 'Opening ports 8080, 8443 in firewall...'
	if [ -z "$DRY_RUN" ]; then
		firewall-cmd --quiet --zone=public --add-port=8080/tcp
		firewall-cmd --quiet --zone=public --add-port=8080/tcp --permanent
		firewall-cmd --quiet --zone=public --add-port=8443/tcp
		firewall-cmd --quiet --zone=public --add-port=8443/tcp --permanent
	fi
}

setup_cockpit () {
	if rpm -q cockpit >/dev/null; then
		if systemctl status cockpit.socket |grep ' disabled;'; then
			echo 'Enabling cockpit service...'
			if [ -z "$DRY_RUN" ]; then
				systemctl enable cockpit.socket
				systemctl start cockpit.socket
			fi
		else
			echo 'Cockpit service already enabled.'
		fi
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
			
			A SolarIn web server private key and certificate have been saved as a PKCS#12 file using
			the password '$SN_IN_JKS_PASS' at
			
			  $CA_ADMIN_HOME/.dogtag/pki-tomcat/$SN_IN_DNS_NAME.p12
			  
			A copy of that has been saved with the password '$SN_IN_JKS_PASS' to:
			
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
	if [ -n "$SN_SERVER_DNS_NAMES" ]; then
		cat <<-EOF
		
			All application server private key and certificates (from the -m argument) have been 
			saved as PKCS#12 files using the password '$SN_SERVER_P12_PASS' to:
			
			  $CA_ADMIN_HOME/.dogtag/pki-tomcat/*.p12
		EOF
	fi
	if [ -n "$SN_USER_NAMES" ]; then
		cat <<-EOF
		
			All user private key and certificates (from the -w argument) have been 
			saved as PKCS#12 files using the password '$SN_USER_P12_PASS' to:
			
			  $CA_ADMIN_HOME/.dogtag/pki-tomcat/*.p12
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

setup_cfg_vars
setup_pkgs
setup_repos
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
setup_cockpit
setup_firewall

show_results
