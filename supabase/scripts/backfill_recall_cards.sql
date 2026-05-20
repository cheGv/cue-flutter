-- Re-runnable backfill for public.recall_cards.
--
-- Calls the shared assembler public.assemble_recall_card(uuid) for every
-- client owned by a clinician, upserts the result, and clears is_dirty.
-- Identical SQL to the trailing block in
-- supabase/migrations/20260519130000_recall_card_assembler_and_backfill.sql
-- — kept here so operators can re-run the backfill at any time without
-- re-applying that migration (Supabase migrations are applied once).
--
-- Idempotent. Safe to run repeatedly. Single bulk pass; no per-client
-- round trips. ON CONFLICT (client_id) DO UPDATE refreshes the row
-- without duplicating.
--
-- Usage (sandbox):
--   psql ... -f cue-source/supabase/scripts/backfill_recall_cards.sql
--   or copy-paste the INSERT below into the MCP execute_sql tool against
--   the sandbox project.
--
-- DO NOT run against production until the recall_cards stack itself has
-- been applied to production (which, as of 2026-05-19, has NOT happened
-- — production sessions RLS is still off; see docs/known-debt.md).

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
