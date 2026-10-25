# nlm-notebook-sync.ps1 — push the Master Context pack into every notebook in nlm.config.json.
#
# THE CONTRACT
#   Every notebook holds **exactly one** repo-derived source, titled by config "sourceTitle"
#   (default "<project> Master Context"). This script replaces it. That is the whole job. One slot per
#   notebook, one thing to refresh, and never a half-updated state where the module map is fresh but
#   the decision index is three weeks old.
#
#   Everything else in a notebook — external research, standards, vendor docs, competitor material —
#   is curated by hand and this script never touches it.
#
# WHY REPLACE AND NOT APPEND
#   A sync that is curated but not incremental re-adds every source on every run, producing duplicates
#   and burning the per-notebook source cap. Duplicated sources are worse than stale ones — NotebookLM
#   cites the old copy with the same confidence as the new one. Here the old source is deleted *by
#   title* after the new one is added, and a hash manifest skips notebooks whose content has not
#   changed since the last successful upload.
#
# WHAT "STALE" MEANS — TWO CONDITIONS, AND WHY IT TAKES BOTH
#   1. CONTENT CHANGED — the pack's content fingerprint differs from the one last uploaded.
#   2. AGED OUT       — the last successful sync is older than -MaxAgeDays.
#
#   Condition 1 alone, computed over the *finished file*, is useless: that file stamps today's date and
#   the main-branch HEAD into itself, so it changes every calendar day and on every commit — including
#   the commit that records the sync. The warning is then on permanently, which is how a signal stops
#   being read at all. The fingerprint therefore covers documents, the decision index and repo facts
#   only (see Get-ContentFingerprint in nlm-context-pack.ps1).
#
#   Condition 2 is what pays for that narrowing. Part I of the pack carries live git state and declares
#   itself the authority on "what is the current state" — so it must not drift quietly just because no
#   packed document happened to change. Age catches exactly that.
#
# Usage:
#   pwsh -File ./scripts/nlm-notebook-sync.ps1                 # sync every notebook in the config
#     └─ renews auth by itself: preflight read → on rejection runs 'nlm auth refresh' → re-probes.
#        Use -NoLogin to opt out and fail with instructions.
#   pwsh -File ./scripts/nlm-notebook-sync.ps1 -HttpOnlyRefresh # renew using nlm auth refresh --http-only
#   pwsh -File ./scripts/nlm-notebook-sync.ps1 -DryRun         # show what would change, touch nothing
#   pwsh -File ./scripts/nlm-notebook-sync.ps1 -Target proj-core,proj-ops
#   pwsh -File ./scripts/nlm-notebook-sync.ps1 -Force          # re-upload even if nothing is stale
#   pwsh -File ./scripts/nlm-notebook-sync.ps1 -Check          # exit 1 if any notebook is stale (CI/doc gate; no auth needed)
#   pwsh -File ./scripts/nlm-notebook-sync.ps1 -MaxAgeDays 3   # tighten the age condition

param(
    [string]$Config,                         # path to nlm.config.json; default = repo root, then cwd
    [string[]]$Target,                       # alias names; default = every notebook in the config
    [switch]$DryRun,
    [switch]$Force,                          # ignore the hash manifest
    [switch]$Check,                          # exit 1 if any notebook is stale; change nothing
    [switch]$NoLogin,                        # never renew auth automatically (no 'nlm auth refresh', no 'nlm login'); fail with instructions
    [switch]$HttpOnlyRefresh,                # pass --http-only to 'nlm auth refresh'
    [int]$WaitTimeout = 600,
    [int]$MaxAgeDays = 7                     # re-sync this often even if no packed document changed
)

$ErrorActionPreference = "Stop"
$env:PYTHONUTF8      = "1"
$env:PYTHONIOENCODING = "utf-8"

. (Join-Path $PSScriptRoot "nlm-config.ps1")
$cfg          = Read-NlmConfig -Path $Config
$ProjectRoot  = $cfg.ProjectRoot
$ManifestPath = Join-Path $ProjectRoot $cfg.manifestFile
$SourceTitle  = $cfg.sourceTitle             # the title this script owns. Never reuse it for anything else.

