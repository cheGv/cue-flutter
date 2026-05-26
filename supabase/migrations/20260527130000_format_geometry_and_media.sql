-- Phase D week 2 — Cue Mirror format-mirroring engine.
--
-- Additive, sandbox-only. Two parts:
--
-- 1. format_geometry jsonb — the deterministic OOXML geometry extracted by
--    POST /format-extract-v2 (page_setup, default_font, structure[],
--    numbering_definitions, media[] anchors+paths). It is deliberately a
--    SEPARATE column from extracted_template: the Flutter ExtractedTemplate
--    model round-trips extracted_template through /format-confirm and its
--    toJson() re-emits only the semantic keys, so geometry stored there would
--    be silently dropped on any clinician edit. Geometry is server-managed and
--    never edited by the LLM or the Flutter semantic round-trip (Cue Mirror
--    C2: "the LLM never sees format").
--
-- 2. format_template_media — private per-user bucket holding the raw image
--    bytes of embedded template media (logos etc.), layout
--    {uid}/{templateId}/{imageId.ext}. RLS scopes every op to the owning
--    clinician's uid prefix, matching format_template_sources /
--    format_draft_exports.
--
-- Sandbox (uuqhusmgoiaxdvtgbmwh) only. NOT applied to production.

alter table public.format_templates
  add column if not exists format_geometry jsonb not null default '{}'::jsonb;

comment on column public.format_templates.format_geometry is
  'Phase D wk2 — deterministic OOXML geometry from /format-extract-v2 (page_setup, default_font, structure[], numbering_definitions, media[]). Server-managed; never round-tripped by the Flutter semantic model.';

insert into storage.buckets (id, name, public)
values ('format_template_media', 'format_template_media', false)
on conflict (id) do nothing;

drop policy if exists "fmt_media_select_own" on storage.objects;
create policy "fmt_media_select_own" on storage.objects
  for select to authenticated using (
    bucket_id = 'format_template_media'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );

drop policy if exists "fmt_media_insert_own" on storage.objects;
create policy "fmt_media_insert_own" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'format_template_media'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );

drop policy if exists "fmt_media_update_own" on storage.objects;
create policy "fmt_media_update_own" on storage.objects
  for update to authenticated using (
    bucket_id = 'format_template_media'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );

drop policy if exists "fmt_media_delete_own" on storage.objects;
create policy "fmt_media_delete_own" on storage.objects
  for delete to authenticated using (
    bucket_id = 'format_template_media'
    and (storage.foldername(name))[1] = (auth.uid())::text
  );
