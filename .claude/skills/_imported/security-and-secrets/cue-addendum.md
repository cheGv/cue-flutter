# cue-addendum.md — security-and-secrets
This addendum overlays Addy Osmani's security-and-secrets skill with Cue-specific PHI and DPDP requirements. Read both files together.
## The threat model Cue is designed against
1. **PHI leak via LLM prompts** — patient identifiable data appearing in API logs at Anthropic or in proxy logs.
2. **Cross-tenant data leak via missing RLS** — Clinician A seeing Clinician B's patients.
3. **Pre-attestation content reaching parents** — fabricated AI content surfacing as fact.
4. **Credential exposure** — Anthropic key or Supabase service role key in client code or git history.
5. **Destructive prod operation** — the migration-discipline failure mode.
This skill focuses on threats 1, 2, and 4. Threat 3 lives in `clinical-invariants` and `supabase-data-layer`. Threat 5 lives in `migration-discipline`.
## DPDP Act compliance — non-negotiable
The Digital Personal Data Protection Act, 2023 governs Cue's handling of patient data in India. Concrete requirements:
### Consent
- Every patient onboarded to Cue requires recorded consent from the appropriate guardian or the patient.
- Consent is stored as a row with timestamp, scope, and clinician witness.
- Withdrawal of consent triggers the right-to-erasure path.
### Right to erasure
- The ONLY hard-delete path in Cue's data layer.
- Lives in a separate admin script, not in the app.
- Runs against prod with explicit Guru approval, full backup, and audit log entry.
- Affects: patient row + all child rows (notes, goals, sessions, attestations).
- Does NOT affect: anonymized aggregate data already extracted for research.
### Data minimization
- Don't collect data Cue doesn't need.
- Don't store data longer than Cue needs.
- Don't send data to third parties (Anthropic, OpenAI for Whisper) that isn't strictly required.
## PHI handling in LLM prompts
### What counts as PHI
- Patient name, parent name, family relationships.
- Address, phone, email.
- Date of birth (year alone is acceptable if needed for age context).
- Photos of patient or family.
- School name, clinic name (if it identifies the patient).
- Any free-text field where the clinician may have written identifiers.
### De-identification rules
- The Render proxy de-identifies request bodies before forwarding to Anthropic.
- Replace identifiers with stable opaque tokens: `P_a3f2`, `G_b7e1` (patient, guardian).
- The mapping `P_a3f2 ↔ patient_uuid` is kept proxy-side, never logged.
- Re-identification happens client-side after the LLM response returns.
### What NOT to de-identify
- Clinical observations, behaviors, symptoms — these are the actual signal.
- Domain tags, goal text, attestation status.
- Generic age band ("8-year-old").
### Audio in PHI
- Audio sent to Whisper for narrator transcription may contain identifiers spoken aloud.
- The transcript returned must pass through de-identification before going to GPT-4o-mini for SOAP structuring.
- Raw audio is not retained after transcription unless explicitly needed for a specific feature with separate consent.
## Credentials and secrets
### What goes where
| Secret                          | Lives in                                | Never in       |
|---------------------------------|-----------------------------------------|----------------|
| Anthropic API key               | Render proxy env vars                   | Client, repo, logs |
| Supabase service role key       | Render proxy env + Edge Function env    | Client, repo, logs |
| Supabase anon key               | Client app config                       | (anon is safe public) |
| Whisper / OpenAI key            | Render proxy env vars                   | Client, repo, logs |
| Personal access tokens (GitHub, Render) | Local dev env, secret manager   | Repo, chat, logs |
### Practices
- Every secret has a documented rotation procedure.
- No secret in commit history. If a secret leaks into git, rotate it immediately — `git history rewrite` does not undo a leak; the secret is compromised.
- `.env` files are gitignored. `.env.example` files document required keys without values.
- New secrets added to the system require a corresponding entry in the rotation doc.
## RLS as a security boundary
- RLS is the primary defense for cross-tenant data isolation.
- Every patient-scoped table has RLS enabled with deny-by-default.
- Service-role queries bypass RLS — use them sparingly, only in Edge Functions, never in client code.
- Every RLS policy change is tested as the wrong role.
## Anti-rationalizations (Cue-specific)
| Excuse                                                              | Counter |
|---------------------------------------------------------------------|---------|
| "Patient name in the prompt gives the model better context"         | The model gets the same context from "the patient" + clinical observations. Names add nothing, add risk. |
| "I'll add DPDP consent flow before launch"                          | Consent is collected at onboarding. Retrofitting consent on existing rows is a compliance liability. |
| "Service role key in the client just for dev"                       | Dev branches merge. Service role key in any client code is a critical bug. |
| "RLS for this admin table is overkill"                              | "Admin" tables get attacked first. RLS or remove the table. |
| "I committed the .env once, but I'll just remove it in the next commit" | Git history persists. Rotate the keys. The commit doesn't matter; the leak does. |
| "Audio transcripts don't have PHI"                                  | They have whatever the clinician or patient said aloud. Treat as PHI by default. |
## Evidence the security discipline is being followed
For changes touching this skill's domain, produce:
- For new LLM-calling features: log proof that the request body sent to Anthropic contains no PHI (run a test prompt and inspect the forwarded body).
- For new tables: RLS enabled, policy tested as the wrong role.
- For new env vars: documented in `.env.example` and in the rotation doc.
- For DPDP-affecting changes (export, erasure, consent): explicit Guru sign-off recorded in `/docs/decisions/`.
