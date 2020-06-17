#!/bin/sh
#
# Script to manage the SolarJobs scheduler state.

HELPER="/usr/local/share/sn/bin/solarjobs.sh"

if [ ! -e "${HELPER}" ]; then
	echo "${HELPER} helper script not found."
	exit 1
fi

. "${HELPER}"

case $1 in
	jobs-status)
		do_job_status
		;;

	pause-jobs)
		pause_scheduler
		do_job_status
		;;

	pause-jobs-wait)
		pause_scheduler
		do_job_status
		wait_all_jobs_complete
		;;

	resume-jobs)
		resume_scheduler
		do_job_status
		;;

	configured-jobs)
		json=`configured_jobs`
		if [ -n "$json" ]; then
			echo  "$json" |$PRETTYJSON
		else
			echo 'No jobs configured.'
		fi
		;;

	running-jobs)
		json=`executing_jobs`
		if [ -n "$json" ]; then
			echo  "$json" |$PRETTYJSON
		else
			echo 'No jobs running.'
		fi
		;;

	*)
		echo "Usage: $0 {jobs-status|pause-jobs|resume-jobs|configured-jobs|running-jobs|pause-jobs-wait}" 1>&2
		exit 1
		;;
esac

exit 0
