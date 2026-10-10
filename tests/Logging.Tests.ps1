$modulePath = Join-Path $PSScriptRoot '..\installer\scripts\common\Logging.psm1'
Import-Module $modulePath -Force

Describe 'Logging' {
    It 'redacts supplied secrets and password assignments' {
        $path = Join-Path $TestDrive 'install.log'
        $secret = 'CorrectHorseBatteryStaple'

        $line = Write-InstallLog -LogFilePath $path -Level Info -Stage 'USER_INPUT_COLLECTED' -Message "admin password=$secret token: abc123" -Secrets @($secret)

        $line | Should Not Match $secret
        $line | Should Match 'password=\*\*\*\*\*\*\*\*'
        $line | Should Match 'token=\*\*\*\*\*\*\*\*'
        (Get-Content -LiteralPath $path -Raw) | Should Not Match $secret
    }
}
