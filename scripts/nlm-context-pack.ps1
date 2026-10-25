# nlm-context-pack.ps1 — build the Master Context pack: the ONE repo-derived source uploaded to EVERY notebook.
#
# WHY THIS EXISTS
#   A domain notebook full of external research knows a lot about its subject and *nothing* about your
#   project. Ask it "how should we model X" and it answers from generic literature — ignoring that you
#   already decided, already built it, and already have a decision record. This pack is the fix: one
#   document, present in every notebook, that grounds every answer in what the system actually is and
#   what is actually built.
#
# WHY ONE FILE AND NOT SEVERAL
#   One source per notebook means: one quota slot (notebooks have a source cap), one thing to replace,
#   and no half-updated state where the module map is fresh but the decision index is three weeks stale.
#   Citation granularity is preserved *inside* the file by the `SOURCE FILE: docs/...` banner in front
#   of every embedded document.
#
# WHAT GOES IN IT
#   Declared in nlm.config.json ("manifest"). Everything else is assembled mechanically, so the pack can
#   never disagree with the files on disk. A missing manifest file is reported loudly, never skipped
#   silently — a vanished section is invisible otherwise.
#
# AUTHORITY
#   The file opens with a header stating the repository is authoritative and this snapshot may lag.
#   Without it, NotebookLM cites a months-old number with total confidence.
#
# Usage:
#   pwsh -File ./scripts/nlm-context-pack.ps1                       # uses ./nlm.config.json
#   pwsh -File ./scripts/nlm-context-pack.ps1 -Config path/to/nlm.config.json -Show
# Upload is NOT done here — that is nlm-notebook-sync.ps1's job. This script only builds, so it is safe
# to run any time.
#
# TWO HASHES, AND THEY ANSWER DIFFERENT QUESTIONS
#   Sha256        = the finished file. It is NOT stable: the pack stamps today's date and the main-branch
#                   HEAD into itself, so this changes daily and on every commit.
#   ContentSha256 = a fingerprint of what the pack *says* — packed documents, decision index, repo facts —
#                   with every timestamp and git pointer excluded.
#   The sync manifest stores ContentSha256. Storing the file hash made "stale" mean "a day passed",
#   which lit the freshness warning permanently and taught everyone to ignore it. Full reasoning in
#   Get-ContentFingerprint below.

param(
    [string]$Config,
    [string]$OutDir = (Join-Path ([System.IO.Path]::GetTempPath()) "nlm-bundles"),
    [switch]$Show
)

$ErrorActionPreference = "Stop"
$env:PYTHONUTF8 = "1"

# PowerShell decodes a native command's stdout using [Console]::OutputEncoding, which is the OEM code
# page unless something set it — and what set it differs between an interactive shell and a freshly
# launched `pwsh -NoProfile` window. Unpinned, `git log` subjects come back as mojibake in the detached
# case (non-ASCII punctuation, and any non-Latin script, destroyed) — in exactly the section the pack
# declares authoritative on current state. Pin it, do not inherit it.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

