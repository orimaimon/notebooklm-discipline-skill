BeforeAll {
    . (Join-Path $PSScriptRoot "TestHelpers.ps1")
    $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) "scripts/nlm-notebook-sync.ps1"
}

Describe "nlm-notebook-sync" {
    It "exits 1 on -Check for a never-synced repo" {
        $repo = New-TestRepo
        $stateFile = Join-Path $repo "nlm-state.json"
        $configPath = Join-Path $repo "nlm.config.json"

        try {
            $p = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-File", "`"$scriptPath`"", "-Config", "`"$configPath`"", "-Check" -Environment @{ NLM_STATE = $stateFile; NLM_AUTH = "" } -NoNewWindow -Wait -PassThru
            $p.ExitCode | Should -Be 1
        } finally {
            Remove-Item -Path $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "replaces pre-seeded source title and leaves unrelated source untouched" {
        $repo = New-TestRepo
        $stateFile = Join-Path $repo "nlm-state.json"
        $configPath = Join-Path $repo "nlm.config.json"

        $initialState = @{
            notebooks = @{
                "id-1" = @{
                    sources = @(
                        @{ id = "src-old1"; title = "TestProj Master Context" },
                        @{ id = "src-other"; title = "Some research" }
                    )
                    delete_fails_once = $false
                }
            }
        }
        $initialState | ConvertTo-Json -Depth 5 | Set-Content -Path $stateFile -Encoding utf8

        try {
            Add-FakeNlmToPath
            $p = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-File", "`"$scriptPath`"", "-Config", "`"$configPath`"" -Environment @{ NLM_STATE = $stateFile; NLM_AUTH = ""; PATH = $env:PATH } -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $repo "sync1.log")
            $p.ExitCode | Should -Be 0

            $output = Get-Content -Path (Join-Path $repo "sync1.log") -Raw -Encoding utf8
            $output | Should -Match "replaced — 1 old copy/copies removed"
            $output | Should -Not -Match "2 old copy"

            $state = Get-Content -Path $stateFile -Raw -Encoding utf8 | ConvertFrom-Json
            $sources1 = $state.notebooks.'id-1'.sources
            $sources1.Count | Should -Be 2
            ($sources1 | Where-Object { $_.title -eq "TestProj Master Context" }).Count | Should -Be 1
            ($sources1 | Where-Object { $_.title -eq "Some research" }).Count | Should -Be 1
        } finally {
            Remove-Item -Path $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "retries delete and reports 1 old copy removed when initial delete fails" {
        $repo = New-TestRepo
        $stateFile = Join-Path $repo "nlm-state.json"
        $configPath = Join-Path $repo "nlm.config.json"

        $initialState = @{
            notebooks = @{
                "id-1" = @{
                    sources = @(
                        @{ id = "src-old1"; title = "TestProj Master Context" }
                    )
                    delete_fails_once = $true
                }
            }
        }
        $initialState | ConvertTo-Json -Depth 5 | Set-Content -Path $stateFile -Encoding utf8

        try {
            Add-FakeNlmToPath
            $p = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-File", "`"$scriptPath`"", "-Config", "`"$configPath`"" -Environment @{ NLM_STATE = $stateFile; NLM_AUTH = ""; PATH = $env:PATH } -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $repo "sync1.log")
            $p.ExitCode | Should -Be 0

            $output = Get-Content -Path (Join-Path $repo "sync1.log") -Raw -Encoding utf8
            $output | Should -Match "replaced — 1 old copy/copies removed"
        } finally {
            Remove-Item -Path $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "skips notebooks on a second sync and passes -Check with exit 0" {
        $repo = New-TestRepo
        $stateFile = Join-Path $repo "nlm-state.json"
        $configPath = Join-Path $repo "nlm.config.json"

        try {
            Add-FakeNlmToPath
            # Sync 1
            $p1 = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-File", "`"$scriptPath`"", "-Config", "`"$configPath`"" -Environment @{ NLM_STATE = $stateFile; NLM_AUTH = ""; PATH = $env:PATH } -NoNewWindow -Wait -PassThru
            $p1.ExitCode | Should -Be 0

            # Sync 2
            $p2 = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-File", "`"$scriptPath`"", "-Config", "`"$configPath`"" -Environment @{ NLM_STATE = $stateFile; NLM_AUTH = ""; PATH = $env:PATH } -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $repo "sync2.log")
            $p2.ExitCode | Should -Be 0

            $output2 = Get-Content -Path (Join-Path $repo "sync2.log") -Raw -Encoding utf8
            $output2 | Should -Match "t1\s+unchanged — skip"
            $output2 | Should -Match "t2\s+unchanged — skip"

            # -Check
            $p3 = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-File", "`"$scriptPath`"", "-Config", "`"$configPath`"", "-Check" -Environment @{ NLM_STATE = $stateFile; NLM_AUTH = ""; PATH = $env:PATH } -NoNewWindow -Wait -PassThru
            $p3.ExitCode | Should -Be 0
        } finally {
            Remove-Item -Path $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "exits 1 and changes nothing in state file when NLM_AUTH=bad with -NoLogin" {
        $repo = New-TestRepo
        $stateFile = Join-Path $repo "nlm-state.json"
        $configPath = Join-Path $repo "nlm.config.json"

        Set-Content -Path $stateFile -Value "{`"notebooks`":{}}" -Encoding utf8

        try {
            Add-FakeNlmToPath
            $p = Start-Process -FilePath "pwsh" -ArgumentList "-NoProfile", "-File", "`"$scriptPath`"", "-Config", "`"$configPath`"", "-NoLogin" -Environment @{ NLM_STATE = $stateFile; NLM_AUTH = "bad"; PATH = $env:PATH } -NoNewWindow -Wait -PassThru
            $p.ExitCode | Should -Be 1

            $content = Get-Content -Path $stateFile -Raw -Encoding utf8
            $content.Trim() | Should -Be "{`"notebooks`":{}}"
        } finally {
            Remove-Item -Path $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "throws Unknown notebook alias for invalid target" {
        $repo = New-TestRepo
        $configPath = Join-Path $repo "nlm.config.json"

        try {
            { & $scriptPath -Config $configPath -Target "nope" } | Should -Throw "*Unknown notebook alias*"
        } finally {
            Remove-Item -Path $repo -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
