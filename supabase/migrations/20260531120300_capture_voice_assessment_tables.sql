-- ============================================================================
-- Capture: voice assessment family  (CAPTURE migration)
-- ============================================================================
-- voice_assessments (parent) + voice_aerodynamic_measures /
-- voice_perceptual_ratings / voice_qol_scores (one-row-per-assessment children,
-- except perceptual_ratings which is one-per-rater). RLS ON throughout.
-- Parent owns via clinician_id; children own via their parent's clinician.
-- Parent has a BEFORE UPDATE updated_at trigger.
--
-- CAPTURE-AS-IS: the three child policies use USING only (NO WITH CHECK),
-- matching the live catalog exactly.
-- ============================================================================
create table if not exists public.voice_assessments (
  id                              uuid        not null default gen_random_uuid(),
  client_id                       uuid        not null,
  clinician_id                    uuid        not null default auth.uid(),
  visit_id                        uuid,
  case_history_payload            jsonb       default '{}'::jsonb,
  rsi_total_score                 integer,
  voice_use_hours_per_day         integer,
  laryngeal_exam_payload          jsonb       default '{}'::jsonb,
  functional_voice_payload        jsonb       default '{}'::jsonb,
  task_based_payload              jsonb       default '{}'::jsonb,
  special_populations_payload     jsonb       default '{}'::jsonb,
  differential_diagnosis_payload  jsonb       default '{}'::jsonb,
  clinical_impression_payload     jsonb       default '{}'::jsonb,
  is_baseline                     boolean     default true,
  baseline_assessment_id          uuid,
  attested_at                     timestamptz,
  attested_by                     uuid,
  created_at                      timestamptz not null default now(),
  updated_at                      timestamptz not null default now(),
  constraint voice_assessments_pkey primary key (id),
  constraint voice_assessments_client_id_fkey
    foreign key (client_id) references public.clients(id) on delete cascade,
  constraint voice_assessments_clinician_id_fkey
    foreign key (clinician_id) references auth.users(id),
  constraint voice_assessments_visit_id_fkey
    foreign key (visit_id) references public.assessment_visits(id) on delete set null,
  constraint voice_assessments_baseline_assessment_id_fkey
    foreign key (baseline_assessment_id) references public.voice_assessments(id) on delete set null,
  constraint voice_assessments_attested_by_fkey
    foreign key (attested_by) references auth.users(id)
);

create index if not exists idx_voice_assessments_client
  on public.voice_assessments (client_id, created_at desc);
create index if not exists idx_voice_assessments_baseline
  on public.voice_assessments (baseline_assessment_id) where baseline_assessment_id is not null;
create index if not exists idx_voice_assessments_visit
  on public.voice_assessments (visit_id) where visit_id is not null;

alter table public.voice_assessments enable row level security;
drop policy if exists "voice_assessments_clinician_own" on public.voice_assessments;
create policy "voice_assessments_clinician_own" on public.voice_assessments
  as permissive for all to authenticated
  using (clinician_id = auth.uid())
  with check (clinician_id = auth.uid());

drop trigger if exists voice_assessments_updated_at on public.voice_assessments;
create trigger voice_assessments_updated_at
  before update on public.voice_assessments
  for each row execute function public.set_updated_at();

-- Child: aerodynamic measures (one row per assessment) -----------------------
create table if not exists public.voice_aerodynamic_measures (
  id                                   uuid         not null default gen_random_uuid(),
  voice_assessment_id                  uuid         not null,
  mpt_seconds                          numeric(5,2),
  s_z_ratio                            numeric(4,2),
  subglottal_pressure_estimated_cmh2o  numeric(5,2),
  mean_airflow_rate_ml_per_sec         numeric(6,2),
  phonation_threshold_pressure_cmh2o   numeric(5,2),
  f0_mean_hz                           numeric(6,2),
  jitter_percent                       numeric(5,3),
  shimmer_percent                      numeric(5,3),
  hnr_db                               numeric(5,2),
  notes                                text,
  created_at                           timestamptz  not null default now(),
  constraint voice_aerodynamic_measures_pkey primary key (id),
  constraint voice_aerodynamic_measures_voice_assessment_id_fkey
    foreign key (voice_assessment_id) references public.voice_assessments(id) on delete cascade,
  constraint voice_aerodynamic_measures_assessment_unique unique (voice_assessment_id)
);

create index if not exists idx_voice_aerodynamic_assessment
  on public.voice_aerodynamic_measures (voice_assessment_id);

alter table public.voice_aerodynamic_measures enable row level security;
drop policy if exists "voice_aerodynamic_clinician_own" on public.voice_aerodynamic_measures;
create policy "voice_aerodynamic_clinician_own" on public.voice_aerodynamic_measures
  as permissive for all to authenticated
  using (exists (select 1 from public.voice_assessments va
                 where va.id = voice_aerodynamic_measures.voice_assessment_id
                   and va.clinician_id = auth.uid()));

