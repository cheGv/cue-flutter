# cue-addendum.md — debugging-and-error-recovery
This addendum overlays Addy Osmani's debugging-and-error-recovery skill with Cue-specific shortcuts. Read both files together.
## Cue-specific debugging shortcuts
These are the most common failure modes from past build sessions. Check these first before deep debugging.
### CORS errors from the Render proxy
- First: confirm the proxy is awake (Render free tier sleeps). Hit the health endpoint.
- Second: check `ALLOWED_ORIGINS` env var on Render. New deploy environments need adding.
- Third: check the proxy's CORS middleware order — must run before route handlers.
### JWT / 401 errors from Edge Functions
- First: confirm the Authorization header is forwarded by the client.
- Second: confirm the JWT hasn't expired (decode at jwt.io to check `exp`).
- Third: confirm the Edge Function is reading `SUPABASE_SERVICE_ROLE_KEY` vs `SUPABASE_ANON_KEY` correctly for the operation.
### LLM returns unexpected content
- First: check the system prompt file in the repo — not your memory of what the prompt says.
- Second: check whether the anti-fabrication preamble is being applied (log the full message array sent to Anthropic).
- Third: check whether structured-output schema was actually requested.
- Never debug LLM behavior by guessing what the prompt "probably" says.
### Supabase query returns wrong rows
- First: check whether `deleted_at IS NULL` filter is applied.
- Second: check whether `clinician_attested = true` filter is applied (if clinical content).
- Third: check RLS — run the same query as the SQL user vs the application user.
### Flutter layout breaks at certain widths
- Almost always: `MediaQuery` being used where `LayoutBuilder` should be. Search for `MediaQuery.of(context).size` in the affected widget tree.
### Voice / Narrator pipeline fails
- First: check Whisper API limits (file size, format).
- Second: check the Edge Function logs in the Supabase dashboard.
- Third: check the GPT-4o-mini SOAP structuring step — it has its own prompt file.
## Forbidden debugging behaviors
### Never debug against prod data
- Reproducing a bug requires reproducing the data, not the live row.
- Export the row from prod, anonymize, load into sandbox, debug there.
- The only exception: a read-only `SELECT` to confirm a row exists. Anything beyond that goes to sandbox.
### Never paste prod credentials into chat
- API keys, service role keys, JWTs, connection strings stay in env files and secret managers.
- If you need to debug an auth issue, describe the shape of the problem; the keys never leave the secure boundary.
### Never "fix" a failing test by deleting it
- A failing test is information. Understand what it's telling you.
- If the test is genuinely wrong, fix the test with a commit message explaining why — never silently delete.
### Never patch around an invariant
- If a fix requires bypassing `clinician_attested`, RLS, or the anti-fabrication preamble, stop. The invariant is more important than the bug. Find a different fix.
## Debugging output discipline
- When investigating, log structured data (the relevant IDs, timestamps, hashes), not free-text "let me check this."
- Remove all `print` / `console.log` debug output before commit. Use the proper logger if logging needs to persist.
- For LLM debugging: log the full message array (system + user) at least once, then summarize subsequent calls.
## Anti-rationalizations (Cue-specific)
| Excuse                                                       | Counter |
|--------------------------------------------------------------|---------|
| "I'll just query prod read-only to check"                    | Reads are fine if truly read-only. The slip happens when "just one quick update" follows. Sandbox. |
| "Deleting the failing test, it was for an old version"       | Then it has a commit explaining that. Never silent deletion. |
| "Bypassing attestation just for this debug session"          | The bypass code merges by accident. Don't write it in the first place. |
| "The bug only repros on prod data"                           | Anonymize and load to sandbox. The bug never repros on prod safely. |
