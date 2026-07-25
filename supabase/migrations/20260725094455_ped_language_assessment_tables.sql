-- Pediatric Language capture surface (Step 3) — parent + milestone rows.
--
-- Pattern: CAS-style parent flat table keyed on client_id, multi-row
-- child table seeded once from the ASHA dataset asset and updated by id.
-- Two deliberate deviations from the CAS-era tables:
--   1. milestone_text/example_text are VERBATIM SNAPSHOTS from the
--      dataset — the clinical record stays self-contained if the asset
--      is ever edited (same instinct as substrate_sources.excerpt).
--   2. A UNIQUE constraint on (assessment, section, milestone_order)
--      guards duplicate seeding (fixing, not copying, the CAS
--      missing-constraint debt).
-- status NULL means "not yet captured" — distinct from an explicit
-- 'absent', which is only written when the SLP completes a section.
-- RLS intentionally OFF — sandbox prototype convention (CLAUDE.md §11
-- deferred debt), hardened with the other assessment tables later.

create table public.ped_language_assessments (
  id                    uuid primary key default gen_random_uuid(),
  client_id             uuid not null references public.clients(id),
  clinician_id          uuid,
  band_key              text not null,
  age_months_at_capture int  not null,
  age_source            text not null check (age_source in ('dob','stated_years')),
  speech_completed_at   timestamptz,
  language_completed_at timestamptz,
  literacy_completed_at timestamptz,
  capture_notes         text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

comment on table public.ped_language_assessments is
  'Parent record for a Pediatric Language milestone-check capture. One '
  'per client (loadOrCreate keys on client_id, most recent wins). '
  'band_key locks the ASHA age band at first open; age_source records '
  'how the age was derived (dob = exact from date_of_birth, '
  'stated_years = midpoint of clients.age). *_completed_at stamp when '
  'the SLP declared each section done. RLS intentionally OFF — sandbox '
  'prototype convention, hardened later.';

create table public.ped_language_milestones (
  id              uuid primary key default gen_random_uuid(),
  ped_language_assessment_id uuid not null
      references public.ped_language_assessments(id) on delete cascade,
  section         text not null check (section in ('speech','language','literacy')),
  milestone_order int  not null,
  milestone_text  text not null,
  example_text    text,
  status          text check (status in ('present','emerging','absent')),
  evidence_source text check (evidence_source in ('observed','parent_reported')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (ped_language_assessment_id, section, milestone_order),
  check (evidence_source is null or status in ('present','emerging'))
);

comment on table public.ped_language_milestones is
  'One row per ASHA milestone in the assessment''s locked age band, '
  'seeded on first open with status NULL (= not yet captured). '
  'milestone_text/example_text are verbatim snapshots from the dataset '
  'asset so the clinical record survives dataset edits. status is only '
  'set to absent explicitly when the SLP completes the section; '
  'evidence_source (observed | parent_reported) applies to present/'
  'emerging only, enforced by check. RLS intentionally OFF — sandbox '
  'prototype convention, hardened later.';

create index ped_language_assessments_client_idx
  on public.ped_language_assessments (client_id, created_at desc);

create index ped_language_milestones_assessment_idx
  on public.ped_language_milestones (ped_language_assessment_id);
