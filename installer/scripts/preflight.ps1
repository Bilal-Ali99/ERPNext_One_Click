[CmdletBinding()]
param([switch]$WhatIf)

Set-StrictMode -Version Latest

$commonDirectory = Join-Path $PSScriptRoot 'common'
Import-Module (Join-Path $commonDirectory 'Preflight.psm1') -Force
Import-Module (Join-Path $commonDirectory 'Logging.psm1') -Force

$report = Get-PreflightReport
$report.Mode = if ($WhatIf) { 'WhatIf' } else { 'CheckOnly' }

if (-not $WhatIf) {
    foreach ($check in $report.Checks) {
        $level = if ($check.Status -eq 'Pass') { 'Info' } elseif ($check.Status -eq 'Warning') { 'Warning' } else { 'Error' }
        Write-InstallLog -Level $level -Stage 'NOT_STARTED' -Message ('{0} ({1}): {2}' -f $check.Name, $check.Code, $check.Message) | Out-Null
    }
}

return $report
