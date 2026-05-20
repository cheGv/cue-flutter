-- Cue Recall Assistant — precomputed-card cache + dirty-flag triggers.
--
-- Architecture (locked 2026-05-19):
--   1. recall_cards = one row per client holding the assembled recall
--      payload as jsonb.
--   2. AFTER INSERT/UPDATE/DELETE triggers on sessions /
--      short_term_goals / long_term_goals mark the affected client's
--      card dirty. Triggers DO NOT compute card content.
--   3. The recall-card edge function reads the row; if dirty (or
--      absent), it runs the direct indexed queries, assembles the
--      verbatim payload, writes it back with is_dirty=false. Assembly
--      logic lives in code (evolvable), never in the trigger.
--
-- Born-protected: RLS enabled in this same migration, scoped to the
-- owning clinician via user_id = auth.uid() — mirrors
-- sessions/short_term_goals/long_term_goals policies (verified
-- against sandbox catalog on 2026-05-19).
--
-- Sandbox-only deploy. Production application is a separate gated
-- operation.

-- ─────────────────────────────────────────────────────────────────
-- 1. recall_cards table
-- ─────────────────────────────────────────────────────────────────

create table if not exists public.recall_cards (
  client_id   uuid primary key
              references public.clients(id) on delete cascade,
  user_id     uuid not null,
  card        jsonb,
  is_dirty    boolean not null default true,
  updated_at  timestamptz not null default now()
);

comment on table public.recall_cards is
  'Per-client recall card cache. Marked dirty by triggers on sessions/short_term_goals/long_term_goals; assembled lazily by the recall-card edge function on first read after dirty. RLS-scoped to the owning clinician (user_id = auth.uid()).';

comment on column public.recall_cards.card is
  'Verbatim recall payload: last session (date, accuracy counts, parent_update, home_programme, soap_note, notes) + active STGs + active LTGs. No truncation, no model-generated content.';

create index if not exists recall_cards_user_idx
  on public.recall_cards (user_id);

-- Partial index over rows that need recomputation. Lets a future
-- background refresher (if ever added) scan only dirty cards per
-- clinician without filtering the whole table. Optional but cheap.
create index if not exists recall_cards_dirty_idx
  on public.recall_cards (user_id, updated_at desc)
  where is_dirty;

-- ─────────────────────────────────────────────────────────────────
-- 2. RLS — enabled in this same migration, never a separate step
-- ─────────────────────────────────────────────────────────────────

alter table public.recall_cards enable row level security;

create policy recall_cards_clinician_select
  on public.recall_cards
  for select
  using (user_id = auth.uid());

create policy recall_cards_clinician_insert
  on public.recall_cards
  for insert
  with check (user_id = auth.uid());

create policy recall_cards_clinician_update
  on public.recall_cards
  for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy recall_cards_clinician_delete
  on public.recall_cards
  for delete
  using (user_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────
-- 3. Trigger function — mark-stale ONLY, no card assembly
-- ─────────────────────────────────────────────────────────────────
--
-- SECURITY DEFINER + fixed search_path:
--   • The trigger must succeed regardless of the calling session's
--     RLS context (clinician JWT, Render proxy with forwarded JWT,
--     admin/service-role maintenance). Definer rights bypass the
--     recall_cards RLS check for this single deterministic upsert.
--   • search_path locked to (public, pg_temp) per the standard
--     SECURITY DEFINER hygiene rule — prevents search-path attacks.
--   • The function reads/writes ONE table (recall_cards) and never
--     touches the three source tables, so it cannot recurse and
--     cannot escalate beyond marking a dirty bit.

create or replace function public.mark_recall_card_dirty()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_client_id uuid;
  v_user_id   uuid;
begin
  if (tg_op = 'DELETE') then
    v_client_id := old.client_id;
    v_user_id   := old.user_id;
  else
    v_client_id := new.client_id;
    v_user_id   := new.user_id;
  end if;

  -- Defensive guard: a malformed row with no client_id cannot map
  -- to a card. Return without raising so the parent INSERT/UPDATE
  -- /DELETE on the source table is never blocked by trigger logic.
  if v_client_id is null then
    return coalesce(new, old);
  end if;

  -- Upsert: create or flip the affected client's card dirty bit.
  -- user_id is updated on conflict so a client transfer (rare edge
  -- case) re-anchors ownership at the next mutating write.
  insert into public.recall_cards (client_id, user_id, is_dirty, updated_at)
  values (v_client_id, v_user_id, true, now())
  on conflict (client_id) do update
    set is_dirty   = true,
        user_id    = coalesce(excluded.user_id, public.recall_cards.user_id),
        updated_at = now();

  return coalesce(new, old);
end;
$$;

comment on function public.mark_recall_card_dirty() is
  'AFTER trigger — marks the affected client''s recall_cards row dirty. NEVER computes card content; assembly lives in the recall-card edge function. SECURITY DEFINER with locked search_path so the dirty-flag write succeeds under every caller context (clinician JWT, proxy, service-role).';

-- ─────────────────────────────────────────────────────────────────
-- 4. Triggers — three source tables, one shared function
-- ─────────────────────────────────────────────────────────────────

drop trigger if exists trg_recall_card_dirty_sessions on public.sessions;
create trigger trg_recall_card_dirty_sessions
  after insert or update or delete on public.sessions
  for each row execute function public.mark_recall_card_dirty();

drop trigger if exists trg_recall_card_dirty_stg on public.short_term_goals;
create trigger trg_recall_card_dirty_stg
  after insert or update or delete on public.short_term_goals
  for each row execute function public.mark_recall_card_dirty();

drop trigger if exists trg_recall_card_dirty_ltg on public.long_term_goals;
create trigger trg_recall_card_dirty_ltg
  after insert or update or delete on public.long_term_goals
  for each row execute function public.mark_recall_card_dirty();
