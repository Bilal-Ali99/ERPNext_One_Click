[CmdletBinding()]
param(
    [Parameter()]
    [string]$CatalogPath = (Join-Path $PSScriptRoot '..\..\assets\release-catalog.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Condition {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,
        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$resolvedCatalogPath = (Resolve-Path -LiteralPath $CatalogPath).Path
$catalog = Get-Content -LiteralPath $resolvedCatalogPath -Raw | ConvertFrom-Json

Assert-Condition ($catalog.schemaVersion -eq '1.0.0') 'schemaVersion must be 1.0.0.'
Assert-Condition ($catalog.catalogStatus -in @('candidate', 'approved')) 'catalogStatus must be candidate or approved.'
Assert-Condition ($catalog.entries.Count -gt 0) 'The catalog must contain at least one entry.'

$ids = @{}
foreach ($entry in $catalog.entries) {
    Assert-Condition ($entry.id -match '^erpnext-v(15|16)-[a-z0-9-]+$') "Invalid entry id: $($entry.id)"
    Assert-Condition (-not $ids.ContainsKey($entry.id)) "Duplicate entry id: $($entry.id)"
    $ids[$entry.id] = $true
    Assert-Condition ($entry.status -in @('candidate', 'approved', 'retired')) "Invalid status for $($entry.id)."
    Assert-Condition ($entry.erpnextMajor -in @(15, 16)) "Unsupported ERPNext major for $($entry.id)."
    Assert-Condition ($entry.compose.repository -eq 'frappe/frappe_docker') "Unexpected Compose source for $($entry.id)."
    Assert-Condition ($entry.requirements.architecture -eq 'x64') "Unsupported architecture for $($entry.id)."

    foreach ($imageName in @('erpnext', 'mariadb', 'redis')) {
        $image = $entry.images.$imageName
        Assert-Condition ($null -ne $image) "Missing $imageName image for $($entry.id)."
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($image.repository)) "Missing $imageName repository for $($entry.id)."
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($image.tag)) "Missing $imageName tag for $($entry.id)."
    }

    if ($entry.status -eq 'approved') {
        foreach ($imageName in @('erpnext', 'mariadb', 'redis')) {
            Assert-Condition ($entry.images.$imageName.digest -match '^sha256:[a-f0-9]{64}$') "Approved entry $($entry.id) requires a digest for $imageName."
        }

        Assert-Condition ($entry.compose.sourceCommit -match '^[a-f0-9]{40}$') "Approved entry $($entry.id) requires a pinned Compose commit."
        Assert-Condition ($null -ne $entry.approval) "Approved entry $($entry.id) requires approval evidence."
        Assert-Condition ($entry.approval.testedWindowsBuilds.Count -gt 0) "Approved entry $($entry.id) requires tested Windows builds."
        Assert-Condition (-not [string]::IsNullOrWhiteSpace($entry.approval.testedDockerDesktopVersion)) "Approved entry $($entry.id) requires a tested Docker Desktop version."
    }
    else {
        Assert-Condition ($null -eq $entry.approval) "Non-approved entry $($entry.id) must not claim approval evidence."
    }
}

Write-Output "Release catalog validation passed: $resolvedCatalogPath"
