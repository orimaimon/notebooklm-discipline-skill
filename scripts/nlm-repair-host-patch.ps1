<#
.SYNOPSIS
  Re-applies the "Gemini Notebook" host-detection patch to an OLD notebooklm-mcp-cli install.

.DESCRIPTION
  Background: Google rebranded NotebookLM to "Gemini Notebook" and moved the authenticated app to
  notebook.google.com. Older notebooklm-mcp-cli releases (seen on 0.9.2) recognise only
  notebooklm.google.com / notebooklm.cloud.google.com in `_is_notebooklm_url`, so `nlm login` opens
  Chrome, reaches a signed-in page — and never recognises it:
      "Waiting for sign-in ... Error: Login timeout"
  after which every command fails with "Profile 'default' not found".
  The API itself (batchexecute) still answers on the old host, so fixing host detection is enough.

  CURRENT RELEASES ALREADY CONTAIN THE FIX (verified in 0.15.7). Prefer upgrading:
      uv tool upgrade notebooklm-mcp-cli        # or: pipx upgrade notebooklm-mcp-cli
  This script exists for installs pinned to an old version. It detects a fixed install and does nothing.

  The patch lives in site-packages and is therefore **wiped by every reinstall/upgrade** of an old
  version. Idempotent — safe to run any time. Works on Windows, macOS and Linux (uv or pipx installs).

.EXAMPLE
  pwsh -File ./scripts/nlm-repair-host-patch.ps1
  pwsh -File ./scripts/nlm-repair-host-patch.ps1 -Check        # exit 1 if the patch is needed and missing
  pwsh -File ./scripts/nlm-repair-host-patch.ps1 -Path <...>/notebooklm_tools/utils/cdp.py
#>
[CmdletBinding()]
param(
    # Only report whether the patch is in place; write nothing. Exits 1 if missing.
    [switch]$Check,
    # Explicit path to notebooklm_tools/utils/cdp.py, if auto-discovery fails.
    [string]$Path
)

$ErrorActionPreference = 'Stop'

function Find-CdpPy {
    $rel = Join-Path 'notebooklm_tools' (Join-Path 'utils' 'cdp.py')
    $roots = @()

    # uv knows where its tools live on every OS — ask it rather than guessing.
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        $d = (& uv tool dir 2>$null | Select-Object -First 1)
        if ($d) { $roots += (Join-Path $d 'notebooklm-mcp-cli') }
    }
    # Common fallbacks: uv on Windows / Linux / macOS, then pipx.
    if ($env:APPDATA)      { $roots += (Join-Path $env:APPDATA 'uv/tools/notebooklm-mcp-cli') }
    if ($env:HOME)         { $roots += (Join-Path $env:HOME '.local/share/uv/tools/notebooklm-mcp-cli')
                             $roots += (Join-Path $env:HOME '.local/pipx/venvs/notebooklm-mcp-cli')
                             $roots += (Join-Path $env:HOME '.local/share/pipx/venvs/notebooklm-mcp-cli') }
    if ($env:USERPROFILE)  { $roots += (Join-Path $env:USERPROFILE 'pipx/venvs/notebooklm-mcp-cli') }

    foreach ($r in ($roots | Select-Object -Unique)) {
        if (-not (Test-Path $r)) { continue }
        # Windows venvs use Lib/site-packages; POSIX venvs use lib/pythonX.Y/site-packages.
        $hit = Get-ChildItem -Path $r -Recurse -Filter 'cdp.py' -File -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName.EndsWith($rel) } | Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

$cdp = if ($Path) { $Path } else { Find-CdpPy }
if (-not $cdp -or -not (Test-Path $cdp)) {
    Write-Error "notebooklm_tools/utils/cdp.py not found. Is notebooklm-mcp-cli installed via uv or pipx? (uv tool list / pipx list) — or pass -Path."
}

$content = Get-Content -Raw -Encoding UTF8 $cdp

if ($content -match 'notebook\.google\.com') {
    Write-Host "OK  host detection already knows notebook.google.com (upstream fix or earlier patch): $cdp" -ForegroundColor Green
    exit 0
}

if ($Check) {
    Write-Host "MISSING  this install predates the host fix. Upgrade notebooklm-mcp-cli, or run without -Check to patch." -ForegroundColor Yellow
    exit 1
}

# Match the old set literal regardless of line endings and surrounding whitespace.
$pattern = '(?m)^(?<indent>[ \t]*)return host in \{\s*"notebooklm\.google\.com",\s*"notebooklm\.cloud\.google\.com"\s*,?\s*\}'
$m = [regex]::Match($content, $pattern)
if (-not $m.Success) {
    Write-Error @"
The expected line in _is_notebooklm_url was not found — upstream changed the code.
Inspect by hand: $cdp
If upstream already supports the new host, upgrade instead and stop using this script.
"@
}

$i = $m.Groups['indent'].Value
$nl = if ($content -match "`r`n") { "`r`n" } else { "`n" }
$new = @(
    "$i# LOCAL PATCH: Google rebranded NotebookLM to ""Gemini Notebook"" and moved the"
    "$i# authenticated app to notebook.google.com. Old releases only know the old hosts,"
    "$i# so login detection never fires. Remove by upgrading notebooklm-mcp-cli."
    "${i}return host in {"
    "$i    ""notebooklm.google.com"","
    "$i    ""notebooklm.cloud.google.com"","
    "$i    ""notebook.google.com"","
    "$i}"
) -join $nl

Copy-Item $cdp "$cdp.bak" -Force
$patched = $content.Substring(0, $m.Index) + $new + $content.Substring($m.Index + $m.Length)
[System.IO.File]::WriteAllText($cdp, $patched, [System.Text.UTF8Encoding]::new($false))

Write-Host "PATCHED  $cdp  (backup: $cdp.bak)" -ForegroundColor Green
Write-Host 'Now run:  nlm login     (on Windows first: $env:PYTHONUTF8=1)' -ForegroundColor Cyan
