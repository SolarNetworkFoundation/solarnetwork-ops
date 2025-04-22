#!/usr/bin/env sh
set -e

BASE_DIR="."
DRY_RUN=""
HOSTNAME="solardb-test.solarnetwork"
OS_LOADER_CONF="example/loader.conf"
OS_SYSCTL_CONF="example/sysctl.conf"
PKG_REPO_CONF="example/pkg/snf.conf"
PKG_REPO_CERT="example/pkg/snf-repo.cert"
PKG_ADD_LIST="example/packages-add.txt"
UPGRADE_PKGS=""
VERBOSE=""

if [ $(id -u) -ne 0 ]; then
	echo "This script must be run as root."
	exit 1
fi

do_help () {
	cat 1>&2 <<EOF
Usage: $0 [-nuv]

Arguments:
 -a <pkg list path>     - relative path to list of packages to install
 -b <base dir>          - base dir for relative paths; defaults to /var/tmp
 -h <hostname>          - the hostname to use; defaults to solardb
 -J <loader conf path>  - relative path to /boot/loader.conf settings to add; defaults to example/loader.conf
 -j <sysctl conf path>  - relative path to /etc/sysctl.conf settings to add; defaults to example/sysctl.conf
 -n                     - dry run; do not make any actual changes
 -P <pkg conf>          - relative path to the pkg configuration to add; defaults to example/snf.conf
 -p <pkg cert>          - relative path to the pkg certificate to add; defaults to example/snf-repo.cert
 -u                     - update package cache
 -v                     - verbose mode; print out more verbose messages
EOF
}

while getopts ":a:b:h:J:j:nP:p:uv" opt; do
	case $opt in
		a) PKG_ADD_LIST="${OPTARG}";;
		b) BASE_DIR="${OPTARG}";;
		h) HOSTNAME="${OPTARG}";;
		J) OS_LOADER_CONF="${OPTARG}";;
		j) OS_SYSCTL_CONF="${OPTARG}";;
		n) DRY_RUN='TRUE';;
		P) PKG_REPO_CONF="${OPTARG}";;
		p) PKG_REPO_CERT="${OPTARG}";;
		u) UPGRADE_PKGS='TRUE';;
		v) VERBOSE='TRUE';;
		?)
			echo "Unknown argument ${OPTARG}"
			do_help
			exit 1
	esac
done
shift $(($OPTIND - 1))

pkg_bootstrap () {
	if pkg -N >/dev/null 2>&1; then
		echo "pkg already bootstrapped."
	else
		echo "Bootstrapping pkg tool..."
		if [ -z "$DRY_RUN" ]; then
			# bootstrap pkg
			env ASSUME_ALWAYS_YES=YES pkg bootstrap
		fi
	fi
}

# install package if not already installed
pkg_install () {
	if pkg info --quiet $1 >/dev/null 2>&1; then
		echo "Package $1 already installed."
	else
		echo "Installing package $1 ..."
		if [ -z "$DRY_RUN" ]; then
			pkg install --no-repo-update --yes $1
		fi
	fi
}

setup_hostname () {
	if grep -q "hostname="'"'"$HOSTNAME"'"' /etc/rc.conf >/dev/null; then
		echo "Hostname already set to $HOSTNAME."
	else
		echo "Setting hostname to $HOSTNAME..."
		if [ -z "$DRY_RUN" ]; then
			hostname "$HOSTNAME"
			sed -Ei '' -e 's/hostname=.*/hostname="'"$HOSTNAME"'"/' /etc/rc.conf
		fi
	fi

	# Setup DNS to resolve hostname
	if grep -q "$HOSTNAME" /etc/hosts >/dev/null; then
		echo "$HOSTNAME already configured in /etc/hosts."
	else
		echo "Setting up $HOSTNAME host entry in /etc/hosts..."
		if [ -z "$DRY_RUN" ]; then
			sed "s/^127.0.0.1[[:space:]]*localhost/127.0.0.1 $HOSTNAME localhost/" /etc/hosts >/tmp/hosts.new
			if diff -q /etc/hosts /tmp/hosts.new >/dev/null; then
				# didn't change anything, try 127.0.1.0
				sed "s/^127.0.1.1.*/127.0.1.1 $HOSTNAME/" /etc/hosts >/tmp/hosts.new
			else
			fi
			if diff -q /etc/hosts /tmp/hosts.new >/dev/null; then
				echo "No change made to /etc/hosts."
			else
				chmod 644 /tmp/hosts.new
				cp -a /etc/hosts /etc/hosts.bak
				mv -f /tmp/hosts.new /etc/hosts
			fi
		fi
	fi
}

setup_pkg () {
	pkg_install ca_root_nss
	if [ -e /usr/local/etc/ssl/certs/snf-repo.cert ]; then
		echo "pkg repo solarnet certificate already configured."
	else
		echo "Configuring pkg repo solarnet cert from ${PKG_REPO_CERT}";
		if [ -z "$DRY_RUN" ]; then
			if [ ! -d /usr/local/etc/ssl/certs ]; then
				mkdir -p /usr/local/etc/ssl/certs
			fi
			cp "$BASE_DIR/${PKG_REPO_CERT}" /usr/local/etc/ssl/certs/snf-repo.cert
		fi
	fi
	if [ -e /usr/local/etc/pkg/repos/snf.conf ]; then
		echo "pkg repo solarnet already configured."
	else
		echo "Configuring pkg repo solarnet from ${PKG_REPO_CONF}";
		if [ -z "$DRY_RUN" ]; then
			if [ ! -d /usr/local/etc/pkg/repos ]; then
				mkdir -p /usr/local/etc/pkg/repos
			fi
			cp "$BASE_DIR/${PKG_REPO_CONF}" /usr/local/etc/pkg/repos/snf.conf
		fi
	fi
	if [ -n "$UPGRADE_PKGS" ]; then
		echo 'Upgrading OS packages...'
		if [ -z "$DRY_RUN" ]; then
			pkg update
			pkg upgrade --yes
		fi
	fi
}

pkg_add () {
	if [ -f "$BASE_DIR/${PKG_ADD_LIST}" ]; then
		echo "Adding packages from ${PKG_ADD_LIST}";
		if [ -z "$DRY_RUN" ]; then
			cat "$BASE_DIR/${PKG_ADD_LIST}" |xargs pkg install -r snf -y
		fi
	fi
}

config_postfix () {
	# TODO
	# mkdir -p /usr/local/etc/mail
	# install -m 0644 /usr/local/share/postfix/mailer.conf.postfix /usr/local/etc/mail/mailer.conf
}

setup_hostname
pkg_bootstrap
setup_pkg
pkg_add
config_postfix
