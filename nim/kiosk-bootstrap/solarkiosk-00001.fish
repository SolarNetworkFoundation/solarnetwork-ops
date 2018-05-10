# Remove SolarNode framework
rm-rf /lib/systemd/system/solarnode.service
rm-rf /lib/systemd/system/solarssh@.service
glob rm-rf /home/solar/*
rm-f /home/solar/config

# Copy system files
tar-in solarkiosk-system-00001.tgz / compress:gzip

# Enable kiosk server
ln-sf /etc/systemd/system/kiosk-server.service /etc/systemd/system/multi-user.target.wants/kiosk-server.service

# Zero free space to make compress of image better
zero-free-space /
