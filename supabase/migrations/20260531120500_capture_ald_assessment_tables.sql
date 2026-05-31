-- ============================================================================
-- Capture: adult language & cognitive (ALD) assessment family  (CAPTURE migration)
-- ============================================================================
-- ald_assessments (parent) + 4 one-row-per-assessment children
-- (cognitive_screens, naming_measures, qol_scores, wab_scores). RLS ON
-- throughout (parent owns via client; children own via parent->client).
-- Parent has a BEFORE UPDATE updated_at trigger.
-- ============================================================================
create table if not exists public.ald_assessments (
  id                              uuid        not null default gen_random_uuid(),
  client_id                       uuid        not null,
  clinician_id                    uuid        not null default auth.uid(),
  visit_id                        uuid,
  case_history_payload            jsonb       not null default '{}'::jsonb,
  etiology_category               text,
  acuity_stage                    text,
  time_post_onset_days            integer,
  lesion_location                 text[],
  bedside_screen_payload          jsonb       not null default '{}'::jsonb,
  comprehension_payload           jsonb       not null default '{}'::jsonb,
  reading_writing_payload         jsonb       not null default '{}'::jsonb,
  discourse_payload               jsonb       not null default '{}'::jsonb,
  aphasia_apraxia_payload         jsonb       not null default '{}'::jsonb,
  tbi_payload                     jsonb       not null default '{}'::jsonb,
  rhd_payload                     jsonb       not null default '{}'::jsonb,
  dementia_payload                jsonb       not null default '{}'::jsonb,
  ppa_payload                     jsonb       not null default '{}'::jsonb,
  multilingual_payload            jsonb       not null default '{}'::jsonb,
  cognitive_communication_payload jsonb       not null default '{}'::jsonb,
  differential_diagnosis_payload  jsonb       not null default '{}'::jsonb,
  clinical_impression_payload     jsonb       not null default '{}'::jsonb,
  is_baseline                     boolean     not null default true,
  baseline_assessment_id          uuid,
  attested_at                     timestamptz,
  attested_by                     uuid,
  created_at                      timestamptz not null default now(),
  updated_at                      timestamptz not null default now(),
  constraint ald_assessments_pkey primary key (id),
  constraint ald_assessments_client_id_fkey
    foreign key (client_id) references public.clients(id) on delete cascade,
  constraint ald_assessments_clinician_id_fkey
    foreign key (clinician_id) references auth.users(id),
  constraint ald_assessments_visit_id_fkey
    foreign key (visit_id) references public.assessment_visits(id) on delete set null,
  constraint ald_assessments_baseline_assessment_id_fkey
    foreign key (baseline_assessment_id) references public.ald_assessments(id) on delete set null,
  constraint ald_assessments_attested_by_fkey
    foreign key (attested_by) references auth.users(id)
);

create index if not exists idx_ald_assessments_client
  on public.ald_assessments (client_id, created_at desc);
create index if not exists idx_ald_assessments_baseline
  on public.ald_assessments (baseline_assessment_id) where baseline_assessment_id is not null;
create index if not exists idx_ald_assessments_etiology
  on public.ald_assessments (etiology_category) where etiology_category is not null;
create index if not exists idx_ald_assessments_visit
  on public.ald_assessments (visit_id) where visit_id is not null;

alter table public.ald_assessments enable row level security;
drop policy if exists "slp_owns_via_client" on public.ald_assessments;
create policy "slp_owns_via_client" on public.ald_assessments
  as permissive for all to authenticated
  using (exists (select 1 from public.clients c
                 where c.id = ald_assessments.client_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.clients c
                 where c.id = ald_assessments.client_id and c.clinician_id = auth.uid()));

drop trigger if exists ald_assessments_updated_at on public.ald_assessments;
create trigger ald_assessments_updated_at
  before update on public.ald_assessments
  for each row execute function public.set_updated_at();

