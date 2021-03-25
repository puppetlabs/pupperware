$ErrorActionPreference = 'Stop'

function Get-ContainerVersion
{
    # Don't need to fetch anything else when running in Azure CI, as that will
    # already have pulled everything down, and more importantly git-fetch will
    # block waiting for authorization. TF_BUILD is set by Azure CI.
    if ($ENV:TF_BUILD -ine 'true')
    {
        # shallow repositories need to pull remaining code to `git describe` correctly
        if (Test-Path "$(git rev-parse --git-dir)/shallow")
        {
            git pull --unshallow
        }

        # tags required for versioning
        git fetch origin 'refs/tags/*:refs/tags/*'
    }

    # in a repo with no tags, --always returns a 8 character SHA
    # when at a specific tag, we get just that number like 2019.2.0.9
    # otherwise we get something like 2019.1.0.93-6-g4c72515
    $gitver = git describe --always
    # most Dockerfiles *don't* build from source, and need
    # this version to find packages, so remove the -#-gXXXXXX portion
    # for repos without tags like pupperware, nothing is built, so short SHA is fine
    $gitver -replace '-.*', ''
}

function Get-EnterpriseContainerVersion(
    $Package,
    $Token,
    $PeVer = "2019.1.x")
{
    $params = @{
      Uri = "https://raw.githubusercontent.com/puppetlabs/enterprise-dist/$PeVer/packages.json"
      Headers = @{ "Authorization" = "token $Token" }
    }
    $packages = Invoke-RestMethod @params
    @{
      Version = $packages."ubuntu-18.04-amd64"."$Package"."version"
      Release = $packages."ubuntu-18.04-amd64"."$Package"."release"
    }
}

# only need to specify -Name or -Path when calling
function Lint-Dockerfile(
    $Name,
    $Path = "docker/$Name/Dockerfile",
    $Ignore = @())
{
    $ignores = $Ignore | % { if ($_) { '--ignore', $_ } }
    Write-Host "& cmd.exe /c docker run --rm -i ghcr.io/hadolint/hadolint hadolint $ignores -< $Path"

    # while a simpler method works locally, there appears to be a bug with stdin in Azure injecting BOMs?
    # https://developercommunity.visualstudio.com/content/problem/451239/powershell-build-step-in-azure-devops-fails-when-p.html
    # https://github.com/microsoft/botbuilder-tools/pull/1046
    & cmd.exe /c docker run --rm -i ghcr.io/hadolint/hadolint hadolint $ignores -< $Path
    if ($LASTEXITCODE -ne 0) { throw "ERROR: Linting $Path" }
}

function Test-NetworkAccess() {
    if ($ENV:REQUIRE_ARTIFACTORY) {
        try {
            Invoke-RestMethod -Uri https://artifactory.delivery.puppetlabs.net/artifactory/api/system/ping -TimeoutSec 10
        } catch {
            throw 'ERROR: Artifactory cannot be reached or unhealthy. Are you on the VPN?'
        }
    }
}

function Build-Container(
    $Name,
    $Namespace = 'puppet',
    $Dockerfile = "docker/$Name/Dockerfile",
    # Context alias set for backward compatibility, but deprecated
    [Alias('Context')]
    $PathOrUri = "docker/$Name",
    $Version = (Get-ContainerVersion),
    $Release = '',
    $Vcs_ref = $(git rev-parse HEAD),
    $Pull = $true,
    $AdditionalOptions = @())
{
    Test-NetworkAccess

    $build_date = (Get-Date).ToUniversalTime().ToString('o')
    $docker_args = @(
        '--build-arg', "version=$Version",
        '--build-arg', "vcs_ref=$Vcs_ref",
        '--build-arg', "build_date=$build_date",
        '--file', $Dockerfile
    ) + $AdditionalOptions

    if ($Release -ne '') {
        $docker_args += '--tag', "$Namespace/${Name}:$Version-$Release"
        $docker_args += '--build-arg', "release=$Release"
    }
    else {
        $docker_args += '--tag', "$Namespace/${Name}:$Version"
    }

    if ($Pull) {
        $docker_args += '--pull'
    }

    Write-Host "docker build $docker_args $PathOrUri"

    # https://docs.docker.com/engine/reference/commandline/build/
    docker build $docker_args $PathOrUri
}

