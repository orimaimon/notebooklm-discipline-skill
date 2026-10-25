#!/usr/bin/env bash
# shellcheck disable=SC2317
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

INSTALL_SH="$REPO_ROOT/scripts/install.sh"
INSTALL_PS1="$REPO_ROOT/scripts/install.ps1"

HAS_PWSH=0
if command -v pwsh >/dev/null 2>&1; then
  HAS_PWSH=1
fi

FAILED=0

invoke_installer() {
  local installer_type="$1"
  shift
  if [[ "$installer_type" == "sh" ]]; then
    bash "$INSTALL_SH" "$@"
  else
    local ps_args=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --target)
          ps_args+=("-Target" "$2")
          shift 2
          ;;
        --dry-run)
          ps_args+=("-DryRun")
          shift
          ;;
        --force)
          ps_args+=("-Force")
          shift
          ;;
        --gitignore-manifest)
          ps_args+=("-GitignoreManifest")
          shift
          ;;
        *)
          ps_args+=("$1")
          shift
          ;;
      esac
    done
    pwsh -NoProfile -File "$INSTALL_PS1" "${ps_args[@]}"
  fi
}

# Test Case 1: Fresh install creates all 8 destination files
test_fresh_install() {
  local type="$1"
  local tmpdir
  tmpdir="$(mktemp -d)"

  invoke_installer "$type" --target "$tmpdir" >/dev/null

  local expected_files=(
    ".claude/skills/notebooklm-discipline/SKILL.md"
    ".claude/commands/nlm.md"
    "scripts/nlm-config.ps1"
    "scripts/nlm-context-pack.ps1"
    "scripts/nlm-notebook-sync.ps1"
    "scripts/nlm-repair-host-patch.ps1"
    "nlm.config.json"
    "docs/notebooklm_notebook_map.md"
  )

  for f in "${expected_files[@]}"; do
    if [[ ! -f "$tmpdir/$f" ]]; then
      echo "Missing expected file: $f" >&2
      rm -rf "$tmpdir"
      return 1
    fi
  done

  rm -rf "$tmpdir"
  return 0
}

# Test Case 2: Second run reports everything unchanged and exits 0
test_second_run_unchanged() {
  local type="$1"
  local tmpdir
  tmpdir="$(mktemp -d)"

  invoke_installer "$type" --target "$tmpdir" >/dev/null
  local out
  out="$(invoke_installer "$type" --target "$tmpdir")"

  if echo "$out" | grep -q "created"; then
    echo "Unexpected 'created' on second run: $out" >&2
    rm -rf "$tmpdir"
    return 1
  fi
  if echo "$out" | grep -q "skipped"; then
    echo "Unexpected 'skipped' on second run: $out" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  rm -rf "$tmpdir"
  return 0
}

# Test Case 3: Existing nlm.config.json with custom content is untouched with and without --force
test_custom_config_untouched() {
  local type="$1"
  local tmpdir
  tmpdir="$(mktemp -d)"

  invoke_installer "$type" --target "$tmpdir" >/dev/null
  echo '{"custom": "data"}' > "$tmpdir/nlm.config.json"

  # Run without --force
  invoke_installer "$type" --target "$tmpdir" >/dev/null
  if [[ "$(cat "$tmpdir/nlm.config.json")" != '{"custom": "data"}' ]]; then
    echo "nlm.config.json was overwritten without --force" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  # Run with --force
  invoke_installer "$type" --target "$tmpdir" --force >/dev/null
  if [[ "$(cat "$tmpdir/nlm.config.json")" != '{"custom": "data"}' ]]; then
    echo "nlm.config.json was overwritten with --force" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  rm -rf "$tmpdir"
  return 0
}

# Test Case 4: Modified .claude/commands/nlm.md is skipped with exit 3, overwritten with --force
test_modified_file_skipped_and_overwritten() {
  local type="$1"
  local tmpdir
  tmpdir="$(mktemp -d)"

  invoke_installer "$type" --target "$tmpdir" >/dev/null
  echo "MODIFIED CONTENT" > "$tmpdir/.claude/commands/nlm.md"

  # Without --force -> expect exit code 3
  set +e
  local out
  out="$(invoke_installer "$type" --target "$tmpdir" 2>&1)"
  local code=$?
  set -e

  if [[ $code -ne 3 ]]; then
    echo "Expected exit code 3 when file modified, got $code" >&2
    rm -rf "$tmpdir"
    return 1
  fi
  if ! echo "$out" | grep -q "skipped (differs; use --force) .claude/commands/nlm.md"; then
    echo "Expected skipped message, got: $out" >&2
    rm -rf "$tmpdir"
    return 1
  fi
  if [[ "$(cat "$tmpdir/.claude/commands/nlm.md")" != "MODIFIED CONTENT" ]]; then
    echo "File was overwritten without --force" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  # With --force -> expect exit code 0 and file overwritten
  invoke_installer "$type" --target "$tmpdir" --force >/dev/null
  if [[ "$(cat "$tmpdir/.claude/commands/nlm.md")" == "MODIFIED CONTENT" ]]; then
    echo "File was not overwritten with --force" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  rm -rf "$tmpdir"
  return 0
}

