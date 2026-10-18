$modulePath = Join-Path $PSScriptRoot '..\installer\scripts\common\DockerReadiness.psm1'
Import-Module $modulePath -Force

Describe 'Docker readiness engine' {
    It 'loads the approved all-user Docker Desktop release configuration' {
        $configPath = Join-Path $PSScriptRoot '..\installer\config\docker-desktop-release.json'

        $release = Get-DockerDesktopRelease -Path $configPath

        $release.version | Should Be '4.95.0'
        $release.installScope | Should Be 'allUsers'
        $release.architecture | Should Be 'amd64'
        $release.sha256 | Should Match '^[A-Fa-f0-9]{64}$'
    }

    It 'reports Docker Desktop as missing when the docker command is absent' {
        Mock -CommandName Get-Command -ModuleName DockerReadiness -MockWith { $null }

        $result = Get-DockerReadiness

        $result.Status | Should Be 'Missing'
        $result.IsReady | Should Be $false
    }

    It 'reports an installed but stopped Docker engine' {
        Mock -CommandName Get-Command -ModuleName DockerReadiness -MockWith { [pscustomobject]@{ Source = 'docker.exe' } }
        Mock -CommandName Invoke-DockerCli -ModuleName DockerReadiness -MockWith { [pscustomobject]@{ ExitCode = 1; Output = '' } }

        $result = Get-DockerReadiness

        $result.Status | Should Be 'EngineNotReady'
    }

    It 'requires Docker Compose before reporting readiness' {
        Mock -CommandName Get-Command -ModuleName DockerReadiness -MockWith { [pscustomobject]@{ Source = 'docker.exe' } }
        Mock -CommandName Invoke-DockerCli -ModuleName DockerReadiness -MockWith {
            if ($Arguments[0] -eq 'version') { return [pscustomobject]@{ ExitCode = 0; Output = '29.0.0' } }
            return [pscustomobject]@{ ExitCode = 1; Output = '' }
        }

        $result = Get-DockerReadiness

        $result.Status | Should Be 'ComposeUnavailable'
        $result.Version | Should Be '29.0.0'
    }

    It 'blocks Windows container mode without switching it automatically' {
        Mock -CommandName Get-Command -ModuleName DockerReadiness -MockWith { [pscustomobject]@{ Source = 'docker.exe' } }
        Mock -CommandName Invoke-DockerCli -ModuleName DockerReadiness -MockWith {
            if ($Arguments[0] -eq 'version') { return [pscustomobject]@{ ExitCode = 0; Output = '29.0.0' } }
            if ($Arguments[0] -eq 'compose') { return [pscustomobject]@{ ExitCode = 0; Output = '2.40.0' } }
            return [pscustomobject]@{ ExitCode = 0; Output = 'windows' }
        }

        $result = Get-DockerReadiness

        $result.Status | Should Be 'WindowsContainers'
        $result.IsReady | Should Be $false
    }

    It 'reports a Linux Docker Engine and Compose as ready' {
        Mock -CommandName Get-Command -ModuleName DockerReadiness -MockWith { [pscustomobject]@{ Source = 'docker.exe' } }
        Mock -CommandName Invoke-DockerCli -ModuleName DockerReadiness -MockWith {
            if ($Arguments[0] -eq 'version') { return [pscustomobject]@{ ExitCode = 0; Output = '29.0.0' } }
            if ($Arguments[0] -eq 'compose') { return [pscustomobject]@{ ExitCode = 0; Output = '2.40.0' } }
            return [pscustomobject]@{ ExitCode = 0; Output = 'linux' }
        }

        $result = Get-DockerReadiness

        $result.Status | Should Be 'Ready'
        $result.IsReady | Should Be $true
        $result.Version | Should Be '29.0.0'
        $result.ComposeVersion | Should Be '2.40.0'
    }

    It 'rejects an installer whose checksum does not match the approved release' {
        $installerPath = Join-Path $TestDrive 'Docker Desktop Installer.exe'
        New-Item -ItemType File -Path $installerPath -Force | Out-Null
        $release = [pscustomobject]@{ sha256 = ('a' * 64) }
        Mock -CommandName Get-FileHash -ModuleName DockerReadiness -MockWith { [pscustomobject]@{ Hash = ('b' * 64) } }

        $result = Test-DockerDesktopInstaller -Path $installerPath -Release $release

        $result.IsValid | Should Be $false
        $result.Reason | Should Match 'checksum'
    }

    It 'requires a valid Authenticode signature after checksum verification' {
        $installerPath = Join-Path $TestDrive 'Docker Desktop Installer.exe'
        New-Item -ItemType File -Path $installerPath -Force | Out-Null
        $release = [pscustomobject]@{ sha256 = ('a' * 64) }
        Mock -CommandName Get-FileHash -ModuleName DockerReadiness -MockWith { [pscustomobject]@{ Hash = ('a' * 64) } }
        Mock -CommandName Get-AuthenticodeSignature -ModuleName DockerReadiness -MockWith { [pscustomobject]@{ Status = 'NotSigned' } }

        $result = Test-DockerDesktopInstaller -Path $installerPath -Release $release

        $result.IsValid | Should Be $false
        $result.Reason | Should Match 'signature'
    }

    It 'does not launch a verified installer in WhatIf mode' {
        $release = [pscustomobject]@{ version = '4.95.0'; installerArguments = @('install') }
        Mock -CommandName Test-DockerDesktopInstaller -ModuleName DockerReadiness -MockWith { [pscustomobject]@{ IsValid = $true; Reason = '' } }
        Mock -CommandName Start-Process -ModuleName DockerReadiness

        $result = Invoke-DockerDesktopInstall -InstallerPath 'C:\test\Docker Desktop Installer.exe' -Release $release -WhatIf

        $result.Status | Should Be 'Planned'
        Assert-MockCalled -CommandName Start-Process -ModuleName DockerReadiness -Times 0 -Exactly
    }
}
