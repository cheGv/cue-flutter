# cue-addendum.md — test-driven-development
This addendum overlays Addy Osmani's test-driven-development skill with Cue-specific requirements. Read both files together.
## Where TDD is non-negotiable in Cue
A failing test must exist before implementation when the code touches:
- `clinician_attested` (any read, write, or filter)
- Soft-delete filters (`deleted_at` IS NULL behavior)
- RLS policies (test as the unauthorized role)
- The narrator's structured-output schema
- Anti-fabrication paths (deliberately thin input → "insufficient information" response)
- Domain-tag enums (the closed 8-domain taxonomy)
- The Render proxy's PHI de-identification logic
- Any code path that decides whether content appears on a parent-facing surface
For other code (UI polish, internal refactors, dev tools), TDD is preferred but not gated.
## Test types and where they apply
### Failing-test-first (red → green → refactor)
Mandatory for the list above. The failing test must prove that the *naive implementation would silently violate an invariant* — not just that the function returns the right value, but that the wrong behavior would actually leak through.
Example: for `clinician_attested`, the failing test isn't "the attested field is set correctly." It's "an unattested row does NOT appear in the parent-facing query."
### Golden tests (Flutter widget visual contracts)
Required for:
- Goal ladder cards (any of them)
- Chart goal ladder
- Report views in the three-tier report architecture
- Today view
- Any component with a documented visual contract in `_cue-native/design-system`
Golden test diffs are reviewed visually, not just accepted. A passing golden test with a changed image is still a contract change.
### Contract tests (Edge Functions, proxy boundary)
Every Edge Function has a contract test that hits it through the Render proxy (`https://cue-ai-proxy.onrender.com`), not directly via the Supabase function URL. The proxy IS the integration surface; testing past it tests the wrong thing.
### Anti-fabrication tests
For every LLM-backed generator:
- Test 1: deliberately thin input → response is the structured "insufficient information" state.
- Test 2: that state survives the full round-trip to UI without being silently coerced to null/empty/default.
- Test 3: a request that would tempt fabrication (asks for a normative milestone) returns refusal or citation, never invented data.
## Anti-rationalizations (Cue-specific)
| Excuse                                                              | Counter |
|---------------------------------------------------------------------|---------|
| "I'll add the attestation test after the feature works"             | Then attestation will silently break in production. Failing test first or not at all. |
| "RLS is enforced by Postgres, no need to test"                      | Untested RLS is unverified RLS. Run the query as the wrong role. |
| "Golden test is too brittle for this UI"                            | Then the design isn't stable enough to ship. Stabilize, then golden. |
| "Anti-fabrication test is hard to write, the LLM is non-deterministic" | Test the *contract* (schema, refusal state), not the *content*. The contract is deterministic. |
| "Edge Function works in the Supabase dashboard"                     | The dashboard isn't the production path. Test via the proxy. |
## Evidence the TDD discipline is being followed
For any change to a gated file, the commit history shows:
1. A test commit that fails CI.
2. An implementation commit that turns it green.
3. Optionally a refactor commit.
Squashed commits that hide this sequence are acceptable in the merged branch but the sequence must have existed during development. "I wrote them at the same time" is a yellow flag — the failing-first step is the whole point.
