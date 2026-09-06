-- Delete affordances, Step 3 — a client / assessment case soft delete
-- writes the same audit trio a session archive writes (sessions has had
-- deleted_at + deleted_by + delete_reason since Phase 4.0.7.10b).
--
-- clients.deleted_at already existed and was READ-gated (ClientsQuery
-- filters `deleted_at IS NULL`) but never written by any affordance;
-- deleted_by and delete_reason did not exist at all. Added here so the
-- app's Delete affordance can record who and why, exactly like sessions.
--
-- Soft delete is RECOVERABLE: restore clears all three columns. Nothing
-- in this migration purges (the purge job is deliberately not built).

alter table public.clients
  add column if not exists deleted_by uuid references auth.users(id),
  add column if not exists delete_reason text;

comment on column public.clients.deleted_at is
  'Soft delete, recoverable. Written by the Delete affordance; read-gated by ClientsQuery and refused by requireLiveClient. NULL = live.';
comment on column public.clients.deleted_by is
  'auth.users id of the clinician who soft-deleted the row. NULL when live.';
comment on column public.clients.delete_reason is
  'Optional reason chosen in the delete dialog (same picker as session archive). NULL when live.';
