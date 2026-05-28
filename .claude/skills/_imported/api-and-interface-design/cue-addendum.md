# cue-addendum.md — api-and-interface-design
This addendum overlays Addy Osmani's api-and-interface-design skill with Cue-specific contracts. Read both files together.
## Cue's integration topology
```
Flutter Web client
        │
        ▼
Render proxy ───────────────► Anthropic API
        │
        ▼
Supabase Edge Functions ───► Supabase Postgres
```
The proxy and the Edge Functions are the two contract surfaces that matter. Get them right; everything else flows.
## The Render proxy contract
### What the proxy does
- Holds the Anthropic API key (the client never sees it).
- Applies the anti-fabrication system prompt preamble.
- De-identifies PHI from the request body before forwarding.
- Re-identifies and returns the response to the client.
- Rate-limits and logs requests.
### Endpoints
- `POST /v1/messages` — proxies to Anthropic Messages API.
- `GET /health` — returns 200 if alive (used for Render wake checks).
- Future endpoints: keep them additive and versioned (`/v2/...`), never breaking changes to `/v1/...`.
### Versioning rule
- The proxy is a public-facing boundary for the Flutter client.
- Once an endpoint shape ships, it does not change. Add new fields with sensible defaults; deprecate by introducing new paths.
- A breaking change to the proxy is a Flutter release coordinated with a proxy release. Coordinate explicitly.
## The Edge Function contract
### Design rules
- Edge Functions are versioned by URL or by a `version` query param — pick one and be consistent.
- Inputs and outputs are JSON-shaped with explicit schemas (TypeScript types in the function source).
- Errors return structured JSON with `error_code` and `message`, never raw stack traces.
- Idempotency: any function that creates or modifies data accepts an `idempotency_key` and dedupes server-side.
### The Narrator function
- Input: audio file reference + session context + clinician ID.
- Output: structured SOAP note draft (`clinician_attested = false` always on creation).
- Never returns a SOAP note marked attested. Attestation is a separate API call.
### Contract tests
Every Edge Function has a contract test that:
1. Hits it via the Render proxy or a direct invocation depending on use.
2. Asserts the response shape against the documented schema.
3. Asserts the side effects (DB writes) match the contract.
## Flutter ↔ proxy contract
### Client-side rules
- Never construct Anthropic request bodies in the client. The client sends a Cue-domain request (e.g., "narrate this audio for session X"); the proxy translates.
- Never hold the Anthropic API key in the client. Not in env files, not in obfuscated form, never.
- Client request bodies are versioned via a `client_version` header so the proxy can handle legacy clients gracefully.
### Error handling
- The client must handle three distinct error states from the proxy:
  - Network / proxy down (Render asleep, network issue).
  - Anthropic upstream error (rate limit, model overloaded).
  - Domain error (PHI rejection, schema validation failure).
- These three render differently in UI. Don't collapse them into "something went wrong."
## Anti-rationalizations (Cue-specific)
| Excuse                                                          | Counter |
|-----------------------------------------------------------------|---------|
| "I'll let the client construct the Anthropic request shape"     | That couples the client to the upstream API. Domain request → proxy translates. |
| "Edge Function can return a raw error message, it's just dev"   | Dev becomes prod. Structured errors from day one. |
| "Versioning the proxy is overkill, I'm the only client"         | Future-you with a new Flutter version is a second client. Version from day one. |
| "Idempotency is too much for the narrator, it's user-initiated" | Network retries happen. Without idempotency, a user gets two notes for one recording. |
| "I'll skip the contract test, the function works in dashboard"  | Contract tests catch shape drift the dashboard misses. Write them. |
## Evidence the contract discipline is being followed
- Proxy endpoints documented in a `PROXY.md` file in the proxy repo.
- Edge Function inputs/outputs documented as TypeScript types (the type IS the doc).
- Contract tests run in CI.
- Versioning header (`client_version`) populated by Flutter client builds.
- Error responses structured with `error_code` for every error path.
