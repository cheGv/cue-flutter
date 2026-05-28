# cue-addendum.md — api-and-interface-design
Overlay on Addy Osmani's API-design skill. Read both.
## Cue's topology
```
Flutter (C:\projects\cue) --http.post--> Render proxy (C:\dev\cue\proxy) --> Anthropic
                                              |
Supabase Edge Functions / DB <---------------+
```
Two repos, two pipelines (`repo-and-path-topology`). The proxy and Edge Functions are the contract surfaces.
## The proxy contract
- Holds the Anthropic key; applies the anti-fabrication preamble; de-identifies PHI; rate-limits; logs (version + SHA256 per call). Details in the proxy's `prompt-discipline`.
- Flutter calls it via plain `http.post` — NEVER `functions.invoke()` (JWT ES256/HS256 mismatch).
- `/health` exists for Render wake checks (free tier sleeps).
- Versioning is additive: once a shape ships, don't break it; add fields with defaults.
## Edge Function contract
- Versioned source in-repo; CLI deploy, not dashboard editing.
- Structured JSON in/out with explicit schemas; structured errors (`error_code` + message), never raw stack traces.
- The Narrator returns SOAP drafts with `clinician_attested = false` always on creation; attestation is a separate call.
- Idempotency keys on create/modify functions (network retries shouldn't double-write a note).
## Error states the Flutter client must distinguish
Proxy-down (Render asleep) vs Anthropic-upstream error vs domain error (PHI rejection, schema-validation fail). Three different UI renderings — don't collapse into "something went wrong."
