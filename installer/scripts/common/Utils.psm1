Set-StrictMode -Version Latest

$script:InstallerStages = @(
    'NOT_STARTED',
    'PREFLIGHT_DONE',
    'FEATURES_ENABLED_PENDING_RESTART',
    'FEATURES_CONFIRMED',
    'DOCKER_READY',
    'USER_INPUT_COLLECTED',
    'EXISTING_INSTALL_RESOLVED',
    'CONTAINERS_PROVISIONED',
    'DB_HEALTHY',
    'SITE_CREATED',
    'BACKUP_CONFIGURED',
    'COMPACTION_SCHEDULED',
    'COMPLETE'
)

function Get-InstallerConstants {
    [CmdletBinding()]
    param()

    $appName = 'ERPNextWindowsInstaller'
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)

    return [pscustomobject][ordered]@{
        AppName = $appName
        StateFilePath = Join-Path (Join-Path $localAppData $appName) 'state.json'
        LogDirectory = Join-Path (Join-Path $localAppData $appName) 'logs'
        LogFilePath = Join-Path (Join-Path (Join-Path $localAppData $appName) 'logs') 'install.log'
        BackupRoot = Join-Path $userProfile 'ERPNext-Backups'
        DockerNetwork = 'erpnext_network'
        DbVolumeName = 'erpnext_db_data'
        SitesVolumeName = 'erpnext_sites'
        DefaultSitePort = 8000
        ResumeTaskName = 'ERPNextWindowsInstaller-Resume'
    }
}

function Get-InstallerStages {
    [CmdletBinding()]
    param()

    return $script:InstallerStages
}

function Test-InstallerStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Stage
    )

    return $script:InstallerStages -contains $Stage
}

function Test-InstallerAdministrator {
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

Export-ModuleMember -Function Get-InstallerConstants, Get-InstallerStages, Test-InstallerStage, Test-InstallerAdministrator
