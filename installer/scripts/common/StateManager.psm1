Set-StrictMode -Version Latest

$utilsPath = Join-Path $PSScriptRoot 'Utils.psm1'
Import-Module $utilsPath

function New-InstallState {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        stage = 'NOT_STARTED'
        erpnext_version = ''
        site_name = ''
        wsl_memory = '6GB'
        wsl_processors = 2
        resume_token = ''
        resume_task_name = ''
        last_updated = [DateTime]::UtcNow.ToString('o')
    }
}

function Assert-InstallState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$State
    )

    foreach ($property in @('stage', 'erpnext_version', 'site_name', 'wsl_memory', 'wsl_processors', 'resume_token', 'resume_task_name', 'last_updated')) {
        if ($null -eq $State.PSObject.Properties[$property]) {
            throw "Install state is missing the required '$property' property."
        }
    }

    if (-not (Test-InstallerStage -Stage $State.stage)) {
        throw "Install state contains unsupported stage '$($State.stage)'."
    }

    if ($State.erpnext_version -notin @('', 'v15', 'v16')) {
        throw "Install state contains unsupported ERPNext version '$($State.erpnext_version)'."
    }

    if ([string]::IsNullOrWhiteSpace([string]$State.wsl_memory)) {
        throw 'Install state must contain a WSL memory setting.'
    }

    if ([int]$State.wsl_processors -lt 1) {
        throw 'Install state must contain at least one WSL processor.'
    }

    if ($State.stage -eq 'FEATURES_ENABLED_PENDING_RESTART' -and ([string]::IsNullOrWhiteSpace($State.resume_token) -or [string]::IsNullOrWhiteSpace($State.resume_task_name))) {
        throw 'Pending feature restart state requires resume metadata.'
    }

    $parsedTimestamp = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$State.last_updated, [ref]$parsedTimestamp)) {
        throw 'Install state must contain an ISO-8601 last_updated timestamp.'
    }

    return $State
}

function ConvertFrom-InstallStateFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    $state = $content | ConvertFrom-Json -ErrorAction Stop
    return Assert-InstallState -State $state
}

function Get-InstallState {
    [CmdletBinding()]
    param(
        [string]$Path = (Get-InstallerConstants).StateFilePath
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return New-InstallState
    }

    try {
        return ConvertFrom-InstallStateFile -Path $Path
    }
    catch {
        $backupPath = "$Path.bak"
        if (Test-Path -LiteralPath $backupPath) {
            return ConvertFrom-InstallStateFile -Path $backupPath
        }

        throw
    }
}

function Set-InstallState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('NOT_STARTED', 'PREFLIGHT_DONE', 'FEATURES_ENABLED_PENDING_RESTART', 'FEATURES_CONFIRMED', 'DOCKER_READY', 'USER_INPUT_COLLECTED', 'EXISTING_INSTALL_RESOLVED', 'CONTAINERS_PROVISIONED', 'DB_HEALTHY', 'SITE_CREATED', 'BACKUP_CONFIGURED', 'COMPACTION_SCHEDULED', 'COMPLETE')]
        [string]$Stage,

        [hashtable]$Values = @{},
        [string]$Path = (Get-InstallerConstants).StateFilePath
    )

    $state = Get-InstallState -Path $Path
    $state.stage = $Stage
    foreach ($key in $Values.Keys) {
        if ($null -eq $state.PSObject.Properties[$key]) {
            throw "Install state does not support the '$key' property."
        }

        $state.$key = $Values[$key]
    }

    $state.last_updated = [DateTime]::UtcNow.ToString('o')
    $null = Assert-InstallState -State $state

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $temporaryPath = Join-Path $directory ('.state-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    $backupPath = "$Path.bak"
    $encoding = New-Object System.Text.UTF8Encoding($false)

    try {
        $json = $state | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText($temporaryPath, $json, $encoding)

        if (Test-Path -LiteralPath $Path) {
            [System.IO.File]::Replace($temporaryPath, $Path, $backupPath, $true)
        }
        else {
            [System.IO.File]::Move($temporaryPath, $Path)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }

    return Get-InstallState -Path $Path
}

Export-ModuleMember -Function New-InstallState, Get-InstallState, Set-InstallState, Assert-InstallState
