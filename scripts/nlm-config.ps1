# nlm-config.ps1 — shared loader for nlm.config.json. Dot-sourced by the pack and sync scripts.
#
# One config file holds everything project-specific (what goes into the pack, which notebooks exist),
# so the scripts themselves never carry a project name or a notebook UUID. Defaults are filled in here,
# once, so the two scripts cannot disagree about them.

function Read-NlmConfig {
    param([string]$Path)

    if (-not $Path) {
        # Default: nlm.config.json in the repository root (the parent of scripts/), else the cwd.
        $candidates = @((Join-Path (Split-Path $PSScriptRoot -Parent) "nlm.config.json"), (Join-Path (Get-Location) "nlm.config.json"))
        $Path = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $Path) { throw "nlm.config.json not found (looked in: $($candidates -join ', ')). Copy nlm.config.example.json and fill it in, or pass -Config." }
    }
    if (-not (Test-Path $Path)) { throw "Config not found: $Path" }

    $full = (Resolve-Path $Path).Path
    $cfg  = Get-Content -Path $full -Raw -Encoding utf8 | ConvertFrom-Json

    foreach ($k in @("project", "manifest", "notebooks")) {
        if (-not $cfg.PSObject.Properties[$k]) { throw "nlm.config.json: missing required key '$k'." }
    }

    $defaults = [ordered]@{
        docsRoot      = "docs"
        mainRef       = "origin/main"
        sourceTitle   = "$($cfg.project) Master Context"
        packFileName  = "$(($cfg.project -replace '[^A-Za-z0-9]+', '_').ToUpper())_MASTER_CONTEXT.md"
        manifestFile  = ".nlm-sync-manifest.json"
        recentCommits = 30
        facts         = @()
        auditPart     = $null
        introFile     = $null
        decisionIndex = $null
    }
    foreach ($k in $defaults.Keys) {
        if (-not $cfg.PSObject.Properties[$k] -or $null -eq $cfg.$k) {
            $cfg | Add-Member -NotePropertyName $k -NotePropertyValue $defaults[$k] -Force
        }
    }
    if ($cfg.decisionIndex) {
        $di = $cfg.decisionIndex
        if (-not $di.PSObject.Properties['fileNumberPattern']) { $di | Add-Member fileNumberPattern '^\d{4}' }
        if (-not $di.PSObject.Properties['headingPattern'])    { $di | Add-Member headingPattern '(?i)^\**ADR[-\s]?\d{3,4}\b' }
        if (-not $di.PSObject.Properties['insertBefore'])      { $di | Add-Member insertBefore $null }
    }

    # The project root is where the config lives: relative paths in it resolve from there.
    $cfg | Add-Member -NotePropertyName ProjectRoot -NotePropertyValue (Split-Path $full -Parent) -Force
    return $cfg
}