# NOTE: no longer necessary, but left in case need arises for temp bind mounts
# https://github.com/moby/moby/issues/39922
# set an Azure variable for temp volumes root
# temp volumes root is deleted in Clear-ContainerBuilds
function Initialize-TestEnv()
{
    $tempVolumeRoot = Join-Path -Path $ENV:TEMP -ChildPath ([System.IO.Path]::GetRandomFileName())
    # tack on a trailing / or \
    $tempVolumeRoot = Join-Path -Path $tempVolumeRoot -ChildPath ([System.IO.Path]::DirectorySeparatorChar)
    Write-Host "##vso[task.setvariable variable=VOLUME_ROOT]$tempVolumeRoot"
}

function Invoke-ContainerTest(
    $Name,
    $Namespace = 'puppet',
    $Specs = 'docker/spec',
    $Options = '.rspec',
    $Version = (Get-ContainerVersion),
    $Release = '')
{
    # NOTE our shared `docker_compose` Ruby method assumes the
    # docker-compose.yml files are in the current working directory,
    # so we assume they're in the same directory as the specdir
    Push-Location (Split-Path $Specs)
    $specdir = Split-Path -Leaf $Specs

    if ($Release -ne '') {
        $Tag = "$Version-$Release"
    }
    else {
        $Tag = "$Version"
    }

    if ($Name -ne $null) {
        $ENV:PUPPET_TEST_DOCKER_IMAGE = "$Namespace/${Name}:$Tag"
        Write-Host "Testing against image: ${ENV:PUPPET_TEST_DOCKER_IMAGE}"
    }
    bundle exec rspec --version

    Write-Host "bundle exec rspec --options $Options $specdir"
    bundle exec rspec --options $Options $specdir

    Pop-Location
}

# removes docker compose volumes / networks
# deletes any allocated builds from ENV:VOLUME_ROOT
# removes unused containers, and prunes images
function Clear-BuildState(
    $Name,
    $Namespace = 'puppet',
    $OlderThan = [DateTime]::Now.Subtract([TimeSpan]::FromDays(14)),
    [Switch]
    $Force = $false
)
{
    Clear-ComposeLeftOvers
    Remove-ContainerVolumeRoot
    Clear-ContainerBuilds @PSBoundParameters
    Clear-DanglingImages
    Write-DockerResourceInformation
}

function Clear-ComposeLeftOvers
{
    # NOTE these calls need to be in a certain order to make sure
    # things like volumes for stopped containers are removed.
    #
    # We should also consider collapsing all these calls into:
    #
    #   docker system prune --volumes --force
    Write-Host "`nPruning Containers"
    docker container prune --force

    Write-Host "`nPruning Volumes"
    docker volume prune --force

    Write-Host "`nPruning Networks"
    docker network prune --force
}

# NOTE: no longer necessary, but left in case need arises for temp bind mounts
# https://github.com/moby/moby/issues/39922
function Remove-ContainerVolumeRoot
{
    # delete directory if ENV variable is defined and directory actually exists
    if (($ENV:VOLUME_ROOT) -and (Test-Path $ENV:VOLUME_ROOT)) {
        Write-Host "Cleaning up temporary volume: $ENV:VOLUME_ROOT"
        Remove-Item $ENV:VOLUME_ROOT -Force -Recurse -ErrorAction Continue
    }
}

