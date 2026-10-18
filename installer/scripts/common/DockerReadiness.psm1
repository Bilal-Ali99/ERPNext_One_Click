Set-StrictMode -Version Latest

function Get-DockerDesktopRelease {
    [CmdletBinding()]
    param([string]$Path = (Join-Path $PSScriptRoot '..\..\config\docker-desktop-release.json'))

    if (-not (Test-Path -LiteralPath $Path)) {
        throw 'The approved Docker Desktop release configuration is missing.'
    }

    $release = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    foreach ($property in @('version', 'architecture', 'installerUrl', 'sha256', 'installScope', 'installerArguments')) {
        if ($null -eq $release.PSObject.Properties[$property] -or [string]::IsNullOrWhiteSpace([string]$release.$property)) {
            throw "The Docker Desktop release configuration is missing '$property'."
        }
    }

    if ($release.architecture -ne 'amd64' -or $release.installScope -ne 'allUsers' -or $release.sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
        throw 'The Docker Desktop release configuration is not approved for this installer.'
    }

    return $release
}

function Test-DockerDesktopInstaller {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][psobject]$Release)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ IsValid = $false; Reason = 'The Docker Desktop installer file is missing.' }
    }

    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($hash -ine $Release.sha256) {
        return [pscustomobject]@{ IsValid = $false; Reason = 'The Docker Desktop installer checksum does not match the approved release.' }
    }

    $signature = Get-AuthenticodeSignature -FilePath $Path
    if ($signature.Status -ne 'Valid') {
        return [pscustomobject]@{ IsValid = $false; Reason = 'The Docker Desktop installer signature is not valid.' }
    }

    return [pscustomobject]@{ IsValid = $true; Reason = '' }
}

function Save-DockerDesktopInstaller {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][psobject]$Release, [Parameter(Mandatory = $true)][string]$DestinationPath)

    $directory = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Invoke-WebRequest -Uri $Release.installerUrl -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop
    return $DestinationPath
}

function Invoke-DockerDesktopInstall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)][psobject]$Release,
        [switch]$WhatIf
    )

    $verification = Test-DockerDesktopInstaller -Path $InstallerPath -Release $Release
    if (-not $verification.IsValid) {
        throw $verification.Reason
    }

    if ($WhatIf) {
        return [pscustomobject]@{ Status = 'Planned'; Version = $Release.version }
    }

    $process = Start-Process -FilePath $InstallerPath -ArgumentList @($Release.installerArguments) -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Docker Desktop installation failed with exit code $($process.ExitCode)."
    }

    return [pscustomobject]@{ Status = 'InstalledPendingUserStart'; Version = $Release.version }
}

function Invoke-DockerCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DockerPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    try {
        $output = & $DockerPath @Arguments 2>$null
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = (@($output) -join [Environment]::NewLine).Trim()
        }
    }
    catch {
        return [pscustomobject]@{ ExitCode = -1; Output = '' }
    }
}

function New-DockerReadinessResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Missing', 'EngineNotReady', 'ComposeUnavailable', 'WindowsContainers', 'Ready')][string]$Status,
        [string]$Version = '',
        [string]$ComposeVersion = '',
        [string]$ContainerOs = '',
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Remediation
    )

    return [pscustomobject][ordered]@{
        Status = $Status
        IsReady = ($Status -eq 'Ready')
        Version = $Version
        ComposeVersion = $ComposeVersion
        ContainerOs = $ContainerOs
        Message = $Message
        Remediation = $Remediation
    }
}

function Get-DockerReadiness {
    [CmdletBinding()]
    param()

    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if ($null -eq $docker) {
        return New-DockerReadinessResult -Status 'Missing' -Message 'Docker Desktop was not found.' -Remediation 'Install Docker Desktop using the installer-provided, verified package.'
    }

    $engine = Invoke-DockerCli -DockerPath $docker.Source -Arguments @('version', '--format', '{{.Server.Version}}')
    if ($engine.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($engine.Output)) {
        return New-DockerReadinessResult -Status 'EngineNotReady' -Message 'Docker was found, but its engine is not ready.' -Remediation 'Start Docker Desktop and wait until its engine is running, then try again.'
    }

    $compose = Invoke-DockerCli -DockerPath $docker.Source -Arguments @('compose', 'version', '--short')
    if ($compose.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($compose.Output)) {
        return New-DockerReadinessResult -Status 'ComposeUnavailable' -Version $engine.Output -Message 'Docker Engine is running, but Docker Compose is unavailable.' -Remediation 'Repair or update Docker Desktop, then try again.'
    }

    $containerOs = Invoke-DockerCli -DockerPath $docker.Source -Arguments @('info', '--format', '{{.OSType}}')
    if ($containerOs.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($containerOs.Output)) {
        return New-DockerReadinessResult -Status 'EngineNotReady' -Version $engine.Output -ComposeVersion $compose.Output -Message 'Docker Engine readiness could not be confirmed.' -Remediation 'Start Docker Desktop and try again.'
    }

    if ($containerOs.Output.Trim().ToLowerInvariant() -ne 'linux') {
        return New-DockerReadinessResult -Status 'WindowsContainers' -Version $engine.Output -ComposeVersion $compose.Output -ContainerOs $containerOs.Output -Message 'Docker Desktop is set to Windows containers.' -Remediation 'Switch Docker Desktop to Linux containers, then try again.'
    }

    return New-DockerReadinessResult -Status 'Ready' -Version $engine.Output -ComposeVersion $compose.Output -ContainerOs $containerOs.Output -Message 'Docker Desktop, Docker Engine, and Docker Compose are ready for Linux containers.' -Remediation ''
}

Export-ModuleMember -Function Get-DockerDesktopRelease, Test-DockerDesktopInstaller, Save-DockerDesktopInstaller, Invoke-DockerDesktopInstall, Invoke-DockerCli, New-DockerReadinessResult, Get-DockerReadiness
