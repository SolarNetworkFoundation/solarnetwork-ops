# SolarNode Image Maker support

# Note on QEMU and host kernel permissions

When NIM uses `guestfish` to customize NIM images, we've seen on home hosts (Ubuntu!) that
the kernels installed in `/boot` have `600` file permissions, and are thus not readable by the 
NIM user. When trying to customize an image, an error like this is returned:

```
guestfish command returned non-zero exit code 1: 
libguestfs: error: /usr/bin/supermin exited with error status 1.
```

To fix, add read permissions to the kernel files, like this:

```sh
sudo chmod 644 /boot/System.map* /boot/vmlinuz*
```
