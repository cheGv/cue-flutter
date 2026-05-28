# cue-addendum.md — test-driven-development
Overlay on Addy Osmani's TDD skill. Read both.
## Failing-test-first is mandatory when code touches
- `clinician_attested` (read, write, or filter) — `clinical-invariants`
- Soft-delete filters (`deleted_at`) — `supabase-data-layer`
- The narrator's / any LLM generator's structured-output schema
- Anti-fabrication paths: thin input → "not documented", never a fabricated value
- Multilingual fidelity: child productions preserved verbatim, never translated
- `language-discipline` output templates: a forbidden-words / Stance-1 regression must fail a test
## When RLS tests apply
RLS is currently DISABLED on goals tables (`supabase-data-layer`). The "query as unauthorized role → zero rows" test is the **post-re-enable** standard. Write it as part of the RLS re-enable migration; it gates onboarding. Don't assert it passes today.
## Test types
- **Golden tests** for visual contracts: goal-ladder cards, chart goal ladder, report views, Today view. A passing golden with a changed image is still a contract change — review the diff.
- **Contract tests** for proxy endpoints: hit via the Render proxy (`http.post`), never `functions.invoke()`, never the direct Supabase function URL.
- **Anti-fabrication tests:** thin input → structured "not documented"; that state survives round-trip to UI without coercion to null/empty.
## Anti-rationalizations
| Excuse | Counter |
|---|---|
| "I'll add the attestation test after it works." | Attestation breaks silently in prod otherwise. Failing test first. |
| "RLS is enforced by Postgres." | RLS is OFF right now. The test is for when it's re-enabled. |
| "Anti-fabrication is hard to test, the LLM is non-deterministic." | Test the contract (schema, refusal state), not the content. The contract is deterministic. |
