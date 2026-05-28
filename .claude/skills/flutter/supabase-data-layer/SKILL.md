# Skill: supabase-data-layer
> **Flutter repo.** Documents what actually exists in Supabase project `cgnjbjbargkxtcnafxaa` (prod) today. Where this skill and an older doc disagree, the live database is the source of truth — read it, don't trust the doc.
## When to use
Triggered by: Supabase queries, schema changes, migrations, RLS, the clients/sessions/goals tables, Edge Functions hitting the DB, anything touching patient-scoped data.
## Projects
- **Prod:** `cgnjbjbargkxtcnafxaa`
- **Sandbox:** `uuqhusmgoiaxdvtgbmwh` (the **x** — verified against the dashboard and `lib/config/app_config.dart` `kSandboxProjectRef`)
Every migration file, env reference, and connection string explicitly names which project it targets. Confusion between these two is a destructive-mistake vector. (See `migration-discipline`.)
## The schema is prototype-real, not the idealized target
The canonical schema is **what exists in the prototype**, not an aspirational shape. Key facts a session must not get wrong:
- The roster table is **`clients`**, NOT `patients`.
- `sessions.id` is **`bigint`**, NOT `uuid`. Its FK is **`client_id`**, NOT `patient_id`.
- `short_term_goals` step shape is `specific + measurable + target_accuracy + time_bound_sessions`, NOT `target_behavior + mastery_criterion jsonb`.
- FKs on `short_term_goals` are `long_term_goal_id`, `client_id`, `user_id`.
> An earlier "canonical target" schema (with `patients`, `sessions.id uuid`, `mastery_criterion jsonb`) was **never migrated to.** Its DDL survives only in git history and the decision archive. **Do not reintroduce those column names in new code.** The Flutter data layer and the proxy both write the prototype shape.
Core tables: `clients` (soft-delete via `deleted_at`), `sessions` (carries `soap_note jsonb`, `parent_update`, attestation columns, `population_payload jsonb`), `long_term_goals`, `short_term_goals`, `goal_plans`, `goal_attestations`, `goal_evidence_tags`, `clinic_profile`, `narrator_transcripts`, `stg_evidence`, plus Phase 4.0 additive tables `case_history_entries` and `assessment_entries`. The Phase 4.0 multi-population JSONB pattern is detailed in `clinical-architecture`.
## RLS — the real current state (NOT aspirational)
> **RLS is currently DISABLED on the goals tables for the prototype.** This is the actual posture as of now. Do not write code or skills that assume RLS is on — it is not.
- The per-clinician isolation policy template exists (below) but is **parked**, not applied.
- **Re-enabling RLS is a HARD GATE before any external / founding-clinician onboarding.** No real clinician data goes into a multi-tenant context until RLS is on and tested.
- Until then, "test as the unauthorized role, expect zero rows" is the **post-re-enable** standard, not a check that passes today.
Parked policy template (apply to `short_term_goals`, `long_term_goals`, `stg_evidence`, `sessions`, `narrator_transcripts` before onboarding):
```sql
alter table short_term_goals enable row level security;
create policy stg_clinician_isolation on short_term_goals
  using (client_id in (
    select id from clients where clinician_id = auth.uid() and deleted_at is null
  ));
```
## Soft delete
`deleted_at IS NOT NULL` removes a row from default queries. No hard-delete UI path. The data layer (repositories/services) applies the filter so UI code never has to remember. Restore = set `deleted_at = NULL`. The only hard-delete path is a DPDP right-to-erasure admin script, separate from the app.
## Attestation gating at the query layer
Tables holding AI-generated clinical content carry `clinician_attested boolean default false` plus `attested_at`, `attested_by`. Default clinical-surface queries filter `clinician_attested = true`; the attestation-review surface explicitly includes drafts. (Clinical rule lives in `clinical-invariants`; this is its data-layer enforcement.)
## Migrations: the MCP-vs-CLI rule (critical)
Two paths apply migrations, and they behave differently:
- **MCP `apply_migration`** stamps the remote `schema_migrations` version with wall-clock apply time, not the repo filename → creates remote-vs-repo drift.
- **Supabase CLI `db push`** uses the filename version → keeps remote history filename-aligned.
**Rule:**
- MCP `apply_migration` is permitted **only for the sandbox project** (`uuqhusmgoiaxdvtgbmwh`).
- Any migration targeting **prod** (`cgnjbjbargkxtcnafxaa`) **MUST** be applied via `supabase db push` from the repo, so remote history stays filename-aligned.
- Sandbox drift is accepted; do not try to realign sandbox remote history with filenames.
**Migration naming:** 14-digit `YYYYMMDDHHMMSS` timestamps. Disambiguate same-date siblings by shifting the time field (`…120000` → `…120200`), **never** a `_NN` suffix — `db push` orders by the numeric prefix before the first `_`, so a bare `YYYYMMDD_NN` sorts ahead of full-timestamp migrations and breaks a fresh apply.
(Full prod-migration safety protocol is in `migration-discipline`.)
## Anti-rationalizations
| Excuse | Counter |
|---|---|
| "RLS is on, so this query is safe." | RLS is OFF on goals tables right now. Don't assume isolation that doesn't exist yet. |
| "I'll use `patients` / `mastery_criterion jsonb`, that's the schema." | That target was never migrated to. The live shape is `clients` / `specific+measurable+...`. Read the DB. |
| "MCP apply_migration is quicker for this prod change." | MCP is sandbox-only. Prod goes through `db push`. Always. |
| "I'll name the migration `20260528_02`." | Breaks fresh-apply ordering. Use a full 14-digit timestamp; shift the time field for siblings. |
| "Hard delete cleans up the dev DB." | Use the sandbox project. App code never hard-deletes. |
## Evidence of compliance
- Migration file path + which project it targets, explicitly.
- For prod migrations: applied via `db push`, not MCP.
- For new patient-scoped tables: `deleted_at` present; default query filters it; RLS gate noted in the re-enable checklist.
- For schema work: confirmed against the live DB shape (`clients`, `bigint` session id), not the deprecated target.
