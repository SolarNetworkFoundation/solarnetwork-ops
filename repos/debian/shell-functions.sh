#/bin/zsh

##################################
# SolarNetwork package add
##################################

function sn-pkg-add-deb () {
	local r="$1"
	if [ -z "$r" ]; then
		echo 'Must provide distribution release number, e.g. sn-pkg-add-deb 12 my-package'
	else
		shift
		aptly repo add "solarnetwork-deb$r" "$@"
	fi
}

##################################
# SolarNetwork package snapshot
##################################

function sn-pkg-snapshot () {
	local r="$1"
	local n="$2"
	if [ -z "$r"]; then
		echo 'Must provide distribution release number, e.g. sn-pkg-add-deb 12 my-package'
	elif [ -z "$n" ]; then
		echo 'Must provide snapshot name, e.g. sn-pkg-snapshot 12 20200129_01'
	else
		aptly snapshot create "sn_deb$r_$n" from repo "solarnetwork-deb$r"
	fi
}

##################################
# SolarNetwork package publish
##################################

function sn-pkg-pub-deb () {
	local force=""
	if [ "$1" = "-f" ]; then
		force="-force-overwrite"
		shift
	fi
	local e="$1"
	local r="$2"
	local n="$3"
	if [ -z "$e" ]; then
		echo 'Must provide environment, one of stage, prod, or all'
	elif [ -z "$r"]; then
		echo 'Must provide distribution release number, e.g. sn-pkg-pub-deb stage 12 20200129_01'
	elif [ -z "$n" ]; then
		echo 'Must provide snapshot name, e.g. sn-pkg-pub-deb stage 12 20200129_01'
	else
		local dist=""
		local archs="amd64,arm64,armhf,armel,i386"
		case $r in
			10) dist='buster';;
			11) dist='bullseye';;
			12) dist='bookworm';;
		esac
		if [ "$e" = 'prod' ]; then
			envir=''
		fi
		if [ -z "$dist" ]; then
			echo "Unsupported disribution release number [$dist]"
		else
			if [ "$e" = 'stage' -o "$e" = 'all' ]; then
				GNUPGHOME=~/.gnupg aptly publish switch $force \
					-gpg-key="8F5B233D" -architectures="$archs" \
					$dist s3:snf-debian-repo-stage: "sn_deb$r_$n"
			fi
			if [ "$e" = 'prod' -o "$e" = 'all' ]; then
				GNUPGHOME=~/.gnupg aptly publish switch $force \
					-gpg-key="8F5B233D" -architectures="$archs" \
					$dist s3:snf-debian-repo: "sn_deb$r_$n"
			fi
		fi
	fi
}
