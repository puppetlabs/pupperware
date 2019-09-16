# Pupperware on Windows

The ecosystem surrounding Docker container support for Linux containers on Windows is currently in flux and in heavy active development. In addition to the constant forward momentum, there have been a number of confusing naming choices to the toolchains as components have made foundational underlying changes. As a result, large swaths of online documentation for these projects don't reflect the current state of these projects, or some of their technical details / limitations.

The Pupperware project is being tested against the latest [LCOW (Linux Containers on Windows)](https://github.com/linuxkit/lcow) support available from Docker and Microsoft, and as such has a number of pre-requisites. At a high level, this support enables running Linux and Windows containers side-by-side on the same host and relies on:

* A build of Windows newer than Windows 10, Build 1809
  - Per [Moby Issue 33850 Comment](https://github.com/moby/moby/issues/33850#issuecomment-478192332) from Mar 29 2019, LCOW will only support V2 HCS APIs which require RS4 / RS5 builds (Windows 10 1803+, Windows Server 2016 1803+, Windows Server 2019+)
  - More specifically, the Postgres Linux container requires RS5 (Windows 10 1809+, Windows Server 2019+)
* Docker edge release 18.02 with experimental features enabled, nightly currently preferred
* A LinuxKit based kernel image
* docker-compose binaries

The February 2018 [Docker for Windows Desktop 18.02 blog post](https://blog.docker.com/2018/02/docker-for-windows-18-02-with-windows-10-fall-creators-update/) covers some of the important changes made in that release. In particular, the previous "Linux mode" capable of running only Linux containers was deprecated in favor of LCOW (though "Linux mode" was not yet removed). The previous "Linux mode" initially ran the `MobyLinuxVM` virtual machine in Hyper-V (later replaced with a `LinuxKit` variant in [Docker for Windows 17.10](https://blog.docker.com/2017/11/docker-for-windows-17-11/)) to host Linux containers. Older "Linux mode" support interacted with Docker volumes differently (using SMB / CIFS) than how LCOW now interfaces with volumes (using [9p](http://9p.cat-v.org/)). Note that the official Docker position is that LCOW is the one path forward for running Linux Containers on Windows:

> As a Windows platform feature, LCOW represents a long term solution for Linux container support on Windows. When the platform features meet or exceed the existing functionality the existing Docker for Windows Linux container support will be retired.

### Setup

The following steps outline how to provision a host with the required support to run this project:

* [Provision a Windows host with LCOW support](#provision-a-windows-host-with-lcow-support)
* [Install the Docker nightly build](#install-the-docker-nightly-build)
* [Install the docker-compose binaries](#install-the-docker-compose-binaries)
* [Set the Volumes directory permissions](#set-the-volumes-directory-permissions)
* [Validate the Install](#validate-the-install)

Some of these instructions are updated from the [A sneak peek at LCOW](https://stefanscherer.github.io/sneak-peek-at-lcow/) written by Stefan Scherer [@stefscherer](https://twitter.com/stefscherer)

At the time of this writing, the Windows 10 Build 1809 test host returns the following Docker versions:

```
Client:
 Version:           master-dockerproject-2019-04-03
 API version:       1.40
 Go version:        go1.12.1
 Git commit:        c500b534
 Built:             Wed Apr  3 23:43:39 2019
 OS/Arch:           windows/amd64
 Experimental:      false

Server:
 Engine:
  Version:          master-dockerproject-2019-04-03
  API version:      1.40 (minimum version 1.24)
  Go version:       go1.12.1
  Git commit:       bcaa613
  Built:            Wed Apr  3 23:50:30 2019
  OS/Arch:          windows/amd64
  Experimental:     true
```

### Additional Reference

* [Moby Project - Epic: Linux Containers on Windows](https://github.com/moby/moby/issues/33850) - tracks current status of LCOW feature implementation
* [Linux Containers](https://docs.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/linux-containers) - Microsoft high-level reference for known issues with LCOW
* [docker-for-win](https://github.com/docker/for-win) - Public issue tracking for `Docker CE for Windows`

## Provision a Windows host with LCOW support

As mentioned, Windows 10 Build 1809+, Windows Server 2019 1809+ or newer builds are necessary to support LCOW.

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
# for upgrades, stop the service before overwriting anything
Stop-Service docker -ErrorAction SilentlyContinue
Expand-Archive -Path docker-master.zip -DestinationPath $Env:ProgramFiles -Force

# unregister / reregister the service to start with system and enable experimental
& $Env:ProgramFiles\docker\dockerd.exe --unregister-service
& $Env:ProgramFiles\docker\dockerd.exe --register-service --experimental

# allow Docker CLI commands to be run from any command line (only add if not present)
if (([Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::Machine) -split ';') -inotcontains "${Env:ProgramFiles}\\docker")
{
  [Environment]::SetEnvironmentVariable("Path", "${Env:Path};${Env:ProgramFiles}\docker", [EnvironmentVariableTarget]::Machine)
}

# download Nov 15, 2018 LCOW kernel image 4.14.35 kernel / 0.3.9 OpenGCS
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -OutFile lcow-kernel.zip https://github.com/linuxkit/lcow/releases/download/v4.14.35-v0.3.9/release.zip
Expand-Archive -Path lcow-kernel.zip -DestinationPath "${Env:ProgramFiles}\Linux Containers" -Force

# Start Docker Engine
Start-Service docker
```

### Build an updated LCOW kernel

In the previous step, an LCOW kernel image [last published release 4.14.35-0.3.9](https://github.com/linuxkit/lcow/releases) was installed to the expected location for Docker. That artifact included files  `initrd.img` and `kernel` that are copied to `$Env:Program Files\Linux Containers`

Since this contains an old kernel, runc and opengcs, an updated kernel image should be built
with the [linuxkit](https://github.com/linuxkit/linuxkit) tooling. This is the current status as of April 2019 based on changes in the [opengcs](https://github.com/Microsoft/opengcs) project, per https://github.com/linuxkit/lcow/pull/41. No builds yet exist.

#### Building on Windows

Windows can be used to build the kernel image. 

Building from source requires `git`, `make`, `go` and `docker` itself. Docker must have LCOW support enabled and must have a valid kernel image installed as in the previous step (otherwise the build will fail with a message like `Error: No such image: docker.io/linuxkit/kernel:4.14.35`)

Run the following PowerShell script to:

* Install Chocolatey package manager for Windows
* Install build tooling with Chocolatey
* Copy and build LinuxKit source
* Copy and build LCOW kernel image source
* Deploy LCOW kernel image to host

```powershell
# set process execution policy
Set-ExecutionPolicy Bypass -Scope Process -Force

# install Chocolatey
iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

# install build tooling
choco install -y git golang make

# make build tools available in current session
# by setting environment variable and importing Chocolatey PowerShell
$env:ChocolateyInstall = Convert-Path "$((Get-Command choco).path)\..\.."
Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
Update-SessionEnvironment

# use `go get` to clone and build linuxkit source
# verbose output since this will generally take a while
go get -v -u github.com/linuxkit/linuxkit/src/cmd/linuxkit
# GOPATH location is documented by running `go env`

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

Restart-Service docker
```

If everything is configured correctly, the `linuxkit build lcow.yml` output should be similar to the following:

```
PS C:\Users\puppet\AppData\Local\Temp\lcow> linuxkit build lcow.yml
Extract kernel image: linuxkit/kernel:4.19.27
Pull image: docker.io/linuxkit/kernel:4.19.27@sha256:64012346855139ee3efeff2cf137f12f251fa6593204a59e142e86de5d39ef97
Add init containers:
Process init image: linuxkit/init-lcow:15f50743b68117f4db1158c89530d47affbbd07b
Pull image: docker.io/linuxkit/init-lcow:15f50743b68117f4db1158c89530d47affbbd07b@sha256:471fcc1af0a8d3723a7cf40dd28f765d81391d04cedfd8f311c7c0474b2220a5
Process init image: linuxkit/runc:606971451ea29b4238029804ca638f9f85caf5af
Pull image: docker.io/linuxkit/runc:606971451ea29b4238029804ca638f9f85caf5af@sha256:aed31e546e3bfa36f575b912f836f7d02b4340698c93c89df4ec6617a5f8ebf2
Add files:
  etc/linuxkit.yml
Create outputs:
  lcow-kernel lcow-initrd.img lcow-cmdline
```

#### Building on OSX (Alternate Build Workflow)

Alternatively, it may be simpler to do this on OSX with the help of Homebrew, as `linuxkit` builds are already available there. Detailed instructions are in [README-OSX-build-LCOW-kernel.md](./README-OSX-build-LCOW-kernel.md). The build artifacts should be copied to the Windows system as previously described.

## Install the docker-compose binaries

To provision the compose files in this repository also requires a working `docker-compose.exe`. Windows nightly builds are not available ([issue 6308 filed](https://github.com/docker/compose/issues/6308)), but reasonably release builds are available at the [docker-compose GitHub releases page](https://github.com/docker/compose/releases/). Run the following PowerShell script to:

* Download the 1.24.0 build of docker-compose
* Install it to expected location

```powershell
# download docker-compose 1.24.0 from Mar 28 2019
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Invoke-WebRequest -OutFile "${ENV:ProgramFiles}\docker\docker-compose.exe" https://github.com/docker/compose/releases/download/1.24.0/docker-compose-Windows-x86_64.exe
```

### Build the docker-compose binaries (Alternate Build Workflow)

Rather than consuming an official release, a `docker-compose` binary can be built from sources if necessary. Fortunately the source code repository includes a build script at https://github.com/docker/compose/blob/master/script/build/windows.ps1 that does most of the heavy lifting.

Run the following PowerShell script to:

* Install Python build tooling with Chocolatey
* Copy and build Docker Compose source
* Install Docker Compose alongside Docker

```powershell
# building docker-compose requires a 3.6 series Python, 3.7 doesn't work
choco install -y python --version 3.6.7

# make build tools available in current session
# by setting environment variable and importing Chocolatey PowerShell
$env:ChocolateyInstall = Convert-Path "$((Get-Command choco).path)\..\.."
Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
Update-SessionEnvironment

pip install 'virtualenv>=15.1.0'

Push-Location $Env:Temp
git clone https://github.com/docker/compose
Push-Location compose

# run the build script from the repo
.\script\build\windows.ps1

# copy binaries to the Docker installation directory
Copy-Item .\dist\docker-compose-Windows-x86_64.exe $ENV:ProgramFiles\Docker\docker-compose.exe -Force
```

NOTE: Python 3.6 series is required to build Windows binaries. 3.7 can be used, but requires manually merging the patch from https://github.com/Alexpux/MINGW-packages/commit/4c18633ba2331d980f00aff075f17135399c43c5 into the cx_Freeze package.

## Set the Volumes directory permissions

Due to bug [#39922](https://github.com/moby/moby/issues/39922) in Docker, the Postgres Linux container cannot use a Docker volume stored in the typical location of `C:\ProgramData\Docker\volumes`. Postgres attempts to create a hardlink, but the `vwmp.exe` process hosting the container lacks the permission to do so. Until the bug is fixed, a workaround is to grant the `NT VIRTUAL MACHINE\Virtual Machines` group inheritable full control to the volumes parent directory. Hopefully in the future this will be automatically managed by Docker and unnecessary for users to manage themselves.

```
icacls C:\ProgramData\docker\volumes /grant *S-1-5-83-0:"(OI)(CI)F" /T
```

## Validate the install

The Docker service should now be running on boot and should now yield details about the LCOW setup like

```powershell
PS> docker info

Client:
 Debug Mode: false
 Plugins:
  app: Docker Application Packages (Docker Inc., v0.6.0-148-ge797c906f6)

Server:
 Containers: 0
  Running: 0
  Paused: 0
  Stopped: 0
 Images: 56
 Server Version: master-dockerproject-2019-04-03
 Storage Driver: lcow (linux) windowsfilter (windows)
  LCOW:
  Windows:
 Logging Driver: json-file
 Plugins:
  Volume: local
  Network: ics l2bridge l2tunnel nat null overlay transparent
  Log: awslogs etwlogs fluentd gcplogs gelf json-file local logentries splunk syslog
 Swarm: inactive
 Default Isolation: hyperv
 Kernel Version: 10.0 17763 (17763.1.amd64fre.rs5_release.180914-1434)
 Operating System: Windows 10 Enterprise Version 1809 (OS Build 17763.379)
 OSType: windows
 Architecture: x86_64
 CPUs: 2
 Total Memory: 16GiB
 Name: ci-lcow-prod-1
 ID: 0ac02c9d-aaba-42f4-8749-5a64af3068d8
 Docker Root Dir: C:\ProgramData\docker
 Debug Mode: false
 Registry: https://index.docker.io/v1/
 Labels:
 Experimental: true
 Insecure Registries:
  127.0.0.0/8
 Live Restore Enabled: false
```

Docker-compose should also provide information like:

```
PS> docker-compose version

docker-compose version 1.24.0, build 0aa59064
docker-py version: 3.7.2
CPython version: 3.6.8
OpenSSL version: OpenSSL 1.0.2q  20 Nov 2018
```

With all of the LCOW setup verified, it should now be possible to launch side-by-side
Linux and Windows containers

```powershell
docker run -itd microsoft/nanoserver
docker run -itd postgres:9.6
```