# removes temporary layers / containers / images used during builds
# removes $Namespace/$Name images > 14 days old by default
function Clear-ContainerBuilds(
    $Name,
    $Namespace = 'puppet',
    $OlderThan = [DateTime]::Now.Subtract([TimeSpan]::FromDays(14)),
    [Switch]
    $Force = $false
)
{
    # given no name, no images to remove
    if ($Name -eq $null) { return }

    Write-Host "`nLooking for ${Namespace}/${Name} image candidates for removal"

    # this provides example data which ConvertFrom-String infers parsing structure with
    $template = @'
{Version*:10.2.3*} {ID:5b84704c1d01} {[DateTime]Created:2019-02-07 18:24:51} +0000 GMT
{Version*:latest} {ID:0123456789ab} {[DateTime]Created:2019-01-29 00:05:33} +0000 GMT
'@
    $output = docker images --filter=reference="$Namespace/${Name}" --format "{{.Tag}} {{.ID}} {{.CreatedAt}}"
    Write-Host @"

Found $Namespace/${Name} images:
$($output | Out-String)

"@

    if ($output -eq $null) { return }

    Write-Host 'Filtering removal candidates...'
    # docker image prune supports filter until= but not repository like 'puppetlabs/foo'
    # must use label= style filtering which is a bit more inconvenient
    # that output is also not user-friendly!
    # engine doesn't maintain "last used" or "last pulled" metadata, which would be more useful
    # https://github.com/moby/moby/issues/4237
    $output |
      ConvertFrom-String -TemplateContent $template |
      ? { $_.Created -lt $OlderThan } |
      # ensure 'latest' are listed first
      Sort-Object -Property Version -Descending |
      % {
        Write-Host "Removing Old $Namespace/${Name} Image $($_.Version) ($($_.ID)) Created On $($_.Created)"
        $forcecli = if ($Force) { '-f' } else { '' }
        docker image rm $_.ID $forcecli
      }
}

function Clear-DanglingImages
{
    Write-Host "`nPruning Dangling Images"
    docker image prune --filter "dangling=true" --force
}

function Write-DockerResourceInformation()
{
    $line = '=' * 80

    Write-Host "`nExisting Docker Resources"

    Write-Host "$line`nContainers`n$line`n"
    docker container ps --all

    Write-Host "$line`nImages`n$line`n"
    docker image ls

    Write-Host "$line`nNetworks`n$line`n"
    docker network ls

    Write-Host "$line`nVolumes`n$line`n"
    docker volume ls
}

function Write-HostDiagnostics()
{
    $line = '=' * 80
    Write-Host "$line`nWindows`n$line`n"
    Get-ComputerInfo |
      select WindowsProductName, WindowsVersion, OsHardwareAbstractionLayer |
      Out-String |
      Write-Host
    #
    # Azure
    #
    $assetTag = Get-WmiObject -class Win32_SystemEnclosure -namespace root\CIMV2 |
      Select -ExpandProperty SMBIOSAssetTag

    # only Azure VMs have this hard-coded DMI value
    if ($assetTag -eq '7783-7084-3265-9085-8269-3286-77')
    {
      Write-Host "`n`n$line`nAzure`n$line`n"
      Invoke-RestMethod -Headers @{'Metadata'='true'} -URI http://169.254.169.254/metadata/instance?api-version=2017-12-01 -Method Get |
        ConvertTo-Json -Depth 10 |
        Write-Host
    }
    #
    # Docker
    #
    Write-Host "`n`n$line`nDocker`n$line`n"
    docker version
    docker images
    docker info
    docker-compose version
    sc.exe qc docker
    Write-Host "`n`n$line`nLinter`n$line`n"
    #
    # Linter
    #
    docker pull ghcr.io/hadolint/hadolint:latest
    # --pull=always crashes hard in Azure CI agent for some reason
    docker run --rm ghcr.io/hadolint/hadolint:latest hadolint --version
    #
    # Ruby
    #
    Write-Host "`n`n$line`nRuby`n$line`n"
    ruby --version
    gem --version
    gem env
    bundle --version
    #
    # Environment
    #
    Write-Host "`n`n$line`nEnvironment`n$line`n"
    Get-ChildItem Env: | % { Write-Host "$($_.Key): $($_.Value)"  }
}
