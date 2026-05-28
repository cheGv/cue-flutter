# Skill: clinical-invariants
## When to use
Triggered any time code touches:
- The `goals` table (LTG, STG, regulatory cascade)
- Session notes, narrator output, or any AI-generated clinical text
- The `clinician_attested` field or attestation flow
- Patient demographics, diagnoses, or domain tags
- Soft-delete or restore flows
- Vocabulary suggestions, milestone references, normative data
- Any path where AI output is shown to a clinician or persisted
## The invariants
### I1. clinician_attested is a one-way gate, not a checkbox
AI-generated content lives in a draft state until a clinician reviews and attests.
- Draft rows MUST NOT appear in: exports, reports, parent-facing surfaces, billing, analytics dashboards.
- Attestation records: `clinician_id`, `attested_at` (timestamp), `content_hash` at attestation time.
- If the content is edited after attestation, the attestation is invalidated and must be re-acquired.
- There is no "auto-attest" path. Not for power users, not for trusted clinicians, not for batch import, not ever.
- The default query for any clinical surface filters `clinician_attested = true` unless the surface explicitly exists to show drafts to the attesting clinician.
### I2. Soft delete is the only delete in app code
`deleted_at IS NOT NULL` removes a row from all default queries.
- There is no hard-delete UI path.
- All queries against patient-scoped tables filter `deleted_at IS NULL` by default.
- A restore flow must exist for every soft-deletable entity.
- DPDP "right to erasure" requests are the ONLY hard-delete path. They go through a separate admin script in a separate repo, NOT through the app.
### I3. The 8-domain goal taxonomy is closed
Domains: **Regulation, Communication, Language, Speech, Feeding, Social, Cognitive, Motor.**
- No new domain can be added without a product decision recorded in `/docs/decisions/`.
- Regulation-first: the Regulation domain ALWAYS renders first in goal ladders, dashboards, and reports.
- Domain tags on patients, goals, and sessions reference this enum, never freeform strings.
- Sub-domains within a domain are also enum-bounded — confirm with Guru before inventing.
### I4. AI anti-fabrication
The narrator and any LLM-backed clinical generator must:
- Refuse to invent vocabulary, milestone ages, normative data, or assessment scores.
- Return a structured "insufficient information" response rather than confabulate.
- Cite the source field for any factual claim (session transcript timestamp, prior note ID, assessment reference).
- Never generate diagnoses. SLPs diagnose. The AI structures and surfaces.
- Treat any quoted "normative" data without a citation as a fabrication signal, even if it sounds correct.
### I5. Clinical surfaces show provenance
For any AI-touched field visible to the clinician:
- The UI shows the source (transcript, prior session, manual entry) on hover or expand.
- "AI-suggested" is always visually distinct from "clinician-entered" until attestation.
- Post-attestation, the source remains in the audit trail even if no longer surfaced in default UI.
## Anti-rationalizations
| Excuse                                                  | Counter |
|---------------------------------------------------------|---------|
| "It's just for the demo, attest later"                  | Demo data lives in seed scripts, not the schema's normal path. Never bypass attestation on real schema. |
| "The clinician already said yes verbally"               | Attestation is a database fact with a timestamp and content hash, not a conversation. |
| "Hard delete is cleaner for the dev DB"                 | Use the sandbox project. Never branch the delete semantics. |
| "Adding a quick domain tag for this one feature"        | If it's not in the 8-domain enum, it's a product decision, not a code change. Stop and ask Guru. |
| "The model is confident, we can skip the citation"      | Confidence ≠ correctness in clinical text. Cite or refuse. |
| "It's a small vocabulary suggestion, not a diagnosis"   | AAC vocab suggestions are clinical decisions. Cite the source (transcript line, prior session, manual). |
| "Showing provenance clutters the UI"                    | Then the UI design is wrong. Provenance is non-negotiable for AI-touched clinical surfaces. |
## Evidence of compliance
Before considering a clinical-surface change complete, produce:
- A failing test that proves the invariant *would have been* violated by the old/naive code, plus the passing test after the fix.
- For RLS-touching changes: a query executed as an unauthorized role that returns 0 rows.
- For attestation-touching changes: a draft row that does NOT leak into any of {parent surface, export, billing, analytics, default clinician dashboard}.
- For AI-generation changes: a test where the model is given deliberately insufficient input and the response is structured "insufficient information," NOT silently null/empty/fabricated.
- For taxonomy changes: a recorded decision in `/docs/decisions/` referenced from the migration.
