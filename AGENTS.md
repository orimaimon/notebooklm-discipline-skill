# AGENTS.md — rules for any agent working in this repository

This repo ships an agent skill (`skills/notebooklm-discipline/SKILL.md`), a slash command (`commands/nlm.md`)
and PowerShell 7 scripts (`scripts/*.ps1`) that build and sync a "Master Context" source into NotebookLM
notebooks through the `nlm` CLI (`notebooklm-mcp-cli` on PyPI).

## Ground rules
- Change only the files your task lists. If more are needed, STOP and explain in the PR description.
- **No project-specific or personal data, ever.** No real notebook UUIDs (use `00000000-0000-0000-0000-00000000000N`),
  no real names, emails, company or product names, no API keys. This repository is public.
- The scripts are one implementation for every OS: **PowerShell 7 (`pwsh`)** on Windows, macOS and Linux.
  Do not add a parallel bash/Python re-implementation of `nlm-context-pack.ps1` or `nlm-notebook-sync.ps1`.
- Paths: use `Join-Path` / `[System.IO.Path]`, never hard-coded `\` or `/`; never `$env:TEMP` or `$env:APPDATA`
  without a fallback (they are unset on Linux/macOS).
- No network calls in tests and no real `nlm`: tests use the fake CLI in `tests/fake-nlm/` (once it exists).
- Never delete, skip or weaken a test.
- Do not document an `nlm` command or flag unless it appears in the upstream docs
  (https://github.com/jacob-bd/gemini-notebook-mcp-cli). If unsure, leave it out and say so in the PR.
- Keep `SKILL.md` frontmatter valid YAML; never put an unquoted `: ` in the `description`.

## Environment
- Ubuntu: install PowerShell 7 with
  `sudo apt-get update && sudo apt-get install -y wget apt-transport-https software-properties-common && wget -q https://packages.microsoft.com/config/ubuntu/$(. /etc/os-release; echo $VERSION_ID)/packages-microsoft-prod.deb && sudo dpkg -i packages-microsoft-prod.deb && sudo apt-get update && sudo apt-get install -y powershell`
- Pester 5: `pwsh -NoProfile -Command "Install-Module Pester -MinimumVersion 5.5 -Force -Scope CurrentUser"`

## Verify before opening a PR (all must pass; judge each by its own exit code)
- `pwsh -NoProfile -Command "Invoke-Pester -Path tests -CI"`  (when `tests/*.Tests.ps1` exist)
- `for f in tests/*.test.sh; do bash "$f" || exit 1; done`     (when `tests/*.test.sh` exist)
- `python3 -c "import yaml;t=open('skills/notebooklm-discipline/SKILL.md').read();yaml.safe_load(t.split('---')[1])"`
