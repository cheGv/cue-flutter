-- Phase C — Cue Mirror Component Four (Word export).
--
-- Private bucket for generated report exports (.docx).
-- Per-user folder layout: {user_id}/{draft_id}/{filename}.docx.
-- The first path segment is the owning clinician's auth uid, so RLS on
-- storage.objects scopes every op to (storage.foldername(name))[1] — a
-- clinician can only reach objects under her own uid prefix. Downloads use
-- short-lived signed URLs (pre-authorized), so these policies are
-- defense-in-depth for any direct client access. Sandbox only.

insert into storage.buckets (id, name, public)
values ('format_draft_exports', 'format_draft_exports', false)
on conflict (id) do nothing;

drop policy if exists "fmt_exports_select_own" on storage.objects;
create policy "fmt_exports_select_own" on storage.objects
  for select to authenticated using (
    bucket_id = 'format_draft_exports'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );

drop policy if exists "fmt_exports_insert_own" on storage.objects;
create policy "fmt_exports_insert_own" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'format_draft_exports'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );

drop policy if exists "fmt_exports_update_own" on storage.objects;
create policy "fmt_exports_update_own" on storage.objects
  for update to authenticated using (
    bucket_id = 'format_draft_exports'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );

drop policy if exists "fmt_exports_delete_own" on storage.objects;
create policy "fmt_exports_delete_own" on storage.objects
  for delete to authenticated using (
    bucket_id = 'format_draft_exports'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );
