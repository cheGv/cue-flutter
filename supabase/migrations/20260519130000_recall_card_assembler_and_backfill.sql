-- Cue Recall Assistant — shared card-assembler + eager backfill.
--
-- Architecture amendment (locked 2026-05-19, sandbox):
--   The recall card payload is now assembled by ONE SQL function,
--   public.assemble_recall_card(uuid) -> jsonb. The recall-card edge
--   function (TypeScript) calls this via RPC; the backfill at the bottom
--   of this migration calls it server-side. Both paths produce
--   byte-identical jsonb because Postgres is the only serializer in
--   the loop — no JS Date.toISOString() vs to_jsonb() format drift.
--
--   This is the "factor the assembly into one shared SQL/source so
--   they cannot diverge" decision from the backfill brief.
--
-- Function posture:
--   • SECURITY INVOKER (the default). RLS on sessions / short_term_goals
--     / long_term_goals filters the inner queries by the caller's
--     auth.uid(). When called via RPC by a clinician's JWT, only that
--     clinician's data is visible. When called server-side from this
--     migration's backfill under the postgres role, RLS is bypassed —
--     correct for the bulk-pass.
--   • STABLE — within a single statement, the function returns the same
--     output for the same input (allows planner to inline / cache).
--   • Locked search_path = public, pg_temp — hygiene, deterministic
--     name resolution.
--   • Same field shape as the edge function's previous inline assembly:
--       { client_id, assembled_at, last_session?, active_stgs[], active_ltgs[] }

create or replace function public.assemble_recall_card(p_client_id uuid)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'client_id',    p_client_id::text,
    'assembled_at', to_jsonb(now()),
    'last_session', (
      select to_jsonb(s)
      from (
        select id, date, attempts, independent_responses, prompted_responses,
               parent_update, home_programme, soap_note, notes,
               target_behaviour, activity_name, next_session_focus,
               client_affect, goal_met, created_at
          from public.sessions
         where client_id = p_client_id
           and deleted_at is null
         order by date desc nulls last, created_at desc
         limit 1
      ) s
    ),
    'active_stgs', coalesce((
      select jsonb_agg(to_jsonb(g) order by g.sequence_num)
      from (
        select id, target_behavior, status, current_accuracy, target_accuracy,
               current_cue_level, sequence_num, domain, mastery_criterion,
               long_term_goal_id, updated_at
          from public.short_term_goals
         where client_id = p_client_id
           and status = 'active'
      ) g
    ), '[]'::jsonb),
    'active_ltgs', coalesce((
      select jsonb_agg(to_jsonb(g) order by g.sequence_num)
      from (
        select id, goal_text, domain, status, sequence_num, updated_at
          from public.long_term_goals
         where client_id = p_client_id
           and status = 'active'
      ) g
    ), '[]'::jsonb)
  );
$$;

comment on function public.assemble_recall_card(uuid) is
  'Single source of truth for recall-card content. Called by the recall-card edge function (via RPC, under the SLP''s JWT) and by the backfill (server-side, under postgres role). SECURITY INVOKER + STABLE + locked search_path. The card''s field set must never be edited in one path without the other — both paths share this function.';

-- Explicit grants so PostgREST can invoke via RPC under the authenticated
-- role (the JWT-authenticated SLP). Anon role is intentionally NOT
-- granted — recall-card has verify_jwt=true and only authenticated
-- callers reach the RPC.
grant execute on function public.assemble_recall_card(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────
-- Initial backfill — eager populate for every existing client.
-- ─────────────────────────────────────────────────────────────────
--
-- Idempotent: ON CONFLICT (client_id) DO UPDATE overwrites the
-- existing row's card content + flips is_dirty=false. Re-applying
-- this migration (or running the standalone script at
-- supabase/scripts/backfill_recall_cards.sql) refreshes every card
-- without duplicating rows.
--
-- Empty-but-present: clients with no sessions / no active goals
-- receive a row with card = { last_session: null, active_stgs: [],
-- active_ltgs: [] }, is_dirty = false. Warm state, not absence.
--
-- WHERE clinician_id IS NOT NULL: orphaned clients with no owning
-- clinician cannot satisfy recall_cards.user_id NOT NULL. Such rows
-- are skipped. Sandbox has no such clients today; this filter is
-- a defensive guard for future data quality issues, not a current
-- exclusion.

insert into public.recall_cards (client_id, user_id, card, is_dirty, updated_at)
select c.id,
       c.clinician_id,
       public.assemble_recall_card(c.id),
       false,
       now()
  from public.clients c
 where c.clinician_id is not null
on conflict (client_id) do update
   set user_id    = excluded.user_id,
       card       = excluded.card,
       is_dirty   = false,
       updated_at = now();
