Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Utils.psm1') -Force

function New-PreflightResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('Pass', 'Warning', 'Block')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Remediation,
        [hashtable]$Evidence = @{}
    )

    return [pscustomobject][ordered]@{
        Code = $Code
        Name = $Name
        Status = $Status
        Message = $Message
        Remediation = $Remediation
        Evidence = [pscustomobject]$Evidence
    }
}

function Get-PreflightWindowsResult {
    param([Version]$Version = [Environment]::OSVersion.Version, [bool]$Is64Bit = [Environment]::Is64BitOperatingSystem)

    if (-not $Is64Bit) {
        return New-PreflightResult 'PF-OS-ARCH' 'Windows architecture' 'Block' 'A 64-bit Windows installation is required.' 'Use a supported x64 Windows 10 or Windows 11 computer.' @{ Is64Bit = $false }
    }
    if ($Version -lt [Version]'10.0.19041') {
        return New-PreflightResult 'PF-OS-VERSION' 'Windows version' 'Block' "Windows version $Version is unsupported." 'Update to Windows 10 build 19041 or later, or use Windows 11.' @{ Version = $Version.ToString() }
    }
    return New-PreflightResult 'PF-OS-VERSION' 'Windows version' 'Pass' "Windows version $Version on x64 is supported." '' @{ Version = $Version.ToString(); Is64Bit = $true }
}

function Get-PreflightDiskResult {
    param([Int64]$FreeBytes)

    if ($FreeBytes -lt 20GB) {
        return New-PreflightResult 'PF-DISK-LOW' 'Free disk space' 'Block' 'Drive C has less than 20 GB free.' 'Free disk space before continuing.' @{ FreeBytes = $FreeBytes }
    }
    if ($FreeBytes -lt 45GB) {
        return New-PreflightResult 'PF-DISK-RECOMMENDED' 'Free disk space' 'Warning' 'Drive C has less than the recommended 45 GB free.' 'Free additional disk space before installing ERPNext.' @{ FreeBytes = $FreeBytes }
    }
    return New-PreflightResult 'PF-DISK-RECOMMENDED' 'Free disk space' 'Pass' 'Drive C meets the 45 GB free-space recommendation.' '' @{ FreeBytes = $FreeBytes }
}

function Get-PreflightMemoryResult {
    param([Int64]$TotalBytes)

    if ($TotalBytes -lt 8GB) {
        return New-PreflightResult 'PF-MEMORY-RECOMMENDED' 'Memory' 'Warning' 'This computer has less than the recommended 8 GB of RAM.' 'Close other applications or use a computer with at least 8 GB of RAM.' @{ TotalBytes = $TotalBytes }
    }
    return New-PreflightResult 'PF-MEMORY-RECOMMENDED' 'Memory' 'Pass' 'This computer meets the 8 GB memory recommendation.' '' @{ TotalBytes = $TotalBytes }
}

function Get-PreflightPortResult {
    param([object[]]$Listeners = @(), [int]$Port = (Get-InstallerConstants).DefaultSitePort)

    if (@($Listeners).Count -gt 0) {
        $processIds = @($Listeners | ForEach-Object { $_.OwningProcess } | Where-Object { $_ } | Select-Object -Unique)
        return New-PreflightResult 'PF-PORT-8000' "Port $Port" 'Warning' "Port $Port is already in use." "Stop or reconfigure the application using port $Port before installing ERPNext." @{ Port = $Port; OwningProcessIds = $processIds }
    }
    return New-PreflightResult 'PF-PORT-8000' "Port $Port" 'Pass' "Port $Port is available for the ERPNext web interface." '' @{ Port = $Port }
}