# Test Case 5: --dry-run creates nothing
test_dry_run() {
  local type="$1"
  local tmpdir
  tmpdir="$(mktemp -d)"

  invoke_installer "$type" --target "$tmpdir" --dry-run >/dev/null

  local count
  count="$(find "$tmpdir" -mindepth 1 | wc -l)"
  if [[ "$count" -ne 0 ]]; then
    echo "--dry-run created files/directories in target" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  rm -rf "$tmpdir"
  return 0
}

# Test Case 6: --gitignore-manifest twice adds the line once
test_gitignore_manifest_twice() {
  local type="$1"
  local tmpdir
  tmpdir="$(mktemp -d)"

  invoke_installer "$type" --target "$tmpdir" --gitignore-manifest >/dev/null
  invoke_installer "$type" --target "$tmpdir" --gitignore-manifest >/dev/null

  if [[ ! -f "$tmpdir/.gitignore" ]]; then
    echo ".gitignore was not created" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  local occurrences
  occurrences="$(grep -c "^\.nlm-sync-manifest\.json$" "$tmpdir/.gitignore" || true)"
  if [[ "$occurrences" -ne 1 ]]; then
    echo "Expected .nlm-sync-manifest.json exactly once in .gitignore, found $occurrences" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  rm -rf "$tmpdir"
  return 0
}

# Test Case 7: --target /does/not/exist exits 2
test_nonexistent_target() {
  local type="$1"
  set +e
  invoke_installer "$type" --target "/does/not/exist/dir" >/dev/null 2>&1
  local code=$?
  set -e

  if [[ $code -ne 2 ]]; then
    echo "Expected exit code 2 for non-existent target, got $code" >&2
    return 1
  fi

  return 0
}

# Test Case 8: Running from a different cwd works
test_different_cwd() {
  local type="$1"
  local tmpdir
  tmpdir="$(mktemp -d)"

  (
    cd /tmp
    if [[ "$type" == "sh" ]]; then
      bash "$INSTALL_SH" --target "$tmpdir" >/dev/null
    else
      pwsh -NoProfile -File "$INSTALL_PS1" -Target "$tmpdir" >/dev/null
    fi
  )

  if [[ ! -f "$tmpdir/.claude/commands/nlm.md" ]]; then
    echo "Failed to install when running from different cwd" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  rm -rf "$tmpdir"
  return 0
}

test_default_target_after_cd() {
  # Default target "." after changing directory inside the shell/session. For install.ps1 this is the
  # case where the PowerShell location and the process working directory differ.
  local type="$1"
  local start proj
  start="$(mktemp -d)"
  proj="$(mktemp -d)"
  printf 'existing\n' > "$proj/.gitignore"

  local _
  for _ in 1 2; do
    if [[ "$type" == "sh" ]]; then
      (cd "$start" && cd "$proj" && bash "$INSTALL_SH" --gitignore-manifest >/dev/null 2>&1) || true
    else
      # Paths embedded in a -Command string are not converted by Git Bash on Windows, so hand
      # native pwsh a Windows path there (cygpath exists only under Git Bash/MSYS/Cygwin).
      local proj_native="$proj" ps1_native="$INSTALL_PS1"
      if command -v cygpath >/dev/null 2>&1; then
        proj_native="$(cygpath -w "$proj")"
        ps1_native="$(cygpath -w "$INSTALL_PS1")"
      fi
      (cd "$start" && pwsh -NoProfile -Command "Set-Location -LiteralPath '$proj_native'; & '$ps1_native' -GitignoreManifest" >/dev/null 2>&1) || true
    fi
  done

  local ok=0
  if [[ -f "$proj/.claude/commands/nlm.md" ]] \
     && [[ "$(grep -cx '.nlm-sync-manifest.json' "$proj/.gitignore")" == "1" ]] \
     && [[ ! -e "$start/.gitignore" ]] && [[ ! -e "$start/.claude" ]]; then
    ok=1
  else
    echo "Default target after cd: files or .gitignore landed in the wrong directory" >&2
  fi

  rm -rf "$start" "$proj"
  [[ $ok -eq 1 ]]
}

run_test() {
  local installer_type="$1" # "sh" or "ps1"
  local test_name="$2"
  local test_func="$3"

  local full_name="${installer_type}: ${test_name}"

  if "$test_func" "$installer_type"; then
    echo "PASS $full_name"
  else
    echo "FAIL $full_name"
    FAILED=1
  fi
}

TEST_TYPES=("sh")
if [[ $HAS_PWSH -eq 1 ]]; then
  TEST_TYPES+=("ps1")
fi

for t in "${TEST_TYPES[@]}"; do
  run_test "$t" "fresh install creates all 8 destination files" test_fresh_install
  run_test "$t" "second run reports everything unchanged and exits 0" test_second_run_unchanged
  run_test "$t" "existing nlm.config.json with custom content is untouched with and without --force" test_custom_config_untouched
  run_test "$t" "modified .claude/commands/nlm.md is skipped with exit 3, overwritten with --force" test_modified_file_skipped_and_overwritten
  run_test "$t" "--dry-run creates nothing" test_dry_run
  run_test "$t" "--gitignore-manifest twice adds line once" test_gitignore_manifest_twice
  run_test "$t" "--target /does/not/exist exits 2" test_nonexistent_target
  run_test "$t" "running from a different cwd works" test_different_cwd
  run_test "$t" "default target after cd installs into the new directory" test_default_target_after_cd
done

if [[ $FAILED -ne 0 ]]; then
  exit 1
fi

exit 0
