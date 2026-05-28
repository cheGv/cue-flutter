# cue-addendum.md — security-and-secrets
Overlay on Addy Osmani's security-and-hardening skill (upstream renamed from security-and-secrets). Read both. The upstream "Secrets Management" + "Broken Authentication/Access Control" sections are what this overlays.
## Cue's threat model
1. PHI leak via LLM prompts — names/identifiers reaching Anthropic logs.
2. Cross-tenant leak — and note RLS is currently DISABLED on goals tables, so isolation is NOT yet enforced (`supabase-data-layer`). Re-enabling RLS is the hard gate before onboarding real clinicians.
3. Pre-attestation content reaching parents/exports.
4. Credential exposure (Anthropic key, Supabase service-role key) in client code or git history.
5. Destructive prod migration (`migration-discipline`).
## DPDP Act compliance (non-negotiable)
- Consent recorded at patient onboarding (timestamp, scope, clinician witness).
- Right-to-erasure is the ONLY hard-delete path — separate admin script, explicit Guru approval, full backup, audit log. App code never hard-deletes.
- Data minimization: don't send Anthropic/Whisper anything not strictly required.
## PHI in prompts
The proxy de-identifies before forwarding (names/addresses/identifiers → opaque tokens); re-identify client-side. Keep clinical observations (the signal); strip identifiers. Audio transcripts may contain spoken identifiers — treat as PHI, de-identify the transcript before the SOAP-structuring step.
## Secrets
| Secret | Lives in | Never in |
|---|---|---|
| Anthropic API key | Render proxy env | client, repo, logs |
| Supabase service-role key | proxy env + Edge Function env | client, repo, logs |
| Supabase anon key | client config | (anon is safe-public) |
| Whisper/OpenAI key | proxy env | client, repo, logs |
A secret committed once is compromised — rotate it; history rewrite doesn't undo a leak. `.env` gitignored; `.env.example` documents keys without values.
