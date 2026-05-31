-- ============================================================================
-- Phase 4.0.7.28 — Pediatric CAS assessment surface  (CAPTURE migration)
-- ============================================================================
-- Rebuilt at the version recorded in the database migration log
-- (20260529175527) so the repo's migration history matches what was actually
-- applied. The original .sql was never committed; this file reconstructs the
-- EXACT current structure of the CAS tables from the live sandbox so a fresh
-- rebuild reproduces them faithfully.
--
-- CAPTURE-AS-IS (intentional — do NOT "fix" here; hardening is a later migration):
--   * RLS is intentionally LEFT OFF on all four CAS tables, matching reality.
--   * cas_ddk and cas_length_gradient intentionally have NO unique constraint
--     on their natural key (multi-row children). Adding one is a deliberate
--     later fix, after checking live data for existing duplicates.
--   * cas_assessments.clinician_id has no FK and no default, matching reality.
-- Idempotent: CREATE TABLE / INDEX IF NOT EXISTS.
-- ============================================================================

-- Parent ---------------------------------------------------------------------
create table if not exists public.cas_assessments (
  id                            uuid        not null default gen_random_uuid(),
  client_id                     uuid        not null,
  clinician_id                  uuid,
  marker_inconsistent_errors    text,
  marker_disrupted_transitions  text,
  marker_inappropriate_prosody  text,
  marker_inconsistent_notes     text,
  marker_transitions_notes      text,
  marker_prosody_notes          text,
  oral_mech_exam                text,
  groping_searching             text,
  vowel_errors                  text,
  receptive_expressive_gap      text,
  consonant_inventory           text,
  vowel_inventory               text,
  syllable_shape_inventory      text,
  age_months                    integer,
  capture_notes                 text,
  created_at                    timestamptz not null default now(),
  updated_at                    timestamptz not null default now(),
  constraint cas_assessments_pkey primary key (id),
  constraint cas_assessments_client_id_fkey
    foreign key (client_id) references public.clients(id) on delete cascade,
  constraint cas_assessments_marker_inconsistent_errors_check
    check (marker_inconsistent_errors = any (array['present','emerging','absent'])),
  constraint cas_assessments_marker_disrupted_transitions_check
    check (marker_disrupted_transitions = any (array['present','emerging','absent'])),
  constraint cas_assessments_marker_inappropriate_prosody_check
    check (marker_inappropriate_prosody = any (array['present','emerging','absent'])),
  constraint cas_assessments_groping_searching_check
    check (groping_searching = any (array['present','emerging','absent'])),
  constraint cas_assessments_vowel_errors_check
    check (vowel_errors = any (array['present','emerging','absent'])),
  constraint cas_assessments_receptive_expressive_gap_check
    check (receptive_expressive_gap = any (array['present','emerging','absent']))
);

create index if not exists idx_cas_assessments_client
  on public.cas_assessments (client_id);

-- Child: length gradient (multi-row; NO unique constraint — captured as-is) ---
create table if not exists public.cas_length_gradient (
  id                 uuid        not null default gen_random_uuid(),
  cas_assessment_id  uuid        not null,
  level_label        text        not null,
  level_order        integer     not null,
  example_tokens     text,
  accuracy           text,
  notes              text,
  created_at         timestamptz not null default now(),
  constraint cas_length_gradient_pkey primary key (id),
  constraint cas_length_gradient_cas_assessment_id_fkey
    foreign key (cas_assessment_id) references public.cas_assessments(id) on delete cascade,
  constraint cas_length_gradient_accuracy_check
    check (accuracy = any (array['accurate','partial','inaccurate']))
);

create index if not exists idx_cas_length_gradient_parent
  on public.cas_length_gradient (cas_assessment_id, level_order);

-- Child: DDK (multi-row; NO unique constraint — captured as-is) ---------------
create table if not exists public.cas_ddk (
  id                     uuid         not null default gen_random_uuid(),
  cas_assessment_id      uuid         not null,
  task                   text         not null,
  rate_syl_per_sec       numeric(4,2),
  sequence_order_errors  boolean      default false,
  method                 text,
  notes                  text,
  created_at             timestamptz  not null default now(),
  constraint cas_ddk_pkey primary key (id),
  constraint cas_ddk_cas_assessment_id_fkey
    foreign key (cas_assessment_id) references public.cas_assessments(id) on delete cascade,
  constraint cas_ddk_task_check
    check (task = any (array['pa','ta','ka','pataka'])),
  constraint cas_ddk_method_check
    check (method = any (array['count_by_time','time_by_count']))
);

create index if not exists idx_cas_ddk_parent
  on public.cas_ddk (cas_assessment_id);

-- Reference: published DDK norms (standalone lookup; no FK) -------------------
create table if not exists public.cas_ddk_norms (
  id                uuid         not null default gen_random_uuid(),
  task              text         not null,
  age_months_min    integer      not null,
  age_months_max    integer      not null,
  mean_syl_per_sec  numeric(4,2) not null,
  sd_syl_per_sec    numeric(4,2) not null,
  source_citation   text         not null,
  source_method     text,
  source_language   text,
  created_at        timestamptz  not null default now(),
  constraint cas_ddk_norms_pkey primary key (id),
  constraint cas_ddk_norms_task_check
    check (task = any (array['amr','smr'])),
  constraint cas_ddk_norms_source_method_check
    check (source_method = any (array['count_by_time','time_by_count']))
);

create index if not exists idx_cas_ddk_norms_lookup
  on public.cas_ddk_norms (task, age_months_min, age_months_max);
