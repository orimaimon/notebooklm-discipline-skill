# notebooklm-discipline

An agent skill (Claude Code / any `SKILL.md`-compatible agent) for using **NotebookLM as the grounding layer
of a project's own documents**: query a cited notebook before you make a decision, and don't trust the
results it gets wrong without warning.

It came out of months of running NotebookLM as the "what did we decide and why" oracle for a large
codebase with a dozen notebooks. Most of the skill is the list of things that went wrong:

- an auth failure read as "the notebook is empty" (a 264-source notebook was written off)
- errors that return exit 0
- `--auto-import` bringing in 40–60% off-topic sources
- syncs that append duplicates, which then get cited as confidently as the originals
- a "stale" warning that was always on, so nobody read it
- hardcoded notebook tables in skills going stale while still looking authoritative

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

## Install

Requires [`notebooklm-mcp-cli`](https://github.com/jacob-bd/gemini-notebook-mcp-cli) (`nlm`). The scripts need
PowerShell 7+ (`pwsh`, which runs on Windows, macOS and Linux) and `git`.

```bash
# Claude Code, per project
mkdir -p .claude/skills .claude/commands scripts
cp -r skills/notebooklm-discipline .claude/skills/
cp commands/nlm.md .claude/commands/
cp scripts/*.ps1 scripts/
cp nlm.config.example.json nlm.config.json           # fill in: manifest docs, decision dirs, notebook IDs
cp templates/notebook-map.md docs/notebooklm_notebook_map.md
echo ".nlm-sync-manifest.json" >> .gitignore          # optional: or commit it to share sync state
```

Then:

```bash
nlm login
pwsh -File ./scripts/nlm-context-pack.ps1 -Show       # build only; inspect the output
pwsh -File ./scripts/nlm-notebook-sync.ps1 -DryRun    # what would change
pwsh -File ./scripts/nlm-notebook-sync.ps1            # sync
```

### `nlm.config.json`

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

Relative paths resolve from the directory that holds the config file.

This is a different thing from the upstream CLI's own bundled skill. That one documents the commands; this
one is about using them without fooling yourself.

## License

MIT
