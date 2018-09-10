# Windows Specific Configuration

There are some details about configuring Windows hosts that may differ from the
standard Linux docker setup.

## Setting up a Windows host with LCOW support

* This project is being validated under [LCOW](https://github.com/linuxkit/lcow) on Windows 10 Build 1709

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

* If running on Azure, the host must be a `*_v3` to supported nested virtualization, like `Standard_D4s_v3`

The follow instructions are updated from the [A sneak peek at LCOW](https://stefanscherer.github.io/sneak-peek-at-lcow/) written by Stefan Scherer [@stefscherer](https://twitter.com/stefscherer)

### Ensure appropriate Windows features are enabled

```powershell
PS> Enable-WindowsOptionalFeature -Online -FeatureName containers, Microsoft-Hyper-V -All -NoRestart
```

### Install the Docker nightly build

Using the Docker project permalink, grab the latest binaries and extract to `Program Files\docker`

```powershell
Push-Location $Env:TEMP
Invoke-WebRequest -OutFile docker-master.zip https://master.dockerproject.com/windows/x86_64/docker.zip
Expand-Archive -Path docker-master.zip -DestinationPath $Env:ProgramFiles -Force
```

### Enable the Docker service with experimental features enabled

A simple command line invocation installs the Docker service, so that it will start on reboot

```powershell
& $Env:ProgramFiles\docker\dockerd.exe --register-service --experimental
```

### Set system PATH to include Docker CLI

For convenience, put the docker binary into the system PATH so that commands can be run from any CLI

```powershell
[Environment]::SetEnvironmentVariable("Path", "${Env:Path};${Env:ProgramFiles}\docker", [EnvironmentVariableTarget]::Machine)
```

**Warning** - On Windows 10, the required LCOW virtal machine files may not exist, and the currently available download ([4.14.29](https://github.com/linuxkit/lcow/releases/tag/4.14.29-0aea33bc)) is too out of date. The LCOW files need to be built as per the instructions in this README.

### Building the LCOW virtual machine

To run Linux containers with LCOW requires a lightweight VM image that runs under Hyper-V. At this time, the
[last published release 4.14.29-0aea33bc](https://github.com/linuxkit/lcow/releases) of the LCOW virtual machine image is
outdated and produces different artifacts than what the master version of Docker installed in the previous step expects.

Therefore, an image must be built using the [linuxkit](https://github.com/linuxkit/linuxkit) tooling. Additionally,
building from source requires `git`, `make` and `docker` itself.

#### Building LCOW files on Windows

Windows can be used to build this VM, with the help of Chocolatey to install prerequisites.  Alternatively the files can be build on [OSX](https://github.com/linuxkit/lcow#prerequisites-1)

* Install Chocolatey

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
```

* Install Tooling

```powershell
choco install -y git golang make
```

* Acquire and build LinuxKit

For Chocolatey tools to be available on PATH, close and reopen a new terminal. The `docker` CLI tool should already be
available from prior steps installing Docker. Acquire the Go source and build the tool with `go get`:

```powershell
go get -u github.com/Iristyle/linuxkit/src/cmd/linuxkit
```

Note that this is a fork of the linuxkit master from Sept 4 2018 at https://github.com/linuxkit/linuxkit/commit/32bc34d168466ab4decf1e7c7f212fbf587a3857
that updates compatible Docker API version from 1.23 to 1.24 with commit https://github.com/Iristyle/linuxkit/commit/b66e94adf6034b3cb89f37afda7584d1cf807476
which is necessary for the Docker master version on Windows.

This will produce the `linuxkit.exe` binary, placing it in the default `$Env:GOPATH` based on the users home directory,
if one is not explicitly configured. This can be verified with:

```powershell
& $Env:USERPROFILE\go\bin\linuxkit.exe help
```

* Acquire and build the LCOW image

Note - The LCOW building process uses `docker` to build, therefore it requires a working installation of Docker.  Due to LCOW not currently working out of the box, you will need to install
[Docker For Windows](https://www.docker.com/products/docker-desktop) locally, or build the LCOW files on another computer.

```powershell
Push-Location $Env:Temp
git clone https://github.com/linuxkit/lcow
Push-Location lcow
$Env:Path += ";$Env:USERPROFILE\go\bin"
linuxkit build lcow.yml
```

If everything is configured correctly, the output should be similar to the following:

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

### Installing the LCOW VM image

Docker expects the LCOW VM image to be installed to `$Env:Program Files\Linux Containers`. It expects files named
`initrd.img` and `kernel`.

To copy the files produced from the Windows build step above, do the following:

```powershell
New-Item "$Env:ProgramFiles\Linux Containers" -Type Directory -Force
Copy-Item .\lcow-initrd.img "$Env:ProgramFiles\Linux Containers\initrd.img"
Copy-Item .\lcow-kernel "$Env:ProgramFiles\Linux Containers\kernel"
```

#### Reboot

For the system and other changes to take effect, reboot the server.

#### Validate the install

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
