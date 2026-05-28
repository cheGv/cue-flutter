# Skill: migration-discipline
> **Flutter repo.** Exists because the single most expensive solo-founder mistake is a destructive prod migration. The protocol is the safety.
## When to use
Triggered by any Supabase schema change, RLS change, data backfill, index change, or anything run with `db push` / `apply_migration` against any project.
## The invariants
### M1. Sandbox first, always
- **Sandbox:** `uuqhusmgoiaxdvtgbmwh` (the **x** — verified against dashboard + `app_config.dart`).
- **Prod:** `cgnjbjbargkxtcnafxaa`.
- Every migration runs against sandbox before it touches prod. Read-only changes too — the habit is the safety. "Just this once" is the sentence before every disaster.
### M2. The MCP-vs-CLI prod rule (load-bearing)
- **MCP `apply_migration` is permitted ONLY for sandbox** (`uuqhusmgoiaxdvtgbmwh`).
- **Prod migrations (`cgnjbjbargkxtcnafxaa`) MUST go through `supabase db push`** from the repo, so remote `schema_migrations` history stays filename-aligned. MCP stamps wall-clock apply time and drifts prod history — which breaks prod migration reasoning under pressure later.
- Sandbox drift is accepted and not realigned.
### M3. Every migration is a versioned file
- `supabase/migrations/YYYYMMDDHHMMSS_description.sql`. Full 14-digit timestamp; shift the time field for same-date siblings, never a `_NN` suffix (it breaks fresh-apply ordering).
- No ad-hoc schema SQL via the dashboard editor. Reads via the editor are fine; schema/RLS writes are not.
### M4. Schema diff reviewed before prod apply
Between sandbox apply and prod `db push`: run a sandbox-vs-prod schema diff, read it line by line, confirm only intended changes appear. Anything unexpected → stop.
### M5. Backup checkpoint before prod
Before applying to prod: `pg_dump` the affected tables (or full DB for schema-wide changes), saved as `prod_backup_YYYYMMDD_HHMM_before_<name>.sql`, confirmed complete before the migration starts.
### M6. Destructive migrations require explicit Guru confirmation
Destructive = `DROP TABLE/COLUMN/CONSTRAINT`, non-trivial `DROP INDEX`, `ALTER COLUMN ... TYPE` with loss risk, `TRUNCATE`, `UPDATE`/`DELETE` without a tight `WHERE`, or any RLS change that broadens access. For these: produce the SQL, state why it's destructive, state the rollback plan, and wait for explicit "proceed" — "sounds good" is not "proceed."
### M7. RLS reality check
RLS is currently disabled on goals tables (see `supabase-data-layer`). When the re-enable migration finally runs, it is by definition access-affecting → treat as M6-destructive, test as the affected role (expect zero rows where restricted) on sandbox first, and it gates external onboarding.
### M8. No tiny exceptions
"It's a tiny change, skip the protocol" is the canonical anti-pattern. Tiny changes are run on autopilot — exactly when the protocol matters.
## Anti-rationalizations
| Excuse | Counter |
|---|---|
| "MCP apply_migration is faster for prod." | MCP is sandbox-only. Prod goes through `db push`. The drift it causes breaks future prod reasoning. |
| "It's a column rename, sandbox is overkill." | Renames break generated types, Edge Functions, and history. Sandbox first. |
| "I'll back up after, if something breaks." | After is too late. Backup before. |
| "The diff looked like my plan, applying." | Read it line by line. The day you skim is the day there's an unintended drop. |
| "It's 11pm, push it and verify tomorrow." | Stop. Sleep. Migrate in the morning. |
## Evidence of compliance
- Migration file path in `supabase/migrations/`.
- Sandbox apply output; for prod, confirmation it went via `db push`, not MCP.
- Schema diff (sandbox vs prod) reviewed.
- For destructive: explicit Guru "proceed" logged + rollback plan.
- For prod: backup file path confirmed complete BEFORE apply.
- Post-apply smoke test of the most-affected query path.
