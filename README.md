# febins

This repository is dedicated to the bundling of assets for the factory engine system. All items will be uploaded as releases under appropriate tags.



## Platform Strings:
```
ARG PLATFORM=linux/amd64

PLATFORM=linux/amd64
PLATFORM=linux/arm64
```


## OS Strings
```
ARG BUILD_IMAGE=bionic-20210512

ubuntu:bionic-20210512
ubuntu:focal
ubuntu:jammy
ubuntu:noble
debian:bookworm
debian:bullseye
```


## Apt requirements for running

### Valgrind
```bash
sudo apt install libc-dbg
```

### GDB
```bash
sudo apt install python3 libc-dbg
```

#### Notes

Discovered via:
```bash
sudo sed -i 's/^# deb-src/deb-src/' /etc/apt/sources.list
sudo apt update
apt source valgrind
apt source gdb
```

Then inspecting:
```
debian/rules # for the configuration flags
debian/control # for the build time and run time dependencies
```

Also `gdb --configuration`

Also there were issues with the gdb configure script, leaving most commands blank and just having the libs existing to automatically enable the flags is better.