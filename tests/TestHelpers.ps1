# TestHelpers.ps1 — test setup helpers for Pester tests

function New-TestRepo {
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("test-repo-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

    # Create directories
    $docsDir = Join-Path $tempDir "docs"
    $adrDir = Join-Path $docsDir "adr"
    $migDir = Join-Path $tempDir "db/migration"
    $modsDir = Join-Path $tempDir "src/mods"

    New-Item -ItemType Directory -Force -Path $adrDir | Out-Null
    New-Item -ItemType Directory -Force -Path $migDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $modsDir "mod-a") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $modsDir "mod-b") | Out-Null

    # Create doc files
    Set-Content -Path (Join-Path $docsDir "IRON_RULES.md") -Value "# Iron Rules`nRule 1: Always test." -Encoding utf8
    Set-Content -Path (Join-Path $docsDir "system_overview.md") -Value "# System Overview`nOverview of the system." -Encoding utf8

    # Create ADRs
    $adr1 = @"
# ADR-0001: A

## Status

Accepted
"@
    Set-Content -Path (Join-Path $adrDir "0001-a.md") -Value $adr1 -Encoding utf8

    $adr2 = @"
# ADR-0002: B

- **Status:** Proposed
"@
    Set-Content -Path (Join-Path $adrDir "0002-b.md") -Value $adr2 -Encoding utf8

    $adrReview = @"
# Review of ADR-0001

Some review notes here.
"@
    Set-Content -Path (Join-Path $adrDir "review-notes.md") -Value $adrReview -Encoding utf8

    # Create migrations
    Set-Content -Path (Join-Path $migDir "V1__a.sql") -Value "-- migration 1" -Encoding utf8
    Set-Content -Path (Join-Path $migDir "V2__b.sql") -Value "-- migration 2" -Encoding utf8
    Set-Content -Path (Join-Path $migDir "V10__c.sql") -Value "-- migration 10" -Encoding utf8

    # Create nlm.config.json
    $cfg = @{
        project = "TestProj"
        docsRoot = "docs"
        mainRef = "origin/main"
        manifest = @(
            @{ part = "A"; doc = "IRON_RULES.md"; title = "Iron Rules"; why = "Core rules" },
            @{ part = "B"; doc = "system_overview.md"; title = "System Overview"; why = "Overview" },
            @{ part = "C"; doc = "missing.md"; title = "Missing Doc"; why = "Test missing handling" }
        )
        decisionIndex = @{
            dirs = @("adr")
        }
        facts = @(
            @{ label = "Modules"; path = "src/mods"; kind = "dirs"; list = $true },
            @{ label = "Migrations"; path = "db/migration"; kind = "files"; filter = "V*.sql" }
        )
        notebooks = @(
            @{ alias = "t1"; id = "id-1"; tier = 0; desc = "Notebook 1" },
            @{ alias = "t2"; id = "id-2"; tier = 1; desc = "Notebook 2" }
        )
    }

    $cfgJson = ConvertTo-Json -InputObject $cfg -Depth 10
    Set-Content -Path (Join-Path $tempDir "nlm.config.json") -Value $cfgJson -Encoding utf8

    # Initialize git repo and make initial commit + origin/main ref
    Push-Location $tempDir
    try {
        git init -q
        git config user.name "Test"
        git config user.email "test@example.com"
        git add .
        git commit -q -m "initial commit"
        git update-ref refs/remotes/origin/main HEAD
    } finally {
        Pop-Location
    }

    return $tempDir
}

function Add-FakeNlmToPath {
    $fakeNlmDir = Resolve-Path (Join-Path $PSScriptRoot "fake-nlm")
    $sep = [System.IO.Path]::PathSeparator
    $env:PATH = "$fakeNlmDir$sep$env:PATH"
}

function Get-PythonCmd {
    if ($IsWindows) { return "python" } else { return "python3" }
}
