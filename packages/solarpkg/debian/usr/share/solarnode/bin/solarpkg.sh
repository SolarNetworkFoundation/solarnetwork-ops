#!/usr/bin/env sh
#
# Debian helper script for managing Debian packages.

VERBOSE=""
APT_FLAGS="-qy"
APT_OUTPUT="/dev/null"

do_help () {
	cat 1>&2 <<"EOF"
Usage: solarpkg [-v] <action> [arguments]

<action> is one of: clean, install, is-installed, list, refresh, remove, set-conf, upgrade

  clean
  
      Remove any cached download packages or temporary files. Remove any packages no longer
      required by other packages (autoremove).

  install <name> [<version>]
  
      Install package `name`. If `name` ends with '.deb' then install the package file `name`.
      Otherwise, download and install `name` from the configured apt repositories; if `version`
      specified then install the specific version.
      
  is-installed <name>
  
      Test if a particular package is installed. Returns 'true' or 'false'.
      
  list [<name>]
  
      List packages. If `name` is provided, only packages matching this name (including wildcards)
      will be listed. The output is a CSV table of columns: name, version, installed (true|false).
      
  list-available [<name>]
  
      List packages available to be installed (but are not yet installed). If `name` is provided, 
      only packages matching this name (including  wildcards) will be listed. The output is a CSV 
      table of columns: name, version, installed (true|false).
      
  list-installed [<name>]
  
      List installed packages. If `name` is provided, only packages matching this name (including 
      wildcards) will be listed. The output is a CSV table of columns: name, version, installed 
      (true|false).
      
  refresh
  
      Refresh the available packages from remote repositories.
      
  remove <name>
  
      Remove the package named `name`.
      
  upgrade [major]
  
      Upgrade all packages. If `major` defined, then perform a "major" upgrade using dist-upgrade.
      
EOF
}

while getopts ":v" opt; do
	case $opt in
		v) 
			VERBOSE="1"
			APT_FLAGS="-y"
			APT_OUTPUT="/dev/stdout"
			;;

		*) do_help; exit 1;;
	esac
done

shift $(($OPTIND - 1))

ACTION="$1"

if [ $# -lt 1 ]; then
	echo "Must provide action, use -? for help."  1>&2
	exit 1
fi

shift 1

# Set the frontend; NOTE sudo must be configured with env_keep+=DEBIAN_FRONTEND for this to work
export DEBIAN_FRONTEND=noninteractive

pkg_wait_not_busy () {
	while fuser /var/lib/dpkg/lock >/dev/null; do
		sleep 0.5
	done
}

pkg_list_files () {
	local pkg="$1"

	# assume dpkg -c output lines look like:
	#
	# drwxr-xr-x 0/0               0 2019-05-20 18:33 ./usr/share/solarnode/bin/
	# -rwxr-xr-x 0/0            2167 2019-05-20 18:29 ./usr/share/solarnode/bin/solarstat.sh
	#
	# We thus extract the 6th field, omitting paths that end in '/' and stripping the leading '.'
	pkg_wait_not_busy
	dpkg -c "$pkg" |awk '$6 !~ "/$" {print substr($6,2)}'
}

pkg_install_file () {
	local pkg="$1"

	if [ -z "$pkg" ]; then
		echo "Must provide path to package to install."  1>&2
		exit 1
	fi
	
	# note: using apt-get here to provide support for installing dependencies
	pkg_wait_not_busy
	sudo apt-get install $APT_FLAGS -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" \
		--no-install-recommends "$pkg" >$APT_OUTPUT </dev/null || exit $?
	pkg_list_files "$pkg"
}

pkg_install_repo () {
	local pkg="$1"
	local ver="$2"
	local redo=""
	
	pkg_wait_not_busy
	if dpkg -s "$pkg" >/dev/null 2>&1; then
		redo="--reinstall"
	fi
		
	pkg_wait_not_busy
	sudo apt-get install $APT_FLAGS -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confnew" \
		--no-install-recommends $redo "$pkg${ver:+=$ver}" >$APT_OUTPUT </dev/null || exit $?
	
	local fname="${pkg}_(dpkg-query -W -f '${Version}_${Architecture}' "$pkg").deb"
	if [ -e "/var/cache/apt/archives/$fname" ]; then
		pkg_list_files "/var/cache/apt/archives/$fname"
	fi	
}

# install a package, and return a list of files installed
pkg_install () {
	local pkg="$1"
	local ver="$2"
	
	case $pkg in
		*.deb) pkg_install_file "$@";;
		
		*) pkg_install_repo "$@";;
	esac
}

pkg_remove () {	
	local pkg="$1"
	if [ -z "$pkg" ]; then
		echo "Must provide name of package to remove."  1>&2
		exit 1
	fi
	pkg_wait_not_busy
	if dpkg -s "$pkg" >/dev/null 2>&1; then
		sudo apt-get remove $APT_FLAGS --purge "$pkg" >$APT_OUTPUT </dev/null
	fi
}

pkg_clean () {
	pkg_wait_not_busy
	sudo apt-get $APT_FLAGS autoremove >$APT_OUTPUT </dev/null \
		&& sudo apt-get clean $APT_FLAGS >$APT_OUTPUT </dev/null
}

# list name,version,installed (true|false)
pkg_list () {
	local name="${1:-*}"
	
	pkg_wait_not_busy
	apt list "$name" 2>/dev/null \
		|awk 'NF >= 3 {sub(/\/.*$/, "", $1); printf "%s,%s,%s\n", $1, $2, match($4, /installed/) ? "true" : "false"}'
}

# list name,version,installed (true|false)
pkg_list_installed () {
	local name="${1:-*}"
	
	pkg_wait_not_busy
	dpkg-query -W -f '${Package},${Version},${db:Status-Status}\n' "$name" \
		|sed -e '/,installed$/! d' -e '/,installed$/ s/,installed$/,true/'
}

# list name,version,installed (true|false)
pkg_list_available () {
	pkg_list "$@" |grep ',false$'
}

# return (true|false)
pkg_is_installed () {
	local pkg="$1"
	if dpkg -s "$pkg" >/dev/null 2>&1; then
		echo "true"
	else
		echo "false"
	fi
}

pkg_refresh () {
	pkg_wait_not_busy
	sudo apt-get update $APT_FLAGS >$APT_OUTPUT  2>&1 </dev/null
}

pkg_upgrade () {
	local major="$1"
	local action="upgrade"

	if [ -n "$major" ]; then
		action="dist-upgrade"
	fi
	
	pkg_wait_not_busy
	sudo apt-get $action -qy -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
		>$APT_OUTPUT </dev/null
}

case $ACTION in
	clean) pkg_clean "$@";;
	
	install) pkg_install "$@";;
	
	is-installed) pkg_is_installed "$@";;
	
	list) pkg_list "$@";;

	list-available) pkg_list_available "$@";;
	
	list-installed) pkg_list_installed "$@";;
	
	refresh) pkg_refresh "$@";;
	
	remove) pkg_remove "$@";;
	
	upgrade) pkg_upgrade "$@";;

	*)
		echo "Action '${ACTION}' not supported." 1>&2
		echo 1>&2
		do_help
		exit 1
		;;
esac