. (Join-Path $PSScriptRoot "nlm-config.ps1")
$cfg         = Read-NlmConfig -Path $Config
$ProjectRoot = $cfg.ProjectRoot
$Docs        = Join-Path $ProjectRoot $cfg.docsRoot
$DocsRel     = $cfg.docsRoot.TrimEnd('/', '\')
$Project     = $cfg.project
$MainRef     = $cfg.mainRef
$ContextManifest = @($cfg.manifest)
$DecisionCfg = $cfg.decisionIndex
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$today = Get-Date -Format "yyyy-MM-dd"

# ── helpers ────────────────────────────────────────────────────────────

function Add-Line { param([string]$Path, [string]$Text = "") ; Add-Content -Path $Path -Encoding utf8 -Value $Text }

function Add-DocSection {
    # Appends a repo file verbatim behind a provenance banner, so NotebookLM can cite the real path.
    param([string]$Path, $Entry)
    $full = Join-Path $Docs $Entry.doc
    if (-not (Test-Path $full)) {
        Write-Warning "MANIFEST ENTRY MISSING: $DocsRel/$($Entry.doc) — part $($Entry.part) will be absent from the pack."
        $script:MissingDocs += "$DocsRel/$($Entry.doc)"
        return
    }
    Add-Line $Path ""
    Add-Line $Path "================================================================"
    Add-Line $Path "PART $($Entry.part) — $($Entry.title)"
    Add-Line $Path "SOURCE FILE: $DocsRel/$($Entry.doc)"
    Add-Line $Path "WHY IT IS HERE: $($Entry.why)"
    Add-Line $Path "================================================================"
    Add-Line $Path ""
    Add-Line $Path (Get-Content -Path $full -Raw -Encoding utf8)
}

function Get-DecisionRecords {
    # Reads every decision record (ADR) in the configured directories. Returns number/title/status/path.
    #
    # Decision directories are rarely pure: audits, reviews and number ledgers tend to live there too.
    # Those are not decisions and must not appear in a decision index — but silently dropping files is
    # how a real ADR goes missing, so every skip is reported via $script:AdrSkipped.
    $records = @()
    $script:AdrSkipped = @()
    if (-not $DecisionCfg) { return @() }
    foreach ($dir in @($DecisionCfg.dirs)) {
        $d = Join-Path $Docs $dir
        if (-not (Test-Path $d)) { continue }
        foreach ($f in (Get-ChildItem -Path $d -Filter *.md -File | Sort-Object Name)) {
            $lines = @(Get-Content -Path $f.FullName -Encoding utf8 -TotalCount 60)

            $title = ($lines | Where-Object { $_ -match '^\s*#\s+\S' } | Select-Object -First 1)
            if ($title) { $title = ($title -replace '^\s*#\s+', '').Trim() } else { $title = $f.BaseName }

            # A decision record is identified by a numeric filename prefix OR a heading that *opens* with
            # "ADR-NNNN". The heading match is anchored deliberately: an unanchored match also pulls in
            # companion docs that merely *reference* a decision ("# Input to ADR-0107 …"), which are then
            # reported as "unparseable Status" because an input paper has no status. A non-decision in
            # the index is worse than a missing one: NotebookLM cites it with the same confidence.
            $isAdr = ($f.BaseName -match $DecisionCfg.fileNumberPattern) -or ($title -match $DecisionCfg.headingPattern)
            if (-not $isAdr) {
                $script:AdrSkipped += "$DocsRel/$dir/$($f.Name)"
                continue
            }

            # Status is written two structurally different ways in the wild:
            #   inline  — "- **Status:** Accepted · date"  /  "**Status**: Proposed (…)"
            #   heading — "## Status" with the value on the next non-empty line
            # Handling only the inline form silently marks real, accepted ADRs as UNKNOWN, which reads as
            # "never decided" — the opposite of the truth.
            $status = $null
            $inline = ($lines | Where-Object { $_ -match '(?i)\*{0,2}status\*{0,2}\s*[:：]' } | Select-Object -First 1)
            if ($inline) {
                $status = ($inline -replace '(?i)^.*?\*{0,2}status\*{0,2}\s*[:：]\s*', '').Trim()
            } else {
                $idx = 0
                foreach ($l in $lines) {
                    if ($l -match '(?i)^\s*#{1,6}\s*\*{0,2}status\*{0,2}\s*$') {
                        $rest = $lines[($idx + 1)..([Math]::Min($idx + 4, $lines.Count - 1))]
                        $status = ($rest | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1)
                        if ($status) { $status = $status.Trim() }
                        break
                    }
                    $idx++
                }
            }
            if ($status) { $status = ($status -replace '\*', '').Trim() }
            if ([string]::IsNullOrWhiteSpace($status)) { $status = "UNKNOWN (no parseable Status)" }

            $num = if ($f.BaseName -match '^(\d+)') { $Matches[1] } else { "----" }

            $records += [pscustomobject]@{
                Number = $num
                Title  = $title
                Status = $status
                Path   = "$DocsRel/$dir/$($f.Name)"
            }
        }
    }
    return $records | Sort-Object Number, Path
}

function Get-RepoFacts {
    # Tree facts that are *content* rather than timing (which modules exist, how far migrations have
    # run …), declared in config "facts". Derived once, here, because the content fingerprint needs them
    # too — deriving the same fact in two places is how the two answers quietly drift apart.
    $facts = @()
    foreach ($f in @($cfg.facts)) {
        if (-not $f) { continue }
        $p = Join-Path $ProjectRoot $f.path
        $filter = if ($f.filter) { $f.filter } else { "*" }
        $found = if ($f.kind -eq "dirs") { Get-ChildItem $p -Directory -Filter $filter -ErrorAction SilentlyContinue }
                 else                    { Get-ChildItem $p -File      -Filter $filter -ErrorAction SilentlyContinue }
        # Natural sort (V2 before V10), so "last" really is the highest-numbered migration.
        $items = @($found | Select-Object -ExpandProperty Name |
                   Sort-Object { [regex]::Replace($_, '\d+', { $args[0].Value.PadLeft(12, '0') }) })
        $facts += [pscustomobject]@{ Label = $f.label; Path = $f.path; Kind = $f.kind; List = [bool]$f.list; Items = $items }
    }
    return $facts
}

function Get-Sha256Text {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString("X2") }) -join ""
    } finally { $sha.Dispose() }
}

