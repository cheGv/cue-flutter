-- ============================================================================
-- Capture: pediatric dysarthria assessment family  (CAPTURE migration)
-- ============================================================================
-- ped_dysarthria_assessments (parent) + 5 one-row-per-assessment children
-- (aerodynamic_measures, ddk_rates, intelligibility, qol_scores,
-- subsystem_severity). RLS ON throughout (parent owns via client; children own
-- via parent->client). Parent has a BEFORE UPDATE updated_at trigger.
-- ============================================================================
create table if not exists public.ped_dysarthria_assessments (
  id                              uuid        not null default gen_random_uuid(),
  client_id                       uuid        not null,
  clinician_id                    uuid        not null default auth.uid(),
  visit_id                        uuid,
  chronological_age_months        integer,
  corrected_age_months            integer,
  gestational_age_weeks           integer,
  mental_age_months               integer,
  mental_age_source               text,
  receptive_language_age_months   integer,
  receptive_age_source            text,
  expressive_language_age_months  integer,
  expressive_age_source           text,
  speech_age_months               integer,
  speech_age_source               text,
  social_pragmatic_age_months     integer,
  social_pragmatic_age_source     text,
  developmental_estimates_notes   text,
  etiology_category               text,
  cp_subtype                      text,
  gmfcs_level                     text,
  macs_level                      text,
  cfcs_level                      text,
  edacs_level                     text,
  vfcs_level                      text,
  last_botox_date                 date,
  mayo_dysarthria_type            text,
  case_history_payload            jsonb       not null default '{}'::jsonb,
  bedside_screen_payload          jsonb       not null default '{}'::jsonb,
  five_subsystems_payload         jsonb       not null default '{}'::jsonb,
  oral_mech_payload               jsonb       not null default '{}'::jsonb,
  connected_speech_payload        jsonb       not null default '{}'::jsonb,
  stimulability_payload           jsonb       not null default '{}'::jsonb,
  cerebral_palsy_payload          jsonb       not null default '{}'::jsonb,
  post_encephalitis_payload       jsonb       not null default '{}'::jsonb,
  post_tbi_payload                jsonb       not null default '{}'::jsonb,
  genetic_syndrome_payload        jsonb       not null default '{}'::jsonb,
  mixed_idiopathic_payload        jsonb       not null default '{}'::jsonb,
  functional_communication_payload jsonb      not null default '{}'::jsonb,
  differential_diagnosis_payload  jsonb       not null default '{}'::jsonb,
  clinical_impression_payload     jsonb       not null default '{}'::jsonb,
  flag_dysphagia_referral         boolean     default false,
  flag_aac_assessment             boolean     default false,
  is_baseline                     boolean     not null default true,
  baseline_assessment_id          uuid,
  attested_at                     timestamptz,
  attested_by                     uuid,
  created_at                      timestamptz not null default now(),
  updated_at                      timestamptz not null default now(),
  constraint ped_dysarthria_assessments_pkey primary key (id),
  constraint ped_dysarthria_assessments_client_id_fkey
    foreign key (client_id) references public.clients(id) on delete cascade,
  constraint ped_dysarthria_assessments_clinician_id_fkey
    foreign key (clinician_id) references auth.users(id),
  constraint ped_dysarthria_assessments_visit_id_fkey
    foreign key (visit_id) references public.assessment_visits(id) on delete set null,
  constraint ped_dysarthria_assessments_baseline_assessment_id_fkey
    foreign key (baseline_assessment_id) references public.ped_dysarthria_assessments(id) on delete set null,
  constraint ped_dysarthria_assessments_attested_by_fkey
    foreign key (attested_by) references auth.users(id),
  constraint ped_dysarthria_assessments_gmfcs_level_check check (gmfcs_level = any (array['I','II','III','IV','V'])),
  constraint ped_dysarthria_assessments_macs_level_check  check (macs_level  = any (array['I','II','III','IV','V'])),
  constraint ped_dysarthria_assessments_cfcs_level_check  check (cfcs_level  = any (array['I','II','III','IV','V'])),
  constraint ped_dysarthria_assessments_edacs_level_check check (edacs_level = any (array['I','II','III','IV','V'])),
  constraint ped_dysarthria_assessments_vfcs_level_check  check (vfcs_level  = any (array['I','II','III','IV','V']))
);

create index if not exists idx_ped_dys_assessments_client
  on public.ped_dysarthria_assessments (client_id, created_at desc);
create index if not exists idx_ped_dys_assessments_baseline
  on public.ped_dysarthria_assessments (baseline_assessment_id) where baseline_assessment_id is not null;
create index if not exists idx_ped_dys_assessments_etiology
  on public.ped_dysarthria_assessments (etiology_category) where etiology_category is not null;

alter table public.ped_dysarthria_assessments enable row level security;
drop policy if exists "slp_owns_via_client" on public.ped_dysarthria_assessments;
create policy "slp_owns_via_client" on public.ped_dysarthria_assessments
  as permissive for all to authenticated
  using (exists (select 1 from public.clients c
                 where c.id = ped_dysarthria_assessments.client_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.clients c
                 where c.id = ped_dysarthria_assessments.client_id and c.clinician_id = auth.uid()));

