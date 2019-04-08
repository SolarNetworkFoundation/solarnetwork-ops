#!/usr/bin/env bash

DRY_RUN=""
DS_INST_NAME="ca"
DS_ROOT_PW="admin"
DS_SUFFIX="dc=solarnetworkdev,dc=net"
HOSTNAME="ca.solarnetworkdev.net"
UPDATE_PKGS=""
VERBOSE=""

do_help () {
	cat 1>&2 <<EOF
Usage: $0 [-nuv]

Arguments:
 -h <host name>      - the FQDN for the machine; defaults to ca.solarnetworkdev.net
 -n                  - dry run; do not make any actual changes
 -o <DS inst name>   - the Directory Server instance name; defaults to ca
 -p <DS root pw>     - the Directory Server root user password; defaults to admin
 -s <DN suffix>      - the Directory Server DN suffix to use; defaults to dc=solarnetworkdev,dc=net
 -u                  - update package cache
 -v                  - verbose mode; print out more verbose messages
EOF
}

while getopts ":h:no:p:s:uv" opt; do
	case $opt in
		
		h) HOSTNAME="${OPTARG}";;
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

# install package if not already installed
apt_install () {	
	if dpkg -s $1 >/dev/null 2>/dev/null; then
		echo "Package $1 already installed."
	else
		echo "Installing package $1 ..."
		if [ -z "$DRY_RUN" ]; then
			sudo apt-get -y -q install $1
		fi
	fi
}

setup_pkgs () {
	if [ -n "$UPDATE_PKGS" ]; then
		sudo apt-get update
	fi
}

setup_desktop () {
	apt_install xfce4
}

setup_vnc () {
	apt_install tigervnc-standalone-server
	
	if sudo ls -d /home/caadmin/.vnc >/dev/null 2>&1; then
		echo 'caadmin VNC configuration dir already exists.'
	else
		if [ -z "$DRY_RUN" ]; then
			sudo -u caadmin mkdir /home/caadmin/.vnc
		fi
	fi
	
	if sudo ls /home/caadmin/.vnc/passwd >/dev/null 2>&1; then
		echo 'caadmin VNC password already exists.'
	else
		echo 'Setting up VNC password for caadmin...'
		if [ -z "$DRY_RUN" ]; then
			sudo /sbin/runuser -u caadmin vncpasswd
		fi
	fi
	
	if sudo ls /home/caadmin/.vnc/config >/dev/null 2>&1; then
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

	if sudo ls /home/caadmin/.vnc/xstartup >/dev/null 2>&1; then
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
		echo 'VNC service already exists.'
	else
		echo 'Configuring VNC server for caadmin...'
		if [ -z "$DRY_RUN" ]; then
			local conf=$(cat <<-"EOF"
				[Unit]
				Description=VNC server
				After=syslog.target network.target

				[Service]
				Type=forking
				User=caadmin
				Group=caadmin
				WorkingDirectory=/home/caadmin

				PIDFile=/home/caadmin/.vnc/%H%i.pid
				ExecStartPre=-/usr/bin/vncserver -kill %i > /dev/null 2>&1
				ExecStart=/usr/bin/vncserver -depth 24 -geometry 1280x1024 %i
				ExecStop=/usr/bin/vncserver -kill %i

				[Install]
				WantedBy=multi-user.target
			EOF
			)
			echo "$conf" |sudo tee /etc/systemd/system/vncserver@:1.service
			sudo systemctl daemon-reload
			sudo systemctl enable vncserver@:1
		fi
	fi
}

setup_ds () {
	apt_install 389-ds
	
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
			sudo dscreate -v fromfile ds.inf
		fi
	fi
}

setup_pki () {
	apt_install dogtag-pki
}

setup_pkgs
setup_hostname
setup_dns
setup_osuser
setup_desktop
setup_vnc
setup_ds
setup_pki
