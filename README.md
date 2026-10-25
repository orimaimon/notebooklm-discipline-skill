# notebooklm-discipline

**NotebookLM as the grounding layer for project context and architectural decisions.**

`notebooklm-discipline` is an agent skill (compatible with Claude Code and `SKILL.md`-compatible AI assistants) and a PowerShell 7 automation toolkit. It helps software teams query cited NotebookLM notebooks before making architecture or codebase decisions, and systematically sync repo documentation into NotebookLM without risking duplicate sources or false conclusions.

*Note on alternative servers:* The legacy [`PleasePrompto/notebooklm-mcp`](https://github.com/PleasePrompto/notebooklm-mcp) server is archived and no longer maintained (since September 2026); using [`notebooklm-mcp-cli`](https://github.com/jacob-bd/gemini-notebook-mcp-cli) is recommended.

For in-depth guides, see:
- [Setup Guide](docs/setup.md)
- [Troubleshooting Guide](docs/troubleshooting.md)

---

## Quick Start

Follow these 5 steps to go from zero to your first query and context sync.

### Step 1: Install Prerequisites

You need **PowerShell 7+ (`pwsh`)**, **git**, **Python with `uv` (or `pipx`)**, and a **Google account with NotebookLM**.

- **Windows:**
  ```powershell
  winget install --id Microsoft.PowerShell
  ```
- **macOS:**
  ```bash
  brew install --cask powershell
  ```
- **Linux (Ubuntu/Debian):**
  Follow the official [Microsoft PowerShell on Linux installation guide](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux).

### Step 2: Install the NotebookLM MCP CLI

Install `notebooklm-mcp-cli` using `uv` or `pipx`. This package provides both the `nlm` CLI and the `notebooklm-mcp` server executable.

```bash
uv tool install notebooklm-mcp-cli
# or: pipx install notebooklm-mcp-cli
```

### Step 3: Sign In and Verify

Authenticate with your Google account and verify system health.

- **Windows:**
  *(If using non-Latin terminal output, set `PYTHONUTF8=1` in your environment first: `$env:PYTHONUTF8=1`)*
  ```powershell
  nlm login
  nlm login --check
  nlm doctor
  ```
- **macOS / Linux:**
  ```bash
  nlm login
  nlm login --check
  nlm doctor
  ```

*(To non-interactively renew tokens later, run `nlm auth refresh`.)*

### Step 4: Install the Skill into Your Project

Run the installer from this repo to copy the skill, command, scripts, and example configuration into your target project directory.

- **Linux / macOS:**
  ```bash
  ./scripts/install.sh --target .
  ```
- **Windows / Any OS (PowerShell 7):**
  ```powershell
  pwsh -File ./scripts/install.ps1 -Target .
  ```

<details>
<summary>Manual Installation Fallback</summary>

If you prefer installing manually without running the installer script:
```bash
mkdir -p .claude/skills .claude/commands scripts
cp -r skills/notebooklm-discipline .claude/skills/
cp commands/nlm.md .claude/commands/
cp scripts/*.ps1 scripts/
cp nlm.config.example.json nlm.config.json
cp templates/notebook-map.md docs/notebooklm_notebook_map.md
echo ".nlm-sync-manifest.json" >> .gitignore
```
</details>

After installation, update `nlm.config.json` with your project's notebook IDs (obtained via `nlm notebook list`). Configure your AI client MCP connections with `nlm setup` (or client-specific commands like `nlm setup add cursor`).

### Step 5: First Query & Sync

1. Inspect the generated Master Context pack without writing to NotebookLM:
   ```bash
   pwsh -File ./scripts/nlm-context-pack.ps1 -Show
   ```

2. Perform a dry-run sync to review planned changes:
   ```bash
   pwsh -File ./scripts/nlm-notebook-sync.ps1 -DryRun
   ```

3. Execute the sync to update your target notebooks:
   ```bash
   pwsh -File ./scripts/nlm-notebook-sync.ps1
   ```

---

## Contents

| Path | What |
|---|---|
| `skills/notebooklm-discipline/SKILL.md` | The skill |
| `commands/nlm.md` | Optional `/nlm <question>` slash command |
| `templates/notebook-map.md` | A map-of-record template (the skill deliberately keeps notebook IDs out of itself) |
| `templates/pack-intro.md` | Template for the "what this project is" paragraph that opens the pack |
| `scripts/nlm-context-pack.ps1` | Builds the **Master Context pack**: one repo-derived Markdown file with your rules, module map, glossary, a generated **decision index** (every ADR + its status) and **live git state** |
| `scripts/nlm-notebook-sync.ps1` | Replaces that pack in every notebook: add first, delete old copies by title (with retry and verification), skip unchanged notebooks via a content fingerprint, renew auth on its own. `-Check` for CI |
| `scripts/nlm-repair-host-patch.ps1` | Fixes `nlm login` → "Login timeout" on **old** CLI versions (Gemini Notebook host move). Does nothing on current releases |
| `scripts/nlm-config.ps1` | Shared loader for `nlm.config.json` |
| `nlm.config.example.json` | All project-specific settings: what goes in the pack, which notebooks exist |

---

## `nlm.config.json` Settings

| Key | Meaning |
|---|---|
| `project` | Name used in the pack header; default source title is `<project> Master Context` |
| `manifest[]` | `{part, doc, title, why}`, the documents (relative to `docsRoot`) embedded verbatim in reading order, each behind a `SOURCE FILE:` banner so citations point at the real path |
| `decisionIndex` | `{dirs, insertBefore, fileNumberPattern, headingPattern}`. Generates a table of every decision record and its parsed `Status:` (inline or `## Status` heading). Omit it to skip the index |
| `auditPart` | Optional `part` of a code-verified audit doc; Part I then lists every commit on `mainRef` since it was written |
| `facts[]` | `{label, path, kind: dirs\|files, filter, list}`, counts from the tree (modules, migrations …), part of the content fingerprint |
| `introFile` | Optional Markdown describing what the project is, and the bar a recommendation has to clear |
| `notebooks[]` | `{alias, id, tier, desc}`, sync targets |
| `docsRoot` · `mainRef` · `sourceTitle` · `packFileName` · `manifestFile` · `recentCommits` | Defaults: `docs` · `origin/main` · derived · derived · `.nlm-sync-manifest.json` · `30` |

*Relative paths resolve from the directory that holds the config file.*

---

## Documentation

- [Setup Guide](docs/setup.md) — Detailed OS-specific installation, connecting MCP clients (Claude Code, Claude Desktop, Cursor), managing notebook IDs/aliases, and CI setup.
- [Troubleshooting Guide](docs/troubleshooting.md) — Common symptoms, causes, and step-by-step fixes for auth timeouts, UNKNOWN responses, bulk uploads, and verification checks.

---

## License

[MIT](LICENSE)
