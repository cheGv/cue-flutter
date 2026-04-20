# Cue — Claude Code Project Context

> **Read this file in full at the start of every non-trivial task.**
> Cue is a clinical operating system for Speech-Language Pathologists. Clinical correctness and memory continuity take priority over code elegance.

---

## 0. The Interface Motto

> "You have one user. The SLP. What is the one thing she needs to
> feel when she opens this? Until you know that feeling, you're
> just building features. Start over from the feeling, not the
> features."
> — Steve Jobs lens on Cue

The feeling Cue must produce:
"This system knows my client better than my paper notes ever
could, and it took me no extra work to get there."

Every UI decision passes this filter before any other.
The enemy of that feeling: clutter, ambiguity, anything that
makes the SLP hunt for a number or re-read a label.

---

## 1. Product Identity

**Cue** is India's first Clinical Operating System for Speech-Language Pathologists (SLPs). It is not a telehealth platform, not a note-taker, not an EMR. It is the **memory and intelligence layer** for an SLP's full caseload.

- **Solo founder:** Guru (AIISH-trained SLP; PROMPT / OPT L1 / COSMI)
- **Brand:** "Cue" — never "Cue AI" in user-facing UI or footer
- **Community & top-of-funnel:** The Engrams (Instagram EBP platform)
- **Thesis:** A *cue* is the smallest possible unit of intervention and the highest possible act of belief in a person with a communication disorder.

## 2. The CUE PRODUCT LAW

> **Cue never adds performative labor to the SLP.**

Every feature must pass this filter before being built. If a feature would require the SLP to do *additional* work to serve the system (extra data entry, extra review steps, extra parent coaching, extra translation), it is rejected or redesigned.

Corollaries:
- AI output must slot into existing clinical workflow, not add a new one.
- Parent-facing artifacts are generated *automatically* from clinician work, never re-typed.
- Structured data capture must be a byproduct of what the SLP already does (documentation, Narrator sessions), not a new form.

## 3. Phase Scope

| Phase | Scope | Status |
|---|---|---|
| **Phase 1** | Clinician OS — caseload, goals (LTG + STG), sessions, SOAP + parent summary AI, Narrator, memory layer | **Active build** |
| **Phase 2** | Clinical AI depth, billing, **Cue Living** parent routine layer | 3–6 mo |
| **Phase 3** | Multi-clinician, full revenue stack, 150 SLPs | 6–12 mo |
| **Phase 4** | Data moat, B2B API, 400 SLPs, ₹2.57Cr/yr | 12–24 mo |

**Phase 1 is strictly clinician-only.** The parent portal does not ship in Phase 1. However, Phase 1 schema must include forward-compatible fields (`parent_visible`, `parent_friendly_label`, `parent_routine_anchor`) so Phase 2 migration is trivial.

**AI success metric:** SLPs edit <10% of generated report content.
**Pricing:** ₹999/month Pro tier. No revenue/money figures displayed in dashboard UI.

## 4. Tech Stack & Infrastructure

- **Frontend:** Flutter Web (`chegv.github.io/cue-flutter`, deployed via GitHub Actions)
- **Backend:** Supabase (project id: `cgnjbjbargkxtcnafxaa`)
- **AI proxy:** Render.com → Anthropic API (bypasses `functions.invoke()` with plain `http.post` due to resolved JWT ES256/HS256 mismatch)
- **Narrator:** OpenAI Whisper + GPT-4o-mini (earmarked for migration to Anthropic Claude)
- **Tooling:** Claude Code is the primary engineering harness. Supabase MCP used for all schema changes and RLS management. Gemini free tier reserved for large-context analysis tasks only.

**Resolved bugs — do not reintroduce:**
- Supabase project URL typo
- CORS whitelist must include GitHub Pages origin
- JWT ES256/HS256 mismatch — use plain `http.post` not `functions.invoke()`
- RLS silently blocking goals reads — currently disabled for prototype (see §11)

## 5. Design System

**"Apple-clinical minimal."** Information density under cognitive load is the north star, not aesthetic flourish.

- **Fonts:** Playfair Display (display), Syne (accent), DM Sans (body)
- **Palette:** Off-white `#FAFAF7` background, navy `#1B2B4B` accent, hairline borders (no shadows)
- **Layout:** Persistent sidebar on desktop (use `LayoutBuilder`, never `MediaQuery`)
- **Mobile:** Responsive, landing page already rebuilt for mobile
- **Principle:** STGs are the **spine** of the patient detail view. Everything else (notes, Narrator, AAC state) hangs off them. Critical clinical info should live in the same spatial location every time — like a chess engine's evaluation bar or a pilot's altimeter.

## 6. Clinical Definitions

