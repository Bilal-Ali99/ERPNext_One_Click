[CmdletBinding()]
param(
    [ValidateSet('Detect', 'Enable')][string]$Mode = 'Detect',
    [ValidateSet('RestartNow', 'RestartLater', 'None')][string]$RestartChoice = 'None',
    [string]$StatePath,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$commonDirectory = Join-Path $PSScriptRoot 'common'
Import-Module (Join-Path $commonDirectory 'Utils.psm1') -Force
Import-Module (Join-Path $commonDirectory 'FeatureResume.psm1') -Force
Import-Module (Join-Path $commonDirectory 'Logging.psm1') -Force
if ([string]::IsNullOrWhiteSpace($StatePath)) { $StatePath = (Get-InstallerConstants).StateFilePath }

if ($Mode -eq 'Detect') { return Get-FeatureReadiness }

try {
    $result = Invoke-FeatureEnablement -StatePath $StatePath -OrchestratorPath (Join-Path $PSScriptRoot 'orchestrate.ps1') -RestartChoice $RestartChoice -WhatIf:$WhatIf
}
catch {
    if (-not $WhatIf) {
        Write-InstallLog -Level Error -Stage 'PREFLIGHT_DONE' -Message 'Windows feature enablement could not be completed.' | Out-Null
    }

    throw
}

if (-not $WhatIf) {
    Write-InstallLog -Level Info -Stage 'FEATURES_ENABLED_PENDING_RESTART' -Message ("Feature enablement result: {0}." -f $result.Status) | Out-Null
}

return $result
