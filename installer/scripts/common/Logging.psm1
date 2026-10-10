Set-StrictMode -Version Latest

function Protect-InstallLogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [string[]]$Secrets = @()
    )

    $redacted = $Message
    foreach ($secret in $Secrets) {
        if (-not [string]::IsNullOrWhiteSpace($secret)) {
            $redacted = $redacted -replace [regex]::Escape($secret), '********'
        }
    }

    return [regex]::Replace(
        $redacted,
        '(?i)\b(password|secret|token)\s*[:=]\s*[^\s;]+',
        '$1=********')
}

function Write-InstallLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$Stage = 'NOT_STARTED',
        [string[]]$Secrets = @(),
        [string]$LogFilePath
    )

    if ([string]::IsNullOrWhiteSpace($LogFilePath)) {
        $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        $LogFilePath = Join-Path (Join-Path (Join-Path $localAppData 'ERPNextWindowsInstaller') 'logs') 'install.log'
    }

    $directory = Split-Path -Parent $LogFilePath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $safeMessage = Protect-InstallLogMessage -Message $Message -Secrets $Secrets
    $timestamp = [DateTime]::UtcNow.ToString('o')
    $line = '[{0}] [{1}] [{2}] {3}' -f $timestamp, $Level.ToUpperInvariant(), $Stage, $safeMessage
    Add-Content -LiteralPath $LogFilePath -Value $line -Encoding UTF8
    return $line
}

Export-ModuleMember -Function Protect-InstallLogMessage, Write-InstallLog
