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

    (git describe) -replace '-.*', ''
}

# only need to specify -Name or -Path when calling
function Lint-Dockerfile(
    $Name,
    $Path = "docker/$Name/Dockerfile",
    $Ignore = @())
{
    $ignores = @()
    foreach ($code in @('DL3008','DL3018','DL4000','DL4001') + $Ignore) {
        $ignores += '--ignore', $code
    }

    Write-Output "hadolint $ignores $Path"

    hadolint $ignores $Path
}

function Build-Container(
    $Name,
    $Namespace = 'puppet',
    $Dockerfile = "docker/$Name/Dockerfile",
    $Context = "docker/$Name",
    $Version = (Get-ContainerVersion),
    $Vcs_ref = $(git rev-parse HEAD),
    $Pull = $true)
{
    $build_date = (Get-Date).ToUniversalTime().ToString('o')
    $docker_args = @(
        '--build-arg', "version=$Version",
        '--build-arg', "vcs_ref=$Vcs_ref",
        '--build-arg', "build_date=$build_date",
        '--build-arg', "namespace=$Namespace",
        '--file', "$Dockerfile",
        '--tag', "$Namespace/${Name}:$Version"
    )

    if ($Pull) {
        $docker_args += '--pull'
    }

    Write-Output "docker build $docker_args $Context"

    docker build $docker_args $Context
}

# set an Azure variable for temp volumes root
# temp volumes root is deleted in Clear-ContainerBuilds
function Initialize-TestEnv()
{
    $tempVolumeRoot = Join-Path -Path $ENV:TEMP -ChildPath ([System.IO.Path]::GetRandomFileName())
    Write-Host "##vso[task.setvariable variable=VOLUME_ROOT]$tempVolumeRoot"
}

function Invoke-ContainerTest(
    $Name,
    $Namespace = 'puppet',
    $Specs = 'docker/spec',
    $Options = '.rspec',
    $Version = (Get-ContainerVersion))
{
    # NOTE our shared `docker_compose` Ruby method assumes the
    # docker-compose.yml files are in the current working directory,
    # so we assume they're in the same directory as the specdir
    Push-Location (Split-Path "$Specs")
    $specdir = Split-Path -Leaf "$Specs"

    $ENV:PUPPET_TEST_DOCKER_IMAGE = "$Namespace/${Name}:$Version"
    Write-Host "Testing against image: ${ENV:PUPPET_TEST_DOCKER_IMAGE}"
    bundle exec rspec --version

    Write-Host "bundle exec rspec --options $Options $specdir"
    bundle exec rspec --options $Options $specdir

    Pop-Location
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
    Write-Output 'Pruning Containers'
    docker container prune --force

    # delete directory if ENV variable is defined and directory actually exists
    if (($ENV:VOLUME_ROOT) -and (Test-Path "$ENV:VOLUME_ROOT")) {
        Write-Host "Cleaning up temporary volume: $ENV:VOLUME_ROOT"
        Remove-Item $ENV:VOLUME_ROOT -Force -Recurse -ErrorAction Continue
    }

    # this provides example data which ConvertFrom-String infers parsing structure with
    $template = @'
{Version*:10.2.3*} {ID:5b84704c1d01} {[DateTime]Created:2019-02-07 18:24:51} +0000 GMT
{Version*:latest} {ID:0123456789ab} {[DateTime]Created:2019-01-29 00:05:33} +0000 GMT
'@
    $output = docker images --filter=reference="$Namespace/${Name}" --format "{{.Tag}} {{.ID}} {{.CreatedAt}}"
    Write-Output @"

Found $Namespace/${Name} images:
$($output | Out-String)

"@

    if ($output -eq $null) { return }

    Write-Output "Filtering removal candidates..."
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
        Write-Output "Removing Old $Namespace/${Name} Image $($_.Version) ($($_.ID)) Created On $($_.Created)"
        $forcecli = if ($Force) { '-f' } else { '' }
        docker image rm $_.ID $forcecli
      }

    Write-Output "`nPruning Dangling Images"
    docker image prune --filter "dangling=true" --force
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
