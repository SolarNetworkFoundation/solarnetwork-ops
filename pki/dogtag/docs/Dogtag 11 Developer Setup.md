# Dogtag Setup - Fedora Server 41

For VM, expand image:

```sh
parted /dev/nvme0n1
# resizepart 3 100%

lvextend -l +100%FREE /dev/mapper/systemVG-LVRoot --resizefs
```

## Setup CA

From host:

```sh
cd ~/Documents/SNF/Sysadmin/solarnetwork-ops/pki/dogtag/setup/vagrant/local/solarca-dev-f31
scp bin/setup-solarca-fedora.sh matt@ca.solarnetworkdev.net:
scp -r example matt@ca.solarnetworkdev.net:dogtag
scp local/* matt@ca.solarnetworkdev.net:dogtag
```

In VM:

```sh
# update paths in ca-migrate.cfg
sed -i -e 's|/vagrant/local|/home/matt/dogtag|' ./dogtag/ca-migrate.cfg

sudo ~matt/setup-solarca-fedora.sh \
  -b ~matt/dogtag -u \
  -c ca-migrate.cfg \
  -d SolarNode.cfg \
  -t ca.solarnetworkdev.net-certsonly-migration-20190423.ldif

```

Then setup SSH access to `caadmin` user in `~caadmin/.ssh/authorized_keys`.

From host:

```sh
mkdir -p ~/Documents/SolarNetwork/Developer/CA/Certs/solarca-dev-f41
cd ~/Documents/SolarNetwork/Developer/CA/Certs/solarca-dev-f41
scp -r caadmin@ca.solarnetworkdev.net:~/.dogtag/pki-tomcat/\* .
```