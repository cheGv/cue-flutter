Read CLAUDE.md fully before starting. Then apply the additive migration
defined in §8 of CLAUDE.md to the Supabase project `cgnjbjbargkxtcnafxaa`
using the Supabase MCP `apply_migration` tool.

Name the migration `20260419_add_stg_memory_layer`.

After applying, verify by:
1. Calling `list_tables` to confirm `short_term_goals` and `stg_evidence`
   exist with every column specified in §8.
2. Confirming the four new columns on `sessions` exist:
   `ai_generated`, `clinician_attested`, `attested_at`, `attested_by`.
3. Inserting one dummy STG row, updating it, confirming `updated_at`
   advances (trigger `trg_stg_updated` is live), then deleting the row.
4. Confirming the `accuracy_pct` generated column on `stg_evidence`
   computes correctly for a test row.

Hard rules:
- Do NOT enable RLS (§11 — remains disabled for prototype).
- Do NOT alter any existing rows in `patients`, `long_term_goals`, or `sessions`.
- If any step fails, roll back and report. No partial migrations.

Report the final state as a pass/fail checklist.