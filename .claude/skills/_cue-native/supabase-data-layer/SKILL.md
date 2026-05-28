# Skill: supabase-data-layer
## When to use
Triggered when the task involves:
- Writing or reading from Supabase tables
- Schema changes, migrations, or RLS policies
- Auth, user/clinician/patient relationships
- Edge Functions that hit the database
- Any query that touches patient-scoped data
## The invariants
### S1. Prod and sandbox project IDs are explicit, always
Cue runs two Supabase projects:
- **Prod:** `cgnjbjbargkxtcnafxaa`
- **Sandbox:** `uuqhusmgoiaxdvtgbmwh`
Every migration file, env file, and connection string must explicitly name which project it targets. No relying on "current default." Confusion between these two is a destructive-mistake vector.
### S2. RLS is mandatory on every patient-scoped table
If a table contains data tied to a specific patient, clinician, or session, it has Row Level Security enabled with policies that prove unauthorized roles return zero rows.
- New tables ship with RLS enabled and a deny-by-default policy.
- Policies are tested via a query executed as the wrong role.
- "Service role for now, RLS later" is not a path. RLS first, always.
### S3. Soft-delete is enforced at the query layer
See `clinical-invariants` I2. Concretely:
- Patient-scoped tables include a `deleted_at TIMESTAMPTZ NULL` column.
- Default views/queries filter `deleted_at IS NULL`.
- The Flutter data layer (repository/service classes) applies this filter — UI code never has to remember.
- Restore = setting `deleted_at = NULL`.
### S4. clinician_attested gating is enforced at the query layer
Tables holding AI-generated clinical content (notes, narrator output, suggested goals) include `clinician_attested BOOLEAN NOT NULL DEFAULT FALSE` and `attested_at`, `attested_by`, `attested_content_hash`.
- Default queries for clinical surfaces filter `clinician_attested = true`.
- Draft surfaces (the attestation review screen) explicitly include unattested rows.
- Exports, parent surfaces, billing, analytics never include unattested rows.
### S5. Migrations are idempotent and reviewed
- Every migration is a SQL file checked into the repo.
- Migrations are written so re-running on a fresh DB produces the same final state.
- Destructive migrations (DROP, TRUNCATE, ALTER without IF EXISTS, type changes that risk data loss) require explicit Guru confirmation — see `migration-discipline`.
### S6. Edge Functions are versioned and contract-tested
- Edge Function source lives in the repo.
- Each function has a contract test that hits it through the Render proxy.
- Deployment is via the Supabase CLI, not the dashboard's web editor.
## Anti-rationalizations
| Excuse                                                          | Counter |
|-----------------------------------------------------------------|---------|
| "I'll connect directly to prod just for this read"              | No. Sandbox first, always. Even reads. The habit is the safety. |
| "RLS is hard to debug, I'll add it before launch"               | RLS is harder to retrofit than to write upfront. Add it now. |
| "Hard delete just for cleaning up test data"                    | Use sandbox. Or write a fixture-reset script. App code never hard-deletes. |
| "This query doesn't need the deleted_at filter, the UI filters" | Defense in depth. Filter at the repository layer too. Never trust the UI to remember. |
| "The migration is small, I'll write it directly in psql"        | Then it's not versioned. Every change is a migration file in the repo, period. |
| "Edge Function edit is faster in the dashboard"                 | Faster today, untrackable tomorrow. CLI deploy from versioned source. |
## Evidence of compliance
Before considering a data-layer change complete, produce:
- The migration file path and contents.
- For RLS-touching changes: a test query as an unauthorized role returning zero rows.
- For new patient-scoped tables: confirmation `deleted_at` column exists and default query filters it.
- For AI-content tables: confirmation `clinician_attested` column exists and default query filters it.
- For Edge Functions: contract test hitting the function via the Render proxy.
- For schema changes that touched data: a row count before/after to prove no silent loss.
