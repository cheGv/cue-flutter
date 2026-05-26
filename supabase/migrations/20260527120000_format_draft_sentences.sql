-- Phase D — Cue Mirror Component Three (full): sentence-level draft storage.
--
-- One row per sentence of a generated/authored draft section. The future
-- fine-tuning corpus is a plain SELECT against this table — no JSON-array
-- surgery. The proxy is the authoritative writer at POST /format-draft,
-- inserting these rows atomically alongside the parent format_drafts row.
-- Clinician edits (Component Three) update text_in_progress (autosave) and
-- promote to text + status on explicit save.
--
-- Sandbox (uuqhusmgoiaxdvtgbmwh) only. NOT applied to production.

create table if not exists public.format_draft_sentences (
  id                 uuid primary key default gen_random_uuid(),
  draft_id           uuid not null references public.format_drafts(id) on delete cascade,
  section_name       text not null,
  sentence_order     integer not null,
  text               text not null,              -- current committed text
  text_in_progress   text,                       -- autosaved, uncommitted edit
  text_original      text not null,              -- immutable Cue-generated version
  status             text not null default 'cue_drafted'
    check (status in ('cue_drafted', 'clinician_edited', 'clinician_authored')),
  source_claims      jsonb,                       -- per-sentence claims (null if clinician_authored)
  lexicon_swaps      jsonb,                       -- per-sentence neutral-language swaps
  clinician_id       uuid not null,               -- denormalized from format_drafts.user_id
  template_id        uuid not null,               -- denormalized from format_drafts.template_id
  substrate_snapshot jsonb,                        -- substrate context at generation (fine-tuning)
  edited_at          timestamptz,
  saved_at           timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

-- Ordered retrieval per section.
create index if not exists fmt_draft_sentences_draft_section_order_idx
  on public.format_draft_sentences (draft_id, section_name, sentence_order);
-- Per-clinician corpus queries (future fine-tuning).
create index if not exists fmt_draft_sentences_clinician_idx
  on public.format_draft_sentences (clinician_id);
-- Per-template analysis.
create index if not exists fmt_draft_sentences_template_idx
  on public.format_draft_sentences (template_id);
-- Edited-only queries (partial — excludes the un-edited majority).
create index if not exists fmt_draft_sentences_edited_idx
  on public.format_draft_sentences (status) where status <> 'cue_drafted';

-- ── RLS — clinician sees only her own sentences ─────────────────────────────
alter table public.format_draft_sentences enable row level security;

create policy "fmt_draft_sentences_select_own" on public.format_draft_sentences
  for select using (auth.uid() = clinician_id);

create policy "fmt_draft_sentences_insert_own" on public.format_draft_sentences
  for insert with check (auth.uid() = clinician_id);

create policy "fmt_draft_sentences_update_own" on public.format_draft_sentences
  for update using (auth.uid() = clinician_id) with check (auth.uid() = clinician_id);

create policy "fmt_draft_sentences_delete_own" on public.format_draft_sentences
  for delete using (auth.uid() = clinician_id);

comment on table public.format_draft_sentences is
  'Phase D — Cue Mirror Component Three: sentence-level draft corpus. Proxy-written at /format-draft (atomic with format_drafts); clinician-edited via Component Three. RLS-isolated by clinician_id.';
