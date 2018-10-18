# Building the LCOW kernel image on OSX

OSX has `linuxkit` builds available in Homebrew, installed with:

```shell
brew install git

brew tap linuxkit/linuxkit
brew install --HEAD linuxkit
```

`make` should already be installed with XCode on OSX. To build the image is then

```shell
cd /tmp
git clone https://github.com/linuxkit/lcow
cd lcow

docker-start
make
```

A successful build of the kernel image with `linuxkit build lcow.yml` should be similar to the following:

```
linuxkit build lcow.yml
Extract kernel image: linuxkit/kernel:4.14.35
Pull image: docker.io/linuxkit/kernel:4.14.35@sha256:3bef6da5bdd9412954b1c971ef43e06bcb1445438e336daf73e681324c58343c
Add init containers:
Process init image: linuxkit/init-lcow:0b6d22dcead2548c4ba8761f0fccb728553ebd06
Pull image: docker.io/linuxkit/init-lcow:0b6d22dcead2548c4ba8761f0fccb728553ebd06@sha256:6756c19a2be2f68ee20f01bf5736c3e6f24ddb282345feb2d7ac5c3885972734
Process init image: linuxkit/runc:v0.5
Pull image: docker.io/linuxkit/runc:v0.5@sha256:9782c306200ad7d3dcbe52ac7b01f2594b9e970c46e002f6a5af407dc8c24165
Add files:
  etc/linuxkit.yml
Create outputs:
  lcow-kernel lcow-initrd.img lcow-cmdline
mv lcow-kernel kernel
mv lcow-initrd.img initrd.img
```

These results were produced with the following tools:

```
> docker version

Client:
 Version:           18.06.1-ce
 API version:       1.38
 Go version:        go1.10.3
 Git commit:        e68fc7a
 Built:             Tue Aug 21 17:21:31 2018
 OS/Arch:           darwin/amd64
 Experimental:      false

Server:
 Engine:
  Version:          18.06.1-ce
  API version:      1.38 (minimum version 1.12)
  Go version:       go1.10.3
  Git commit:       e68fc7a
  Built:            Tue Aug 21 17:28:38 2018
  OS/Arch:          linux/amd64
  Experimental:     false

> linuxkit version

linuxkit version v0.6+
commit: c8449ba2dbc0e26a80b2e4acfb4946be68d3239b

> make --version

GNU Make 3.81
Copyright (C) 2006  Free Software Foundation, Inc.
This is free software; see the source for copying conditions.
There is NO warranty; not even for MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.

This program built for i386-apple-darwin11.3.0
```
