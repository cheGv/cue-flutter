# cue-addendum.md — debugging-and-error-recovery
Overlay on Addy Osmani's debugging skill. Read both. Check these Cue-specific causes FIRST.
## Common Cue failure modes
- **CORS from the proxy:** Render free tier sleeps — hit `/health` first. Then check `ALLOWED_ORIGINS` includes the GitHub Pages / Netlify origin. Then CORS middleware order.
- **JWT / 401:** confirm Authorization header forwarded; check `exp`; confirm service-role vs anon key. Reminder: Flutter→proxy is `http.post`, never `functions.invoke()` (the ES256/HS256 mismatch).
- **LLM returns unexpected content:** read the actual prompt file (not your memory of it); log the full message array; confirm the anti-fabrication preamble is applied; confirm structured output requested.
- **Wrong rows from Supabase:** check `deleted_at IS NULL`; check `clinician_attested = true`; RLS is OFF on goals tables right now so it's NOT the cause there.
- **Layout breaks at some widths:** almost always `MediaQuery` where `LayoutBuilder` belongs.
- **Wrong file edited / no effect:** you may be in the wrong repo or editing the decoy CLAUDE.md. Run the `repo-and-path-topology` session-open checks.
## Forbidden debugging behaviors
- Never debug against prod data — anonymize a row into sandbox (`uuqhusmgoiaxdvtgbmwh`) and debug there. Read-only `SELECT` on prod to confirm existence is the only exception.
- Never paste prod credentials/keys/JWTs into chat.
- Never "fix" a failing test by deleting it — understand what it's telling you.
- Never patch around an invariant (attestation, anti-fabrication, language-discipline). The invariant outranks the bug.