function Get-PreflightReport {
    [CmdletBinding()]
    param()

    $results = @()
    $results += Get-PreflightWindowsResult

    if (Test-InstallerAdministrator) {
        $results += New-PreflightResult 'PF-ADMIN' 'Administrator privileges' 'Pass' 'The installer is running elevated.' '' @{}
    }
    else {
        $results += New-PreflightResult 'PF-ADMIN' 'Administrator privileges' 'Block' 'Administrator privileges are required.' 'Restart the installer and approve the Windows UAC prompt.' @{}
    }

    try {
        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($computer.HypervisorPresent) {
            $results += New-PreflightResult 'PF-VIRTUALIZATION' 'Virtualization' 'Pass' 'A Windows hypervisor is available.' '' @{}
        }
        else {
            $results += New-PreflightResult 'PF-VIRTUALIZATION' 'Virtualization' 'Block' 'Hardware virtualization is not available to Windows.' 'Enable VT-x or AMD-V in firmware, then restart Windows.' @{}
        }
        $results += Get-PreflightDiskResult -FreeBytes (Get-PSDrive -Name C -ErrorAction Stop).Free
        $results += Get-PreflightMemoryResult -TotalBytes ([Int64]$computer.TotalPhysicalMemory)
    }
    catch {
        $results += New-PreflightResult 'PF-HARDWARE-READ' 'Hardware information' 'Block' 'The installer could not read required hardware information.' 'Run as an administrator and contact support if the problem continues.' @{}
    }

    try {
        $wsl = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction Stop
        $vmp = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction Stop
        if ($wsl.State -eq 'Enabled' -and $vmp.State -eq 'Enabled') {
            $wslStatus = & wsl.exe --status 2>$null
            if ($LASTEXITCODE -eq 0) {
                $results += New-PreflightResult 'PF-WSL' 'WSL2 readiness' 'Pass' 'WSL and Virtual Machine Platform are enabled.' '' @{ WslState = $wsl.State; VmpState = $vmp.State }
            }
            else {
                $results += New-PreflightResult 'PF-WSL' 'WSL2 readiness' 'Warning' 'WSL features are enabled but WSL status could not be confirmed.' 'Restart Windows if features were recently enabled, then try again.' @{ WslState = $wsl.State; VmpState = $vmp.State }
            }
        }
        else {
            $results += New-PreflightResult 'PF-WSL' 'WSL2 readiness' 'Warning' 'WSL or Virtual Machine Platform is not enabled yet.' 'The installer will offer feature enablement and a user-approved restart.' @{ WslState = $wsl.State; VmpState = $vmp.State }
        }
    }
    catch {
        $results += New-PreflightResult 'PF-WSL-READ' 'WSL feature state' 'Warning' 'WSL feature state could not be read.' 'Run as an administrator; policy restrictions will be reported during feature enablement.' @{}
    }

    if (Test-Connection -ComputerName '8.8.8.8' -Count 1 -Quiet -ErrorAction SilentlyContinue) {
        $results += New-PreflightResult 'PF-INTERNET' 'Internet connectivity' 'Pass' 'A network connectivity probe succeeded.' '' @{}
    }
    else {
        $results += New-PreflightResult 'PF-INTERNET' 'Internet connectivity' 'Block' 'The installer could not reach the Internet.' 'Connect to the Internet and try again. Corporate proxy support is not available in v1.' @{}
    }

    try {
        $listeners = @(Get-NetTCPConnection -State Listen -LocalPort (Get-InstallerConstants).DefaultSitePort -ErrorAction SilentlyContinue)
        $results += Get-PreflightPortResult -Listeners $listeners
    }
    catch {
        $results += New-PreflightResult 'PF-PORT-8000' 'Port 8000' 'Warning' 'Port 8000 availability could not be determined.' 'Confirm port 8000 is free before installing ERPNext.' @{}
    }

    try {
        $profiles = @(Get-NetFirewallProfile -ErrorAction Stop)
        $results += New-PreflightResult 'PF-FIREWALL' 'Windows Firewall' 'Pass' 'Windows Firewall profiles were detected.' '' @{ ProfileCount = $profiles.Count }
    }
    catch {
        $results += New-PreflightResult 'PF-FIREWALL' 'Windows Firewall' 'Warning' 'Windows Firewall status could not be read.' 'Check Windows Firewall settings before installation.' @{}
    }

    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if ($null -eq $docker) {
        $results += New-PreflightResult 'PF-DOCKER' 'Docker Desktop' 'Warning' 'Docker Desktop was not found.' 'The installer will offer Docker Desktop setup in a later stage.' @{}
    }
    else {
        $version = & $docker.Source version --format '{{.Server.Version}}' 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($version)) {
            $results += New-PreflightResult 'PF-DOCKER' 'Docker Desktop' 'Pass' "Docker Engine $version is available." '' @{ Version = $version.Trim() }
        }
        else {
            $results += New-PreflightResult 'PF-DOCKER' 'Docker Desktop' 'Warning' 'Docker was found but its engine is not ready.' 'Start Docker Desktop before continuing.' @{}
        }
    }

    return [pscustomobject][ordered]@{
        Mode = 'CheckOnly'
        HasBlockers = @($results | Where-Object { $_.Status -eq 'Block' }).Count -gt 0
        Checks = $results
    }
}

Export-ModuleMember -Function New-PreflightResult, Get-PreflightWindowsResult, Get-PreflightDiskResult, Get-PreflightMemoryResult, Get-PreflightPortResult, Get-PreflightReport
