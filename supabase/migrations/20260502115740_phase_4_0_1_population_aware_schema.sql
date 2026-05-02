-- Phase 4.0.1 — Population-aware schema
-- See PHASE_4_SPEC.md Section 2 for the full contract.
-- Additive only. No drops, no renames. RLS deferred per CLAUDE.md §11.

-- 1. clients: population discriminator + Layer-01 intake fields.
alter table public.clients
  add column if not exists population_type text not null default 'asd_aac',
  add column if not exists primary_language text,
  add column if not exists additional_languages text[],
  add column if not exists primary_concern_verbatim text;

-- 2. sessions: per-session population_payload (Layer-03 live_entry / debrief).
alter table public.sessions
  add column if not exists population_payload jsonb;

-- 3. goal_plans: Layer-05 lesson plan inputs.
alter table public.goal_plans
  add column if not exists lesson_plan_inputs jsonb;

-- 4. stg_evidence: Layer-06 per-session per-STG population metrics.
alter table public.stg_evidence
  add column if not exists population_payload jsonb;

-- 5. case_history_entries (Layer 02).
create table if not exists public.case_history_entries (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  population_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

create index if not exists idx_case_history_entries_client_pop
  on public.case_history_entries(client_id, population_type);
create index if not exists idx_case_history_entries_client_created
  on public.case_history_entries(client_id, created_at desc);

-- 6. assessment_entries (Layer 03 — three sub-modes via `mode` discriminator).
create table if not exists public.assessment_entries (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  session_id bigint references public.sessions(id) on delete set null,
  mode text not null check (mode in ('live_entry','debrief','parent_interview')),
  population_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

create index if not exists idx_assessment_entries_client_mode_created
  on public.assessment_entries(client_id, mode, created_at desc);
create index if not exists idx_assessment_entries_session
  on public.assessment_entries(session_id);
