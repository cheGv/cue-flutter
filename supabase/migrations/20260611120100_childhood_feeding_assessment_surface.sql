-- ============================================================================
-- Childhood Feeding — Phase 1 (capture): feeding assessment surface  (CREATE)
-- ============================================================================
-- Net-new FEEDING-SKILLS capture surface (oral-motor dissociation + the
-- developmental feeding ladder + mealtime behaviours). This is NOT a
-- swallowing / dysphagia surface — airway safety is a separate later surface
-- with its own boundary; this surface only FLAGS toward it (the off-ramp).
--
-- SAFETY POSTURE (the SSD/CAS contract, TIGHTENED for airway-adjacent scope —
-- do NOT relax):
--   1. Cue NEVER judges feeding adequacy, developmental status, or swallow
--      safety. No column stores a Cue-computed verdict; every judgement
--      column (ladder marking, behaviour status, dissociation status) is
--      clinician-set, NULL by default, never auto-set.
--   2. The ladder surfaces what is EXPECTED at an age — it never declares a
--      child "behind". The gap between expectation and observation is visible
--      to the clinician; Cue never computes or labels it. There is no derived
--      metric anywhere on this surface.
--   3. Red-flag text is an OBSERVATION PROMPT ("watch for X at this age"),
--      never a verdict ("this child has X"). The red_flag_prompt column is
--      seeded reference content, not a finding.
--   4. Empty stays empty. No column carries a clinical DB default, so an
--      untouched column is NULL and renders as absent — never a fabricated
--      "within normal limits", never an invented mark.
--   5. Overt airway signs (coughing / choking / wet voice on textured food)
--      are beyond feeding-skills scope. The surface renders the swallow
--      off-ramp caution; rows that represent airway signs carry
--      airway_sign = true so the off-ramp trigger is structural, not
--      inferred from free text.
--
-- CONTENT PROVENANCE (brand-neutral — no commercial framework names):
--   Developmental expectations and observation prompts derive from the
--   developmental-feeding literature: Arvedson (pediatric feeding/swallowing
--   assessment), Delaney & Goday (development of oral feeding skills),
--   the New York State Early Intervention clinical practice guideline,
--   ASHA practice guidance, and the Goday et al. pediatric feeding disorder
--   consensus. Milestones are predominantly Western-cohort derived; the
--   surface renders a cultural-context caveat with every band (wording in
--   lib/constants/feeding_ladder_content.dart, draft pending founder review).
--
-- DRAFT-CONTENT FLAG (clinician sign-off PENDING — acceptable in sandbox,
-- MUST be reviewed before this surface graduates to draftable):
--   * feeding_ladder_bands.red_flag_prompt seeded text
--   * the off-ramp trigger conditions (band >= 18mo OR airway-sign behaviour
--     marked present)
--   * the Western-norm caveat wording
--
-- CAPTURE-AS-IS (intentional — hardening is a later, deliberate migration):
--   * RLS is LEFT OFF on all three feeding tables, matching the live SSD/CAS
--     siblings.
--   * Child tables carry NO unique constraint on their FK (multi-row
--     children); adding one is a later fix after checking live data.
--   * clinician_id has no FK and no default, matching the SSD/CAS parents.
--   * No set_updated_at trigger — the SSD/CAS parents do not hook it.
-- Idempotent: CREATE TABLE / INDEX IF NOT EXISTS; guarded ADD CONSTRAINT.
-- ============================================================================

