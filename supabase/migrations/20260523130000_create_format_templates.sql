-- Phase C — Cue Format Adaptation, Component One (Format Extractor).
--
-- format_templates: per-clinician structural templates Cue extracts from her
-- own sample reports, then locks against her account. Future drafting
-- (Component Two) reads the confirmed template. Per-clinician, RLS-isolated —
-- no cross-clinician visibility ever.
--
-- Sandbox (uuqhusmgoiaxdvtgbmwh) only. NOT applied to production.

create table if not exists public.format_templates (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users(id) on delete cascade,
  name                text not null,
  -- 'pt_report' | 'lp_report' | 'progress_report' | 'session_note'
  -- | 'discharge_summary' | 'other'
  format_type         text not null,
  -- [{filename, storage_path, uploaded_at, file_type ('pdf'|'docx')}]
  source_documents    jsonb not null default '[]'::jsonb,
  -- the structural skeleton (sections, ordering, hierarchy, length
  -- conventions, voice register, placeholders, canonical mapping rules)
  extracted_template  jsonb not null default '{}'::jsonb,
  -- 'pending' | 'confirmed' | 'archived'
  confirmation_status text not null default 'pending',
  confirmed_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  is_fixture          boolean default false,
  notes               text,
  constraint format_templates_format_type_check check (
    format_type in (
      'pt_report', 'lp_report', 'progress_report',
      'session_note', 'discharge_summary', 'other'
    )
  ),
  constraint format_templates_confirmation_status_check check (
    confirmation_status in ('pending', 'confirmed', 'archived')
  )
);

create index if not exists format_templates_user_type_status_idx
  on public.format_templates (user_id, format_type, confirmation_status);

-- ── RLS — clinician sees only her own templates ─────────────────────────────
alter table public.format_templates enable row level security;

create policy "format_templates_select_own" on public.format_templates
  for select using (auth.uid() = user_id);

create policy "format_templates_insert_own" on public.format_templates
  for insert with check (auth.uid() = user_id);

create policy "format_templates_update_own" on public.format_templates
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "format_templates_delete_own" on public.format_templates
  for delete using (auth.uid() = user_id);

comment on table public.format_templates is
  'Phase C — per-clinician extracted report-format templates (Format Extractor). RLS-isolated by user_id.';
