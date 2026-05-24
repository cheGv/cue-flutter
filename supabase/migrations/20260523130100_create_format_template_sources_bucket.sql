-- Phase C — storage bucket for clinician-uploaded format sample documents.
--
-- Private bucket. Per-user folder layout: {user_id}/{template_id}/{filename}.
-- The first path segment is the owning clinician's auth uid, so RLS on
-- storage.objects scopes every op to (storage.foldername(name))[1].
-- Sandbox only.

insert into storage.buckets (id, name, public)
values ('format_template_sources', 'format_template_sources', false)
on conflict (id) do nothing;

drop policy if exists "fmt_sources_select_own" on storage.objects;
create policy "fmt_sources_select_own" on storage.objects
  for select to authenticated using (
    bucket_id = 'format_template_sources'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );

drop policy if exists "fmt_sources_insert_own" on storage.objects;
create policy "fmt_sources_insert_own" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'format_template_sources'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );

drop policy if exists "fmt_sources_update_own" on storage.objects;
create policy "fmt_sources_update_own" on storage.objects
  for update to authenticated using (
    bucket_id = 'format_template_sources'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );

drop policy if exists "fmt_sources_delete_own" on storage.objects;
create policy "fmt_sources_delete_own" on storage.objects
  for delete to authenticated using (
    bucket_id = 'format_template_sources'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );
