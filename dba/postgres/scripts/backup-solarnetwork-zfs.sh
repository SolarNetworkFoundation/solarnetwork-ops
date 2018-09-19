#!/usr/local/bin/bash
#
# Pass the destination host as the 1st argument, and optionally
# the destination pool name as the 2nd (defaults to sndb).
#
# Switches:
#
# -c    Compress (requires lz4)
# -v    Verbose output


pools="db/solar93/data db/solar93/index solar/data93"
skip="db/solar93/log"
comp=""
decomp=""
keep=168
wal_dir=/solar93/data/archives
ver=

while getopts ":cv" opt; do
	case $opt in
		c)
			comp="/usr/local/bin/lz4 -c -9"
			decomp="/usr/local/bin/lz4 -d"
			;;

		v)
			ver="1"
			;;
	esac
done

shift $(($OPTIND - 1))

dest=$1
destpool=${2:-sndb}

if [ -z "$dest" ]; then
	echo "Must specify the destination host as the first argument."
	exit 1
fi

[[ -n "$ver" ]] && echo "Sending ($pools) to $dest..."

# pull in support for do_snapshots function
. /usr/local/bin/zfs-snapshot

# pull in support for ssh-find-agent function
. ~/bin/ssh-find-agent.sh

# make_pg_snapshot()
#
# Function to create the backup snapshots, by calling pg_start_backup(), do_snapshots, and pg_stop_backup
# Prints out the snapshot name used
#
# Pass the pool name, keep number, and skip list as arguments.
make_pg_snapshot()
{
		p=$1
		k=$2
		s=$3

		su - pgsql -c "/usr/local/bin/psql -d postgres -p 5493 -c "'"'"select pg_start_backup('hourly');"'"' \
				>/dev/null

		now=`date +"$type-%Y-%m-%d-%H"`

		if [ -n "$ver" ]; then
			do_snapshots "$p" $k 'hourly' "$s" >&2
			su - pgsql -c "/usr/local/bin/psql -d postgres -p 5493 -c "'"'"select pg_stop_backup();"'"' \
					>/dev/null
		else
			do_snapshots "$p" $k 'hourly' "$s" >/dev/null
			su - pgsql -c "/usr/local/bin/psql -d postgres -p 5493 -c "'"'"select pg_stop_backup();"'"' \
					>/dev/null 2>&1
		fi
		echo $now;
}

# find_inc_start()
#
# Function to look for the most recent snapshot matching a specific name on the destination host.
# Prints out the found snapshot name, if found.
#
# Pass the source snapshot name to look for as the only argument.
find_inc_start()
{
		src_snap=$1
		dest_snap="$destpool/${src_snap#*/}"
		prev_snap=$(ssh $dest zfs list -t snapshot -H -o name -S creation -r $dest_snap |head -1)
		echo ${prev_snap##*@}
}

ssh-find-agent -a

[[ -n "$ver" ]] && echo "Creating snapshots..."

ts=$(make_pg_snapshot "$pools" $keep "$skip")

[[ -n "$ver" ]] && echo "Got snapshot $ts"

count=0
complete=0
newest_wal="$(ls -1t $wal_dir/ |head -1)"
for pool in $pools; do
	count+=1
		snap="$pool@$ts"

		inc_snap=$(find_inc_start $pool)

		if [ -z "$inc_snap" ]; then
				[[ -n "$ver" ]] && echo "Sending initial snapshot $snap to $dest $destpool..."
				if [ -n "$comp" -a -n "$decomp" ]; then
					zfs send -R $snap |$comp |ssh -C $dest "$decomp |zfs recv -F -d $destpool"
				else
					zfs send -R $snap |ssh -C $dest "zfs recv -F -d $destpool"
				fi
				if [ $? -eq 0 ]; then
					complete+=1
				fi
		elif [ "$ts" = "$inc_snap" ]; then
				[[ -n "$ver" ]] && echo "Destination already contains $snap, not sending again."
				complete+=1
		else
				[[ -n "$ver" ]] && echo "Sending incremental snapshot $pool $inc_snap - $ts to $dest $destpool..."
				if [ -n "$comp" -a -n "$decomp" ]; then
					zfs send -R -i $pool@$inc_snap $snap |$comp |ssh -C $dest "$decomp |zfs recv -F -d $destpool"
				else
					zfs send -R -i $pool@$inc_snap $snap |ssh -C $dest "zfs recv -F -d $destpool"
				fi
				if [ $? -eq 0 ]; then
					complete+=1
					[[ -n "$ver" ]] && echo "Destroying incremental source snapshot $pool@$inc_snap..."
					zfs destroy $pool@$inc_snap
				fi
		fi
done

if [ $count -eq $complete ]; then
	[[ -n "$ver" ]] && echo "Cleaning archived WAL files from $wal_dir older than $newest_wal..."
	find /solar93/data/archives -type f ! -name $newest_wal -a ! -newer $wal_dir/$newest_wal -exec rm -f {} \;
fi

[[ -n "$ver" ]] && echo "Done."
