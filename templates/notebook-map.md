# NotebookLM notebook map (map of record)

> This file beats every other description of the notebook structure. A notebook not listed here is not a
> routing target.

**Content boundary:** only `<paths>` are uploaded. Never code, credentials or production config.
**Plan / quota:** `<plan>`: `<N>` sources per notebook, `~<N>` queries per day.

| Prefix | Purpose | Alias | UUID | Sources (date counted) |
|---|---|---|---|---|
| *(default)* | Hub: "what was decided / why", task grounding | `proj-core` | `…` | `…` |
| `adr:` | Individual decision records (precise citation) | `proj-adr` | `…` | `…` |
| `ops:` | Runbooks, processes, incidents | `proj-ops` | `…` | `…` |
| `sec:` | Security, tenancy, threat model | `proj-sec` | `…` | `…` |

## Repo-derived source

Every notebook holds exactly one repo-derived source titled `<Project> Master Context`. The sync replaces it
(add first, then remove). Everything else in a notebook is curated by hand and the sync never touches it.
