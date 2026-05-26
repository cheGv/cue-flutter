-- Phase D week 3 — Content-slot bridge. Sandbox-only. Additive.
--
-- Two new artifacts complete the Cue Mirror "three artifacts" model:
--   1. extracted_template (V1 semantic skeleton)        — existing
--   2. format_geometry   (V2 deterministic OOXML)        — wk2
--   3. format_slot_map   (LLM-identified content slots)  — THIS migration
--
-- format_slot_map maps locations in format_geometry to semantic content slots.
-- The empty default '{}' is a meaningful STATE: "{}" = slots not yet identified
-- (renderer falls back to the V1 renderer); populated = ready for content-fill
-- mirroring. Never round-tripped by the Flutter semantic model.
--
-- format_drafts.slot_content carries the slot-keyed drafted content (slot_id ->
-- content) the drafter produces ALONGSIDE draft_sections in a single LLM call.
-- draft_sections keeps its exact shape so Component Three (sentence editing) and
-- the format_draft_sentences corpus continue working unchanged. '{}' = no
-- slot-fill (V1 export path).
--
-- Sandbox (uuqhusmgoiaxdvtgbmwh) only. NOT applied to production.

alter table public.format_templates
  add column if not exists format_slot_map jsonb not null default '{}'::jsonb;

comment on column public.format_templates.format_slot_map is
  'Phase D wk3 — LLM-identified content-slot map over format_geometry. {} = not yet identified (renderer falls back to V1); populated = ready for content-fill mirroring. Server-managed.';

alter table public.format_drafts
  add column if not exists slot_content jsonb not null default '{}'::jsonb;

comment on column public.format_drafts.slot_content is
  'Phase D wk3 — slot-keyed drafted content (slot_id -> content), produced alongside draft_sections in one drafter call. {} = no slot-fill (V1 export path).';
