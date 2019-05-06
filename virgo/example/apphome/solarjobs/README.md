# SolarJobs: SolarNetwork scheduled jobs and background tasks

# Data import shared file system

SolarUser handles the UI for the datum import, and saves the data files to a filesystem. The SolarJobs
application then loads the data from those files, and thus must have access to the files. Thus a shared
filesystem must be used for both applications. This path is configured as the `workPath` property in the
`net.solarnetwork.central.datum.imp.biz.dao` Configuration Admin PID.
