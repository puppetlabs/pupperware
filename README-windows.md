# Pupperware on Windows

The ecosystem surrounding Docker container support for Linux containers on Windows is currently in flux and in heavy active development. In addition to the constant forward momentum, there have been a number of confusing naming choices to the toolchains as components have made foundational underlying changes. As a result, large swaths of online documentation for these projects don't reflect the current state of these projects, or some of their technical details / limitations.

The Pupperware project is being tested against Windows 10 2004 build 19041 using WSL2 support, and as such has a few pre-requisites:

* A build of Windows at least as new as Windows 10 2004, Build 194041.1 (Insider Slow Ring as of Apr 15 2020)
* Docker Desktop Edge 2.2.3.0 with WSL2 enabled

### A Brief History

There have been a number of iterations on the Docker toolchain to support running Linux containers on Windows.

* MobyLinuxVM / Linux mode - initally a fat MobyLinux Hyper-V VM that allowed hosting Linux containers on Windows, which later became a lighter LinuxKit variant in [Docker for Windows 17.10](https://blog.docker.com/2017/11/docker-for-windows-17-11/). In this mode, Windows containers could not be run concurrently. Docker volumes in Linux used SMB / CIFS.
* LCOW v1 - initial support for side-by-side Windows / Linux containers using a completely different architecture. Both the Docker server / daemon *and* the client run on Windows. The February 2018 [Docker for Windows Desktop 18.02 blog post](https://blog.docker.com/2018/02/docker-for-windows-18-02-with-windows-10-fall-creators-update/) covers the release. "Linux mode" was deprecated (but not quite removed). LCOW now interfaces with volumes using [9p](http://9p.cat-v.org/). Docker claimed that LCOW is the one path forward for running Linux Containers on Windows:

> As a Windows platform feature, LCOW represents a long term solution for Linux container support on Windows. When the platform features meet or exceed the existing functionality the existing Docker for Windows Linux container support will be retired.
* LCOW v2 - as more container use cases cropped up, and issues presented themselves, Hyper-V APIs had to be revisioned. The POSIX APIs used in some containers (chmod, chattr, chown, flock) required very specific API versions - for instance, Postgres requires RS5 API (Windows 10 1809+ / Windows Server 2019+) [Moby Issue 33850 Comment](https://github.com/moby/moby/issues/33850#issuecomment-478192332) from Mar 29 2019 details LCOW will only support V2 HCS APIs which require RS4 / RS5 builds (Windows 10 1803+, Windows Server 2016 1803+, Windows Server 2019+)
* WSL2 - LCOW is seemingly dead. With Microsoft now supporting Linux distros, running in a VM, inside of Windows, focus has switched once again. The current design runs a Docker daemon in a lightweight VM that the Windows Docker client communicates with. This removes at least 2 major features from LCOW - the ability to run side-by-side Windows and Linux containers, and Hyper-V isolation (between containers). However, many of the [bugs plaguing LCOW](https://docs.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/linux-containers) are no longer a problem *and* the system is much faster.

### Setup

The following steps outline how to provision a host with the required support to run this project:

* [Provision a Windows host with WSL2 support](#provision-a-windows-host-with-wsl2-support)
* [Install the Docker Desktop Edge Release](#install-the-docker-desktop-edge-release)
* [Validate the Install](#validate-the-install)

At the time of this writing, the Windows 10 2004 test host returns the following Docker versions:

```
Client: Docker Engine - Community
 Version:           19.03.8
 API version:       1.40
 Go version:        go1.12.17
 Git commit:        afacb8b
 Built:             Wed Mar 11 01:23:10 2020
 OS/Arch:           windows/amd64
 Experimental:      true

Server: Docker Engine - Community
 Engine:
  Version:          19.03.8
  API version:      1.40 (minimum version 1.12)
  Go version:       go1.12.17
  Git commit:       afacb8b
  Built:            Wed Mar 11 01:29:16 2020
  OS/Arch:          linux/amd64
  Experimental:     true
 containerd:
  Version:          v1.2.13
  GitCommit:        7ad184331fa3e55e52b890ea95e65ba581ae3429
 runc:
  Version:          1.0.0-rc10
  GitCommit:        dc9208a3303feef5b3839f4323d9beb36df0a9dd
 docker-init:
  Version:          0.18.0
  GitCommit:        fec3683
```

### Additional Reference

* [docker-for-win](https://github.com/docker/for-win) - Public issue tracking for `Docker CE for Windows`

## Provision a Windows host with WSL2 support

As mentioned, Windows 10 2004 build 19041.1 is necessary to support WSL2.

If the host is provisioned in Azure, the host must be a `v3` SKU to support nested virtualization, like `Standard_D4s_v3`. Other cloud providers or virtualized infrastructure will have similar requirements / configuration needed to enable nested virtualization.

### Install Slow Ring

Follow the [basic instructions](https://insider.windows.com/en-us/how-to-pc/) for joining the Insider Program and installing Slow Ring

### Install WSL2

The latest directions are available [from Microsoft](https://docs.microsoft.com/en-us/windows/wsl/wsl2-install), but are essentially the following steps

#### Enable Windows features

WSL2 support requires enabling several features with the PowerShell command, and generally will require rebooting:

```powershell
PS> $reboot = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V,Microsoft-Windows-Subsystem-Linux,VirtualMachinePlatform -All -NoRestart

# WSL2 cannot run until the computer is restarted
if ($reboot.RestartNeeded) { Restart-Computer }
```

Note that Hyper-V support is still currently necessary to be able to run the WSL2 distributions, though no Hyper-V virtual machine will be visible in any of the Microsoft management tools when running Linux containers.

#### Upgrade the kernel

The [WSL2 Linux kernel](https://aka.ms/wsl2kernel) must also be [upgraded](https://docs.microsoft.com/en-us/windows/wsl/wsl2-kernel) to support the latest version of Windows:

```powershell
Invoke-WebRequest -Uri https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi -OutFile $ENV:TEMP\wsl_update_x64.msi -UseBasicParsing
msiexec /qn /i $ENV:TEMP\wsl_update_x64.msi
```

#### Install a Linux distro

Install Ubuntu 18.04 into WSL2

```powershell
Invoke-WebRequest -Uri https://aka.ms/wsl-ubuntu-1804 -OutFile $ENV:TEMP\wsl-ubuntu-1804.appx -UseBasicParsing
Add-AppxPackage $ENV:TEMP\wsl-ubuntu-1804.appx
```

NOTE: The application must now be launched from the Start Menu to complete initialization. The system will prompt for a new user and password to be created. (For test instances the values `puppet` and `puppet` have been chosen). It's possible this can be scripted following [these instructions](https://superuser.com/a/1272559)

#### Set Default WSL2 Version Distribution

Make sure that WSL2 is the default and the previously installed distro is set to be the default:

```
wsl --set-default-version 2
wsl --set-version Ubuntu-18.04 2
```

## Install the Docker Desktop Edge Release

On the provisioned host, the Docker Desktop Edge release most now be installed. For more information, see the [Docker documentation](https://docs.docker.com/docker-for-windows/wsl-tech-preview/)

Run the following PowerShell script to:

* Install Chocolatey package manager for Windows
* Install the edge release of Docker Desktop with Chocolatey

```powershell
# set process execution policy
Set-ExecutionPolicy Bypass -Scope Process -Force

# install Chocolatey
iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

choco install -y --pre docker-desktop
```

The Docker installer will automatically detect WSL2 support and will configure the default distribution to run the Docker server.

### Firewall exclusions

Depending on how Docker is being used, there may be a couple of additional steps to making things work. For instance, running an Azure DevOps agent that uses Docker requires two additional system changes:

* The `Network Service` account (or whichever account runs the agent) must be a member of the `docker-users` group.
* Firewall exclusions must be added as inbound rules for `com.docker.backend` for application `C:\program files\docker\docker\resources\com.docker.backend.exe`

## Validate the install

The Docker service should now be running on boot and should now yield details about the WSL2 setup like

```powershell
PS> docker info

Client:
 Debug Mode: false
 Plugins:
  app: Docker Application (Docker Inc., v0.8.0)
  buildx: Build with BuildKit (Docker Inc., v0.3.1-tp-docker)
  mutagen: Synchronize files with Docker Desktop (Docker Inc., testing)

Server:
 Containers: 2
  Running: 2
  Paused: 0
  Stopped: 0
 Images: 46
 Server Version: 19.03.8
 Storage Driver: overlay2
  Backing Filesystem: <unknown>
  Supports d_type: true
  Native Overlay Diff: true
 Logging Driver: json-file
 Cgroup Driver: cgroupfs
 Plugins:
  Volume: local
  Network: bridge host ipvlan macvlan null overlay
  Log: awslogs fluentd gcplogs gelf journald json-file local logentries splunk syslog
 Swarm: inactive
 Runtimes: runc
 Default Runtime: runc
 Init Binary: docker-init
 containerd version: 7ad184331fa3e55e52b890ea95e65ba581ae3429
 runc version: dc9208a3303feef5b3839f4323d9beb36df0a9dd
 init version: fec3683
 Security Options:
  seccomp
   Profile: default
 Kernel Version: 4.19.84-microsoft-standard
 Operating System: Docker Desktop
 OSType: linux
 Architecture: x86_64
 CPUs: 2
 Total Memory: 12.49GiB
 Name: docker-desktop
 ID: CU4P:YEJH:OG4G:UV2M:CQNR:FUNG:UXQI:FFX5:OGTY:YAW3:3LIT:3RJ3
 Docker Root Dir: /var/lib/docker
 Debug Mode: true
  File Descriptors: 58
  Goroutines: 65
  System Time: 2020-04-15T17:36:28.4071887Z
  EventsListeners: 3
 Registry: https://index.docker.io/v1/
 Labels:
 Experimental: true
 Insecure Registries:
  127.0.0.0/8
 Live Restore Enabled: false
 Product License: Community Engine

WARNING: bridge-nf-call-iptables is disabled
WARNING: bridge-nf-call-ip6tables is disabled
```

Docker-compose should also provide information like:

```
PS> docker-compose version

docker-compose version 1.26.0-rc3, build 46118bc5
docker-py version: 4.2.0
CPython version: 3.7.4
OpenSSL version: OpenSSL 1.1.1c  28 May 2019
```

With all of the WSL2 setup verified, it should now be possible to launch a Linux container:

```powershell
docker run --rm alpine uname
```
