# CLAUDE.md — Cue AI
You are working on Cue AI, a clinical OS for speech-language pathologists.
Solo founder: Guru. Stack: Flutter Web + Supabase + Anthropic API via Render proxy.
This file is a ROUTER. Read it fully at the start of every session.
Load the relevant skill file BEFORE writing code for any triggered task.
---
## HARD INVARIANTS (never violate, no exceptions)
1. Never add performative labor to the SLP. (see: `_cue-native/product-law`)
2. AI-generated clinical content requires `clinician_attested` before persistence. (see: `_cue-native/clinical-invariants`)
3. Use `LayoutBuilder` for any width-responsive UI, never `MediaQuery`. (see: `_cue-native/flutter-layout`)
4. Patient data is soft-deleted via `deleted_at`, never hard-deleted in app code. (see: `_cue-native/supabase-data-layer`)
5. No PHI in LLM prompts without explicit de-identification. (see: `_cue-native/ai-integration`, `_imported/security-and-secrets`)
6. Every Supabase migration runs on sandbox before prod. No exceptions. (see: `_cue-native/migration-discipline`)
7. All Anthropic API calls go through the Render proxy. Never direct from client. (see: `_cue-native/ai-integration`)
---
## SKILL ROUTING
When a task matches a trigger, `view` the skill file FIRST, then proceed.
| If the task touches…                              | Load skill                                                          |
|---------------------------------------------------|---------------------------------------------------------------------|
| New feature, unclear scope, product decision      | `_imported/spec-driven-development` + `_cue-native/product-law`     |
| Writing or modifying production code              | `_imported/test-driven-development`                                 |
| Before opening a PR or self-review                | `_imported/code-review-and-quality`                                 |
| Bug, broken behavior, unexpected state            | `_imported/debugging-and-error-recovery`                            |
| Edge Function, proxy, or API contract changes     | `_imported/api-and-interface-design` + `_cue-native/ai-integration` |
| Auth, RLS, secrets, PHI, DPDP                     | `_imported/security-and-secrets`                                    |
| Clinical fields (goals, notes, attestation)       | `_cue-native/clinical-invariants`                                   |
| UI work (layout, components, responsiveness)      | `_cue-native/flutter-layout` + `_cue-native/design-system`          |
| Supabase queries, schema, RLS                     | `_cue-native/supabase-data-layer`                                   |
| Anthropic calls, prompts, structured output       | `_cue-native/ai-integration`                                        |
| Any schema change, RLS change, data backfill      | `_cue-native/migration-discipline`                                  |
Imported skills have a sibling `cue-addendum.md`. Read both when an imported skill is loaded.
---
## ENVIRONMENT
- Prod Supabase: `cgnjbjbargkxtcnafxaa`
- Sandbox Supabase: `uuqhusmgoiaxdvtgbmwh`
- Proxy: `https://cue-ai-proxy.onrender.com`
- Repos: `cheGv/cue-ai` (proxy), `cheGv/cue-flutter` (app)
- Local: `C:\projects\cue`
---
## WHEN UNSURE
Ask Guru. Do not invent:
- Clinical behavior, vocabulary taxonomies, normative milestone ages
- Attestation rules or who can attest
- Domain tags beyond the closed 8-domain enum
- Final brand marks (logo not locked)
- Migration steps (run sandbox first, always)
