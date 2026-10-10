Describe 'Preflight WhatIf mode' {
    It 'returns structured non-mutating results' {
        $scriptPath = Join-Path $PSScriptRoot '..\installer\scripts\preflight.ps1'

        $result = & $scriptPath -WhatIf

        $result.Mode | Should Be 'WhatIf'
        $result.Checks.Count | Should BeGreaterThan 0
        @($result.Checks | Where-Object { $_.Name -eq 'Windows version' }).Count | Should Be 1
    }
}