-- Child: perceptual ratings (one row per assessment per rater) ---------------
create table if not exists public.voice_perceptual_ratings (
  id                      uuid        not null default gen_random_uuid(),
  voice_assessment_id     uuid        not null,
  rater                   text        not null default 'primary_clinician',
  capev_overall_severity  integer,
  capev_roughness         integer,
  capev_breathiness       integer,
  capev_strain            integer,
  capev_pitch             integer,
  capev_loudness          integer,
  capev_resonance_notes   text,
  grbas_grade             integer,
  grbas_roughness         integer,
  grbas_breathiness       integer,
  grbas_asthenia          integer,
  grbas_strain            integer,
  audio_recording_url     text,
  notes                   text,
  created_at              timestamptz not null default now(),
  constraint voice_perceptual_ratings_pkey primary key (id),
  constraint voice_perceptual_ratings_voice_assessment_id_fkey
    foreign key (voice_assessment_id) references public.voice_assessments(id) on delete cascade,
  constraint voice_perceptual_ratings_assessment_rater_unique unique (voice_assessment_id, rater),
  constraint voice_perceptual_ratings_capev_overall_severity_check check (capev_overall_severity >= 0 and capev_overall_severity <= 100),
  constraint voice_perceptual_ratings_capev_roughness_check check (capev_roughness >= 0 and capev_roughness <= 100),
  constraint voice_perceptual_ratings_capev_breathiness_check check (capev_breathiness >= 0 and capev_breathiness <= 100),
  constraint voice_perceptual_ratings_capev_strain_check check (capev_strain >= 0 and capev_strain <= 100),
  constraint voice_perceptual_ratings_capev_pitch_check check (capev_pitch >= 0 and capev_pitch <= 100),
  constraint voice_perceptual_ratings_capev_loudness_check check (capev_loudness >= 0 and capev_loudness <= 100),
  constraint voice_perceptual_ratings_grbas_grade_check check (grbas_grade >= 0 and grbas_grade <= 3),
  constraint voice_perceptual_ratings_grbas_roughness_check check (grbas_roughness >= 0 and grbas_roughness <= 3),
  constraint voice_perceptual_ratings_grbas_breathiness_check check (grbas_breathiness >= 0 and grbas_breathiness <= 3),
  constraint voice_perceptual_ratings_grbas_asthenia_check check (grbas_asthenia >= 0 and grbas_asthenia <= 3),
  constraint voice_perceptual_ratings_grbas_strain_check check (grbas_strain >= 0 and grbas_strain <= 3)
);

create index if not exists idx_voice_perceptual_assessment
  on public.voice_perceptual_ratings (voice_assessment_id);

alter table public.voice_perceptual_ratings enable row level security;
drop policy if exists "voice_perceptual_clinician_own" on public.voice_perceptual_ratings;
create policy "voice_perceptual_clinician_own" on public.voice_perceptual_ratings
  as permissive for all to authenticated
  using (exists (select 1 from public.voice_assessments va
                 where va.id = voice_perceptual_ratings.voice_assessment_id
                   and va.clinician_id = auth.uid()));

-- Child: QoL scores (one row per assessment) ---------------------------------
create table if not exists public.voice_qol_scores (
  id                   uuid        not null default gen_random_uuid(),
  voice_assessment_id  uuid        not null,
  vhi10_total          integer,
  vhi30_total          integer,
  vhi30_functional     integer,
  vhi30_physical       integer,
  vhi30_emotional      integer,
  vrqol_total          integer,
  svhi_total           integer,
  notes                text,
  created_at           timestamptz not null default now(),
  constraint voice_qol_scores_pkey primary key (id),
  constraint voice_qol_scores_voice_assessment_id_fkey
    foreign key (voice_assessment_id) references public.voice_assessments(id) on delete cascade,
  constraint voice_qol_scores_assessment_unique unique (voice_assessment_id),
  constraint voice_qol_scores_vhi10_total_check check (vhi10_total >= 0 and vhi10_total <= 40),
  constraint voice_qol_scores_vhi30_total_check check (vhi30_total >= 0 and vhi30_total <= 120)
);

create index if not exists idx_voice_qol_assessment
  on public.voice_qol_scores (voice_assessment_id);

alter table public.voice_qol_scores enable row level security;
drop policy if exists "voice_qol_clinician_own" on public.voice_qol_scores;
create policy "voice_qol_clinician_own" on public.voice_qol_scores
  as permissive for all to authenticated
  using (exists (select 1 from public.voice_assessments va
                 where va.id = voice_qol_scores.voice_assessment_id
                   and va.clinician_id = auth.uid()));
