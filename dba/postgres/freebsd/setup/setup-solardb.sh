#!/usr/bin/env sh
set -e

AWS_CONF="${AWS_CONF:-aws-config.tmpl}"
AWS_USERNAME="${AWS_USERNAME:-USERNAME_CHANGEME}"
AWS_PASSWORD="${AWS_PASSWORD:-PASSWORD_CHANGEME}"
CERTBOT_RENEWAL_HOOK="${CERTBOT_RENEWAL_HOOK:-certbot-renewal-hook.sh}"
CERTBOT_CERT_SUPPORT_SERVICE="${CERTBOT_CERT_SUPPORT_SERVICE:-certbot-cert-support-service.sh}"
CRON_POSTGRES_CONF="${CRON_POSTGRES_CONF:-cron-postgres.tmpl}"
MUNIN_CONF="${MUNIN_CONF:-munin-conf.tmpl}"
MUNIN_CONF_SED="${MUNIN_CONF_SED:-munin-conf.sed}"
MUNIN_ZFS_FSGRAPH="${MUNIN_ZFS_FSGRAPH:-zfs-filesystem-graph.sh}"
OS_HOSTNAME="${OS_HOSTNAME:-solardb-test}"
OS_LOADER_CONF="${OS_LOADER_CONF:-loader.conf}"
OS_SYSCTL_CONF="${OS_SYSCTL_CONF:-sysctl.conf}"
PKG_ADD_LIST="${PKG_ADD_LIST:-packages-add.txt}"
PKG_REPO_CERT="${PKG_REPO_CERT:-pkg-repo-snf.cert}"
PKG_REPO_CONF="${PKG_REPO_CONF:-pkg-repo-snf.conf}"
POSTGRES_LOGIN_CONF="${POSTGRES_LOGIN_CONF:-postgres-login.conf}"
POSTFIX_CONF="${POSTFIX_CONF:-postfix-main.cf}"
POSTFIX_ROOT_EMAIL="${POSTFIX_ROOT_EMAIL:-operations@localhost}"
POSTFIX_SASL_CONF="${POSTFIX_SASL_CONF:-postfix-sasl_passwd.tmpl}"
POSTFIX_SASL_USERNAME="${POSTFIX_SASL_USERNAME:-USERNAME_CHANGEME}"
POSTFIX_SASL_PASSWORD="${POSTFIX_SASL_PASSWORD:-PASSWORD_CHANGEME}"

BASE_DIR="./example"
DRY_RUN=""
UPGRADE_PKGS=""
VERBOSE=""

do_help () {
	cat 1>&2 <<EOF
Usage: $0 [-b dir] [-hnuv]

Arguments:
 -b <base dir>          - base dir for relative paths (${BASE_DIR})
 -h                     - print this help
 -n                     - dry run; do not make any actual changes
 -u                     - update package cache
 -v                     - verbose mode; print out more verbose messages

Environment variables:

AWS_CONF ..................... ${AWS_CONF}
AWS_USERNAME                   ${AWS_USERNAME}
AWS_PASSWORD                   ${AWS_PASSWORD}
CERTBOT_RENEWAL_HOOK ......... ${CERTBOT_RENEWAL_HOOK}
CERTBOT_CERT_SUPPORT_SERVICE   ${CERTBOT_CERT_SUPPORT_SERVICE}
CRON_POSTGRES_CONF ........... ${CRON_POSTGRES_CONF}
MININ_CONF ................... ${MUNIN_CONF}
MININ_CONF_SED                 ${MININ_CONF_SED}
OS_HOSTNAME .................. ${OS_HOSTNAME}
OS_LOADER_CONF                 ${OS_LOADER_CONF}
OS_SYSCTL_CONF                 ${OS_SYSCTL_CONF}
PKG_REPO_CERT ................ ${PKG_REPO_CERT}
PKG_REPO_CONF                  ${PKG_REPO_CONF}
PKG_ADD_LIST                   ${PKG_ADD_LIST}
POSTGRES_LOGIN_CONF .......... ${POSTGRES_LOGIN_CONF}
POSTFIX_CONF ................. ${POSTFIX_CONF}
POSTFIX_ROOT_EMAIL             ${POSTFIX_ROOT_EMAIL}
POSTFIX_SASL_CONF              ${POSTFIX_SASL_CONF}
POSTFIX_SASL_USERNAME          ${POSTFIX_SASL_USERNAME}
POSTFIX_SASL_PASSWORD          ${POSTFIX_SASL_PASSWORD}

EOF
}

