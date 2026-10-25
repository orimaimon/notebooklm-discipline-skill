[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Target = ".",

    [switch]$DryRun,

    [switch]$Force,

    [switch]$GitignoreManifest
)

$ErrorActionPreference = "Stop"

# Find repository root relative to script location
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

if (-not (Test-Path -Path $Target -PathType Container)) {
    [Console]::Error.WriteLine("Error: Target directory '$Target' does not exist or is not a directory.")
    exit 2
}

# Prerequisite checks (warn, never fail)
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    if ($IsMacOS) {
        [Console]::Error.WriteLine("Warning: pwsh not found. Install via: brew install --cask powershell")
    } elseif ($IsLinux) {
        [Console]::Error.WriteLine("Warning: pwsh not found. Install via: https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux")
    } elseif ($IsWindows) {
        [Console]::Error.WriteLine("Warning: pwsh not found. Install via: winget install --id Microsoft.PowerShell")
    } else {
        [Console]::Error.WriteLine("Warning: pwsh not found. Install via: brew install --cask powershell (macOS) / https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux (Linux) / winget install --id Microsoft.PowerShell (Windows)")
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine("Warning: git not found. Install git using your package manager.")
}

if (-not (Get-Command nlm -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine("Warning: nlm not found. Install via: uv tool install notebooklm-mcp-cli or pipx install notebooklm-mcp-cli")
}

$script:SkippedAny = $false

function Copy-InstallerFile {
    param(
        [string]$SrcRel,
        [string]$DstRel,
        [string]$Mode # 'normal' or 'never-overwrite'
    )

    $SrcFull = Join-Path $RepoRoot $SrcRel
    $DstFull = Join-Path $Target $DstRel

    if (-not (Test-Path -Path $SrcFull -PathType Leaf)) {
        [Console]::Error.WriteLine("Error: Source file missing: $SrcRel")
        exit 2
    }

    if (-not (Test-Path -Path $DstFull)) {
        if ($DryRun) {
            Write-Host "[dry-run] create $DstRel"
        } else {
            $DstDir = Split-Path -Parent $DstFull
            if (-not (Test-Path -Path $DstDir)) {
                New-Item -ItemType Directory -Path $DstDir -Force | Out-Null
            }
            Copy-Item -Path $SrcFull -Destination $DstFull -Force
            Write-Host "created $DstRel"
        }
    } else {
        # Compare byte-for-byte or content
        $srcBytes = [System.IO.File]::ReadAllBytes($SrcFull)
        $dstBytes = [System.IO.File]::ReadAllBytes($DstFull)

        $areEqual = $false
        if ($srcBytes.Length -eq $dstBytes.Length) {
            $areEqual = $true
            for ($i = 0; $i -lt $srcBytes.Length; $i++) {
                if ($srcBytes[$i] -ne $dstBytes[$i]) {
                    $areEqual = $false
                    break
                }
            }
        }

        if ($areEqual) {
            Write-Host "unchanged $DstRel"
        } else {
            if ($Mode -eq "never-overwrite") {
                Write-Host "unchanged $DstRel"
            } else {
                if ($Force) {
                    if ($DryRun) {
                        Write-Host "[dry-run] overwrite $DstRel"
                    } else {
                        Copy-Item -Path $SrcFull -Destination $DstFull -Force
                        Write-Host "overwritten $DstRel"
                    }
                } else {
                    Write-Host "skipped (differs; use --force) $DstRel"
                    $script:SkippedAny = $true
                }
            }
        }
    }
}

Copy-InstallerFile "skills/notebooklm-discipline/SKILL.md" ".claude/skills/notebooklm-discipline/SKILL.md" "normal"
Copy-InstallerFile "commands/nlm.md" ".claude/commands/nlm.md" "normal"
Copy-InstallerFile "scripts/nlm-config.ps1" "scripts/nlm-config.ps1" "normal"
Copy-InstallerFile "scripts/nlm-context-pack.ps1" "scripts/nlm-context-pack.ps1" "normal"
Copy-InstallerFile "scripts/nlm-notebook-sync.ps1" "scripts/nlm-notebook-sync.ps1" "normal"
Copy-InstallerFile "scripts/nlm-repair-host-patch.ps1" "scripts/nlm-repair-host-patch.ps1" "normal"
Copy-InstallerFile "nlm.config.example.json" "nlm.config.json" "never-overwrite"
Copy-InstallerFile "templates/notebook-map.md" "docs/notebooklm_notebook_map.md" "never-overwrite"

if ($GitignoreManifest) {
    $GitignorePath = Join-Path $Target ".gitignore"
    $Entry = ".nlm-sync-manifest.json"

    $containsEntry = $false
    if (Test-Path -Path $GitignorePath -PathType Leaf) {
        $lines = Get-Content -Path $GitignorePath
        foreach ($line in $lines) {
            if ($line.Trim() -eq $Entry) {
                $containsEntry = $true
                break
            }
        }
    }

    if ($containsEntry) {
        Write-Host "unchanged .gitignore"
    } else {
        if ($DryRun) {
            Write-Host "[dry-run] append $Entry to .gitignore"
        } else {
            if (Test-Path -Path $GitignorePath -PathType Leaf) {
                $content = [System.IO.File]::ReadAllText($GitignorePath)
                if ($content.Length -gt 0 -and -not $content.EndsWith("`n") -and -not $content.EndsWith("`r")) {
                    [System.IO.File]::AppendAllText($GitignorePath, [System.Environment]::NewLine)
                }
            }
            [System.IO.File]::AppendAllText($GitignorePath, "$Entry$([System.Environment]::NewLine)")
            Write-Host "appended $Entry to .gitignore"
        }
    }
}

Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Fill nlm.config.json with your notebook IDs."
Write-Host "2. Run 'nlm login' to authenticate."
Write-Host "3. Run 'pwsh -File ./scripts/nlm-context-pack.ps1 -Show' to test your setup."

if ($script:SkippedAny) {
    exit 3
}

exit 0
