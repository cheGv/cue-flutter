-- ============================================================================
-- Capture: assessment_reports  (CAPTURE migration)
-- ============================================================================
-- Existing (ad-hoc) assessment report record: draft -> attested -> exported,
-- with a JSONB report_payload, rendered HTML/PDF, and a shareable URL.
-- RLS ON (clinician owns own rows). BEFORE UPDATE trigger maintains updated_at.
-- ============================================================================
create table if not exists public.assessment_reports (
  id                  uuid        not null default gen_random_uuid(),
  client_id           uuid        not null,
  clinician_id        uuid        not null default auth.uid(),
  clinical_area       text        not null,
  diagnostic_summary  text,
  diagnostic_codes    text[],
  report_payload      jsonb       default '{}'::jsonb,
  rendered_html       text,
  rendered_pdf_url    text,
  draft_status        text        not null default 'draft',
  attested_at         timestamptz,
  attested_by         uuid,
  exported_at         timestamptz,
  share_url           text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint assessment_reports_pkey primary key (id),
  constraint assessment_reports_client_id_fkey
    foreign key (client_id) references public.clients(id) on delete cascade,
  constraint assessment_reports_clinician_id_fkey
    foreign key (clinician_id) references auth.users(id),
  constraint assessment_reports_attested_by_fkey
    foreign key (attested_by) references auth.users(id),
  constraint assessment_reports_draft_status_check
    check (draft_status = any (array['draft','attested','exported','archived']))
);

create index if not exists idx_assessment_reports_client
  on public.assessment_reports (client_id, created_at desc);
create index if not exists idx_assessment_reports_status
  on public.assessment_reports (draft_status);

alter table public.assessment_reports enable row level security;

drop policy if exists "assessment_reports_clinician_own" on public.assessment_reports;
create policy "assessment_reports_clinician_own" on public.assessment_reports
  as permissive for all to authenticated
  using (clinician_id = auth.uid())
  with check (clinician_id = auth.uid());

drop trigger if exists assessment_reports_updated_at on public.assessment_reports;
create trigger assessment_reports_updated_at
  before update on public.assessment_reports
  for each row execute function public.set_updated_at();
