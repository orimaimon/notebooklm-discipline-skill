#!/usr/bin/env bash
set -euo pipefail

# Find repository root relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TARGET="."
DRY_RUN=0
FORCE=0
GITIGNORE_MANIFEST=0

show_help() {
  cat <<'EOF'
Usage: install.sh [--target <dir>] [--dry-run] [--force] [--gitignore-manifest] [--help]

Options:
  --target <dir>        Target directory for installation (default: current directory)
  --dry-run             Show what would be copied/modified without writing files
  --force               Overwrite existing files if they differ
  --gitignore-manifest  Append .nlm-sync-manifest.json to .gitignore if not present
  --help, -h            Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      if [[ $# -lt 2 ]]; then
        echo "Error: --target requires a directory argument" >&2
        exit 2
      fi
      TARGET="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --gitignore-manifest)
      GITIGNORE_MANIFEST=1
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      echo "Error: Unknown option $1" >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$TARGET" ]]; then
  echo "Error: Target directory '$TARGET' does not exist or is not a directory." >&2
  exit 2
fi

# Prerequisite checks (warn, never fail)
OS_TYPE="$(uname -s)"
if ! command -v pwsh >/dev/null 2>&1; then
  case "$OS_TYPE" in
    Darwin*)
      echo "Warning: pwsh not found. Install via: brew install --cask powershell" >&2
      ;;
    Linux*)
      echo "Warning: pwsh not found. Install via: https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux" >&2
      ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "Warning: pwsh not found. Install via: winget install --id Microsoft.PowerShell" >&2
      ;;
    *)
      echo "Warning: pwsh not found. Install via: brew install --cask powershell (macOS) / https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux (Linux) / winget install --id Microsoft.PowerShell (Windows)" >&2
      ;;
  esac
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Warning: git not found. Install git using your package manager." >&2
fi

if ! command -v nlm >/dev/null 2>&1; then
  echo "Warning: nlm not found. Install via: uv tool install notebooklm-mcp-cli or pipx install notebooklm-mcp-cli" >&2
fi

SKIPPED_ANY=0

copy_file() {
  local src_rel="$1"
  local dst_rel="$2"
  local mode="$3" # normal | never-overwrite

  local src_full="$REPO_ROOT/$src_rel"
  local dst_full="$TARGET/$dst_rel"

  if [[ ! -f "$src_full" ]]; then
    echo "Error: Source file missing: $src_rel" >&2
    exit 2
  fi

  if [[ ! -e "$dst_full" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[dry-run] create $dst_rel"
    else
      local dst_dir
      dst_dir="$(dirname "$dst_full")"
      mkdir -p "$dst_dir"
      cp "$src_full" "$dst_full"
      echo "created $dst_rel"
    fi
  else
    if cmp -s "$src_full" "$dst_full"; then
      echo "unchanged $dst_rel"
    else
      if [[ "$mode" == "never-overwrite" ]]; then
        echo "unchanged $dst_rel"
      else
        if [[ "$FORCE" -eq 1 ]]; then
          if [[ "$DRY_RUN" -eq 1 ]]; then
            echo "[dry-run] overwrite $dst_rel"
          else
            cp "$src_full" "$dst_full"
            echo "overwritten $dst_rel"
          fi
        else
          echo "skipped (differs; use --force) $dst_rel"
          SKIPPED_ANY=1
        fi
      fi
    fi
  fi
}

copy_file "skills/notebooklm-discipline/SKILL.md" ".claude/skills/notebooklm-discipline/SKILL.md" "normal"
copy_file "commands/nlm.md" ".claude/commands/nlm.md" "normal"
copy_file "scripts/nlm-config.ps1" "scripts/nlm-config.ps1" "normal"
copy_file "scripts/nlm-context-pack.ps1" "scripts/nlm-context-pack.ps1" "normal"
copy_file "scripts/nlm-notebook-sync.ps1" "scripts/nlm-notebook-sync.ps1" "normal"
copy_file "scripts/nlm-repair-host-patch.ps1" "scripts/nlm-repair-host-patch.ps1" "normal"
copy_file "nlm.config.example.json" "nlm.config.json" "never-overwrite"
copy_file "templates/notebook-map.md" "docs/notebooklm_notebook_map.md" "never-overwrite"

if [[ "$GITIGNORE_MANIFEST" -eq 1 ]]; then
  GITIGNORE_PATH="$TARGET/.gitignore"
  ENTRY=".nlm-sync-manifest.json"
  if [[ -f "$GITIGNORE_PATH" ]] && grep -Fqx "$ENTRY" "$GITIGNORE_PATH"; then
    echo "unchanged .gitignore"
  else
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "[dry-run] append $ENTRY to .gitignore"
    else
      if [[ -f "$GITIGNORE_PATH" ]] && [[ -s "$GITIGNORE_PATH" ]]; then
        # Ensure trailing newline before appending
        if [ -n "$(tail -c 1 "$GITIGNORE_PATH")" ]; then
          echo "" >> "$GITIGNORE_PATH"
        fi
      fi
      echo "$ENTRY" >> "$GITIGNORE_PATH"
      echo "appended $ENTRY to .gitignore"
    fi
  fi
fi

cat <<'EOF'

Next steps:
1. Fill nlm.config.json with your notebook IDs.
2. Run 'nlm login' to authenticate.
3. Run 'pwsh -File ./scripts/nlm-context-pack.ps1 -Show' to test your setup.
EOF

if [[ "$SKIPPED_ANY" -eq 1 ]]; then
  exit 3
fi

exit 0
