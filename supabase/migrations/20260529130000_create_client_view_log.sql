-- Client briefing — Layer 1: per-SLP "last viewed" anchor.
--
-- Records when a clinician last opened a client's chart so the briefing can
-- compute "since your last visit". Per-SLP per-client: two clinicians viewing
-- the same client keep INDEPENDENT timestamps (PK = user_id, client_id).
--
-- The briefing reads the PRIOR last_viewed_at (the value before this open) to
-- compute "since last visit", THEN the app upserts the new now(). Read-then-
-- write — see ClientViewLogRepository.readPriorThenRecord.
--
-- Born-protected: RLS enabled in THIS migration, scoped to the owning clinician
-- (user_id = auth.uid()) — mirrors recall_cards / sessions / *_goals.
--
-- Sandbox-only deploy. Production application is a separate gated operation.
--
-- ROLLBACK (reverse migration):
--   drop table if exists public.client_view_log;  -- drops its policies + index too

create table if not exists public.client_view_log (
  user_id        uuid        not null,
  client_id      uuid        not null
                 references public.clients(id) on delete cascade,
  last_viewed_at timestamptz not null default now(),
  primary key (user_id, client_id)
);

comment on table public.client_view_log is
  'Per-SLP per-client last-chart-open timestamp. The briefing reads the PRIOR value (before this open) to compute "since your last visit", then the app upserts the new now(). RLS-scoped to the owning clinician (user_id = auth.uid()).';

-- PK already covers (user_id, client_id) point lookups. This user-scoped,
-- time-ordered index supports a future "recently viewed clients" listing.
create index if not exists client_view_log_user_idx
  on public.client_view_log (user_id, last_viewed_at desc);

-- ── RLS — enabled in this same migration, never a separate step ──────────────
alter table public.client_view_log enable row level security;

create policy client_view_log_clinician_select
  on public.client_view_log for select
  using (user_id = auth.uid());

create policy client_view_log_clinician_insert
  on public.client_view_log for insert
  with check (user_id = auth.uid());

create policy client_view_log_clinician_update
  on public.client_view_log for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy client_view_log_clinician_delete
  on public.client_view_log for delete
  using (user_id = auth.uid());
