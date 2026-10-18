[CmdletBinding()]
param(
    [ValidateSet('Detect', 'Install')][string]$Mode = 'Detect',
    [string]$StatePath,
    [string]$ReleaseConfigPath,
    [string]$InstallerPath,
    [switch]$InstallApproved,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$commonDirectory = Join-Path $PSScriptRoot 'common'
Import-Module (Join-Path $commonDirectory 'Utils.psm1') -Force
Import-Module (Join-Path $commonDirectory 'StateManager.psm1') -Force
Import-Module (Join-Path $commonDirectory 'Logging.psm1') -Force
Import-Module (Join-Path $commonDirectory 'DockerReadiness.psm1') -Force

if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = (Get-InstallerConstants).StateFilePath }
if ([string]::IsNullOrWhiteSpace($ReleaseConfigPath)) { $ReleaseConfigPath = Join-Path $PSScriptRoot '..\config\docker-desktop-release.json' }

if ($Mode -eq 'Detect') {
    $readiness = Get-DockerReadiness
    if ($readiness.IsReady -and -not $WhatIf) {
        Set-InstallState -Path $StatePath -Stage 'DOCKER_READY' -Values @{ docker_install_approved = $false } | Out-Null
        Write-InstallLog -Level Info -Stage 'DOCKER_READY' -Message 'Docker Desktop is ready for Linux containers.' | Out-Null
    }

    return [pscustomobject]@{ Readiness = $readiness; State = Get-InstallState -Path $StatePath }
}

if (-not $InstallApproved) {
    throw 'Docker Desktop installation requires explicit user approval.'
}

$existingReadiness = Get-DockerReadiness
if ($existingReadiness.Status -ne 'Missing') {
    return [pscustomobject]@{
        Status = 'ExistingInstallationNeedsAttention'
        Readiness = $existingReadiness
        Message = 'Docker Desktop is already present but is not ready. Start, repair, or switch the existing Docker Desktop installation; the ERPNext installer will not upgrade or reinstall it automatically.'
    }
}

$release = Get-DockerDesktopRelease -Path $ReleaseConfigPath
if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    $InstallerPath = Join-Path ([System.IO.Path]::GetTempPath()) ("ERPNextWindowsInstaller-DockerDesktop-$($release.version).exe")
}

if ($WhatIf) {
    return [pscustomobject]@{ Status = 'Planned'; Version = $release.version; InstallerPath = $InstallerPath }
}

if (-not (Test-Path -LiteralPath $InstallerPath) -and -not $WhatIf) {
    Save-DockerDesktopInstaller -Release $release -DestinationPath $InstallerPath | Out-Null
}

$result = Invoke-DockerDesktopInstall -InstallerPath $InstallerPath -Release $release -WhatIf:$WhatIf
if (-not $WhatIf) {
    Write-InstallLog -Level Info -Stage 'FEATURES_CONFIRMED' -Message ("Docker Desktop {0} installed for all Windows users; it must be started and its license accepted before setup can continue." -f $release.version) | Out-Null
}

return $result
