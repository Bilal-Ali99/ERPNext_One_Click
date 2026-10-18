[CmdletBinding()]
param(
    [switch]$WhatIf,
    [string]$StatePath,
    [string]$ResumeToken,
    [ValidateSet('RestartNow', 'RestartLater', 'None')]
    [string]$RestartChoice = 'None',
    [switch]$InstallDocker
)

Set-StrictMode -Version Latest

$commonDirectory = Join-Path $PSScriptRoot 'common'
Import-Module (Join-Path $commonDirectory 'Logging.psm1') -Force
Import-Module (Join-Path $commonDirectory 'StateManager.psm1') -Force
Import-Module (Join-Path $commonDirectory 'FeatureResume.psm1') -Force
Import-Module (Join-Path $commonDirectory 'Utils.psm1') -Force

if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = (Get-InstallerConstants).StateFilePath
}

$state = Get-InstallState -Path $StatePath

if ($state.stage -eq 'NOT_STARTED') {
    $preflightPath = Join-Path $PSScriptRoot 'preflight.ps1'
    $preflight = & $preflightPath -WhatIf:$WhatIf

    if ($preflight.HasBlockers) {
        if (-not $WhatIf) {
            Write-InstallLog -Level Error -Stage 'NOT_STARTED' -Message 'Preflight reported one or more blocking issues.' | Out-Null
        }

        throw 'Preflight reported blocking issues. Resolve them before continuing.'
    }

    if (-not $WhatIf) {
        $state = Set-InstallState -Path $StatePath -Stage 'PREFLIGHT_DONE' -Values @{ docker_install_approved = [bool]$InstallDocker }
        Write-InstallLog -Level Info -Stage $state.stage -Message 'Preflight completed successfully.' | Out-Null
    }

    if ($WhatIf) {
        return [pscustomobject]@{
            Mode = 'WhatIf'
            State = $state
            Preflight = $preflight
        }
    }

    $state = Get-InstallState -Path $StatePath
}

if ($state.stage -eq 'PREFLIGHT_DONE') {
    if (-not $WhatIf) {
        $state = Set-InstallState -Path $StatePath -Stage 'PREFLIGHT_DONE' -Values @{ docker_install_approved = [bool]$InstallDocker }
    }

    if ($RestartChoice -ne 'None') {
        $featureScriptPath = Join-Path $PSScriptRoot 'enable-features.ps1'
        $featureEnablement = & $featureScriptPath -Mode Enable -RestartChoice $RestartChoice -StatePath $StatePath
        if ($featureEnablement.RestartRequired) {
            return [pscustomobject]@{
                Mode = 'Execute'
                State = Get-InstallState -Path $StatePath
                FeatureEnablement = $featureEnablement
            }
        }

        $state = Get-InstallState -Path $StatePath
    }

    return [pscustomobject]@{
        Mode = if ($WhatIf) { 'WhatIf' } else { 'Execute' }
        State = $state
        NextAction = 'Run enable-features.ps1 with an explicit RestartNow or RestartLater choice.'
    }
}

if ($state.stage -eq 'FEATURES_ENABLED_PENDING_RESTART') {
    if ([string]::IsNullOrWhiteSpace($ResumeToken)) {
        throw 'A resume token is required after the feature-enable restart.'
    }

    return Confirm-FeatureResume -StatePath $StatePath -ResumeToken $ResumeToken -WhatIf:$WhatIf
}

if ($state.stage -eq 'FEATURES_CONFIRMED') {
    $dockerScriptPath = Join-Path $PSScriptRoot 'install-docker.ps1'
    $dockerInstallApproved = $InstallDocker -or $state.docker_install_approved
    if ($dockerInstallApproved) {
        $dockerResult = & $dockerScriptPath -Mode Install -InstallApproved -StatePath $StatePath -WhatIf:$WhatIf
    }
    else {
        $dockerResult = & $dockerScriptPath -Mode Detect -StatePath $StatePath -WhatIf:$WhatIf
    }

    return [pscustomobject]@{
        Mode = if ($WhatIf) { 'WhatIf' } else { 'Execute' }
        State = Get-InstallState -Path $StatePath
        Docker = $dockerResult
    }
}

throw "Stage '$($state.stage)' is not implemented yet. No machine changes were made."