while getopts ":b:hnuv" opt; do
	case $opt in
		b) BASE_DIR="${OPTARG}";;
		h) do_help; exit 1;;
		n) DRY_RUN='TRUE';;
		u) UPGRADE_PKGS='TRUE';;
		v) VERBOSE='TRUE';;
		*)
			echo "Unknown argument ${OPTARG}"
			do_help
			exit 1
	esac
done
shift $(($OPTIND - 1))

if [ $(id -u) -ne 0 ]; then
	echo "This script must be run as root."
	exit 1
fi

check_file_contains () {
	local msg="$1"
	local src_file="$2"
	local dest_file="$3"
	if [ -e "$src_file" ]; then
		if [ ! -e "$dest_file" ]; then
			echo "Configuring $msg."
			if [ -z "$DRY_RUN" ]; then
				install -m 0644 "$src_file" "$dest_file"
			fi
		else
			sed '/^$/d' "$src_file" >/tmp/f1.tmp
			sed '/^$/d' "$dest_file" >/tmp/f2.tmp
			if ! grep -Fqx -f /tmp/f1.tmp /tmp/f2.tmp; then
				echo "Configuring $msg in $dest_file."
				if [ -z "$DRY_RUN" ]; then
					cat "$src_file" >>"$dest_file"
				fi
			else
				echo "$msg already configured in $dest_file."
			fi
			rm -f /tmp/f1.tmp /tmp/f2.tmp
		fi
	fi
}

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