# ══ THE NOTEBOOK MAP ══ lives in nlm.config.json ("notebooks"). Keep it in step with your human-readable
# notebook map; if they disagree, one of them is the bug.
$NotebookMap = @($cfg.notebooks | ForEach-Object {
    if (-not $_.alias -or -not $_.id) { throw "nlm.config.json: every notebook needs 'alias' and 'id'." }
    @{ Alias = $_.alias; Id = $_.id; Tier = $_.tier; Desc = $_.desc }
})
if (-not $NotebookMap.Count) { throw "nlm.config.json: 'notebooks' is empty." }

# ── select targets ─────────────────────────────────────────────────────

# [array] is load-bearing: PowerShell unwraps a one-element array on assignment, so a single -Target
# left $selected holding the hashtable itself — and $selected.Count then reported its *key* count (4).
[array]$selected = if ($Target) {
    [array]$miss = $Target | Where-Object { $_ -notin $NotebookMap.Alias }
    if ($miss.Count) { throw "Unknown notebook alias(es): $($miss -join ', '). Known: $($NotebookMap.Alias -join ', ')" }
    $NotebookMap | Where-Object { $Target -contains $_.Alias }
} else {
    $NotebookMap
}

# ── build the pack ─────────────────────────────────────────────────────

Write-Host "Building master context pack..." -ForegroundColor Cyan
$packArgs = @{}; if ($Config) { $packArgs.Config = $Config }
$pack = & (Join-Path $PSScriptRoot "nlm-context-pack.ps1") @packArgs | Select-Object -Last 1
if (-not $pack -or -not (Test-Path $pack.Path)) { throw "Context pack build produced no artifact." }
$packPath = $pack.Path
$packHash = $pack.ContentSha256
if (-not $packHash) { throw "Context pack did not report a ContentSha256 — scripts are out of step; update nlm-context-pack.ps1." }

# ── manifest: notebook id -> what was last successfully uploaded ────────
#
# Schema: { "<notebook-id>": { "contentHash": "<hex>", "syncedAt": "<ISO-8601 UTC>", "packSha256": "<hex>" } }
# An entry in any other shape (e.g. a bare artifact hash from an older scheme) is read as "never synced
# under the current scheme" rather than silently trusted: it was computed over a different input.

$manifest = if (Test-Path $ManifestPath) {
    Get-Content $ManifestPath -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
} else { @{} }

