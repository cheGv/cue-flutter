-- ============================================================================
-- CAS session-progress DATA SPINE  (Phase: CAS progress capture)
-- ============================================================================
-- The per-session progress counterpart to the one-time cas_assessments snapshot.
-- cas_session_progress stands beside cas_assessments exactly as stg_evidence
-- stands beside a goal: one row per (session x complexity level), capturing the
-- spine complexity (level) x accuracy x cue, repeated across sessions over time.
--
-- Three parts, mirroring proven shapes already in this schema:
--   1. cas_session_progress  — the capture table (mirrors cas_length_gradient's
--      level/accuracy shape + stg_session_metrics' (stg_id, session_id) keying).
--   2. cas_progress_brief + mark_cas_progress_brief_dirty() trigger — clones the
--      recall_cards dirty-flag cache (20260519120000): the trigger ONLY flips a
--      dirty bit, never assembles content.
--   3. assemble_cas_progress(uuid) -> jsonb — clones assemble_recall_card
--      (20260519130000): ONE SQL function, verbatim columns, no AI, no
--      fabrication. Postgres is the only serializer in the loop, so every
--      read path is byte-identical.
--
-- VERIFIED against source before authoring (2026-06-27):
--   * sessions.id is BIGINT  (stg_session_metrics.sql:10; phase_4_0_1.sql:44).
--   * short_term_goals.id is UUID  (stg_session_metrics.sql:9).
--   * accuracy check copied VERBATIM from cas_length_gradient
--     (20260529175527_phase_4_0_7_28_cas_assessment_surface.sql:74-75).
--   * client FK named client_id (NOT patient_id): mirrors the cas_* family this
--     table joins (cas_assessments.client_id, surface.sql:22). stg_evidence is
--     the lone schema outlier that names it patient_id; we do not follow it here.
--
-- RLS POSTURE — DELIBERATE DEFERRED DEBT (not silent):
--   RLS intentionally left off, matching cas_* and stg_session_metrics;
--   hardening is a later verified migration (verify clients ownership column
--   clinician_id vs user_id at that time).
--   NOTE: this is a documented deviation from recall_cards, which ships RLS ON
--   via its user_id column. cas_session_progress carries no user_id/clinician_id
--   to scope by, and deriving one requires the same clients-ownership-column
--   resolution being deferred above. The capture table and its brief cache
--   harden together in that later migration.
--
-- Additive only. Idempotent: CREATE ... IF NOT EXISTS. Sandbox-only deploy;
-- production application is a separate gated operation.
-- ============================================================================


-- ─────────────────────────────────────────────────────────────────
-- 1. cas_session_progress — the capture table
--    One row per (session x complexity level).
-- ─────────────────────────────────────────────────────────────────

create table if not exists public.cas_session_progress (
  id                  uuid        not null default gen_random_uuid(),
  stg_id              uuid        not null,
  session_id          bigint      not null,
  client_id           uuid        not null,
  level_label         text        not null,
  level_order         integer     not null,
  accuracy            text,
  cue_level_used      text,
  cue_level_used_raw  text,
  created_at          timestamptz not null default now(),
  constraint cas_session_progress_pkey primary key (id),
  constraint cas_session_progress_stg_id_fkey
    foreign key (stg_id) references public.short_term_goals(id) on delete cascade,
  constraint cas_session_progress_session_id_fkey
    foreign key (session_id) references public.sessions(id) on delete cascade,
  constraint cas_session_progress_client_id_fkey
    foreign key (client_id) references public.clients(id) on delete cascade,
  -- accuracy vocabulary copied VERBATIM from cas_length_gradient (surface.sql:74-75).
  constraint cas_session_progress_accuracy_check
    check (accuracy = any (array['accurate','partial','inaccurate'])),
  -- Re-capture upserts cleanly: one row per (session, stg, level). Extends
  -- stg_session_metrics' UNIQUE(stg_id, session_id) idea by complexity level.
  constraint cas_session_progress_uniq_session_stg_level
    unique (session_id, stg_id, level_order)
);

comment on table public.cas_session_progress is
  'Per-session CAS progress capture. One row per (session x complexity level): the spine complexity (level_label/level_order) x accuracy x cue (cue_level_used), repeated across sessions. Stands beside cas_assessments (the one-time snapshot) as stg_evidence stands beside a goal. RLS intentionally OFF — deferred debt, hardened in a later verified migration.';

comment on column public.cas_session_progress.level_label is
  'Complexity-ladder level name. Mirrors cas_length_gradient.level_label (no DB enum; canonical level names live in CAS app constants — e.g. CV, CVC, bisyllabic, trisyllabic, polysyllabic/phrase).';

comment on column public.cas_session_progress.cue_level_used is
  'CueLevel wire string: independent | minimal | moderate | maximal | hand_over_hand | unknown. No DB check (tolerant, like stg_evidence.cue_level_used); an unrecognized value is preserved in cue_level_used_raw.';

comment on column public.cas_session_progress.cue_level_used_raw is
  'Raw passthrough of the original cue value as captured, so an unexpected/non-canonical value survives a round-trip even when cue_level_used normalizes to unknown.';

create index if not exists idx_cas_session_progress_stg
  on public.cas_session_progress (stg_id, level_order);
create index if not exists idx_cas_session_progress_session
  on public.cas_session_progress (session_id);
create index if not exists idx_cas_session_progress_client
  on public.cas_session_progress (client_id);


-- ─────────────────────────────────────────────────────────────────
-- 2. cas_progress_brief — precomputed brief cache (one row per STG)
--    Clones the recall_cards dirty-flag pattern (20260519120000).
-- ─────────────────────────────────────────────────────────────────

create table if not exists public.cas_progress_brief (
  stg_id      uuid primary key
              references public.short_term_goals(id) on delete cascade,
  client_id   uuid,
  card        jsonb,
  is_dirty    boolean not null default true,
  updated_at  timestamptz not null default now()
);

comment on table public.cas_progress_brief is
  'Per-STG CAS-progress brief cache. Marked dirty by a trigger on cas_session_progress; assembled lazily by assemble_cas_progress(stg_id) on first read after dirty. Verbatim payload, no model-generated content. RLS intentionally OFF — deferred debt (see migration header); deviates from recall_cards, which ships RLS ON, because there is no user_id to scope by yet.';

comment on column public.cas_progress_brief.card is
  'Verbatim CAS-progress brief: the last N sessions (ordered by session date) each carrying their per-level accuracy + cue rows (ordered by level_order). No truncation, no AI, no fabrication.';

-- Partial index over rows needing recomputation (mirrors recall_cards_dirty_idx).
create index if not exists cas_progress_brief_dirty_idx
  on public.cas_progress_brief (updated_at desc)
  where is_dirty;


-- ─────────────────────────────────────────────────────────────────
-- 3. Trigger function — mark-stale ONLY, never assembles.
--    Mirrors mark_recall_card_dirty() exactly in shape
--    (SECURITY DEFINER + locked search_path; DELETE branch; null guard;
--    upsert; coalesce(new, old) return).
-- ─────────────────────────────────────────────────────────────────

create or replace function public.mark_cas_progress_brief_dirty()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_stg_id    uuid;
  v_client_id uuid;
begin
  if (tg_op = 'DELETE') then
    v_stg_id    := old.stg_id;
    v_client_id := old.client_id;
  else
    v_stg_id    := new.stg_id;
    v_client_id := new.client_id;
  end if;

  -- Defensive guard: a row with no stg_id cannot map to a brief. Return
  -- without raising so the parent write on cas_session_progress is never
  -- blocked by trigger logic.
  if v_stg_id is null then
    return coalesce(new, old);
  end if;

  -- Upsert: create or flip the affected STG's brief dirty bit. client_id is
  -- refreshed on conflict so it re-anchors at the next mutating write.
  insert into public.cas_progress_brief (stg_id, client_id, is_dirty, updated_at)
  values (v_stg_id, v_client_id, true, now())
  on conflict (stg_id) do update
    set is_dirty   = true,
        client_id  = coalesce(excluded.client_id, public.cas_progress_brief.client_id),
        updated_at = now();

  return coalesce(new, old);
end;
$$;

comment on function public.mark_cas_progress_brief_dirty() is
  'AFTER trigger — marks the affected STG''s cas_progress_brief row dirty. NEVER computes brief content; assembly lives in assemble_cas_progress(uuid). SECURITY DEFINER with locked search_path so the dirty-flag write succeeds under every caller context.';

drop trigger if exists trg_cas_progress_brief_dirty on public.cas_session_progress;
create trigger trg_cas_progress_brief_dirty
  after insert or update or delete on public.cas_session_progress
  for each row execute function public.mark_cas_progress_brief_dirty();


-- ─────────────────────────────────────────────────────────────────
-- 4. assemble_cas_progress — ONE SQL function, verbatim, no AI.
--    Clones assemble_recall_card (20260519130000): SECURITY INVOKER +
--    STABLE + locked search_path. Postgres is the only serializer, so
--    every read path is byte-identical.
--
--    Shape: { stg_id, assembled_at, sessions[] }
--    sessions[] = the last N (=3) sessions that have progress rows for this
--    STG, ordered by session date desc; each carrying levels[] ordered by
--    level_order. Empty -> '[]'::jsonb, never null.
-- ─────────────────────────────────────────────────────────────────

create or replace function public.assemble_cas_progress(p_stg_id uuid)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'stg_id',       p_stg_id::text,
    'assembled_at', to_jsonb(now()),
    'sessions', coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'session_id',   sess.session_id,
                 'session_date', sess.session_date,
                 'levels',       sess.levels
               )
               order by sess.session_date desc nulls last, sess.session_id desc
             )
      from (
        select s.id   as session_id,
               s.date as session_date,
               jsonb_agg(
                 jsonb_build_object(
                   'level_label',        p.level_label,
                   'level_order',        p.level_order,
                   'accuracy',           p.accuracy,
                   'cue_level_used',     p.cue_level_used,
                   'cue_level_used_raw', p.cue_level_used_raw
                 )
                 order by p.level_order
               ) as levels
          from public.cas_session_progress p
          join public.sessions s on s.id = p.session_id
         where p.stg_id = p_stg_id
           and s.deleted_at is null
         group by s.id, s.date, s.created_at
         order by s.date desc nulls last, s.created_at desc
         limit 3
      ) sess
    ), '[]'::jsonb)
  );
$$;

comment on function public.assemble_cas_progress(uuid) is
  'Single source of truth for CAS-progress brief content. Verbatim columns from cas_session_progress (joined to sessions for date ordering); no AI, no fabrication. SECURITY INVOKER + STABLE + locked search_path — mirrors assemble_recall_card. The brief''s field set must never be edited in one read path without the other; all paths share this function.';

-- Explicit grant so PostgREST can invoke via RPC under the authenticated role.
grant execute on function public.assemble_cas_progress(uuid) to authenticated;
