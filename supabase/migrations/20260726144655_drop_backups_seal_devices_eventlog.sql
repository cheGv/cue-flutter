-- Task F (approved 2026-07-26) — three pieces:
--
-- 1. DROP the two spent one-time repair backups. Audited: both 0 rows,
--    no FKs in or out, no function/view/trigger, no repo/proxy
--    reference. Guarded: the drop aborts if either table has grown a
--    row since the audit.
-- 2. Seal security_trusted_devices (slp_owns_row). Zero readers today;
--    sealing lands BEFORE the trusted-device feature ships so a forged
--    row can never arrive pre-trusted.
-- 3. Seal clinical_event_log INSERT + SELECT ONLY (slp-scoped). No
--    update or delete policy for ANY client role — rows are immutable
--    through PostgREST, preserving chain_hash integrity.

do $$
begin
  if (select count(*) from public._ltg_seq_repair_backup) > 0 then
    raise exception 'ABORT: _ltg_seq_repair_backup is no longer empty';
  end if;
  if (select count(*) from public._priya_cleanup_backup_20260516) > 0 then
    raise exception 'ABORT: _priya_cleanup_backup_20260516 is no longer empty';
  end if;
end $$;
drop table public._ltg_seq_repair_backup;
drop table public._priya_cleanup_backup_20260516;

alter table public.security_trusted_devices enable row level security;
drop policy if exists "slp_owns_row" on public.security_trusted_devices;
create policy "slp_owns_row" on public.security_trusted_devices
  as permissive for all to authenticated
  using (slp_id = auth.uid())
  with check (slp_id = auth.uid());

alter table public.clinical_event_log enable row level security;
drop policy if exists "slp_inserts_own_events" on public.clinical_event_log;
create policy "slp_inserts_own_events" on public.clinical_event_log
  as permissive for insert to authenticated
  with check (slp_id = auth.uid());
drop policy if exists "slp_reads_own_events" on public.clinical_event_log;
create policy "slp_reads_own_events" on public.clinical_event_log
  as permissive for select to authenticated
  using (slp_id = auth.uid());
