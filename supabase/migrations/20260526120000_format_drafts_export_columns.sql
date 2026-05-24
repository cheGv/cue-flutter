-- Phase C — Cue Mirror Component Four (Word export).
-- Export-tracking columns on format_drafts. Sandbox only.
--   exported_at   : when the draft was last exported.
--   export_path   : storage path of the latest export (nullable).
--   export_format : 'docx' for now ('pdf' reserved for a future component).

alter table public.format_drafts
  add column if not exists exported_at   timestamptz,
  add column if not exists export_path   text,
  add column if not exists export_format text;
