-- Task D (urgent) — seal data_export_requests + account_deletion_requests.
-- archive_url points at a full clinical-data export and
-- cancellation_token is a bearer capability; neither may be
-- anon-readable. slp_owns_row shape, matching the 15 slp_* tables:
-- for all to authenticated, slp_id = auth.uid(). Both tables are
-- 0 rows with no code writers yet (schema-ahead-of-feature), so no
-- write path can break.

alter table public.data_export_requests enable row level security;
drop policy if exists "slp_owns_row" on public.data_export_requests;
create policy "slp_owns_row" on public.data_export_requests
  as permissive for all to authenticated
  using (slp_id = auth.uid())
  with check (slp_id = auth.uid());

alter table public.account_deletion_requests enable row level security;
drop policy if exists "slp_owns_row" on public.account_deletion_requests;
create policy "slp_owns_row" on public.account_deletion_requests
  as permissive for all to authenticated
  using (slp_id = auth.uid())
  with check (slp_id = auth.uid());
