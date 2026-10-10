$modulePath = Join-Path $PSScriptRoot '..\installer\scripts\common\Preflight.psm1'
Import-Module $modulePath -Force

Describe 'Preflight engine boundaries' {
    It 'blocks when free disk capacity is below 20 GB' {
        $result = Get-PreflightDiskResult -FreeBytes 19GB

        $result.Status | Should Be 'Block'
        $result.Code | Should Be 'PF-DISK-LOW'
    }

    It 'warns when free disk capacity is between 20 and 45 GB' {
        $result = Get-PreflightDiskResult -FreeBytes 30GB

        $result.Status | Should Be 'Warning'
        $result.Code | Should Be 'PF-DISK-RECOMMENDED'
    }

    It 'blocks unsupported Windows versions' {
        $result = Get-PreflightWindowsResult -Version ([Version]'10.0.19040') -Is64Bit $true

        $result.Status | Should Be 'Block'
        $result.Code | Should Be 'PF-OS-VERSION'
    }

    It 'warns only for an occupied port 8000 and does not select another port' {
        $listener = [pscustomobject]@{ OwningProcess = 1234 }
        $result = Get-PreflightPortResult -Listeners @($listener) -Port 8000

        $result.Status | Should Be 'Warning'
        $result.Code | Should Be 'PF-PORT-8000'
        $result.Evidence.Port | Should Be 8000
        $result.Message | Should Match '8000'
    }
}
