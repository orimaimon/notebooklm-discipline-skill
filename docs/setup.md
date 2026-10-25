# Setup Guide

This guide provides step-by-step instructions for installing and configuring `notebooklm-discipline` on Windows, macOS, and Linux.

---

## 1. Prerequisites

Before installing the skill and CLI, ensure you have the following installed on your operating system:

1. **PowerShell 7+ (`pwsh`)**: Required on all operating systems to run the context packing and sync scripts.
   - **Windows:**
     ```powershell
     winget install --id Microsoft.PowerShell
     ```
   - **macOS:**
     ```bash
     brew install --cask powershell
     ```
   - **Linux (Ubuntu/Debian):**
     Refer to the [Microsoft PowerShell on Linux installation guide](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux) to add the Microsoft package repository and install `powershell`.
2. **Git**: Installed and available on your PATH (`git --version`).
3. **Python (3.10+) with `uv` or `pipx`**: Used to manage isolated tool installations.
4. **Google Account with NotebookLM**: An active account with access to [NotebookLM](https://notebooklm.google.com).

---

## 2. Installing the CLI

Install the `notebooklm-mcp-cli` package using `uv` (recommended) or `pipx`:

```bash
uv tool install notebooklm-mcp-cli
```
or
```bash
pipx install notebooklm-mcp-cli
```

This installs two executables on your system PATH:
- `nlm`: The command-line interface for managing NotebookLM notebooks, sources, aliases, and auth.
- `notebooklm-mcp`: The Model Context Protocol (MCP) server executable for AI agent integration.

---

## 3. Signing In & Authentication

Authenticate the CLI with your Google account.

### Initial Sign-In

Run `nlm login` to start the interactive authentication process. This will launch a browser window where you can sign in to your Google account:

```bash
nlm login
```

*Note for Windows users with non-Latin terminal output or code pages:* Set `PYTHONUTF8=1` in your environment before running `nlm` commands:
```powershell
$env:PYTHONUTF8=1
nlm login
```

### Validating & Diagnosing

Verify that your authentication session is valid and healthy:

```bash
nlm login --check
nlm doctor
```

### Renewing Auth Non-Interactively

When your login session needs renewal, run headless refresh without opening a browser:

```bash
nlm auth refresh
```

---

## 4. Connecting an MCP Client

`notebooklm-mcp-cli` includes a guided wizard to help connect your installed AI tools to the `notebooklm-mcp` server.

### Guided Setup Wizard

Run the setup wizard interactively:
```bash
nlm setup
```

To list current MCP connection statuses across detected tools:
```bash
nlm setup list
```

### Configuring Specific Clients

- **Claude Desktop:**
  ```bash
  nlm setup add claude-desktop
  ```
- **Cursor:**
  ```bash
  nlm setup add cursor
  ```
- **Claude Code:**
  Use `nlm setup add json` as the source of truth for the MCP server configuration JSON. If adding via the Claude Code CLI, run `claude mcp add <name> -- <command>` using the command and arguments output by `nlm setup add json`.
- **Other MCP Clients:**
  To generate and print a raw JSON configuration snippet for any other MCP client:
  ```bash
  nlm setup add json
  ```

---

## 5. Finding Notebook IDs & Setting Aliases

`notebooklm-mcp-cli` tools interact with notebooks using their UUIDs. You can assign user-friendly aliases to UUIDs for easier CLI operations.

### Listing Notebooks

List all notebooks available in your Google account:
```bash
nlm notebook list
```
*(Supports `--json` for machine-readable output and `--quiet` for listing IDs only.)*

### Managing Aliases

To map a friendly name to a notebook UUID:
```bash
nlm alias set project-master 00000000-0000-0000-0000-000000000001
```

To list all configured aliases:
```bash
nlm alias list
```

> **Note:** MCP tools expect and require the notebook UUID (e.g., `00000000-0000-0000-0000-000000000001`), whereas `nlm` CLI commands accept both aliases and UUIDs.

---

## 6. Installing the Skill into Your Project

To install `notebooklm-discipline` into your target codebase, use the repository installer scripts.

### Installer Interface

The installer supports the following options:
- **Linux / macOS (`scripts/install.sh`):**
  ```bash
  ./scripts/install.sh [--target <dir>] [--dry-run] [--force] [--gitignore-manifest]
  ```
- **Windows / Any OS (`scripts/install.ps1`):**
  ```powershell
  pwsh -File ./scripts/install.ps1 [-Target <dir>] [-DryRun] [-Force] [-GitignoreManifest]
  ```

By default, the installer targets the current directory (`.`). It copies:
- Skill files to `<target>/.claude/skills/notebooklm-discipline/`
- Slash command to `<target>/.claude/commands/nlm.md`
- PowerShell scripts to `<target>/scripts/`
- Configuration template `nlm.config.example.json` to `<target>/nlm.config.json` (only if `<target>/nlm.config.json` does not already exist)

The installer verifies prerequisites (`pwsh`, `git`, and `nlm`) and prints installation hints if any are missing.

### Manual Installation Fallback

If you cannot run the installer scripts, copy the files manually:
```bash
mkdir -p .claude/skills .claude/commands scripts
cp -r skills/notebooklm-discipline .claude/skills/
cp commands/nlm.md .claude/commands/
cp scripts/*.ps1 scripts/
cp nlm.config.example.json nlm.config.json
cp templates/notebook-map.md docs/notebooklm_notebook_map.md
echo ".nlm-sync-manifest.json" >> .gitignore
```

---

## 7. Configuring `nlm.config.json`

Open `nlm.config.json` in your project root and configure your target notebooks and context pack settings:

```json
{
  "project": "MyProject",
  "docsRoot": "docs",
  "mainRef": "origin/main",
  "notebooks": [
    {
      "alias": "project-master",
      "id": "00000000-0000-0000-0000-000000000001",
      "tier": "primary",
      "desc": "Master context notebook"
    }
  ]
}
```

*For full configuration key descriptions, refer to the table in [README.md](../README.md).*

---

## 8. First Pack & Sync Run

Once configured, test and run the context generation and sync scripts.

1. **Build and inspect the context pack locally:**
   ```bash
   pwsh -File ./scripts/nlm-context-pack.ps1 -Show
   ```
2. **Perform a dry-run sync:**
   ```bash
   pwsh -File ./scripts/nlm-notebook-sync.ps1 -DryRun
   ```
3. **Execute the sync:**
   ```bash
   pwsh -File ./scripts/nlm-notebook-sync.ps1
   ```

---

## 9. CI Integration (`-Check` Gate)

You can wire `nlm-notebook-sync.ps1` into your CI/CD pipeline (e.g., GitHub Actions) to ensure that NotebookLM notebooks remain up to date with repository changes.

Running the sync script with `-Check` checks the content fingerprint against the stored manifest:
```bash
pwsh -File ./scripts/nlm-notebook-sync.ps1 -Check
```

- **Behavior:**
  `-Check` exits with code `1` if a notebook is stale and requires syncing. Crucially, `-Check` requires no Google authentication tokens or network calls to NotebookLM, making it safe and fast as a CI gate.