config_hostname () {
	if [ "$(sysrc -nq hostname)" = "$OS_HOSTNAME" ]; then
		echo "Hostname already set to $OS_HOSTNAME."
	else
		echo "Setting hostname to $OS_HOSTNAME..."
		if [ -z "$DRY_RUN" ]; then
			hostname "$OS_HOSTNAME"
			sysrc "hostname=$OS_HOSTNAME"
		fi
	fi

	# Setup DNS to resolve hostname
	if grep -q "$OS_HOSTNAME" /etc/hosts >/dev/null; then
		echo "$OS_HOSTNAME already configured in /etc/hosts."
	else
		echo "Setting up $OS_HOSTNAME host entry in /etc/hosts..."
		if [ -z "$DRY_RUN" ]; then
			sed "s/^127.0.0.1[[:space:]]*localhost/127.0.0.1 $OS_HOSTNAME localhost/" /etc/hosts >/tmp/hosts.new
			if diff -q /etc/hosts /tmp/hosts.new >/dev/null; then
				# didn't change anything, try 127.0.1.0
				sed "s/^127.0.1.1.*/127.0.1.1 $OS_HOSTNAME/" /etc/hosts >/tmp/hosts.new
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

config_boot_loader () {
	check_file_contains "Kernel settings" "$BASE_DIR/$OS_LOADER_CONF" /boot/loader.conf
}

config_sysctl () {
	check_file_contains "System settings" "$BASE_DIR/$OS_SYSCTL_CONF" /etc/sysctl.conf
}

config_syslog () {
	if [ "$(sysrc -nq syslogd_flags)" = "-ss" ]; then
		echo "Configuring syslog."
		if [ -z "$DRY_RUN" ]; then
			sysrc syslogd_flags=-ss
		fi
	else
		echo "Syslog already configured."
	fi
}

config_swap () {
	if [ -e /usr/swap0 ]; then
		echo "Swap already configured."
	else
		echo "Configuring swap."
		if [ -z "$DRY_RUN" ]; then
			dd if=/dev/zero of=/usr/swap0 bs=1m count=1024
			chmod 600 /usr/swap0
			echo 'md99   none    swap    sw,file=/usr/swap0,late 0       0' >>/etc/fstab
			swapon -aL
		fi
	fi
}

config_zfs () {
	if [ "$(sysrc -nq zfs_enable)" = "YES" ]; then
		echo "Configuring ZFS."
		if [ -z "$DRY_RUN" ]; then
			sysrc zfs_enable=YES
		fi
	else
		echo "ZFS already configured."
	fi
}

config_pkg () {
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

config_periodic () {
	if sysrc -qn -f /etc/periodic.conf daily_clean_hoststat_enable >/dev/null; then
		echo "Periodic already configured."
	else
		echo "Configuring Periodic"
		if [ -z "$DRY_RUN" ]; then
			echo daily_clean_hoststat_enable daily_status_mail_rejects_enable daily_status_include_submit_mailq daily_submit_queuerun \
				| xargs printf -- '%s=NO\n' \
				| xargs sysrc -f /etc/periodic.conf
		fi
	fi
}

config_postfix () {
	if [ -e /usr/local/etc/mail/mailer.conf ]; then
		echo "Postfix already configured."
	elif [ -e /usr/local/share/postfix/mailer.conf.postfix ]; then
		echo "Configuring Postfix"
		if [ -z "$DRY_RUN" ]; then
			mkdir -p /usr/local/etc/mail
			install -m 0644 /usr/local/share/postfix/mailer.conf.postfix /usr/local/etc/mail/mailer.conf

			if [ -e "$BASE_DIR/$POSTFIX_CONF" ]; then
				cat "$BASE_DIR/$POSTFIX_CONF" >>/usr/local/etc/postfix/main.cf
			fi
			if [ -e "$BASE_DIR/$POSTFIX_SASL_CONF" ]; then
				install -m 0600 "$BASE_DIR/$POSTFIX_SASL_CONF" /usr/local/etc/postfix/sasl_passwd
				sed -i '' -e "s/USERNAME/${POSTFIX_SASL_USERNAME}/" \
					-e "s/PASSWORD/${POSTFIX_SASL_PASSWORD}/" \
					/usr/local/etc/postfix/sasl_passwd
				postmap hash:/usr/local/etc/postfix/sasl_passwd
			fi

			sysrc sendmail_enable="NONE"
			sysrc postfix_enable="YES"
		fi
	else
		echo "Postfix not installed; not configuring."
	fi
	if grep -q "^root: ${POSTFIX_ROOT_EMAIL}" /etc/mail/aliases 2>/dev/null; then
		echo "Root email ${POSTFIX_ROOT_EMAIL} already configured."
	else
		echo "Configuring root email ${POSTFIX_ROOT_EMAIL}."
		if [ -z "$DRY_RUN" ]; then
			sed -i '' -e "s/^[# ]*root:.*/root: ${POSTFIX_ROOT_EMAIL}/" /etc/mail/aliases
			newaliases
		fi
	fi
}

config_cron () {
	if grep -q "cron_enable" /etc/rc.conf 2>/dev/null; then
		echo "Cron already configured."
	else
		echo "Configuring cron."
		if [ -z "$DRY_RUN" ]; then
			sysrc cron_enable=YES 'cron_flags=$cron_flags -J 15'
			if [ -e "${CRON_POSTGRES_CONF}" ]; then
				crontab -u postgres "${CRON_POSTGRES_CONF}"
			fi
		fi
	fi
}

config_certbot () {
	if [ -e ~/.aws/config ]; then
		echo "AWS already configured for Certbot."
	elif [ -e "$BASE_DIR/$AWS_CONF" ]; then
		echo "Configuring AWS for Certbot."
		if [ -z "$DRY_RUN" ]; then
			mkdir -p ~/.aws
			install -m 0600 "$BASE_DIR/$AWS_CONF"  ~/.aws/config
			sed -i '' -e "s/USERNAME/${AWS_USERNAME}/" \
				-e "s/PASSWORD/${AWS_PASSWORD}/" \
				~/.aws/config
		fi
	fi
	if [ -e /usr/local/etc/letsencrypt/renewal-hooks/deploy/solardb.sh ]; then
		echo "Certbot already configured."
	elif [ -e "$BASE_DIR/$CERTBOT_RENEWAL_HOOK" ]; then
		echo "Configuring Certbot."
		if [ -z "$DRY_RUN" ]; then
			mkdir -p /usr/local/etc/letsencrypt/renewal-hooks/deploy
			install -m 0755 "$BASE_DIR/$CERTBOT_RENEWAL_HOOK" \
				/usr/local/etc/letsencrypt/renewal-hooks/deploy/solardb.sh
		fi
	fi
	if [ -e /usr/local/etc/rc.d/cert-support ]; then
		echo "Certbot cert-support service already configured."
	elif [ -e "$BASE_DIR/$CERTBOT_CERT_SUPPORT_SERVICE" ]; then
		echo "Configuring Certbot cert-support service."
		if [ -z "$DRY_RUN" ]; then
			install -m 0755 "$BASE_DIR/$CERTBOT_CERT_SUPPORT_SERVICE" \
				/usr/local/etc/rc.d/cert-support
			sysrc cert_support_enable=YES
		fi
	fi
}

config_munin () {
	if grep -q "postgres_" /usr/local/etc/munin/plugin-conf.d/plugins.conf 2>/dev/null; then
		echo "Munin already configured."
	elif [ -e "$BASE_DIR/$MUNIN_CONF" -a -e /usr/local/etc/munin/plugin-conf.d/plugins.conf ]; then
		echo "Configuring Munin."
		if [ -z "$DRY_RUN" ]; then
			if [ -e "$BASE_DIR/$MUNIN_CONF_SED" ]; then
				sed -i '' \
					-e "s/^#host_name .*/host_name ${OS_HOSTNAME}/" \
					-f "$BASE_DIR/$MUNIN_CONF_SED" \
					/usr/local/etc/munin/munin-node.conf
			else
				sed -i '' \
					-e "s/^#host_name .*/host_name ${OS_HOSTNAME}/" \
					/usr/local/etc/munin/munin-node.conf
			fi

			cat "$BASE_DIR/$MUNIN_CONF"  >>/usr/local/etc/munin/plugin-conf.d/plugins.conf

			local s="/usr/local/share/munin/plugins"
			local d="/usr/local/etc/munin/plugins"

			ln -sf "$s/cpu" "$d/cpu"
			ln -sf "$s/if_" "$d/if_ena0"
			ln -sf "$s/iostat" "$d/iostat"
			ln -sf "$s/load" "$d/load"
			ln -sf "$s/memory" "$d/memory"
			ln -sf "$s/netstat" "$d/netstat"

			ln -sf "$s/postgres_autovacuum" "$d/postgres_autovacuum"
			ln -sf "$s/postgres_bgwriter" "$d/postgres_bgwriter"
			ln -sf "$s/postgres_cache_" "$d/postgres_cache_solarnetwork"
			ln -sf "$s/postgres_checkpoints" "$d/postgres_checkpoints"
			ln -sf "$s/postgres_connections_db" "$d/postgres_connections_db"
			ln -sf "$s/postgres_connections_" "$d/postgres_connections_solarnetwork"
			ln -sf "$s/postgres_locks_" "$d/postgres_locks_solarnetwork"
			ln -sf "$s/postgres_querylength_" "$d/postgres_querylength_solarnetwork"
			ln -sf "$s/postgres_scans_" "$d/postgres_scans_solarnetwork"
			ln -sf "$s/postgres_size_" "$d/postgres_size_solarnetwork"
			ln -sf "$s/postgres_transactions_" "$d/postgres_transactions_solarnetwork"
			ln -sf "$s/postgres_tuples_" "$d/postgres_tuples_solarnetwork"
			ln -sf "$s/postgres_users" "$d/postgres_users"
			ln -sf "$s/postgres_xlog" "$d/postgres_xlog"

			ln -sf "$s/processes" "$d/processes"
			ln -sf "$s/swap" "$d/swap"
			ln -sf "$s/systat" "$d/systat"
			ln -sf "$s/uptime" "$d/uptime"
			ln -sf "$s/users" "$d/users"
			ln -sf "$s/vmstat" "$d/vmstat"
			ln -sf "$s/zfs_arcstats" "$d/zfs_arcstats"

			if [ -e "$BASE_DIR/$MUNIN_ZFS_FSGRAPH" ]; then
				install -m 0755 "$BASE_DIR/$MUNIN_ZFS_FSGRAPH" \
					$s/zfs-filesystem-graph
				ln -sf "$s/zfs-filesystem-graph" "$d/zfs_fs_dat"
				ln -sf "$s/zfs-filesystem-graph" "$d/zfs_fs_idx"
				ln -sf "$s/zfs-filesystem-graph" "$d/zfs_fs_wal"
			fi

			if [ -n "$VERBOSE" ]; then
				echo "Munin configurations:"
				ls -l $d/
				echo
			fi

			sysrc munin_node_enable=YES
		fi
	fi
}

config_postgres () {
	local pg_home=/sndb/home/17
	if [ "$(sysrc -nq postgresql_data)" != "/sndb/home/17" ]; then
		echo "Configuring Postgres."
		if [ -z "$DRY_RUN" ]; then
			sysrc postgresql_enable=NO \
				"postgresql_data=$pg_home" \
				'postgresql_flags=-w -s -m fast' \
				'postgresql_initdb_flags=--encoding=utf-8 --locale=C' \
				postgresql_user=postgres \
				postgresql_class=postgres
		fi
	else
		echo "Postgres already configured."
	fi
	check_file_contains "Postgres user" "$BASE_DIR/$POSTGRES_LOGIN_CONF" /etc/login.conf
	if [ -z "$DRY_RUN" ]; then
		cap_mkdb /etc/login.conf
	fi
	if [ -d "$pg_home" -a ! -e "$pg_home/postgresql.conf" ]; then
		echo "Initializing Postgres cluster in $pg_home"
		if [ -z "$DRY_RUN" ]; then
			service postgresql oneinitdb
		fi
	elif [ ! -d "$pg_home" ]; then
		echo "WARN: Postgres cluster home does not exist, cannot initialize: $pg_home"
	else
		echo "Postgres cluster already initialized in $pg_home"
	fi
}

config_hostname
config_boot_loader
config_sysctl
config_syslog
config_swap
pkg_bootstrap
config_pkg
pkg_add
config_periodic
config_postfix
config_cron
config_certbot
config_munin
config_postgres
