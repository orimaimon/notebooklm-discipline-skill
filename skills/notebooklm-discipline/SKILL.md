---
name: notebooklm-discipline
description: "Consult a NotebookLM notebook before an architecture decision, removing a blocker, writing a task prompt, or answering 'what was decided and why'. Answers are cited from your own sources. Includes the failure modes that make NotebookLM results lie."
---

# notebooklm-discipline

**Use when:** before writing or deciding an ADR · before writing a task prompt for another agent
(grounding) · before removing a blocker · answering "what was decided / why" · any domain or regulatory
question your notebooks were built for.

NotebookLM answers **only from the sources you gave it, with citations**. That makes it cheaper and faster
than grepping a large corpus of ADRs and research documents, and less likely to make things up than the
model's own memory. This skill covers how to query it, and the ways its results go wrong without warning.

Requires the [`notebooklm-mcp-cli`](https://github.com/jacob-bd/gemini-notebook-mcp-cli) CLI (`nlm`) and/or its MCP server.

## 🔴 Keep the notebook map out of this file

Once you have more than one notebook (a hub, per-decision, per-domain), aliases and UUIDs change. **Do not
hardcode a notebook table in this skill.** Every copy of a hardcoded table goes stale while still looking
authoritative.

- Keep **one map of record** in your repo (start from `templates/notebook-map.md`) and point to it here.
- Optional routing prefixes (e.g. `reg:` `ops:` `fin:` `sec:`) belong in the `/nlm` command, which reads the map.
- Live truth for aliases: `nlm alias list`.

**If this file and the map disagree, the map wins and this file is the bug.**

**Recommended:** give every notebook one repo-derived source, such as `<Project> Master Context`, with your
iron rules, module map, glossary, priorities and decision index. Without it, a domain notebook full of
external research answers from generic literature and ignores what you already decided and built.

## How to query

```bash
export PYTHONUTF8=1          # PowerShell: $env:PYTHONUTF8=1 — required on Windows for non-Latin output
nlm notebook query <alias-or-id> "What was decided about X, and why?"
```

MCP: tool `notebook_query` takes the **UUID**. Aliases exist only in the CLI, so MCP returns `NOT_FOUND` on an alias.

## Auth: check, renew, then ask

When auth fails or results look suspicious, handle auth non-interactively before asking a human:

1. **Check session:** Run `nlm login --check` to validate current credentials without changing them.
2. **Renew credentials:** On failure, run `nlm auth refresh` (or `nlm auth refresh --http-only` where no browser may open; MCP equivalent: `refresh_auth`). *Caveat:* If `NOTEBOOKLM_COOKIES` is set, it overrides saved credentials and `nlm auth refresh` refuses (exit 1); update `NOTEBOOKLM_COOKIES` in your environment or MCP config instead.
3. **Diagnose:** If refresh fails, run `nlm doctor` to diagnose installation, MCP server, and auth issues.
4. **Ask human:** Only if `nlm doctor` cannot fix it, ask a human to run interactive `nlm login`. An unattended agent must never run interactive `nlm login`.

A failure at any step means UNKNOWN, never "the notebook is empty" (see [Rules for correct use](#rules-for-correct-use-break-these-and-you-waste-quota-leak-ip-or-believe-something-false)).

## Ground a task prompt before writing code

Query the relevant notebook for the area's boundaries, decisions, events and anti-patterns. Then paste
the cited answer into the prompt as a `<!-- GROUNDING -->` block, so the implementing agent starts from
what was decided instead of rediscovering it.

## Research (to close a blocker): one topic at a time

Each notebook has **a single research slot**. A new `research start` **overwrites** the one that is
running, so never run research jobs in parallel on the same notebook.

```bash
nlm research start "<narrow query>" --notebook-id <id> [--mode deep]
nlm research status <id>
nlm research import <id> <task-id> --indices 1,3,4   # import BY INDEX after reading the list
```

**Do not use `--auto-import` on anything that matters.** In practice 40–60% of what it brings in is off-topic,
and an off-topic source gets cited with the same confidence as a good one.

## Keeping notebooks fresh

A stale notebook is worse than a slow grep: it cites last month's facts with this month's confidence.

```bash
pwsh -File ./scripts/nlm-notebook-sync.ps1 -Check    # which notebooks serve a stale pack (no auth, instant; exit 1 = stale)
pwsh -File ./scripts/nlm-notebook-sync.ps1           # build the pack and replace it in every notebook in nlm.config.json
```

Run the sync after any merge that touches canonical docs. `-Check` belongs in your docs/CI gate.
The scripts (`scripts/` in this repo, configured by `nlm.config.json`) already follow these rules. If you
write your own, keep them:
- **Replace, don't append.** A sync that re-adds sources creates duplicates, and NotebookLM cites the old
  copy as readily as the new one. It also uses up the per-notebook source cap.
- **Add first, then remove.** If a sync fails halfway, the notebook is left *stale*, not *empty*.
- **Fingerprint the *content* you pack, not the finished file.** A file that embeds today's date or the
  current commit changes every day, so the "stale" warning stays on permanently and people stop reading
  it. Add an age limit so live git state can't drift unnoticed either.
- **Report every skip.** A missing manifest file or a decision record with an unparseable status gets
  printed. If it's dropped silently, the decision disappears and an agent "discovers" it needs deciding again.

## ⚠️ Can't connect? `nlm login` hangs → "Login timeout"

Run `nlm doctor` before anything else.

Chain of symptoms: `nlm login` → `Waiting for sign-in... (300s elapsed)` → `Error: Login timeout`; after that
**every** command fails with `Profile 'default' not found`.

That is **not** expired cookies and **not** an empty notebook. Google rebranded NotebookLM as "Gemini Notebook" and
moved the *authenticated* app to `notebook.google.com`. Old CLI versions only recognised the old hosts,
so they never detect the signed-in page they are already showing. The old host still redirects to its own `/login`
when you are signed out, so it *looks* alive.

**Fix: upgrade.** Current releases recognise the new hosts (verified in 0.15.7):
```bash
uv tool upgrade notebooklm-mcp-cli      # or: pipx upgrade notebooklm-mcp-cli
nlm login
```
Pinned to an old version? Run `pwsh -File ./scripts/nlm-repair-host-patch.ps1`. It is idempotent, and
`-Check` exits 1 when the patch is needed. It does nothing on an install that is already fixed. A
reinstall of the old version wipes it, so run `-Check` **before** concluding anything else when NotebookLM misbehaves.

If it still hangs, check the page instead of guessing. With the login window open, query the Chrome
DevTools endpoint the CLI opened (`curl http://127.0.0.1:<cdp-port>/json/list`). It prints the page's
real URL and title.

## Rules for correct use (break these and you waste quota, leak IP, or believe something false)

- **Content boundary (iron rule):** upload documentation only, never source code, credentials or
  production config. Decide which paths qualify (e.g. `docs/**/*.md`) and say so in your map.
- **A failure means UNKNOWN, never "nothing was decided".** An auth failure, an empty result, or a timeout does not
  show that the notebook is empty. Re-authenticate and query again. If it still fails, report
  `BLOCKED: nlm auth` and move on. (We once wrote off a 264-source notebook as empty after an auth failure.)
- **Check the result, not the exit code.** Some errors come back with exit 0. Only a fresh
  `nlm source list` proves that a write landed.
- **`source delete` needs a fresh listing.** A bulk delete built from a stale list can drop all but the
  first ID. A delete sent immediately after an `add` on the same notebook can also be rejected, still with exit 0.
- **"✓ Added" does not mean the content was read.** A source can be added after reading 0 bytes. Some converters
  reverse right-to-left (Hebrew/Arabic) PDFs. To verify, ask something only that source could answer.
- **A notebook's title says nothing about what is in it.** Audit before you route questions to it.
- **NotebookLM is derived, not a second source of truth.** The repository is authoritative. A cited
  answer can still be stale. Say so when it matters.
- **Know your quota.** Source caps per notebook and daily query limits depend on the plan. Look them up and
  write them into your map.
