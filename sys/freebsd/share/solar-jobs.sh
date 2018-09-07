#!/bin/sh
#
# Helper functions for dealing with SolarNetwork jobs via the /scheduler REST API.
# This script is meant to be sourced by other scripts that wish to use the functions
# defined within it.

NETRC_FILE=${NETRC_FILE:-"/root/netrc/solarjobs-admin"}
JOBAPI_BASE=${JOBAPI_BASE:-"https://data.solarnetwork.net/solarjobs"}
CURL=${CURL:-"/usr/local/bin/curl"}
PRETTYJSON=${PRETTYJSON:-"/usr/local/bin/python -m json.tool"}

# functions for job scheduler
scheduler_status () {
	json=`$CURL -s -H "Accept: application/json" --netrc-file "$NETRC_FILE" "$JOBAPI_BASE/api/v1/sec/scheduler/status"`
	status=unknown
	case "$json" in
		*Paused*) status=paused ;;
		*Running*) status=running ;;
		*Starting*) status=running ;;
	esac
	echo $status
}

pause_scheduler () {
	json=`$CURL -s -H "Accept: application/json" --netrc-file "$NETRC_FILE" "$JOBAPI_BASE/api/v1/sec/scheduler/status" -d status=Paused`
}

resume_scheduler () {
	json=`$CURL -s -H "Accept: application/json" --netrc-file "$NETRC_FILE" "$JOBAPI_BASE/api/v1/sec/scheduler/status" -d status=Running`
}

configured_jobs () {
	$CURL -s -H "Accept: application/json" --netrc-file "$NETRC_FILE" "$JOBAPI_BASE/api/v1/sec/scheduler/jobs" |grep jobStatus
}

executing_jobs () {
	$CURL -s -H "Accept: application/json" --netrc-file "$NETRC_FILE" "$JOBAPI_BASE/api/v1/sec/scheduler/jobs?executing=true" |grep jobStatus
}

wait_all_jobs_complete () {
	json=`executing_jobs`
	saw_job=
	if [ -n "$json" ]; then
		echo -n 'Waiting for jobs to complete...'
		saw_job=1
	fi
	while [ -n "$json" ]; do
		sleep 5
		json=`executing_jobs`
		echo -n '.'
	done
	if [ -n "$saw_job" ];then
		echo ' done.'
	fi
}

do_job_status () {
	sched_status=`scheduler_status`
	echo "Job scheduler is $sched_status"
}
