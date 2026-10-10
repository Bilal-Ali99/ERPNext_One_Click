Describe 'Preflight WhatIf mode' {
    It 'returns structured non-mutating results' {
        $scriptPath = Join-Path $PSScriptRoot '..\installer\scripts\preflight.ps1'

        $result = & $scriptPath -WhatIf

        $result.Mode | Should Be 'WhatIf'
        $result.Checks.Count | Should BeGreaterThan 0
        @($result.Checks | Where-Object { $_.Code -eq 'PF-OS-VERSION' }).Count | Should Be 1
        @($result.Checks | Where-Object { $_.Code -eq 'PF-PORT-8000' }).Count | Should Be 1
    }
}
