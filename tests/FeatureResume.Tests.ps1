$stateModulePath = Join-Path $PSScriptRoot '..\installer\scripts\common\StateManager.psm1'
$featureModulePath = Join-Path $PSScriptRoot '..\installer\scripts\common\FeatureResume.psm1'
Import-Module $stateModulePath -Force
Import-Module $featureModulePath -Force

Describe 'Feature resume workflow' {
    It 'classifies enabled and missing required features' {
        $result = Get-FeatureReadiness -Features @(
            [pscustomobject]@{ FeatureName = 'Microsoft-Windows-Subsystem-Linux'; State = 'Enabled' },
            [pscustomobject]@{ FeatureName = 'VirtualMachinePlatform'; State = 'Disabled' }
        )

        $result.Ready | Should Be $false
        $result.Missing.Count | Should Be 1
        $result.Missing[0] | Should Be 'VirtualMachinePlatform'
    }

    It 'plans missing feature work in WhatIf mode without changing state or enabling features' {
        Mock -CommandName Get-FeatureReadiness -ModuleName FeatureResume -MockWith {
            [pscustomobject]@{ Ready = $false; Missing = @('VirtualMachinePlatform'); Features = @() }
        }
        Mock -CommandName Enable-WindowsOptionalFeature -ModuleName FeatureResume
        $statePath = Join-Path $TestDrive 'state.json'

        $result = Invoke-FeatureEnablement -StatePath $statePath -OrchestratorPath 'C:\installer\orchestrate.ps1' -WhatIf

        $result.Status | Should Be 'Planned'
        (Test-Path -LiteralPath $statePath) | Should Be $false
        Assert-MockCalled -CommandName Enable-WindowsOptionalFeature -ModuleName FeatureResume -Times 0 -Exactly
    }

    It 'uses NoRestart and never restarts for an explicit RestartLater choice' {
        Mock -CommandName Get-FeatureReadiness -ModuleName FeatureResume -MockWith {
            [pscustomobject]@{ Ready = $false; Missing = @('Microsoft-Windows-Subsystem-Linux'); Features = @() }
        }
        Mock -CommandName Test-InstallerAdministrator -ModuleName FeatureResume -MockWith { $true }
        Mock -CommandName Enable-WindowsOptionalFeature -ModuleName FeatureResume
        Mock -CommandName Register-InstallerResumeTask -ModuleName FeatureResume
        Mock -CommandName Restart-Computer -ModuleName FeatureResume
        $statePath = Join-Path $TestDrive 'state.json'

        $result = Invoke-FeatureEnablement -StatePath $statePath -OrchestratorPath 'C:\installer\orchestrate.ps1' -RestartChoice RestartLater
        $state = Get-InstallState -Path $statePath

        $result.Status | Should Be 'RestartRequired'
        $result.RestartChoice | Should Be 'RestartLater'
        $state.stage | Should Be 'FEATURES_ENABLED_PENDING_RESTART'
        $state.resume_token | Should Not BeNullOrEmpty
        Assert-MockCalled -CommandName Enable-WindowsOptionalFeature -ModuleName FeatureResume -Times 1 -Exactly -ParameterFilter { $NoRestart -eq $true }
        Assert-MockCalled -CommandName Restart-Computer -ModuleName FeatureResume -Times 0 -Exactly
    }

    It 'rejects an invalid resume token before advancing state' {
        $statePath = Join-Path $TestDrive 'state.json'
        Set-InstallState -Path $statePath -Stage 'PREFLIGHT_DONE' | Out-Null
        Set-InstallState -Path $statePath -Stage 'FEATURES_ENABLED_PENDING_RESTART' -Values @{ resume_token = 'correct-token'; resume_task_name = 'ERPNextWindowsInstaller-Resume' } | Out-Null

        { Confirm-FeatureResume -StatePath $statePath -ResumeToken 'wrong-token' } | Should Throw
        (Get-InstallState -Path $statePath).stage | Should Be 'FEATURES_ENABLED_PENDING_RESTART'
    }

    It 'keeps the pending restart state if resume task registration fails' {
        Mock -CommandName Get-FeatureReadiness -ModuleName FeatureResume -MockWith {
            [pscustomobject]@{ Ready = $false; Missing = @('VirtualMachinePlatform'); Features = @() }
        }
        Mock -CommandName Test-InstallerAdministrator -ModuleName FeatureResume -MockWith { $true }
        Mock -CommandName Enable-WindowsOptionalFeature -ModuleName FeatureResume
        Mock -CommandName Register-InstallerResumeTask -ModuleName FeatureResume -MockWith { throw 'Access denied' }
        $statePath = Join-Path $TestDrive 'state.json'

        { Invoke-FeatureEnablement -StatePath $statePath -OrchestratorPath 'C:\installer\orchestrate.ps1' -RestartChoice RestartLater } | Should Throw
        $state = Get-InstallState -Path $statePath

        $state.stage | Should Be 'FEATURES_ENABLED_PENDING_RESTART'
        $state.resume_token | Should Not BeNullOrEmpty
    }

    It 'confirms a valid resumed install only after WSL is functional and removes its task' {
        Mock -CommandName Test-WslFunctional -ModuleName FeatureResume -MockWith { $true }
        Mock -CommandName Remove-InstallerResumeTask -ModuleName FeatureResume
        $statePath = Join-Path $TestDrive 'state.json'
        Set-InstallState -Path $statePath -Stage 'PREFLIGHT_DONE' | Out-Null
        Set-InstallState -Path $statePath -Stage 'FEATURES_ENABLED_PENDING_RESTART' -Values @{ resume_token = 'valid-token'; resume_task_name = 'ERPNextWindowsInstaller-Resume' } | Out-Null

        $result = Confirm-FeatureResume -StatePath $statePath -ResumeToken 'valid-token'
        $state = Get-InstallState -Path $statePath

        $result.Status | Should Be 'Confirmed'
        $state.stage | Should Be 'FEATURES_CONFIRMED'
        $state.resume_token | Should Be ''
        $state.resume_task_name | Should Be ''
        Assert-MockCalled -CommandName Remove-InstallerResumeTask -ModuleName FeatureResume -Times 1 -Exactly
    }
}
