-- ============================================================================
-- Capture: assessment_visits  (CAPTURE migration)
-- ============================================================================
-- A point-in-time assessment visit. Referenced by the voice / ped-dysarthria /
-- ald assessment parents via visit_id, so it is created before them.
-- RLS ON (clinician owns own rows). BEFORE UPDATE trigger maintains updated_at.
-- ============================================================================
create table if not exists public.assessment_visits (
  id                      uuid        not null default gen_random_uuid(),
  client_id               uuid        not null,
  clinician_id            uuid        not null default auth.uid(),
  visit_number            integer     not null default 1,
  visit_date              date        not null,
  visit_duration_minutes  integer,
  visit_status            text        not null default 'scheduled',
  primary_capture_focus   text,
  observations            text,
  parent_present          boolean     default true,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint assessment_visits_pkey primary key (id),
  constraint assessment_visits_client_id_fkey
    foreign key (client_id) references public.clients(id) on delete cascade,
  constraint assessment_visits_clinician_id_fkey
    foreign key (clinician_id) references auth.users(id),
  constraint assessment_visits_visit_status_check
    check (visit_status = any (array['scheduled','in_progress','completed','no_show','cancelled']))
);

create index if not exists idx_assessment_visits_client
  on public.assessment_visits (client_id, visit_date desc);
create index if not exists idx_assessment_visits_clinician
  on public.assessment_visits (clinician_id, visit_date desc);

alter table public.assessment_visits enable row level security;

drop policy if exists "assessment_visits_clinician_own" on public.assessment_visits;
create policy "assessment_visits_clinician_own" on public.assessment_visits
  as permissive for all to authenticated
  using (clinician_id = auth.uid())
  with check (clinician_id = auth.uid());

drop trigger if exists assessment_visits_updated_at on public.assessment_visits;
create trigger assessment_visits_updated_at
  before update on public.assessment_visits
  for each row execute function public.set_updated_at();