-- Parent ---------------------------------------------------------------------
-- Layer 1 (oral-motor dissociation) lives FLAT on the parent: five fixed
-- functions, one status + one notes column each — the SSD pattern for fixed
-- singletons (groping_searching et al.). status: present | emerging | absent,
-- clinician-marked, NULL until touched.
create table if not exists public.feeding_assessments (
  id            uuid        not null default gen_random_uuid(),
  client_id     uuid        not null,
  clinician_id  uuid,
  age_months    integer,

  -- LAYER 1 — oral-motor dissociation (observable-sign-first capture; the
  -- plain-language sign + clinical term render in the surface, the column
  -- stores only the clinician's mark).
  jaw_stability             text,   -- jaw stability / grading
  jaw_stability_notes       text,
  jaw_lip_dissociation      text,
  jaw_lip_dissociation_notes  text,
  jaw_tongue_dissociation   text,
  jaw_tongue_dissociation_notes text,
  lip_control               text,
  lip_control_notes         text,
  tongue_control            text,
  tongue_control_notes      text,

  capture_notes text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint feeding_assessments_pkey primary key (id),
  constraint feeding_assessments_client_id_fkey
    foreign key (client_id) references public.clients(id) on delete cascade,
  constraint feeding_assessments_jaw_stability_check
    check (jaw_stability = any (array['present','emerging','absent'])),
  constraint feeding_assessments_jaw_lip_dissociation_check
    check (jaw_lip_dissociation = any (array['present','emerging','absent'])),
  constraint feeding_assessments_jaw_tongue_dissociation_check
    check (jaw_tongue_dissociation = any (array['present','emerging','absent'])),
  constraint feeding_assessments_lip_control_check
    check (lip_control = any (array['present','emerging','absent'])),
  constraint feeding_assessments_tongue_control_check
    check (tongue_control = any (array['present','emerging','absent']))
);

create index if not exists idx_feeding_assessments_client
  on public.feeding_assessments (client_id);

-- Child: developmental feeding ladder (SEEDED — the normative spine) ----------
-- Seven fixed age bands, seeded per assessment like ssd_length_effect's three
-- levels (FeedingAssessmentService.ensureLadderBands). The band CONTENT
-- (expected texture / self-feeding / oral-motor, red-flag prompt) is seeded
-- INTO the row, version-freezing what the clinician saw at capture time —
-- if the reference text is later revised, past assessments keep the text
-- they were marked against (clinical provenance).
--
-- The ONLY clinical capture columns are clinician_marking + notes; both NULL
-- until the clinician touches them. clinician_marking is the clinician's
-- judgement of the child against the band — Cue never sets it and never
-- derives anything from it.
create table if not exists public.feeding_ladder_bands (
  id                     uuid        not null default gen_random_uuid(),
  feeding_assessment_id  uuid        not null,
  band_key               text        not null,   -- '0_6mo' … '30_36mo_plus' (structural)
  band_order             integer     not null,   -- 1..7
  band_label             text        not null,   -- '0–6 months' …
  age_min_months         integer     not null,
  age_max_months         integer,                -- NULL = open-ended (band 7)
  expected_texture       text        not null,   -- seeded reference content
  expected_self_feeding  text        not null,
  expected_oral_motor    text        not null,
  red_flag_prompt        text        not null,   -- OBSERVATION PROMPT — DRAFT, sign-off pending
  off_ramp_band          boolean     not null,   -- structural: 18mo+ bands carry the off-ramp marker
  clinician_marking      text,                   -- at_level | emerging | below_level | not_tested
  notes                  text,
  created_at             timestamptz not null default now(),
  constraint feeding_ladder_bands_pkey primary key (id),
  constraint feeding_ladder_bands_assessment_fkey
    foreign key (feeding_assessment_id) references public.feeding_assessments(id) on delete cascade,
  constraint feeding_ladder_bands_clinician_marking_check
    check (clinician_marking = any (array['at_level','emerging','below_level','not_tested']))
);

create index if not exists idx_feeding_ladder_bands_parent
  on public.feeding_ladder_bands (feeding_assessment_id, band_order);

-- Child: feeding behaviours (CLINICIAN-ADDED) ---------------------------------
-- One row per observed-for behaviour. The clinician adds rows from a
-- literature-grounded starter set or free-types her own. behavior_key is the
-- starter-set key (NULL for free-typed rows); behavior_label is the display
-- text either way. airway_sign is CLASSIFICATION METADATA (set explicitly at
-- insert, never a DB default) — true marks the row as an overt airway sign
-- whose presence triggers the swallow off-ramp. status is the clinical
-- capture: present | absent (absent is a real negative finding — "checked,
-- not observed"); NULL = not yet marked.
create table if not exists public.feeding_behaviors (
  id                     uuid        not null default gen_random_uuid(),
  feeding_assessment_id  uuid        not null,
  behavior_key           text,                   -- starter-set key; NULL for free-typed
  behavior_label         text        not null,
  airway_sign            boolean     not null,   -- explicit at insert; drives the off-ramp
  status                 text,                   -- present | absent
  notes                  text,
  created_at             timestamptz not null default now(),
  constraint feeding_behaviors_pkey primary key (id),
  constraint feeding_behaviors_assessment_fkey
    foreign key (feeding_assessment_id) references public.feeding_assessments(id) on delete cascade,
  constraint feeding_behaviors_status_check
    check (status = any (array['present','absent']))
);

create index if not exists idx_feeding_behaviors_parent
  on public.feeding_behaviors (feeding_assessment_id);