-- Child: cognitive screens (MoCA + MMSE) -------------------------------------
create table if not exists public.ald_cognitive_screens (
  id                          uuid        not null default gen_random_uuid(),
  ald_assessment_id           uuid        not null,
  moca_total                  integer,
  moca_visuospatial           integer,
  moca_naming                 integer,
  moca_memory                 integer,
  moca_attention              integer,
  moca_language               integer,
  moca_abstraction            integer,
  moca_orientation            integer,
  moca_education_adjusted     boolean     default false,
  moca_language_administered  text,
  mmse_total                  integer,
  mmse_orientation            integer,
  mmse_registration           integer,
  mmse_attention_calc         integer,
  mmse_recall                 integer,
  mmse_language               integer,
  mmse_language_administered  text,
  notes                       text,
  created_at                  timestamptz not null default now(),
  constraint ald_cognitive_screens_pkey primary key (id),
  constraint ald_cognitive_screens_ald_assessment_id_fkey
    foreign key (ald_assessment_id) references public.ald_assessments(id) on delete cascade,
  constraint ald_cognitive_screens_ald_assessment_id_key unique (ald_assessment_id),
  constraint ald_cognitive_screens_moca_total_check        check (moca_total >= 0 and moca_total <= 30),
  constraint ald_cognitive_screens_moca_visuospatial_check check (moca_visuospatial >= 0 and moca_visuospatial <= 5),
  constraint ald_cognitive_screens_moca_naming_check       check (moca_naming >= 0 and moca_naming <= 3),
  constraint ald_cognitive_screens_moca_memory_check       check (moca_memory >= 0 and moca_memory <= 5),
  constraint ald_cognitive_screens_moca_attention_check    check (moca_attention >= 0 and moca_attention <= 6),
  constraint ald_cognitive_screens_moca_language_check     check (moca_language >= 0 and moca_language <= 3),
  constraint ald_cognitive_screens_moca_abstraction_check  check (moca_abstraction >= 0 and moca_abstraction <= 2),
  constraint ald_cognitive_screens_moca_orientation_check  check (moca_orientation >= 0 and moca_orientation <= 6),
  constraint ald_cognitive_screens_mmse_total_check        check (mmse_total >= 0 and mmse_total <= 30),
  constraint ald_cognitive_screens_mmse_orientation_check  check (mmse_orientation >= 0 and mmse_orientation <= 10),
  constraint ald_cognitive_screens_mmse_registration_check check (mmse_registration >= 0 and mmse_registration <= 3),
  constraint ald_cognitive_screens_mmse_attention_calc_check check (mmse_attention_calc >= 0 and mmse_attention_calc <= 5),
  constraint ald_cognitive_screens_mmse_recall_check       check (mmse_recall >= 0 and mmse_recall <= 3),
  constraint ald_cognitive_screens_mmse_language_check     check (mmse_language >= 0 and mmse_language <= 9)
);
create index if not exists idx_ald_cognitive_assessment
  on public.ald_cognitive_screens (ald_assessment_id);
alter table public.ald_cognitive_screens enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.ald_cognitive_screens;
create policy "slp_owns_via_assessment" on public.ald_cognitive_screens
  as permissive for all to authenticated
  using (exists (select 1 from public.ald_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ald_cognitive_screens.ald_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.ald_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ald_cognitive_screens.ald_assessment_id and c.clinician_id = auth.uid()));

-- Child: naming measures -----------------------------------------------------
create table if not exists public.ald_naming_measures (
  id                        uuid         not null default gen_random_uuid(),
  ald_assessment_id         uuid         not null,
  bnt_raw_score             integer,
  bnt_z_score               numeric(4,2),
  bnt_age_adjusted          boolean      default false,
  ant_raw_score             integer,
  fluency_semantic_animals  integer,
  fluency_phonemic_f        integer,
  fluency_phonemic_a        integer,
  fluency_phonemic_s        integer,
  error_profile             jsonb        default '[]'::jsonb,
  semantic_cue_helps        boolean,
  phonemic_cue_helps        boolean,
  choice_cue_helps          boolean,
  notes                     text,
  created_at                timestamptz  not null default now(),
  constraint ald_naming_measures_pkey primary key (id),
  constraint ald_naming_measures_ald_assessment_id_fkey
    foreign key (ald_assessment_id) references public.ald_assessments(id) on delete cascade,
  constraint ald_naming_measures_ald_assessment_id_key unique (ald_assessment_id),
  constraint ald_naming_measures_bnt_raw_score_check check (bnt_raw_score >= 0 and bnt_raw_score <= 60)
);
create index if not exists idx_ald_naming_assessment
  on public.ald_naming_measures (ald_assessment_id);
alter table public.ald_naming_measures enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.ald_naming_measures;
create policy "slp_owns_via_assessment" on public.ald_naming_measures
  as permissive for all to authenticated
  using (exists (select 1 from public.ald_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ald_naming_measures.ald_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.ald_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ald_naming_measures.ald_assessment_id and c.clinician_id = auth.uid()));