function Get-ContentFingerprint {
    # ══ WHY THIS EXISTS, AND WHY IT IS NOT Get-FileHash ON THE PACK ══
    #
    # Storing the SHA256 of the finished pack looks exact and is useless: the pack embeds `Generated
    # <today>` and the main-branch HEAD plus a commit list in Part I, so the hash changes **every
    # calendar day even with zero edits**, and every commit changes it again. Worse, committing the sync
    # manifest is self-defeating — syncing writes the manifest, committing it moves main, the pack
    # changes, and every notebook is "stale" again. There is no fixpoint: the warning is always on.
    #
    # A signal that is always on is a signal people learn to ignore. So the manifest stores a
    # fingerprint of what actually determines *content*: the packed documents, the decision index and
    # the repo facts. Timestamps, HEADs and commit lists are deliberately excluded — they still go into
    # the uploaded artifact, they just no longer claim the docs changed when they did not.
    #
    # The cost of excluding Part I is that live git state could drift without anything objecting. That
    # is covered on the other side: nlm-notebook-sync.ps1 also re-syncs on age (-MaxAgeDays).
    param([object[]]$Adrs)

    $sb = [System.Text.StringBuilder]::new()

    foreach ($e in $ContextManifest) {
        $full = Join-Path $Docs $e.doc
        $body = if (Test-Path $full) {
            # Normalise line endings before hashing: a fingerprint that flips on `core.autocrlf` is not a
            # fingerprint of the content.
            Get-Sha256Text (((Get-Content -Path $full -Raw -Encoding utf8) -replace "\r\n", "\n"))
        } else { "MISSING" }
        [void]$sb.AppendLine("DOC|$($e.part)|$($e.doc)|$($e.title)|$($e.why)|$body")
    }
    if ($script:IntroText) { [void]$sb.AppendLine("INTRO|$(Get-Sha256Text ($script:IntroText -replace "\r\n", "\n"))") }

    foreach ($a in $Adrs) { [void]$sb.AppendLine("ADR|$($a.Number)|$($a.Title)|$($a.Status)|$($a.Path)") }
    foreach ($f in $script:Facts) { [void]$sb.AppendLine("FACT|$($f.Label)|$($f.Items -join ',')") }

    return Get-Sha256Text $sb.ToString()
}

# ── build ──────────────────────────────────────────────────────────────