function Get-StaleReason {
    # Returns $null when the notebook is up to date, otherwise a human sentence saying which of the two
    # conditions fired. Returning the *reason* rather than a boolean is deliberate: "stale" with no
    # cause is what made the old warning unactionable.
    param($Id)

    $e = $manifest[$Id]
    if (-not $e)          { return "never synced" }
    if ($e -isnot [System.Collections.IDictionary]) { return "manifest predates the content-fingerprint scheme" }
    if ($e['contentHash'] -ne $packHash)            { return "packed documentation changed" }

    # [ref] binds by the variable's *declared* type, so seeding with $null gives TryParse a ref-to-object
    # and PowerShell reports "no overload for 2 arguments" at runtime.
    [datetime]$at = [datetime]::MinValue

    # ConvertFrom-Json -AsHashtable hands back an ISO-8601 field as a *[datetime]*, not a string.
    # Round-tripping it through [string] is a culture trap that fails two different ways on any box with
    # a dd/MM short-date culture: PowerShell's [string] cast renders a DateTime with the INVARIANT
    # culture ("08/13/2026"), while TryParse without an explicit culture reads the CURRENT one. Days
    # 13-31 -> month 13 -> parse fails -> permanent "no usable syncedAt", a full sync reported stale
    # seconds after it succeeded. Days 1-12 are worse: they parse *silently swapped* (Aug 12 -> 12 Dec),
    # so the age check runs against a fabricated date. Never render a DateTime to text to read it back.
    $rawSyncedAt = $e['syncedAt']
    if ($rawSyncedAt -is [datetime]) {
        $at = $rawSyncedAt
    } elseif (-not [datetime]::TryParse([string]$rawSyncedAt, [cultureinfo]::InvariantCulture,
                                        [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$at)) {
        return "no usable syncedAt timestamp"
    }

    $age = [int]((Get-Date).ToUniversalTime() - $at.ToUniversalTime()).TotalDays
    if ($age -gt $MaxAgeDays) { return "last synced $age days ago (cap: $MaxAgeDays) — Part I git state has drifted" }

    return $null
}

# ── -Check: is any notebook serving an out-of-date pack? ───────────────
# Exact, not heuristic. The pack is deterministic, so "the hash I would upload differs from the hash I
# last uploaded" *is* staleness — no git-timestamp guessing, and it works on uncommitted edits too.
# Wire this into a docs gate / CI; it never contacts NotebookLM, so it needs no auth and is instant.

if ($Check) {
    [array]$stale = $selected | ForEach-Object {
        $why = Get-StaleReason -Id $_.Id
        if ($why) { [pscustomobject]@{ Alias = $_.Alias; Why = $why } }
    }
    if (-not $stale.Count) {
        Write-Host "NLM FRESH — all $($selected.Count) notebooks serve the current content (fingerprint:$($packHash.Substring(0,16)), max age ${MaxAgeDays}d)." -ForegroundColor Green
        exit 0
    }
    Write-Host "NLM STALE — $($stale.Count) of $($selected.Count) notebook(s) serve an out-of-date pack:" -ForegroundColor Yellow
    foreach ($s in $stale) {
        Write-Host ("  {0,-20} {1}" -f $s.Alias, $s.Why) -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "An un-synced pack makes NotebookLM cite stale facts *authoritatively* — worse than no answer," -ForegroundColor Yellow
    Write-Host "because it arrives with a citation. Fix:  pwsh -File ./scripts/nlm-notebook-sync.ps1" -ForegroundColor Yellow
    exit 1
}

# ── sync ───────────────────────────────────────────────────────────────

Write-Host ""
Write-Host ("Syncing {0} notebook(s){1}" -f $selected.Count, $(if ($DryRun) { "  [DRY RUN — nothing will change]" } else { "" })) -ForegroundColor Cyan
Write-Host ("Pack: {0} KB  fingerprint:{1}  artifact:{2}  max-age:{3}d" -f `
    $pack.SizeKB, $packHash.Substring(0, 16), $pack.Sha256.Substring(0, 16), $MaxAgeDays) -ForegroundColor DarkGray
Write-Host ""

$stats = @{ Skipped = 0; Updated = 0; Failed = 0 }
$failures = @()

# Preflight: one cheap read before touching anything. Auth expires mid-day and *writes* need fresher
# credentials than reads, so a run can start fine and die halfway — burning one identical failure per
# notebook before anyone sees the first one.
function Test-NlmAuth {
    # One cheap read. Returns the raw output; caller decides. Never throws — `nlm` writes errors to
    # stderr with a zero exit as often as not, so BOTH signals are checked by the caller.
    param($Id)
    $out = nlm notebook get $Id --json 2>&1 | Out-String
    [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0 -and $out -notmatch 'Authentication|Profile .* not found'); Out = $out }
}

if (-not $DryRun) {
    $probe = Test-NlmAuth -Id $selected[0].Id

    # Expired auth is the single most common failure here, it happens mid-day on a schedule nobody
    # controls, and the fix is one command. Making the operator run it by hand buys nothing except a
    # dead run — so renewal is part of THIS script's job, not a note in its output. `nlm auth refresh` is
    # the CLI's unattended command (headless, never prompts); current `nlm login` opens a browser for an
    # interactive sign-in, so it is only the fallback for old CLIs that have no `auth refresh`.
    if (-not $probe.Ok -and -not $NoLogin) {
        Write-Host "Auth rejected — renewing (nlm auth refresh)..." -ForegroundColor Yellow
        $refreshArgs = @("auth", "refresh")
        if ($HttpOnlyRefresh) { $refreshArgs += "--http-only" }
        $refreshOut = nlm @refreshArgs 2>&1 | Out-String
        if ($refreshOut) {
            $refreshOut.TrimEnd().Split("`n") | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        }

        if ($refreshOut -match "No such command") {
            Write-Host "CLI is old and should be upgraded. Falling back to nlm login..." -ForegroundColor Yellow
            nlm login 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        }

        # Re-probe rather than trusting renewal's exit code: the CLI reports success on failures often
        # enough that only a completed read proves the credentials are actually usable.
        $probe = Test-NlmAuth -Id $selected[0].Id
        if ($probe.Ok) { Write-Host "Auth renewed." -ForegroundColor Green }
    }

    if (-not $probe.Ok) {
        Write-Host "PREFLIGHT FAILED — NotebookLM rejected a basic read. Nothing was changed." -ForegroundColor Red
        Write-Host $probe.Out.Trim() -ForegroundColor DarkGray
        Write-Host ""
        if ($NoLogin) {
            Write-Host "Renew auth and re-run:  nlm login" -ForegroundColor Yellow
        } else {
            Write-Host "Automatic nlm auth refresh failed. A human must run nlm login interactively." -ForegroundColor Yellow
        }
        Write-Host "Running from an agent on someone else's machine? Ask them to run it:  nlm login" -ForegroundColor Yellow
        Write-Host "If 'nlm login' itself times out, your CLI predates the notebook.google.com host move:" -ForegroundColor Yellow
        Write-Host "  upgrade notebooklm-mcp-cli, or run: pwsh -File ./scripts/nlm-repair-host-patch.ps1" -ForegroundColor Yellow
        exit 1
    }
}

foreach ($nb in $selected) {
    $label = "{0,-20}" -f $nb.Alias

    $why = Get-StaleReason -Id $nb.Id
    if (-not $Force -and -not $why) {
        Write-Host "$label  unchanged — skip" -ForegroundColor DarkGray
        $stats.Skipped++
        continue
    }

    if ($DryRun) {
        Write-Host "$label  WOULD replace '$SourceTitle'  ($(if ($why) { $why } else { 'forced' }))" -ForegroundColor Yellow
        $stats.Updated++
        continue
    }

    try {
        # 1. Upload the new copy FIRST, then delete the old ones. Delete-then-add would leave the
        #    notebook with no context at all if the upload fails — worse than a stale copy.
        $addRaw = nlm source add $nb.Id --file $packPath --title $SourceTitle --wait --wait-timeout $WaitTimeout --json 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "source add failed: $($addRaw.Trim())" }

        # The add response names the source we just created. Identifying the keeper by ID — rather than
        # by listing before the add — is what makes the cleanup safe: every other source carrying our
        # title is by definition an older copy, no matter how many failed runs left them behind.
        $newId = $null
        try {
            $addJson = $addRaw | ConvertFrom-Json
            $newId = @($addJson.source_id, $addJson.id, $addJson.source.id | Where-Object { $_ })[0]
        } catch { }

        # 2. Delete every other copy, with a retry. NotebookLM rejects a delete issued immediately after
        #    an add on the same notebook ("Failed to delete sources") — and it reports that failure in
        #    the JSON body while still exiting 0, so the exit code alone silently produced duplicates.
        #    A duplicated context source is worse than a stale one: NLM cites the old copy just as
        #    confidently. Hence: parse the body, retry once, then verify by re-listing.
        # $deleted counts what was actually removed; $leftovers is what survived the retries. Keeping
        # them separate matters: the verification pass zeroes the leftover count on success, so reusing
        # one variable reported "no prior copy" on a notebook that had just had a duplicate cleaned out.
        # Count unique IDs: a retry re-issues the same delete, and summing per attempt over-reports.
        $deletedIds = @()
        $leftovers  = 0
        foreach ($attempt in 1..2) {
            if ($attempt -gt 1) { Start-Sleep -Seconds 5 }

            $listRaw = nlm source list $nb.Id --json 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { throw "source list failed: $($listRaw.Trim())" }
            [array]$stale = ($listRaw | ConvertFrom-Json) |
                Where-Object { $_.title -eq $SourceTitle -and $_.id -ne $newId }

            if (-not $stale.Count) { $leftovers = 0; break }

            [array]$ids = $stale | ForEach-Object { $_.id }
            nlm source delete @ids --confirm --json 2>&1 | Out-Null
            $deletedIds = @($deletedIds + $ids | Select-Object -Unique)
            $leftovers  = $ids.Count
        }

        if ($leftovers -ne 0) {
            # Verify rather than trust: re-list one final time before reporting a duplicate.
            $finalRaw = nlm source list $nb.Id --json 2>&1 | Out-String
            [array]$still = ($finalRaw | ConvertFrom-Json) | Where-Object { $_.title -eq $SourceTitle }
            if ($still.Count -gt 1) {
                throw "uploaded, but $($still.Count) copies of '$SourceTitle' remain — NLM will cite the stale one. Delete by hand: nlm source delete $($still.id -join ' ') --confirm"
            }
        }

        # packSha256 is recorded for forensics only — never compared. It answers "which exact file is
        # this notebook holding" when a citation looks wrong, without being allowed to drive staleness.
        $manifest[$nb.Id] = [ordered]@{
            contentHash = $packHash
            syncedAt    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            packSha256  = $pack.Sha256
        }
        $manifest | ConvertTo-Json -Depth 4 | Set-Content -Path $ManifestPath -Encoding utf8

        $verb = if ($deletedIds.Count) { "replaced — $($deletedIds.Count) old copy/copies removed" } else { "added (no prior copy)" }
        Write-Host "$label  OK — $verb" -ForegroundColor Green
        $stats.Updated++
    }
    catch {
        Write-Host "$label  FAILED — $_" -ForegroundColor Red
        $stats.Failed++
        $failures += "$($nb.Alias): $_"
    }
}

