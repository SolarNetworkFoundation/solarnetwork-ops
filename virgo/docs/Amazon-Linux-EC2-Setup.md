# Java 8

```sh
amazon-linux-extras install java-1.8.0-openjdk-headless
```

# Create Virgo user

```sh
mkdir /usr/local/opt
groupadd -g 1001 virgo
useradd -d /usr/local/opt/virgo -c 'Virgo Server' -m -u 1001 -g 1001 virgo
mkdir -p /var/log/virgo
chgrp virgo /var/log/virgo
chmod g+w /var/log/virgo

vi /etc/systemd/system/virgo@.service # paste content
systemctl enable virgo@solarin

su - virgo
mkdir .ssh
chmod 700 .ssh
touch authorized_keys
chmod 600 authorized_keys
vi authorized_keys # add key
cd ..
mkdir bin
vi bin/clean-bundle-cache.sh # paste content
```


