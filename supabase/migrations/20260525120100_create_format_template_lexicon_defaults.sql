-- Phase C — Cue Mirror, Component Two (Format Drafter).
-- format_template_lexicon_defaults: the SLP's once-per-template decision for
-- each forbidden term observed in her format — swap it for Cue's neutral
-- replacement, or keep her original wording. Set once via the first-time
-- lexicon flow; reused on every subsequent draft for that template. RLS
-- scopes every row to the owning clinician.

create table if not exists public.format_template_lexicon_defaults (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  template_id      uuid not null references public.format_templates(id) on delete cascade,
  forbidden_term   text not null,
  replacement_term text,           -- nullable when decision = 'keep_original'
  decision         text not null check (decision in ('swap','keep_original')),
  created_at       timestamptz default now(),
  updated_at       timestamptz default now(),
  unique (template_id, forbidden_term)
);

alter table public.format_template_lexicon_defaults enable row level security;

create policy "format_lexicon_defaults_select_own"
  on public.format_template_lexicon_defaults for select
  using (auth.uid() = user_id);

create policy "format_lexicon_defaults_insert_own"
  on public.format_template_lexicon_defaults for insert
  with check (auth.uid() = user_id);

create policy "format_lexicon_defaults_update_own"
  on public.format_template_lexicon_defaults for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "format_lexicon_defaults_delete_own"
  on public.format_template_lexicon_defaults for delete
  using (auth.uid() = user_id);

create index if not exists format_lexicon_defaults_template_idx
  on public.format_template_lexicon_defaults (user_id, template_id);
