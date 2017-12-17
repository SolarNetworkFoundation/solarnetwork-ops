#!/bin/sh

pushd .
cd init/updates

echo `date` Starting NET-111 migration
time psql96 -h postgres96 -p 5496 -U solarnet -d solarnetwork -v ON_ERROR_STOP=1 -f NET-111-remove-domains.sql
echo `date` Finished NET-111 migration

popd

time psql96 -h postgres96 -p 5496 -U solarnet -d solarnetwork -v ON_ERROR_STOP=1 -f NET-112-production.sql

echo $PWD