drop trigger if exists ped_dysarthria_assessments_updated_at on public.ped_dysarthria_assessments;
create trigger ped_dysarthria_assessments_updated_at
  before update on public.ped_dysarthria_assessments
  for each row execute function public.set_updated_at();

-- Child: aerodynamic measures ------------------------------------------------
create table if not exists public.ped_dys_aerodynamic_measures (
  id                            uuid         not null default gen_random_uuid(),
  ped_dysarthria_assessment_id  uuid         not null,
  max_sustained_ah_seconds      numeric(5,2),
  s_z_ratio                     numeric(4,2),
  vital_capacity_estimate       text,
  words_per_breath              integer,
  syllables_per_breath          integer,
  breath_support_pattern        text,
  air_wastage                   text,
  notes                         text,
  created_at                    timestamptz  not null default now(),
  constraint ped_dys_aerodynamic_measures_pkey primary key (id),
  constraint ped_dys_aerodynamic_measures_ped_dysarthria_assessment_id_fkey
    foreign key (ped_dysarthria_assessment_id) references public.ped_dysarthria_assessments(id) on delete cascade,
  constraint ped_dys_aerodynamic_measures_ped_dysarthria_assessment_id_key unique (ped_dysarthria_assessment_id)
);
create index if not exists idx_ped_dys_aerodynamic_assessment
  on public.ped_dys_aerodynamic_measures (ped_dysarthria_assessment_id);
alter table public.ped_dys_aerodynamic_measures enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.ped_dys_aerodynamic_measures;
create policy "slp_owns_via_assessment" on public.ped_dys_aerodynamic_measures
  as permissive for all to authenticated
  using (exists (select 1 from public.ped_dysarthria_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ped_dys_aerodynamic_measures.ped_dysarthria_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.ped_dysarthria_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ped_dys_aerodynamic_measures.ped_dysarthria_assessment_id and c.clinician_id = auth.uid()));

-- Child: DDK rates -----------------------------------------------------------
create table if not exists public.ped_dys_ddk_rates (
  id                            uuid         not null default gen_random_uuid(),
  ped_dysarthria_assessment_id  uuid         not null,
  puh_per_sec                   numeric(4,2),
  tuh_per_sec                   numeric(4,2),
  kuh_per_sec                   numeric(4,2),
  pataka_per_sec                numeric(4,2),
  ddk_regularity                text,
  ddk_accuracy                  text,
  notes                         text,
  created_at                    timestamptz  not null default now(),
  constraint ped_dys_ddk_rates_pkey primary key (id),
  constraint ped_dys_ddk_rates_ped_dysarthria_assessment_id_fkey
    foreign key (ped_dysarthria_assessment_id) references public.ped_dysarthria_assessments(id) on delete cascade,
  constraint ped_dys_ddk_rates_ped_dysarthria_assessment_id_key unique (ped_dysarthria_assessment_id)
);
create index if not exists idx_ped_dys_ddk_assessment
  on public.ped_dys_ddk_rates (ped_dysarthria_assessment_id);
alter table public.ped_dys_ddk_rates enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.ped_dys_ddk_rates;
create policy "slp_owns_via_assessment" on public.ped_dys_ddk_rates
  as permissive for all to authenticated
  using (exists (select 1 from public.ped_dysarthria_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ped_dys_ddk_rates.ped_dysarthria_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.ped_dysarthria_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ped_dys_ddk_rates.ped_dysarthria_assessment_id and c.clinician_id = auth.uid()));

-- Child: intelligibility -----------------------------------------------------
create table if not exists public.ped_dys_intelligibility (
  id                               uuid         not null default gen_random_uuid(),
  ped_dysarthria_assessment_id     uuid         not null,
  ics_item1                        integer,
  ics_item2                        integer,
  ics_item3                        integer,
  ics_item4                        integer,
  ics_item5                        integer,
  ics_item6                        integer,
  ics_item7                        integer,
  ics_total                        integer,
  ics_average                      numeric(3,2),
  csim_single_word_pct             numeric(5,2),
  csim_sentence_pct                numeric(5,2),
  listener_familiar_primary_pct    numeric(5,2),
  listener_familiar_secondary_pct  numeric(5,2),
  listener_peers_pct               numeric(5,2),
  listener_teachers_pct            numeric(5,2),
  listener_unfamiliar_adults_pct   numeric(5,2),
  context_familiar_pct             numeric(5,2),
  context_unfamiliar_pct           numeric(5,2),
  words_per_minute                 numeric(5,2),
  audio_recording_url              text,
  notes                            text,
  created_at                       timestamptz  not null default now(),
  constraint ped_dys_intelligibility_pkey primary key (id),
  constraint ped_dys_intelligibility_ped_dysarthria_assessment_id_fkey
    foreign key (ped_dysarthria_assessment_id) references public.ped_dysarthria_assessments(id) on delete cascade,
  constraint ped_dys_intelligibility_ped_dysarthria_assessment_id_key unique (ped_dysarthria_assessment_id),
  constraint ped_dys_intelligibility_ics_item1_check check (ics_item1 >= 1 and ics_item1 <= 5),
  constraint ped_dys_intelligibility_ics_item2_check check (ics_item2 >= 1 and ics_item2 <= 5),
  constraint ped_dys_intelligibility_ics_item3_check check (ics_item3 >= 1 and ics_item3 <= 5),
  constraint ped_dys_intelligibility_ics_item4_check check (ics_item4 >= 1 and ics_item4 <= 5),
  constraint ped_dys_intelligibility_ics_item5_check check (ics_item5 >= 1 and ics_item5 <= 5),
  constraint ped_dys_intelligibility_ics_item6_check check (ics_item6 >= 1 and ics_item6 <= 5),
  constraint ped_dys_intelligibility_ics_item7_check check (ics_item7 >= 1 and ics_item7 <= 5)
);
create index if not exists idx_ped_dys_intelligibility_assessment
  on public.ped_dys_intelligibility (ped_dysarthria_assessment_id);