# ── report ─────────────────────────────────────────────────────────────

Write-Host ""
Write-Host ("Done. updated={0}  skipped={1}  failed={2}" -f $stats.Updated, $stats.Skipped, $stats.Failed) `
    -ForegroundColor $(if ($stats.Failed) { "Red" } else { "Cyan" })

if ($stats.Failed) {
    Write-Host ""
    Write-Host "Failures:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host ""

    # Two failure modes look identical in the summary line but need OPPOSITE responses, and blaming
    # auth for both sends you to re-login when the credentials were never the problem. Observed: a
    # 4-notebook batch failed 3-of-4 on HTTP 400 at the upload endpoint; retried one alias at a time,
    # on the SAME credentials, all three succeeded. Auth was valid the whole time.
    if ($failures -match '400 Bad Request|upload') {
        Write-Host "Upload rejected (HTTP 400) — this is NOT auth. Auth failures say 'Authentication'." -ForegroundColor Yellow
        Write-Host "It shows up when several notebooks are pushed back-to-back. Retry ONE alias at a time:" -ForegroundColor Yellow
        ($failures -replace ':.*$', '') | Select-Object -Unique | ForEach-Object {
            Write-Host "  pwsh -File ./scripts/nlm-notebook-sync.ps1 -Target $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Most common cause is expired auth — writes need fresh credentials even when reads still work." -ForegroundColor Yellow
        Write-Host "Re-run; this script renews auth itself (see preflight). If 'nlm login' times out, upgrade" -ForegroundColor Yellow
        Write-Host "notebooklm-mcp-cli or run: pwsh -File ./scripts/nlm-repair-host-patch.ps1" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "A failed notebook is STALE, never empty or duplicated (add-then-remove). Prove state with -Check." -ForegroundColor DarkGray
    exit 1
}
