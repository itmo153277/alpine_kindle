# Alpine Linux for Kindle

See [original docs](https://github.com/schuhumi/alpine_kindle) for basic info.

## Building image

Prerequisites:

- qemu-user-static
- curl
- e2fsprogs

Run create_kindle_alpine_image.sh as root. This will build the latest **stable** alpine in alpine.img

## Installing

1. Copy alpine.conf and alpine.img to storage root

2. Install alpine upstart service

```sh
mntroot rw
cp /mnt/us/alpine.conf /etc/upstart/
mntroot r
```

## Launching

```sh
start alpine
```

## kaf-stub and chroot-escape

[chroot-escape](https://github.com/itmo153277/chroot-escape)

[kaf-stub](https://github.com/itmo153277/kindle-kaf-stub)

`kaf-stub` registers framework flags to allow device locking.
It has to be launched from the real fs root (not alpine's chroot),
hence a need for `chroot-escape`.

