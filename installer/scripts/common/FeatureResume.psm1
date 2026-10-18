Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Utils.psm1')
Import-Module (Join-Path $PSScriptRoot 'StateManager.psm1')

$script:RequiredFeatureNames = @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')

function Get-RequiredWindowsFeatures {
    return $script:RequiredFeatureNames
}

function Get-FeatureReadiness {
    [CmdletBinding()]
    param([object[]]$Features)

    if ($null -eq $Features) {
        $ErrorActionPreference = 'Stop'
        $Features = foreach ($name in Get-RequiredWindowsFeatures) {
            try {
                $feature = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop
            }
            catch {
                throw "Could not inspect the Windows feature '$name'. Run the installer as Administrator and try again."
            }

            if ($null -eq $feature -or $null -eq $feature.PSObject.Properties['State']) {
                throw "Could not inspect the Windows feature '$name'. Run the installer as Administrator and try again."
            }

            $feature
        }
    }

    $missing = @($Features | Where-Object { $_.State -ne 'Enabled' } | ForEach-Object { $_.FeatureName })
    return [pscustomobject]@{ Ready = ($missing.Count -eq 0); Missing = $missing; Features = $Features }
}

function New-ResumeMetadata {
    $constants = Get-InstallerConstants
    return [pscustomobject]@{ Token = [Guid]::NewGuid().ToString('N'); TaskName = $constants.ResumeTaskName }
}

function Test-WslFunctional {
    [CmdletBinding()]
    param()

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($null -eq $wsl) {
        return $false
    }

    try {
        & $wsl.Source --status 2>$null | Out-Null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Register-InstallerResumeTask {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$TaskName, [Parameter(Mandatory = $true)][string]$ScriptPath, [Parameter(Mandatory = $true)][string]$ResumeToken)

    $powerShellPath = Join-Path $PSHOME 'powershell.exe'
    $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -ResumeToken {1}' -f $ScriptPath, $ResumeToken
    $action = New-ScheduledTaskAction -Execute $powerShellPath -Argument $arguments
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -RunLevel Highest
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
}

function Remove-InstallerResumeTask {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$TaskName)

    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Invoke-FeatureEnablement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)][string]$OrchestratorPath,
        [ValidateSet('RestartNow', 'RestartLater', 'None')][string]$RestartChoice = 'None',
        [switch]$WhatIf
    )

    $readiness = Get-FeatureReadiness
    $existingState = Get-InstallState -Path $StatePath
    if ($readiness.Ready) {
        if ($existingState.stage -eq 'FEATURES_ENABLED_PENDING_RESTART') {
            if ($WhatIf) {
                return [pscustomobject]@{ Status = 'RestartPending'; RestartRequired = $true; Missing = @() }
            }

            if ($RestartChoice -eq 'None') {
                throw 'Choose Restart Now or Restart Later before resuming the pending Windows feature restart.'
            }

            try {
                Register-InstallerResumeTask -TaskName $existingState.resume_task_name -ScriptPath $OrchestratorPath -ResumeToken $existingState.resume_token
            }
            catch {
                throw 'Could not register the installer resume task. Reopen the installer as Administrator and try again before restarting Windows.'
            }

            if ($RestartChoice -eq 'RestartNow') {
                Restart-Computer -Force
            }

            return [pscustomobject]@{ Status = 'RestartRequired'; RestartRequired = $true; Missing = @(); RestartChoice = $RestartChoice }
        }

        if (-not $WhatIf) { Set-InstallState -Path $StatePath -Stage 'FEATURES_CONFIRMED' | Out-Null }
        return [pscustomobject]@{ Status = 'AlreadyReady'; RestartRequired = $false; Missing = @() }
    }

    if ($WhatIf) {
        return [pscustomobject]@{ Status = 'Planned'; RestartRequired = $true; Missing = $readiness.Missing }
    }

    if ($RestartChoice -eq 'None') {
        throw 'Choose Restart Now or Restart Later before enabling Windows features.'
    }

    if (-not (Test-InstallerAdministrator)) {
        throw 'Administrator privileges are required to enable Windows features.'
    }

    foreach ($featureName in $readiness.Missing) {
        Enable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart -ErrorAction Stop | Out-Null
    }

    $metadata = New-ResumeMetadata
    Set-InstallState -Path $StatePath -Stage 'FEATURES_ENABLED_PENDING_RESTART' -Values @{ resume_token = $metadata.Token; resume_task_name = $metadata.TaskName } | Out-Null
    try {
        Register-InstallerResumeTask -TaskName $metadata.TaskName -ScriptPath $OrchestratorPath -ResumeToken $metadata.Token
    }
    catch {
        throw 'Could not register the installer resume task. Windows features may have changed; reopen the installer as Administrator and try again before restarting Windows.'
    }

    if ($RestartChoice -eq 'RestartNow') {
        Restart-Computer -Force
    }

    return [pscustomobject]@{ Status = 'RestartRequired'; RestartRequired = $true; Missing = $readiness.Missing; RestartChoice = $RestartChoice }
}

function Confirm-FeatureResume {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$StatePath, [Parameter(Mandatory = $true)][string]$ResumeToken, [switch]$WhatIf)

    $state = Get-InstallState -Path $StatePath
    if ($state.stage -ne 'FEATURES_ENABLED_PENDING_RESTART') { throw "State '$($state.stage)' is not awaiting a feature restart." }
    if ($ResumeToken -ne $state.resume_token) { throw 'The resume token is invalid.' }
    if (-not (Test-WslFunctional)) { return [pscustomobject]@{ Status = 'WaitingForWsl'; State = $state } }

    if (-not $WhatIf) {
        $taskName = $state.resume_task_name
        $state = Set-InstallState -Path $StatePath -Stage 'FEATURES_CONFIRMED' -Values @{ resume_token = ''; resume_task_name = '' }
        Remove-InstallerResumeTask -TaskName $taskName
    }

    return [pscustomobject]@{ Status = 'Confirmed'; State = $state }
}

Export-ModuleMember -Function Get-RequiredWindowsFeatures, Get-FeatureReadiness, New-ResumeMetadata, Test-WslFunctional, Register-InstallerResumeTask, Remove-InstallerResumeTask, Invoke-FeatureEnablement, Confirm-FeatureResume