alter table public.ped_dys_intelligibility enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.ped_dys_intelligibility;
create policy "slp_owns_via_assessment" on public.ped_dys_intelligibility
  as permissive for all to authenticated
  using (exists (select 1 from public.ped_dysarthria_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ped_dys_intelligibility.ped_dysarthria_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.ped_dysarthria_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ped_dys_intelligibility.ped_dysarthria_assessment_id and c.clinician_id = auth.uid()));

-- Child: QoL scores ----------------------------------------------------------
create table if not exists public.ped_dys_qol_scores (
  id                            uuid        not null default gen_random_uuid(),
  ped_dysarthria_assessment_id  uuid        not null,
  focus34_total                 integer,
  parent_confidence_rating      integer,
  teacher_impact_rating         integer,
  peer_interaction_rating       integer,
  notes                         text,
  created_at                    timestamptz not null default now(),
  constraint ped_dys_qol_scores_pkey primary key (id),
  constraint ped_dys_qol_scores_ped_dysarthria_assessment_id_fkey
    foreign key (ped_dysarthria_assessment_id) references public.ped_dysarthria_assessments(id) on delete cascade,
  constraint ped_dys_qol_scores_ped_dysarthria_assessment_id_key unique (ped_dysarthria_assessment_id)
);
create index if not exists idx_ped_dys_qol_assessment
  on public.ped_dys_qol_scores (ped_dysarthria_assessment_id);
alter table public.ped_dys_qol_scores enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.ped_dys_qol_scores;
create policy "slp_owns_via_assessment" on public.ped_dys_qol_scores
  as permissive for all to authenticated
  using (exists (select 1 from public.ped_dysarthria_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ped_dys_qol_scores.ped_dysarthria_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.ped_dysarthria_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ped_dys_qol_scores.ped_dysarthria_assessment_id and c.clinician_id = auth.uid()));

-- Child: subsystem severity --------------------------------------------------
create table if not exists public.ped_dys_subsystem_severity (
  id                            uuid        not null default gen_random_uuid(),
  ped_dysarthria_assessment_id  uuid        not null,
  respiration_severity          text,
  phonation_severity            text,
  articulation_severity         text,
  resonance_severity            text,
  prosody_severity              text,
  primary_subsystem             text,
  notes                         text,
  created_at                    timestamptz not null default now(),
  constraint ped_dys_subsystem_severity_pkey primary key (id),
  constraint ped_dys_subsystem_severity_ped_dysarthria_assessment_id_fkey
    foreign key (ped_dysarthria_assessment_id) references public.ped_dysarthria_assessments(id) on delete cascade,
  constraint ped_dys_subsystem_severity_ped_dysarthria_assessment_id_key unique (ped_dysarthria_assessment_id),
  constraint ped_dys_subsystem_severity_respiration_severity_check check (respiration_severity = any (array['mild','moderate','severe'])),
  constraint ped_dys_subsystem_severity_phonation_severity_check   check (phonation_severity   = any (array['mild','moderate','severe'])),
  constraint ped_dys_subsystem_severity_articulation_severity_check check (articulation_severity = any (array['mild','moderate','severe'])),
  constraint ped_dys_subsystem_severity_resonance_severity_check   check (resonance_severity   = any (array['mild','moderate','severe'])),
  constraint ped_dys_subsystem_severity_prosody_severity_check     check (prosody_severity     = any (array['mild','moderate','severe']))
);
create index if not exists idx_ped_dys_subsystem_assessment
  on public.ped_dys_subsystem_severity (ped_dysarthria_assessment_id);
alter table public.ped_dys_subsystem_severity enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.ped_dys_subsystem_severity;
create policy "slp_owns_via_assessment" on public.ped_dys_subsystem_severity
  as permissive for all to authenticated
  using (exists (select 1 from public.ped_dysarthria_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ped_dys_subsystem_severity.ped_dysarthria_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.ped_dysarthria_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ped_dys_subsystem_severity.ped_dysarthria_assessment_id and c.clinician_id = auth.uid()));