$script:MissingDocs = @()
$script:Facts = Get-RepoFacts
$adrs = @(Get-DecisionRecords)
$script:IntroText = $null
if ($cfg.introFile) {
    $ip = Join-Path $ProjectRoot $cfg.introFile
    if (Test-Path $ip) { $script:IntroText = Get-Content -Path $ip -Raw -Encoding utf8 }
    else { Write-Warning "introFile not found: $($cfg.introFile) — the pack will carry no project description."; $script:MissingDocs += $cfg.introFile }
}

$out = Join-Path $OutDir $cfg.packFileName
$hasIndex = [bool]($DecisionCfg -and $DecisionCfg.dirs)

Set-Content -Path $out -Encoding utf8 -Value "# $Project — Master Context Pack"
Add-Line $out ""
Add-Line $out @"
> **This is the $Project grounding document. Read it before answering anything about $Project.**
> Generated $today by ``scripts/nlm-context-pack.ps1``. It is present in **every** $Project notebook, so
> whichever notebook you are in, this is the shared picture of the system.

> **Authority rule — do not skip.** The **git repository is the only source of truth.** This document
> is a derived snapshot and may lag the code by hours or days. When asked whether something exists, is
> built, or is decided: answer from what is written here **and say that this snapshot is dated $today
> and the repository is authoritative**. Never state that something does not exist merely because it is
> absent here — say it is absent *from this snapshot*.

> **If this notebook also holds external research** (industry articles, vendor documentation, standards,
> competitor material): that material describes how *other people* solve these problems. This document
> describes what **we** already decided and already built. When they conflict, **surface the conflict
> explicitly** — never quietly recommend the textbook answer over a decision we already ratified.

> **Two questions that are constantly confused — keep them apart.**
> 1. **Does a decision record exist, and what is its status?** Answer from the decision index. Read the
>    **Status column**, never the directory a file happens to sit in.
> 2. **Is the thing built in code?** Answer from Part I and any code-verified audit — never from a plan
>    document, a roadmap, or a task description. Plans routinely describe things as missing months after
>    they were built, and agents then propose rebuilding them.
"@

if ($script:IntroText) {
    Add-Line $out ""
    Add-Line $out "---"
    Add-Line $out ""
    Add-Line $out $script:IntroText
}

Add-Line $out ""
Add-Line $out "## How this document is assembled"
Add-Line $out ""
Add-Line $out "| Part | Contents |"
Add-Line $out "|---|---|"
Add-Line $out "| **I** | **Project progress — live git state, newer than everything below** |"
foreach ($e in $ContextManifest) {
    if ($hasIndex -and $DecisionCfg.insertBefore -eq $e.part) { Add-Line $out "| **G** | **Decision index — every decision record and its status** (generated) |" }
    Add-Line $out "| $($e.part) | $($e.title) |"
}
if ($hasIndex -and -not ($ContextManifest.part -contains $DecisionCfg.insertBefore)) {
    Add-Line $out "| **G** | **Decision index — every decision record and its status** (generated) |"
}

# ── Part I — project progress (generated from git, inserted first) ─────
# A code-verified audit is a dated document: accurate the day it was written, blind to everything that
# landed after. That blindness is the whole failure this pack exists to stop, so progress is derived
# live from git on every build rather than hand-maintained anywhere.

