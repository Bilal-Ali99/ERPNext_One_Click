[CmdletBinding()]
param(
    [switch]$WhatIf
)

Set-StrictMode -Version Latest

$commonDirectory = Join-Path $PSScriptRoot 'common'
Import-Module (Join-Path $commonDirectory 'Utils.psm1') -Force
Import-Module (Join-Path $commonDirectory 'Logging.psm1') -Force

function New-PreflightResult {
    param(
        [string]$Name,
        [ValidateSet('Pass', 'Warning', 'Block')]
        [string]$Status,
        [string]$Message,
        [string]$Remediation
    )

    return [pscustomobject][ordered]@{
        Name = $Name
        Status = $Status
        Message = $Message
        Remediation = $Remediation
    }
}

$results = @()
$osVersion = [Environment]::OSVersion.Version
if ($osVersion -ge [Version]'10.0.19041') {
    $results += New-PreflightResult -Name 'Windows version' -Status Pass -Message "Windows version $osVersion is supported." -Remediation ''
}
else {
    $results += New-PreflightResult -Name 'Windows version' -Status Block -Message "Windows version $osVersion is unsupported." -Remediation 'Use Windows 10 build 19041 or later, or Windows 11.'
}

if (Test-InstallerAdministrator) {
    $results += New-PreflightResult -Name 'Administrator privileges' -Status Pass -Message 'The installer is running elevated.' -Remediation ''
}
else {
    $results += New-PreflightResult -Name 'Administrator privileges' -Status Block -Message 'Administrator privileges are required.' -Remediation 'Restart the installer and approve the Windows UAC prompt.'
}

try {
    $computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if ($computerSystem.HypervisorPresent) {
        $results += New-PreflightResult -Name 'Virtualization' -Status Pass -Message 'A Windows hypervisor is available.' -Remediation ''
    }
    else {
        $results += New-PreflightResult -Name 'Virtualization' -Status Block -Message 'Hardware virtualization is not available to Windows.' -Remediation 'Enable VT-x or AMD-V in firmware, then restart Windows.'
    }

    $freeBytes = (Get-PSDrive -Name C -ErrorAction Stop).Free
    if ($freeBytes -lt 20GB) {
        $results += New-PreflightResult -Name 'Free disk space' -Status Block -Message 'Drive C has less than 20 GB free.' -Remediation 'Free disk space before continuing.'
    }
    elseif ($freeBytes -lt 45GB) {
        $results += New-PreflightResult -Name 'Free disk space' -Status Warning -Message 'Drive C has less than the recommended 45 GB free.' -Remediation 'Free additional disk space before installing ERPNext.'
    }
    else {
        $results += New-PreflightResult -Name 'Free disk space' -Status Pass -Message 'Drive C meets the 45 GB recommended free-space baseline.' -Remediation ''
    }

    $ramBytes = [int64]$computerSystem.TotalPhysicalMemory
    if ($ramBytes -lt 8GB) {
        $results += New-PreflightResult -Name 'Memory' -Status Warning -Message 'This computer has less than the recommended 8 GB of RAM.' -Remediation 'Close other applications or use a computer with at least 8 GB of RAM.'
    }
    else {
        $results += New-PreflightResult -Name 'Memory' -Status Pass -Message 'This computer meets the 8 GB memory recommendation.' -Remediation ''
    }
}
catch {
    $results += New-PreflightResult -Name 'Hardware information' -Status Block -Message 'The installer could not read required hardware information.' -Remediation 'Run the installer as an administrator and contact support if the problem continues.'
}

if (Test-Connection -ComputerName '8.8.8.8' -Count 1 -Quiet -ErrorAction SilentlyContinue) {
    $results += New-PreflightResult -Name 'Internet connectivity' -Status Pass -Message 'A network connectivity probe succeeded.' -Remediation ''
}
else {
    $results += New-PreflightResult -Name 'Internet connectivity' -Status Block -Message 'The installer could not reach the Internet.' -Remediation 'Connect to the Internet and try again. Corporate proxy support is not available in v1.'
}

try {
    $firewallProfiles = @(Get-NetFirewallProfile -ErrorAction Stop)
    if ($firewallProfiles.Count -gt 0) {
        $results += New-PreflightResult -Name 'Windows Firewall' -Status Pass -Message 'Windows Firewall profiles were detected.' -Remediation ''
    }
    else {
        $results += New-PreflightResult -Name 'Windows Firewall' -Status Warning -Message 'Windows Firewall status could not be confirmed.' -Remediation 'Check Windows Firewall settings before installation.'
    }
}
catch {
    $results += New-PreflightResult -Name 'Windows Firewall' -Status Warning -Message 'Windows Firewall status could not be read.' -Remediation 'Check Windows Firewall settings before installation.'
}

$dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
if ($null -eq $dockerCommand) {
    $results += New-PreflightResult -Name 'Docker Desktop' -Status Warning -Message 'Docker Desktop was not found.' -Remediation 'The installer will offer Docker Desktop setup in a later stage.'
}
else {
    $dockerVersion = & $dockerCommand.Source version --format '{{.Server.Version}}' 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($dockerVersion)) {
        $results += New-PreflightResult -Name 'Docker Desktop' -Status Pass -Message "Docker Engine $dockerVersion is available." -Remediation ''
    }
    else {
        $results += New-PreflightResult -Name 'Docker Desktop' -Status Warning -Message 'Docker was found but its engine is not ready.' -Remediation 'Start Docker Desktop before continuing.'
    }
}

$summary = [pscustomobject][ordered]@{
    Mode = if ($WhatIf) { 'WhatIf' } else { 'CheckOnly' }
    HasBlockers = @($results | Where-Object { $_.Status -eq 'Block' }).Count -gt 0
    Checks = $results
}

if (-not $WhatIf) {
    foreach ($check in $results) {
        $level = if ($check.Status -eq 'Pass') { 'Info' } elseif ($check.Status -eq 'Warning') { 'Warning' } else { 'Error' }
        Write-InstallLog -Level $level -Stage 'NOT_STARTED' -Message ('Preflight {0}: {1}' -f $check.Name, $check.Message) | Out-Null
    }
}

return $summary
