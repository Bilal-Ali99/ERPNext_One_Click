$modulePath = Join-Path $PSScriptRoot '..\installer\scripts\common\StateManager.psm1'
Import-Module $modulePath -Force

Describe 'StateManager' {
    It 'returns a valid initial state when no state file exists' {
        $path = Join-Path $TestDrive 'missing-state.json'

        $state = Get-InstallState -Path $path

        $state.stage | Should Be 'NOT_STARTED'
        $state.wsl_memory | Should Be '6GB'
        $state.wsl_processors | Should Be 2
    }

    It 'writes a state document and retains a readable backup on update' {
        $path = Join-Path $TestDrive 'state.json'

        Set-InstallState -Path $path -Stage 'PREFLIGHT_DONE' | Out-Null
        $state = Set-InstallState -Path $path -Stage 'USER_INPUT_COLLECTED' -Values @{ erpnext_version = 'v16'; site_name = 'demo.localhost' }

        $state.stage | Should Be 'USER_INPUT_COLLECTED'
        $state.erpnext_version | Should Be 'v16'
        (Test-Path -LiteralPath $path) | Should Be $true
        (Test-Path -LiteralPath "$path.bak") | Should Be $true
    }

    It 'rejects unsupported stages before writing state' {
        $path = Join-Path $TestDrive 'invalid-stage-state.json'

        { Set-InstallState -Path $path -Stage 'NOT_A_STAGE' } | Should Throw
        (Test-Path -LiteralPath $path) | Should Be $false
    }
}
