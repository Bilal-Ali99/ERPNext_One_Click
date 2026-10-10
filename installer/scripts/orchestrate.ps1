[CmdletBinding()]
param(
    [switch]$WhatIf,
    [string]$StatePath
)

Set-StrictMode -Version Latest

$commonDirectory = Join-Path $PSScriptRoot 'common'
Import-Module (Join-Path $commonDirectory 'Utils.psm1') -Force
Import-Module (Join-Path $commonDirectory 'Logging.psm1') -Force
Import-Module (Join-Path $commonDirectory 'StateManager.psm1') -Force

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
        $state = Set-InstallState -Path $StatePath -Stage 'PREFLIGHT_DONE'
        Write-InstallLog -Level Info -Stage $state.stage -Message 'Preflight completed successfully.' | Out-Null
    }

    return [pscustomobject]@{
        Mode = if ($WhatIf) { 'WhatIf' } else { 'Execute' }
        State = if ($WhatIf) { $state } else { (Get-InstallState -Path $StatePath) }
        Preflight = $preflight
    }
}

throw "Stage '$($state.stage)' is not implemented yet. No machine changes were made."
