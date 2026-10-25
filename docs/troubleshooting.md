# Troubleshooting Guide

This guide covers common issues, their root causes, and recommended fixes when working with `notebooklm-mcp-cli` and `notebooklm-discipline`.

---

## 1. Login Timeout Followed by `Profile 'default' not found`

### Symptom
When running `nlm login`, the process waits until a "Login timeout" error occurs, followed by `Profile 'default' not found`.

### Cause
You are using an older version of `notebooklm-mcp-cli` that predates Google's host migration to `notebook.google.com` / `notebook.cloud.google.com`. The outdated CLI attempts to capture auth cookies from the old URL endpoint, causing the login flow to time out.

### Fix
Upgrade the CLI package to the latest version:

```bash
uv tool install --force notebooklm-mcp-cli
```
or
```bash
pipx upgrade notebooklm-mcp-cli
```

Alternatively, if you cannot immediately upgrade the package, run the repair patch script provided in this repository:

```powershell
pwsh -File ./scripts/nlm-repair-host-patch.ps1
```

---

## 2. Auth Errors or Empty Answers Interpreted as "Empty Notebook"

### Symptom
An agent or query returns an empty response, or an authentication error occurs, and the result is assumed to mean the notebook contains no sources.

### Cause
When session authentication expires or an unhandled RPC response occurs, the CLI or agent may receive an empty payload or error structure. Treating an empty answer or auth failure as an empty notebook is invalid—it conceals authentication failures and leads to false assumptions about notebook state.

### Fix
Treat any auth error or unexpected empty answer as **UNKNOWN** status rather than "empty notebook":
1. Check your authentication status with `nlm login --check`.
2. Run `nlm doctor` to diagnose connection and auth session issues.
3. Refresh your authentication session using `nlm auth refresh` or `nlm login`.
4. Re-run your query only after confirming auth health.

---

## 3. Exit Code 0 Without Confirmed Write Operations

### Symptom
An `nlm` command or sync script completes with exit code `0`, but the expected source changes or updates are missing from the notebook.

### Cause
In some underlying API scenarios, network or CLI operations may complete without throwing a non-zero exit code even if the backend write failed or was delayed.

### Fix
Do not rely solely on exit code `0` to confirm that a write or upload landed in NotebookLM. Always verify the source list explicitly after performing write or sync operations:

```bash
nlm source list <notebook-uuid-or-alias>
```

Verify that the expected source title, document count, and content match your target state.

---

## 4. HTTP 400 Errors During Back-to-Back Bulk Upload Syncs

### Symptom
When syncing multiple notebooks sequentially in rapid succession, uploading sources fails with an `HTTP 400` error.

### Cause
Sending rapid back-to-back upload requests across multiple notebooks can trigger transient backend rate limits or request validation errors on NotebookLM endpoints. This is a temporary API throttling behavior, not an authentication failure.

### Fix
1. Do not re-authenticate or re-run `nlm login` (the session is still valid).
2. Sync the failing notebook individually using the `-Target` parameter:
   ```powershell
   pwsh -File ./scripts/nlm-notebook-sync.ps1 -Target <notebook-alias>
   ```
3. If necessary, introduce a short pause between bulk operations when scripting custom workflows.