function Add-ProgressSection {
    param([string]$Path)

    $auditEntry = if ($cfg.auditPart) { $ContextManifest | Where-Object { $_.part -eq $cfg.auditPart } | Select-Object -First 1 }
    $auditDate = $null; $auditNote = ""
    Push-Location $ProjectRoot
    try {
        $head     = (git log -1 --format='%h %ad %s' --date=short 2>$null)
        $mainHead = (git log -1 --format='%h %ad %s' --date=short $MainRef 2>$null)
        $branch   = (git rev-parse --abbrev-ref HEAD 2>$null)
        if ($auditEntry) {
            $auditFile = "$DocsRel/$($auditEntry.doc)"
            $auditDate = (git log -1 --format=%ad --date=short -- $auditFile 2>$null)
            if (-not $auditDate) {
                # Uncommitted audit: fall back to its mtime, and say so rather than implying a commit exists.
                $af = Join-Path $ProjectRoot $auditFile
                $auditDate = if (Test-Path $af) { (Get-Item $af).LastWriteTime.ToString('yyyy-MM-dd') } else { $null }
                $auditNote = " (file not yet committed — date taken from its mtime)"
            }
        }
        $since = if ($auditDate) { @(git log --format='%h %ad %s' --date=short --since="$auditDate" $MainRef 2>$null) }
                 else            { @(git log --format='%h %ad %s' --date=short -n $cfg.recentCommits $MainRef 2>$null) }
    }
    finally { Pop-Location }

    Add-Line $Path ""
    Add-Line $Path "================================================================"
    Add-Line $Path "PART I — Project progress (generated from git on $today)"
    Add-Line $Path "SOURCE: live git state + the directories declared as repo facts"
    Add-Line $Path "WHY IT IS HERE: every hand-written document is dated and cannot see anything that landed after it."
    Add-Line $Path "================================================================"
    Add-Line $Path ""
    Add-Line $Path "**This section outranks every other part of this document on the question ""what is the"
    Add-Line $Path "current state"".** It is regenerated from the repository each time the pack is built."
    Add-Line $Path ""
    Add-Line $Path "| | |"
    Add-Line $Path "|---|---|"
    Add-Line $Path "| Pack generated | $today |"
    Add-Line $Path "| Working branch | ``$branch`` |"
    Add-Line $Path "| Working HEAD | ``$head`` |"
    Add-Line $Path "| ``$MainRef`` HEAD | ``$mainHead`` |"
    foreach ($f in $script:Facts) {
        $last = if ($f.Kind -ne 'dirs' -and $f.Items.Count) { ', last `' + $f.Items[-1] + '`' } else { '' }
        Add-Line $Path "| $($f.Label) | **$($f.Items.Count)** ($($f.Kind) in ``$($f.Path)``$last) |"
    }
    if ($auditEntry) { Add-Line $Path "| Code-verified audit (Part $($auditEntry.part)) dated | $auditDate$auditNote |" }
    Add-Line $Path ""

    foreach ($f in ($script:Facts | Where-Object { $_.List })) {
        Add-Line $Path "### $($f.Label) present on disk — this list overrides any list elsewhere"
        Add-Line $Path ""
        Add-Line $Path (($f.Items | ForEach-Object { "``$_``" }) -join " · ")
        Add-Line $Path ""
    }

    if ($auditEntry) {
        Add-Line $Path "### What landed on ``$MainRef`` since the Part $($auditEntry.part) audit was written"
        Add-Line $Path ""
        if ($since.Count) {
            Add-Line $Path "**$($since.Count) commits.** Anything here is *newer than the audit*, so where they conflict, these win."
        } else {
            Add-Line $Path "No commits on ``$MainRef`` since the audit date. Part $($auditEntry.part) is current with respect to main."
        }
    } else {
        Add-Line $Path "### Most recent commits on ``$MainRef``"
    }
    Add-Line $Path ""
    foreach ($c in $since) { Add-Line $Path "- $c" }
    Add-Line $Path ""
    Add-Line $Path "> Work in flight on feature branches is **not** listed here — only what reached ``$MainRef``."
    Add-Line $Path "> A feature that exists on a branch is not yet part of the system."
    Add-Line $Path ""
}

