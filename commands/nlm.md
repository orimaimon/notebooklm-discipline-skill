---
description: Consult NotebookLM for a cited answer (what was decided / why, or a domain question)
argument-hint: [question] — optional routing prefix defined in your notebook map (e.g. reg: ops: sec:)
---

Consult NotebookLM and report the **cited** answer for: $ARGUMENTS

Use the `notebooklm-discipline` skill. **Map of record: `docs/notebooklm_notebook_map.md`** (adjust the path).
If the map and this file ever disagree, the map wins.

1. Pick the notebook: use the map's routing table and the question's prefix. With no prefix, use the hub.
2. Run `nlm notebook query <alias> "<question>"` (set `PYTHONUTF8=1` on Windows), or the MCP
   `notebook_query` tool with the **UUID** (MCP rejects aliases; get the UUID from `nlm alias list`).
3. **Empty or failed result? Check auth FIRST.** `Authentication expired`, `Profile 'default' not found`
   or a silent empty answer does not mean an empty notebook. Run `nlm login` and query again.
4. Report the answer **with its citations**; do not paraphrase the sources away. If the question is a decision
   or a blocker, name the decision record or source that resolves it.
