-- Tier 1 RLS sealing, Task 3 — generations (clinical AI generation
-- audit log). Not an assessment family: ownership is DIRECT via
-- clinician_id -> auth.users (verified: the Render proxy is the sole
-- writer through writeAuditRow/'/generate-report' behind requireAuth,
-- and every one of its six write paths — success, validation_error,
-- insufficient_content, and all upstream_error variants — sets
-- clinician_id from the verified req.user.id; no path can write NULL).
--
-- Shape (approved 2026-07-26): RLS on, ONE select policy to
-- authenticated (clinician_id = auth.uid()), NO insert/update/delete
-- policies. Writes remain service-role only (bypasses RLS), anon gets
-- nothing.

alter table public.generations enable row level security;
drop policy if exists "clinician_reads_own_generations" on public.generations;
create policy "clinician_reads_own_generations" on public.generations
  as permissive for select to authenticated
  using (clinician_id = auth.uid());