-- Child: QoL scores ----------------------------------------------------------
create table if not exists public.ald_qol_scores (
  id                     uuid         not null default gen_random_uuid(),
  ald_assessment_id      uuid         not null,
  coast_total            integer,
  aiq21_total            integer,
  aiq21_communication    integer,
  aiq21_participation    integer,
  aiq21_emotional        integer,
  saqol39_total          numeric(5,2),
  saqol39_physical       numeric(5,2),
  saqol39_communication  numeric(5,2),
  saqol39_psychosocial   numeric(5,2),
  saqol39_energy         numeric(5,2),
  ceti_total             integer,
  notes                  text,
  created_at             timestamptz  not null default now(),
  constraint ald_qol_scores_pkey primary key (id),
  constraint ald_qol_scores_ald_assessment_id_fkey
    foreign key (ald_assessment_id) references public.ald_assessments(id) on delete cascade,
  constraint ald_qol_scores_ald_assessment_id_key unique (ald_assessment_id)
);
create index if not exists idx_ald_qol_assessment
  on public.ald_qol_scores (ald_assessment_id);
alter table public.ald_qol_scores enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.ald_qol_scores;
create policy "slp_owns_via_assessment" on public.ald_qol_scores
  as permissive for all to authenticated
  using (exists (select 1 from public.ald_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ald_qol_scores.ald_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.ald_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ald_qol_scores.ald_assessment_id and c.clinician_id = auth.uid()));

-- Child: WAB-R scores --------------------------------------------------------
create table if not exists public.ald_wab_scores (
  id                          uuid         not null default gen_random_uuid(),
  ald_assessment_id           uuid         not null,
  ss_information_content      integer,
  ss_fluency                  integer,
  avc_yes_no                  integer,
  avc_word_recognition        integer,
  avc_sequential_commands     integer,
  repetition_score            integer,
  naming_object               integer,
  naming_word_fluency         integer,
  naming_sentence_completion  integer,
  naming_responsive_speech    integer,
  aphasia_quotient            numeric(5,2),
  cortical_quotient           numeric(5,2),
  aphasia_type                text,
  reading_score               integer,
  writing_score               integer,
  battery_version             text         default 'WAB-R',
  language_administered       text,
  notes                       text,
  created_at                  timestamptz  not null default now(),
  constraint ald_wab_scores_pkey primary key (id),
  constraint ald_wab_scores_ald_assessment_id_fkey
    foreign key (ald_assessment_id) references public.ald_assessments(id) on delete cascade,
  constraint ald_wab_scores_ald_assessment_id_key unique (ald_assessment_id),
  constraint ald_wab_scores_ss_information_content_check check (ss_information_content >= 0 and ss_information_content <= 10),
  constraint ald_wab_scores_ss_fluency_check check (ss_fluency >= 0 and ss_fluency <= 10),
  constraint ald_wab_scores_avc_yes_no_check check (avc_yes_no >= 0 and avc_yes_no <= 60),
  constraint ald_wab_scores_avc_word_recognition_check check (avc_word_recognition >= 0 and avc_word_recognition <= 60),
  constraint ald_wab_scores_avc_sequential_commands_check check (avc_sequential_commands >= 0 and avc_sequential_commands <= 80),
  constraint ald_wab_scores_repetition_score_check check (repetition_score >= 0 and repetition_score <= 100),
  constraint ald_wab_scores_naming_object_check check (naming_object >= 0 and naming_object <= 60),
  constraint ald_wab_scores_naming_word_fluency_check check (naming_word_fluency >= 0 and naming_word_fluency <= 20),
  constraint ald_wab_scores_naming_sentence_completion_check check (naming_sentence_completion >= 0 and naming_sentence_completion <= 10),
  constraint ald_wab_scores_naming_responsive_speech_check check (naming_responsive_speech >= 0 and naming_responsive_speech <= 10),
  constraint ald_wab_scores_aphasia_quotient_check check (aphasia_quotient >= 0 and aphasia_quotient <= 100),
  constraint ald_wab_scores_cortical_quotient_check check (cortical_quotient >= 0 and cortical_quotient <= 100)
);
create index if not exists idx_ald_wab_assessment
  on public.ald_wab_scores (ald_assessment_id);
alter table public.ald_wab_scores enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.ald_wab_scores;
create policy "slp_owns_via_assessment" on public.ald_wab_scores
  as permissive for all to authenticated
  using (exists (select 1 from public.ald_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ald_wab_scores.ald_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.ald_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ald_wab_scores.ald_assessment_id and c.clinician_id = auth.uid()));
