# Skill: migration-discipline
## When to use
Triggered when the task involves:
- Any Supabase schema change (CREATE, ALTER, DROP)
- RLS policy changes
- Data backfills, mass updates, or column transforms
- Index creation or removal on large tables
- Anything you'd run with `supabase db push` or against the production database
This skill exists because the single most expensive solo-founder mistake is a destructive prod migration at 2am. The protocol is the safety.
## The invariants
### M1. Sandbox first, always
The sandbox project (`uuqhusmgoiaxdvtgbmwh`) exists for exactly this reason. Every migration runs against sandbox before it touches prod (`cgnjbjbargkxtcnafxaa`).
- Read-only migrations? Still sandbox first. The habit is the safety, not the technical necessity.
- "I'll skip sandbox just this once" is the sentence preceding every disaster. There is no "just this once."
### M2. Every migration is a file, checked in, named with timestamp
- Format: `supabase/migrations/YYYYMMDDHHMMSS_short_description.sql`.
- Never run ad-hoc SQL against prod via the dashboard SQL editor for schema changes.
- Reads via the SQL editor are fine. Writes that change schema or RLS are not.
### M3. Schema diff is reviewed before prod apply
Between sandbox apply and prod apply:
- Run a schema diff (sandbox vs prod) and read it line-by-line.
- Confirm only the intended changes appear.
- Anything unexpected = stop, do not proceed to prod.
### M4. Backup checkpoint before prod migration
Before applying any migration to prod:
- Take a `pg_dump` of the relevant tables (or the full DB for schema-wide changes).
- Save with a clear name: `prod_backup_YYYYMMDD_HHMM_before_<migration_name>.sql`.
- Backup must be confirmed complete before the migration starts.
### M5. Destructive migrations require explicit Guru confirmation
A migration is **destructive** if it includes any of:
- `DROP TABLE`, `DROP COLUMN`, `DROP CONSTRAINT`, `DROP INDEX` (non-trivially-rebuildable)
- `ALTER COLUMN ... TYPE` with potential data loss
- `TRUNCATE`
- Data-modifying `UPDATE` or `DELETE` without a tight `WHERE` clause
- Any change to an RLS policy that broadens access
For destructive migrations:
1. Pause and produce the migration SQL.
2. State explicitly: "this is destructive because [reason]."
3. State the rollback plan.
4. Wait for Guru's explicit "proceed" before applying to prod. "Sounds good" is not "proceed."
### M6. RLS changes are tested as the wrong role
Any RLS policy change is verified by running the relevant query as the role being restricted — and confirming zero rows return where expected.
- A passing RLS change without this test is not a passing RLS change.
### M7. No "tiny exceptions"
"It's a tiny change, I don't need to follow the protocol" is the canonical anti-pattern. Tiny changes are exactly when the protocol matters, because they're the ones you run on autopilot.
## Anti-rationalizations
| Excuse                                                       | Counter |
|--------------------------------------------------------------|---------|
| "It's just a column rename, sandbox is overkill"             | Renames break Flutter generated types, Edge Functions, and migration history. Sandbox first. |
| "I'll back up after the migration if anything goes wrong"    | After = too late. Backup before. |
| "Schema diff looked the same as my plan, applying"           | Read the diff line by line. The day you skim is the day there's an unintended drop. |
| "Adding an index can't break anything"                       | Index creation on a large prod table can lock writes for minutes. Sandbox confirms timing. |
| "RLS change is just opening up read for clinicians"          | "Just opening up" = broadening access. Test as the role being affected before prod. |
| "It's 11pm, just push it through and verify tomorrow"        | Stop. Sleep. Migrate in the morning. |
## Evidence of compliance
Before considering a migration complete, produce:
- Migration file path in `supabase/migrations/`.
- Sandbox apply output (success/failure + any warnings).
- Schema diff between sandbox and prod, reviewed.
- For destructive migrations: explicit Guru confirmation logged.
- For prod apply: backup file path and confirmation of completion BEFORE the migration ran.
- For RLS changes: test query as the affected role with expected zero-row or expected-row-count result.
- Post-apply: smoke test of the most-affected query path from the app to confirm nothing silently broke.