function Add-DecisionIndex {
    param([string]$Path)
    Add-Line $Path ""
    Add-Line $Path "================================================================"
    Add-Line $Path "PART G — Decision index: every decision record on disk and its status"
    Add-Line $Path "SOURCE: generated from $((@($DecisionCfg.dirs) | ForEach-Object { "$DocsRel/$_/*.md" }) -join ' + ') on $today"
    Add-Line $Path "WHY IT IS HERE: the single answer to 'was this already decided, and does my idea contradict it'."
    Add-Line $Path "================================================================"
    Add-Line $Path ""
    Add-Line $Path "Derived mechanically from the title heading and the ``Status:`` line of every decision file."
    Add-Line $Path "A status of UNKNOWN means the file has no parseable Status line — that is a documentation"
    Add-Line $Path "defect, **not** a decision that was never taken."
    Add-Line $Path ""
    Add-Line $Path "$($adrs.Count) decision documents indexed."
    Add-Line $Path ""
    Add-Line $Path "| # | Title | Status | File |"
    Add-Line $Path "|---|---|---|---|"
    foreach ($a in $adrs) {
        $t = ($a.Title  -replace '\|', '\|')
        $s = ($a.Status -replace '\|', '\|')
        Add-Line $Path "| $($a.Number) | $t | $s | ``$($a.Path)`` |"
    }
}

Add-ProgressSection -Path $out

$indexWritten = $false
foreach ($entry in $ContextManifest) {
    if ($hasIndex -and -not $indexWritten -and $entry.part -eq $DecisionCfg.insertBefore) {
        Add-DecisionIndex -Path $out; $indexWritten = $true
    }
    Add-DocSection -Path $out -Entry $entry
}
if ($hasIndex -and -not $indexWritten) { Add-DecisionIndex -Path $out }

# ── report ─────────────────────────────────────────────────────────────

$item = Get-Item $out
$hash = (Get-FileHash -Path $out -Algorithm SHA256).Hash
$contentHash = Get-ContentFingerprint -Adrs $adrs

Write-Host ""
Write-Host "$Project Master Context Pack built" -ForegroundColor Cyan
Write-Host ("  {0}" -f $out)
Write-Host ("  {0:N0} KB   artifact-sha256:{1}" -f ($item.Length / 1KB), $hash.Substring(0, 16))
Write-Host ("  content-fingerprint:{0}  (docs + decision index + repo facts; no timestamps)" -f $contentHash.Substring(0, 16)) -ForegroundColor DarkGray
Write-Host ("  parts: {0} manifest documents{1}" -f $ContextManifest.Count, $(if ($hasIndex) { " + 1 generated index" } else { "" })) -ForegroundColor DarkGray

$unknown = @($adrs | Where-Object { $_.Status -match 'UNKNOWN' })
if ($hasIndex) {
    Write-Host ("  Decisions indexed: {0}  (accepted: {1}, proposed/draft: {2}, unknown-status: {3})" -f `
        $adrs.Count,
        (@($adrs | Where-Object { $_.Status -match '(?i)accept' }).Count),
        (@($adrs | Where-Object { $_.Status -match '(?i)propos|draft' }).Count),
        $unknown.Count) -ForegroundColor DarkGray
}

# Missing manifest entries, skips and unknown statuses are real defects. Print them — a silent skip is
# how a ratified decision disappears from the corpus and an agent "discovers" it must be decided again.
if ($script:MissingDocs.Count) {
    Write-Host "  MANIFEST FILES NOT FOUND (pack is incomplete):" -ForegroundColor Red
    $script:MissingDocs | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
}
if ($script:AdrSkipped.Count) {
    Write-Host ("  Non-decision companion docs in decision dirs, excluded from the index: {0}" -f $script:AdrSkipped.Count) -ForegroundColor DarkGray
    if ($Show) { $script:AdrSkipped | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkGray } }
}
if ($unknown.Count) {
    Write-Host "  Decision records with an unparseable Status line (fix these in the repo):" -ForegroundColor Yellow
    $unknown | ForEach-Object { Write-Host "    - $($_.Path)" -ForegroundColor Yellow }
}

if ($Show -and $adrs.Count) {
    Write-Host ""
    $adrs | Format-Table Number, Status, Path -AutoSize | Out-Host
}

# Emit the artifact path + both hashes so the sync script can consume them without re-deriving anything.
[pscustomobject]@{ Path = $out; Sha256 = $hash; ContentSha256 = $contentHash; SizeKB = [math]::Round($item.Length / 1KB) }
