# SolarKiosk Bootstrap NIM Custom Configuration

This directory contains the configuration source files for bootstrapping a
SolarKiosk image out of a SolarNode image. The produced image is not meant
to be used directly, but rather once it boots up and installs all the
necessary software, a new base image can be created from that and then
used for actual kiosks.

# Filesystem root

The `solarkiosk-root` directory contains updated files to apply to the
generated image. Run the `solarkiosk-mksetup.sh` script to create a
`solarkiosk-system-00001.tgz` archive out of those files, which can
then be uploaded to NIM.

# NIM

The NIM image should be created by uploading these `dataFile` resources:

 * `solarkiosk-00001.firstboot`
 * `solarkiosk-00001.fish`
 * `solarkiosk-system-00001.tgz`

The `options` resource should be set to `solarkiosk-00001.json`.


