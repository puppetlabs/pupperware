# Pupperware on Windows

The ecosystem surrounding Docker container support for Linux containers on Windows is currently in flux and in heavy active development. In addition to the constant forward momentum, there have been a number of confusing naming choices to the toolchains as components have made foundational underlying changes. As a result, large swaths of online documentation for these projects don't reflect the current state of these projects, or some of their technical details / limitations.

The Pupperware project is being tested against the latest [LCOW (Linux Containers on Windows)](https://github.com/linuxkit/lcow) support available from Docker and Microsoft, and as such has a number of pre-requisites. At a high level, this support enables running Linux and Windows containers side-by-side on the same host and relies on:

* A build of Windows newer than Windows 10, Build 1709
* Docker edge release 18.02 with experimental features enabled, nightly currently preferred
* A LinuxKit based kernel image

The February 2018 [Docker for Windows Desktop 18.02 blog post](https://blog.docker.com/2018/02/docker-for-windows-18-02-with-windows-10-fall-creators-update/) covers some of the important changes made in that release. In particular, the previous "Linux mode" capable of running only Linux containers was deprecated in favor of LCOW (though "Linux mode" was not yet removed). The previous "Linux mode" initially ran the `MobyLinuxVM` virtual machine in Hyper-V (later replaced with a `LinuxKit` variant in [Docker for Windows 17.10](https://blog.docker.com/2017/11/docker-for-windows-17-11/)) to host Linux containers. Older "Linux mode" support interacted with Docker volumes differently (using SMB / CIFS) than how LCOW now interfaces with volumes (using [9p](http://9p.cat-v.org/)). Note that the official Docker position is that LCOW is the one path forward for running Linux Containers on Windows:

> As a Windows platform feature, LCOW represents a long term solution for Linux container support on Windows. When the platform features meet or exceed the existing functionality the existing Docker for Windows Linux container support will be retired.

### Setup

The following steps outline how to provision a host with the required support to run this project:

* [Provision a Windows host with LCOW support](#provision-a-windows-host-with-lcow-support)
* [Install the Docker nightly build](#install-the-docker-nightly-build)
* [Build an updated LCOW kernel](#build-an-updated-lcow-kernel)
* [Validate the Install](#validate-the-install)

Some of these instructions are updated from the [A sneak peek at LCOW](https://stefanscherer.github.io/sneak-peek-at-lcow/) written by Stefan Scherer [@stefscherer](https://twitter.com/stefscherer)

At the time of this writing, the Windows 10 Build 1709 test host returns the following Docker versions:

````
Client:
 Version:           master-dockerproject-2018-09-03
 API version:       1.39
 Go version:        go1.10.4
 Git commit:        3ea56aa0
 Built:             Mon Sep  3 23:53:23 2018
 OS/Arch:           windows/amd64
 Experimental:      false

Server:
 Engine:
  Version:          master-dockerproject-2018-09-03
  API version:      1.39 (minimum version 1.24)
  Go version:       go1.10.4
  Git commit:       8af9176
  Built:            Tue Sep  4 00:02:00 2018
  OS/Arch:          windows/amd64
  Experimental:     true
````

### Additional Reference

* [Moby Project - Epic: Linux Containers on Windows](https://github.com/moby/moby/issues/33850) - tracks current status of LCOW feature implementation
* [Linux Containers](https://docs.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/linux-containers) - Microsoft high-level reference for known issues with LCOW
* [docker-for-win](https://github.com/docker/for-win) - Public issue tracking for `Docker CE for Windows`

## Provision a Windows host with LCOW support

As mentioned, Windows 10 Build 1709+, Windows Server 2019 or newer builds are necessary to support LCOW.

If the host is provisioned in Azure, the host must be a `v3` SKU to support nested virtualization, like `Standard_D4s_v3`. Other cloud providers or virtualized infrastructure will have similar requirements / configuration needed to enable nested virtualization.

### Windows features

LCOW support requires enabling several features with the PowerShell command, and generally will require rebooting:

```powershell
PS> $reboot = Enable-WindowsOptionalFeature -Online -FeatureName containers, Microsoft-Hyper-V -All -NoRestart

# docker cannot run until the computer is restarted
if ($reboot.RestartNeeded) { Restart-Computer }
```

Note that Hyper-V support is still currently necessary to be able to run the LinuxKit based kernel, though no Hyper-V virtual machine will be visible in any of the Microsoft management tools when running Linux containers. The LCOW support uses a very thin layer that optimally leverages the Hyper-V stack.

## Install the Docker nightly build

On the provisioned host, the Docker nightly build must now be installed. It's available at a Docker project permalink.

Run the following PowerShell script to:

* download the latest Docker binaries and install them
* install the Windows service with experimental support
* add Docker to the machine `PATH` for convenience
* download an LCOW kernel image and install it
* start the Docker service

```powershell
# download nightly zip and extract to application directory
Push-Location $Env:TEMP
Invoke-WebRequest -OutFile docker-master.zip https://master.dockerproject.com/windows/x86_64/docker.zip
Expand-Archive -Path docker-master.zip -DestinationPath $Env:ProgramFiles -Force

# register the service to start with system and enable experimental
& $Env:ProgramFiles\docker\dockerd.exe --register-service --experimental

# allow Docker CLI commands to be run from any command line
[Environment]::SetEnvironmentVariable("Path", "${Env:Path};${Env:ProgramFiles}\docker", [EnvironmentVariableTarget]::Machine)

# download March 23, 2018 existing LCOW kernel image
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -OutFile lcow-kernel.zip http://github.com/linuxkit/lcow/releases/download/4.14.29-0aea33bc/release.zip
Expand-Archive -Path lcow-kernel.zip -DestinationPath "${Env:ProgramFiles}\Linux Containers" -Force
# this older image named files differently than expected in current Docker
Move-Item "${Env:ProgramFiles}\Linux Containers\bootx64.efi" "${Env:ProgramFiles}\Linux Containers\kernel" -Force

# Start Docker Engine
Start-Service docker
```

## Build an updated LCOW kernel

In the previous step, an outdated LCOW kernel image [last published release 4.14.29-0aea33bc](https://github.com/linuxkit/lcow/releases) was installed to the expected location for Docker. That artifact included files that are renamed to conform to the latest Docker expectations  `initrd.img` and `kernel`, and that are copied to `$Env:Program Files\Linux Containers`

While not strictly necessary, it's now useful to build an updated kernel image 
with the [linuxkit](https://github.com/linuxkit/linuxkit) tooling. 

### Building on Windows

Windows can be used to build the kernel image. 

Building from source requires `git`, `make` and `docker` itself. Docker must have LCOW support enabled and must have a valid kernel image installed as in the previous step (otherwise the build will fail with a message like `Error: No such image: docker.io/linuxkit/kernel:4.14.35`)

Run the following PowerShell script to:

* Install Chocolatey package manager for Windows
* Install build tooling with Chocolatey
* Copy and build LinuxKit source
* Copy and build LCOW kernel image source
* Deploy LCOW kernel image to host

```powershell
# install Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

# install build tooling
choco install -y git golang make

# make build tools available in current session
# by setting environment variable and importing Chocolatey PowerShell
$env:ChocolateyInstall = Convert-Path "$((Get-Command choco).path)\..\.."
Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
Update-SessionEnvironment

# use `go get` to clone and build linuxkit source
# verbose output since this will generally take a while
# https://github.com/linuxkit/linuxkit/issues/3207 follows the upstream issue
go get -v -u github.com/Iristyle/linuxkit/src/cmd/linuxkit

# verify linuxkit built
# go copies binaries to $Env:GOPATH by default unless explicitly configured
& $Env:USERPROFILE\go\bin\linuxkit.exe help

# copy LCOW kernel source and build it with linuxkit
Push-Location $Env:Temp
git clone https://github.com/linuxkit/lcow
Push-Location lcow
$Env:Path += ";$Env:USERPROFILE\go\bin"
linuxkit build lcow.yml

# install the LCOW kernel image
New-Item "$Env:ProgramFiles\Linux Containers" -Type Directory -Force
Copy-Item .\lcow-initrd.img "$Env:ProgramFiles\Linux Containers\initrd.img"
Copy-Item .\lcow-kernel "$Env:ProgramFiles\Linux Containers\kernel"

# write version info to sidecar text file for posterity
git rev-parse head > "${Env:ProgramFiles}\Linux Containers\versions.txt"
type .\lcow.yml >> "${Env:ProgramFiles}\Linux Containers\versions.txt"
```

Note: This uses a fork of the linuxkit master from Oct 17 2018 at https://github.com/linuxkit/linuxkit/commit/73dd7b219d239d038567cbd8ee23a2771d270a8a
that updates compatible Docker API version from 1.23 to 1.24 with commit https://github.com/Iristyle/linuxkit/commit/4daf9158491bb3effd0a258c2231c042921cc780
which is necessary for the Docker version installed earlier. This issue has been reported to the LinuxKit project at https://github.com/linuxkit/linuxkit/issues/3207.

If everything is configured correctly, the `linuxkit build lcow.yml` output should be similar to the following:

```
PS C:\Users\puppet\AppData\Local\Temp\lcow> linuxkit build lcow.yml
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
```

### Building on OSX (Alternate Build Workflow)

Alternatively, it may be simpler to do this on OSX with the help of Homebrew, as `linuxkit` builds are already available there.

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

Proceed to copy the artifacts to the Windows system as before.

## Validate the install

The Docker service should now be running on boot and should now yield details about the LCOW setup like

```powershell
PS> docker info

Containers: 10
 Running: 0
 Paused: 0
 Stopped: 10
Images: 6
Server Version: master-dockerproject-2018-09-03
Storage Driver: windowsfilter (windows) lcow (linux)
 Windows:
 LCOW:
Logging Driver: json-file
Plugins:
 Volume: local
 Network: ics l2bridge l2tunnel nat null overlay transparent
 Log: awslogs etwlogs fluentd gcplogs gelf json-file local logentries splunk syslog
Swarm: inactive
Default Isolation: hyperv
Kernel Version: 10.0 16299 (16299.431.amd64fre.rs3_release_svc_escrow.180502-1908)
Operating System: Windows 10 Pro Version 1709 (OS Build 16299.611)
OSType: windows
Architecture: x86_64
CPUs: 4
Total Memory: 16GiB
Name: pupperware
ID: VQWA:Y5TW:RNVF:GBSU:JKSH:LLAX:IHSR:G465:7OEH:3EJ3:7JJ3:CWRT
Docker Root Dir: C:\ProgramData\docker
Debug Mode (client): false
Debug Mode (server): false
Registry: https://index.docker.io/v1/
Labels:
Experimental: true
Insecure Registries:
 127.0.0.0/8
Live Restore Enabled: false
```

With all of the LCOW setup verified, it should now be possible to launch side-by-side
Linux and Windows containers

```powershell
docker run -itd microsoft/nanoserver
docker run -itd alpine
```