These definitions are load-bearing. Every schema field and AI prompt must respect this vocabulary.

### 6.1 Long-Term Goal (LTG)
Directional, typically 6–12 months. Narrative but **categorized** (domain + framework). Answers "where is this client going?"

### 6.2 Short-Term Goal (STG)
The **measurable operational unit** of clinical work. Typically 4–12 weeks. An STG in Cue is **not a static record** — it is a living object that accumulates session-level evidence. The same STG row at week 1 vs week 6 carries different clinical meaning because of accumulated evidence.

Every STG has:
- A **target behavior** (what)
- A **context** (where/how: structured drill, play-based, natural routine)
- A **mastery criterion** (accuracy %, consecutive sessions, trials)
- A **support level** (current + initial, see §6.3)
- A **domain** and **framework** tag

### 6.3 Support Level (controlled vocabulary)
From least to most scaffolding:
`independent` → `minimal` → `moderate` → `maximal` → `hand_over_hand`

> **Neurodiversity-affirming framing:** the support level describes the degree of scaffolding the clinician brings to a communicative moment, not a behaviorist prompt hierarchy. "Maximal support" is not a failure state — it reflects the current level of co-regulation the client needs to access a target skill.

### 6.4 Domain (controlled vocabulary)
`articulation`, `phonology`, `expressive_language`, `receptive_language`, `pragmatics`, `fluency`, `voice`, `motor_speech`, `feeding_swallowing`, `AAC_operational`, `AAC_linguistic`, `AAC_social`, `literacy`, `cognitive_communication`

### 6.5 Framework (controlled vocabulary)
`PROMPT`, `OPT`, `AAC`, `NLA`, `DIR`, `Hanen`, `PECS`, `Core_Word`, `Motor_Speech`, `Phonological_Process`, `Interoception_Informed`, `Polyvagal_Informed`, `Other`

### 6.6 STG Status
`active` | `mastered` | `on_hold` | `discontinued` | `modified`

### 6.7 Evidence
A row in `stg_evidence` represents one session's measurable contribution to an STG. Evidence may be manually entered by the SLP or AI-extracted from the Narrator transcript / session note. Every AI-extracted row carries a confidence score and a `clinician_verified` flag.

---

## 7. Database Schema — Target State
> ⚠️ Schema drift note (confirmed 19 Apr 2026):
> Prototype uses `clients` (not `patients`) and `sessions.id` is `bigint` (not `uuid`).
> `short_term_goals` uses `long_term_goal_id`, `client_id`, `user_id` as FK column names.
> Flutter data layer must match actual Supabase column names, not §7 canonical names.
> DDL below is the canonical target. Run it via Supabase MCP `apply_migration`.
> For the immediate additive migration (STG + evidence + attestation), see §8.

