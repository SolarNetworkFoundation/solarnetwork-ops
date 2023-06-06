# FreeBSD System Admin Help

## Swap file

To add and enable a swap file:

```sh
dd if=/dev/zero of=/usr/swap0 bs=1m count=4096
chmod 0600 /usr/swap0
echo 'md99 none swap sw,file=/usr/swap0,late 0 0' >>/etc/fstab
swapon -aL
```
