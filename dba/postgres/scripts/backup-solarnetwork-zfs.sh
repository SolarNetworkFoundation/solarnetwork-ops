#!/usr/local/bin/bash
#
# Pass the destination host as the 1st argument, and optionally
# the destination pool name as the 2nd (defaults to sndb).
#
# Switches:
#
# -c            Compress (requires lz4)
# -n            Dry run.
# -p <pools>    List space-delimited pools to send
# -v            Verbose output


pools="db/solar93 db/solar93/index db/solar93/log db2/data93 solar/wal96"
skip=""
#skip="db/solar93/log"
dry=""
comp=""
decomp=""
keep=168
wal_dir=/solar93/9.6/archives
ver=
send_opt=

while getopts ":cnp:v" opt; do
	case $opt in
		c)
			comp="/usr/local/bin/lz4 -c -9"
			decomp="/usr/local/bin/lz4 -d"
			;;

		n)
			dry="1"
			;;

		p)
			pools="$OPTARG"
			;;

		v)
			ver="1"
			send_opt="-v"
			;;
	esac
done

shift $(($OPTIND - 1))

dest=$1
destpool=${2:-sndb}

if [ -z "$pools" ]; then
	echo 'Must specify the pools to export (-p "pool1 pool2...").'
	exit 1
fi

if [ -z "$dest" ]; then
	echo "Must specify the destination host as the first argument."
	exit 1
fi

[[ -n "$dry" ]] && echo "DRY RUN"

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

	if [ -z "$dry" ]; then
		su - pgsql -c "/usr/local/bin/psql -d postgres -p 5496 -c "'"'"select pg_start_backup('hourly');"'"' \
			>/dev/null
	fi

	now=`date +"hourly-%Y-%m-%d-%H"`

	if [ -z "$dry" -a -n "$ver" ]; then
		do_snapshots "$p" $k 'hourly' "$s" >&2
		su - pgsql -c "/usr/local/bin/psql -d postgres -p 5496 -c "'"'"select pg_stop_backup();"'"' \
				>/dev/null
	elif [ -z "$dry" ]; then
		do_snapshots "$p" $k 'hourly' "$s" >/dev/null
		su - pgsql -c "/usr/local/bin/psql -d postgres -p 5496 -c "'"'"select pg_stop_backup();"'"' \
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
		prev_snap=$(ssh $dest zfs list -t snapshot -H -o name -S creation -r $dest_snap 2>/dev/null |grep "^${dest_snap}@" |head -1)
		echo ${prev_snap##*@}
}

find_prev_inc()
{
		src_snap=$1
		dest_snap="$destpool/${src_snap#*/}"
		prev_snap=$(ssh $dest zfs list -t snapshot -H -o name -S creation -r $dest_snap 2>/dev/null |grep "^${dest_snap}@" |head -2 |tail -1)
		echo ${prev_snap##*@}
}

destroy_snapshot_if_exists()
{
	snap=$1
	if zfs list $snap >/dev/null 2>&1; then
		if [ -z "$dry" ]; then
			[[ -n "$ver" ]] && echo "Destroying incremental source snapshot $snap..."
			zfs destroy $snap
		else
			echo "Would destroy incremental source snapshot $snap..."
		fi
	else
		[[ -n "$ver" ]] && echo "Incremental source snapshot $snap already destroyed."
	fi
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
		[[ -n "$ver" ]] && echo "Initial snapshot for $pool is [$inc_snap]."

		if [ -z "$inc_snap" ]; then
				[[ -n "$ver" ]] && echo "Sending initial snapshot $snap to $dest $destpool..."
				if [ -z "$dry" -a -n "$comp" -a -n "$decomp" ]; then
					zfs send -R $send_opt $snap |$comp |ssh -C $dest "$decomp |zfs recv -F -d $destpool"
				elif [ -z "$dry" ]; then
					zfs send -R $send_opt $snap |ssh -C $dest "zfs recv -F -d $destpool"
				else
					zfs send -R -n -v $snap
				fi
				if [ $? -eq 0 ]; then
					complete+=1
				fi
		elif [ "$ts" = "$inc_snap" ]; then
				[[ -n "$ver" ]] && echo "Destination already contains $snap, not sending again."
				complete+=1
				prev_snap=$(find_prev_inc $pool)
				if [ "$inc_snap" != "$prev_snap" ]; then
					destroy_snapshot_if_exists $pool@$prev_snap
				fi
		else
				[[ -n "$ver" ]] && echo "Sending incremental snapshot $pool $inc_snap - $ts to $dest $destpool..."
				if [ -z "$dry" -a -n "$comp" -a -n "$decomp" ]; then
					zfs send -R $send_opt -i $pool@$inc_snap $snap |$comp |ssh -C $dest "$decomp |zfs recv -F -d $destpool"
				elif [ -z "$dry" ]; then
					zfs send -R $send_opt -i $pool@$inc_snap $snap |ssh -C $dest "zfs recv -F -d $destpool"
				else
					zfs send -R -n -v -i $pool@$inc_snap $snap
				fi
				if [ $? -eq 0 ]; then
					complete+=1
					destroy_snapshot_if_exists $pool@$inc_snap
				fi
		fi
done

if [ $count -eq $complete ]; then
	[[ -n "$ver" ]] && echo "Cleaning archived WAL files from $wal_dir older than $newest_wal..."
	if [ -z "$dry" ]; then
		find $wal_dir -type f ! -name $newest_wal -a ! -newer $wal_dir/$newest_wal -exec rm -f {} \;
	else
		find $wal_dir -type f ! -name $newest_wal -a ! -newer $wal_dir/$newest_wal -print
	fi
fi

[[ -n "$ver" ]] && echo "Done."