```sql
-- =========================================================
-- PATIENTS (soft-deleted roster)
-- =========================================================
create table if not exists patients (
  id uuid primary key default gen_random_uuid(),
  clinician_id uuid not null references auth.users(id),

  full_name text not null,
  date_of_birth date,
  primary_language text,
  additional_languages text[],
  diagnosis text[],

  intake_summary text,

  deleted_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_patients_clinician_active
  on patients(clinician_id) where deleted_at is null;

-- =========================================================
-- LONG-TERM GOALS
-- =========================================================
create table if not exists long_term_goals (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references patients(id) on delete cascade,

  description text not null,
  domain text,        -- see §6.4
  framework text,     -- see §6.5

  target_date date,
  status text not null default 'active',  -- active | met | modified | discontinued
  rationale text,

  created_by uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_ltg_patient on long_term_goals(patient_id, status);

-- =========================================================
-- SHORT-TERM GOALS  (the memory layer spine)
-- =========================================================
create table if not exists short_term_goals (
  id uuid primary key default gen_random_uuid(),
  ltg_id uuid not null references long_term_goals(id) on delete cascade,
  patient_id uuid not null references patients(id) on delete cascade,

  -- Core clinical structure
  target_behavior text not null,
  context text not null,
  mastery_criterion jsonb not null,
    -- canonical shape: {
    --   "accuracy_pct": 80,
    --   "consecutive_sessions": 3,
    --   "trials_per_session": 10
    -- }

  -- Cue hierarchy
  current_cue_level text not null,  -- see §6.3
  initial_cue_level text not null,
  cue_fade_plan text,

  -- State (updated by AI from stg_evidence)
  status text not null default 'active',  -- see §6.6
  current_accuracy numeric,               -- rolling average
  sessions_at_criterion int default 0,    -- consecutive meeting criterion
  total_sessions_worked int default 0,

  -- Clinical tags
  framework text,  -- see §6.5
  domain text,     -- see §6.4

  -- Phase 2 forward-compatible (keep null in Phase 1)
  parent_visible boolean default false,
  parent_friendly_label text,
  parent_routine_anchor text,
    -- expected values: 'morning_routine', 'mealtime', 'bathtime',
    -- 'school_pickup', 'bedtime', 'play_time', 'commute'

  -- Metadata
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  mastered_at timestamptz
);
create index if not exists idx_stg_patient_active
  on short_term_goals(patient_id, status);
create index if not exists idx_stg_ltg on short_term_goals(ltg_id);

-- =========================================================
-- STG EVIDENCE  (session-level accumulation — the moat)
-- =========================================================
create table if not exists stg_evidence (
  id uuid primary key default gen_random_uuid(),
  stg_id uuid not null references short_term_goals(id) on delete cascade,
  session_id uuid not null references sessions(id) on delete cascade,
  patient_id uuid not null references patients(id) on delete cascade,

  -- Measurement
  trials_attempted int,
  trials_correct int,
  accuracy_pct numeric generated always as (
    case when trials_attempted > 0
      then round((trials_correct::numeric / trials_attempted) * 100, 2)
      else null end
  ) stored,

  cue_level_used text,         -- see §6.3
  context_this_session text,

  -- Qualitative
  clinician_observation text,  -- AI-extracted or manually entered
  recommendation text,         -- e.g., "fade to minimal cue next session"

  -- AI provenance + clinical verification
  source text not null,
    -- 'manual_entry' | 'ai_extracted_narrator' | 'ai_extracted_note'
  ai_confidence numeric,       -- 0-1
  clinician_verified boolean default false,

  created_at timestamptz default now()
);
create index if not exists idx_evidence_stg
  on stg_evidence(stg_id, created_at desc);
create index if not exists idx_evidence_session on stg_evidence(session_id);

-- =========================================================
-- SESSIONS
-- =========================================================
create table if not exists sessions (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references patients(id) on delete cascade,
  clinician_id uuid not null references auth.users(id),

  session_date timestamptz not null,
  duration_minutes int,
  session_type text,
    -- 'individual' | 'group' | 'parent_coaching' | 'assessment'

  -- Content
  soap_note jsonb,          -- { s: ..., o: ..., a: ..., p: ... }
  parent_summary text,      -- plain-language version

  -- AI attestation gate (liability architecture — §9)
  ai_generated boolean default false,
  clinician_attested boolean default false,
  attested_at timestamptz,
  attested_by uuid references auth.users(id),

  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists idx_sessions_patient_date
  on sessions(patient_id, session_date desc);

-- =========================================================
-- NARRATOR TRANSCRIPTS
-- =========================================================
create table if not exists narrator_transcripts (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references sessions(id) on delete cascade,

  raw_audio_url text,
  raw_transcript text,       -- Whisper output (migrating to Claude)
  processed_transcript text, -- cleaned

  primary_language text,
  detected_languages text[], -- for code-switching detection

  processing_status text default 'pending',
    -- 'pending' | 'transcribing' | 'processing' | 'complete' | 'failed'

  created_at timestamptz default now()
);
create index if not exists idx_narrator_session
  on narrator_transcripts(session_id);
```

## 8. Database Schema — Additive Migration (this sprint)

Run this via Supabase MCP `apply_migration` on project `cgnjbjbargkxtcnafxaa`. It is safe to run against the existing prototype database — it does not drop data.

```sql
-- Migration: 20260419_add_stg_memory_layer

-- 1. Forward-extend LTG if it lacks domain/framework/rationale
alter table long_term_goals
  add column if not exists domain text,
  add column if not exists framework text,
  add column if not exists rationale text,
  add column if not exists target_date date,
  add column if not exists status text not null default 'active';

-- 2. Create STG table
create table if not exists short_term_goals (
  id uuid primary key default gen_random_uuid(),
  ltg_id uuid not null references long_term_goals(id) on delete cascade,
  patient_id uuid not null references patients(id) on delete cascade,
  target_behavior text not null,
  context text not null,
  mastery_criterion jsonb not null,
  current_cue_level text not null,
  initial_cue_level text not null,
  cue_fade_plan text,
  status text not null default 'active',
  current_accuracy numeric,
  sessions_at_criterion int default 0,
  total_sessions_worked int default 0,
  framework text,
  domain text,
  parent_visible boolean default false,
  parent_friendly_label text,
  parent_routine_anchor text,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  mastered_at timestamptz
);
create index if not exists idx_stg_patient_active
  on short_term_goals(patient_id, status);
create index if not exists idx_stg_ltg on short_term_goals(ltg_id);

-- 3. Create evidence table
create table if not exists stg_evidence (
  id uuid primary key default gen_random_uuid(),
  stg_id uuid not null references short_term_goals(id) on delete cascade,
  session_id uuid not null references sessions(id) on delete cascade,
  patient_id uuid not null references patients(id) on delete cascade,
  trials_attempted int,
  trials_correct int,
  accuracy_pct numeric generated always as (
    case when trials_attempted > 0
      then round((trials_correct::numeric / trials_attempted) * 100, 2)
      else null end
  ) stored,
  cue_level_used text,
  context_this_session text,
  clinician_observation text,
  recommendation text,
  source text not null,
  ai_confidence numeric,
  clinician_verified boolean default false,
  created_at timestamptz default now()
);
create index if not exists idx_evidence_stg
  on stg_evidence(stg_id, created_at desc);
create index if not exists idx_evidence_session on stg_evidence(session_id);

-- 4. Attestation gate on sessions
alter table sessions
  add column if not exists ai_generated boolean default false,
  add column if not exists clinician_attested boolean default false,
  add column if not exists attested_at timestamptz,
  add column if not exists attested_by uuid references auth.users(id);

-- 5. updated_at trigger helper (apply to stg + ltg + sessions + patients)
create or replace function set_updated_at() returns trigger as $$
begin new.updated_at = now(); return new; end;
$$ language plpgsql;

drop trigger if exists trg_stg_updated on short_term_goals;
create trigger trg_stg_updated before update on short_term_goals
  for each row execute function set_updated_at();

drop trigger if exists trg_ltg_updated on long_term_goals;
create trigger trg_ltg_updated before update on long_term_goals
  for each row execute function set_updated_at();
```

## 9. AI Behavior Rules

### 9.1 Anti-hallucination (applies to ALL clinical generation)
- Never invent clinical observations not grounded in the Narrator transcript or session note input.
- If data is missing, say "not documented" — never fabricate.
- Structured fields (trials, accuracy, support level) must be `null` if unextractable from source.
- `ai_confidence` must be populated for every `stg_evidence` row with `source = 'ai_extracted_*'`.

### 9.2 Clinician attestation (liability gate)
- **No AI-generated session note enters the clinical record without `clinician_attested = true`.**
- UI must make the attestation action explicit (not a pre-checked box).
- Attestation stores `attested_at` + `attested_by` for audit.

### 9.3 Multilingual fidelity (non-negotiable)
- Telugu, Kannada, Hindi and English code-switching must be preserved in Narrator output verbatim.
- Do **not** translate the child's productions — clinical evidence depends on the exact form produced.
- Parent summaries may be translated on explicit SLP opt-in (Phase 2+).

### 9.4 STG state updates from evidence
When a session is documented, the AI extracts per-STG evidence and updates:
- `current_accuracy` = rolling mean of last N evidence rows (N=5 default)
- `sessions_at_criterion` = consecutive count where `accuracy_pct >= mastery_criterion.accuracy_pct`
- `total_sessions_worked` += 1
- If `sessions_at_criterion >= mastery_criterion.consecutive_sessions` → propose `status = 'mastered'` (requires clinician confirm, never auto-sets)

## 10. Key Invariants / Don't Do This

- ❌ Do not use `MediaQuery` for responsive layout. Use `LayoutBuilder`.
- ❌ Do not use `functions.invoke()` for the Anthropic proxy. Use plain `http.post` to Render.
- ❌ Do not display monetary figures in the SLP dashboard UI.
- ❌ Do not brand as "Cue AI" anywhere. It is "Cue."
- ❌ Do not auto-master an STG. AI proposes, clinician confirms.
- ❌ Do not expose STGs to parents in Phase 1 (schema is ready; UI is not).
- ❌ Do not add a feature that requires *extra* SLP action to serve the system. (CUE PRODUCT LAW.)
- ❌ Do not translate child language productions in Narrator output.
- ❌ Do not use free-form strings where a controlled vocabulary exists (§6.3–6.6).

## 11. Known Issues & Debt

- **RLS is currently disabled** on goals tables for prototype. Before external user onboarding, RLS must be re-enabled with per-clinician row scoping. Policy template:
  ```sql
  alter table short_term_goals enable row level security;
  create policy stg_clinician_isolation on short_term_goals
    using (patient_id in (
      select id from patients where clinician_id = auth.uid() and deleted_at is null
    ));
  ```
  Apply the equivalent policy to `long_term_goals`, `stg_evidence`, `sessions`, `narrator_transcripts`.
- Narrator still uses OpenAI Whisper + GPT-4o-mini. Migrate to Anthropic once Claude voice/transcription maturity permits.
- CDSCO SaMD regulatory pathway mapped but not yet filed — track as Phase 2 prerequisite.
- No billing infrastructure — Phase 2.
- No parent portal — Phase 2 (Cue Living).