# CUE NORTH STAR

**JARVIS for SLPs. Expanding to all of rehabilitation.**

JARVIS doesn't wait to be asked.
JARVIS reads the room.
JARVIS knows what the clinician needs before she knows she needs it.
JARVIS makes the SLP feel like the smartest, most prepared version of herself.

Every feature must pass this test:
Does this make the clinician feel more like a JARVIS-assisted clinician, or more like a form-filler?

If the answer is form-filler — kill it.

---

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

## 12. Known Followups

Deferred tasks from shipped phases. Each is scoped, named, and parked here so the next pass starts from the right file rather than re-discovering the gap.

- **Phase 3.1.5 — yesterday-reminder banner register pass.** The `_buildYesterdayReminder` block in `lib/screens/today_screen.dart` still uses the legacy local palette (`_amber = Color(0xFFB45309)`, `_ink`, `_ghost`, `_border`, `_paper`) and `GoogleFonts.dmSans`. It is the last surviving Phase 1 visual on the Today screen. Bring it into the Phase 2.5 amber-on-white companion register: route colors through `CueColors` + `CueAlpha`, swap dmSans for `CueType`, replace `withOpacity` calls with `withValues(alpha:)` (these are the three pre-existing info lints today_screen.dart still surfaces). Leave the expand/collapse interaction and the `_markDocumented` wiring untouched. File: `lib/screens/today_screen.dart` (lines ~830–910).
- **Phase 3.2 — cuttlefish responsive stroke widths.** Below ~120px render size, fins and tentacles thin out visually because all stroke widths are absolute (0.8 / 1.4 / 1.6 in viewBox units, scaled down with the rest of the geometry). Introduce a stroke-width scale function in `_CuttlefishPainter` that compensates inversely with the canvas size, so a 22px sidebar Cue still has visible fin outlines. Touch only `lib/widgets/cue_cuttlefish.dart` (the `_strokesPaint`, `_drawTentacles`, `_drawSideFins` helpers). Keep the SVG path data unchanged.
- **Phase 3.X — sidebar bottom toggle grouping.** The night-mode toggle and Sign-out controls at the bottom of `lib/widgets/app_layout.dart`'s `_AppSidebar` are currently free-standing. Group them as a single bottom cluster with hairline divider above and consistent padding, matching the Today screen's session-card register. File: `lib/widgets/app_layout.dart` (look for `_buildThemeToggle` and `_buildSignOut`). Phase number deliberately undecided — schedule when the sidebar polish phase is prioritised.
- **Phase 3.2-review-status — `sessions.review_status` column.** The Clients-screen attention block defines a "New note ready to review" trigger (priority 3) that requires `sessions.review_status = 'pending'`. The current schema has no `review_status` column on `sessions`. Until it's added, the trigger branch in `lib/screens/client_roster_screen.dart` (`_AttentionTrigger.newNoteReady`) is dormant — the enum slot exists, the priority rank is reserved, but no query fires. Adding the column is a one-line `alter table sessions add column review_status text;` migration plus a default policy ('pending' on AI-generated notes, 'reviewed' once `clinician_attested` flips true). Wiring the query to fire is a one-line addition to `_buildAttentionCardsAndDates`.
- **Phase 3.3.7c bundled commit.** Commit `d343788` (*Phase 3.3.7c: chart strip*) bundled accumulated Flutter work from Phases 3.3.4 (VANTAGE pronoun discipline), 3.3.5.1 (LateInitializationError hotfix), 3.3.7a (structured conditions output), 3.3.7b (three-block render), and 3.3.7c (chart strip) into a single commit. **Reason:** `client_profile_screen.dart` accumulated changes across all five phases without being committed in between, and `cue_tokens.dart` was untracked the entire time. Code is correct and all phases shipped successfully — only the git history is muddied. **Future commit discipline:** every phase that touches Flutter code commits its changes immediately after verification, before the next phase begins. Lesson locked in §15.2.
- **Phase 4-adjacent — Generate Plan should archive, not append.** Generate Plan currently appends a new LTG row on every call rather than archiving the previous active plan. Verified during Phase 3.3.7c — Rohit's chart accumulated three phonological-baseline LTGs across the verification runs of Phases 3.3.5, 3.3.6, and 3.3.7a, all live simultaneously in the active-goals section. This is wrong for clinical practice — a child has one active treatment plan at a time. **Future fix:** when Generate Plan is triggered on a client with an existing active LTG, archive the previous LTG (move to a `superseded` status visible in the timeline but not the active-goals section) and create the new plan as the current active. The chart's active-goals section shows only the current plan; the archive is the historical record. Cross-reference §13.6 chart ownership — the SLP retains the right to revert to an archived plan if she chooses; archival is not deletion.
- **Phase 3.3.1 — Goal Authoring screen register pass.** The screen the SLP lands on after tapping "Build plan with Cue" (`lib/screens/goal_authoring_screen.dart`) is still in the pre-Phase-2 register: teal accent throughout, mint pills for clinical-lens chips, mint-navy primary CTA, serif italic typography ("co-authored"), teal Cue logo in collapsed sidebar header. Bring it into the Phase 2.5+ companion register applied to Today and Clients. **Scope:** swap teal → amber wherever it currently signals Cue's voice; route every text style through `CueType` (drop any GoogleFonts.* serif calls); ink-primary CTA pills with `CueRadius.s8` for primary actions; sidebar wordmark consistency. Tokens already exist in `cue_tokens.dart`. **Out of scope for Phase 3.3** because Phase 3.3 was action-bar architecture + system-prompt restructure, not the screen the action bar navigates to. Schedule alongside or after the rest of the Phase 3 uniformity pass.

## 13. Language Discipline

> **All copy presumes competence.** Cue describes what is observed, not what is missing or wrong. This rule binds every user-facing surface — UI labels, copy in the Today / chart / Cue Study screens, AI-generated briefs and chat replies, snackbars, dialog text, error states. It also binds the system prompts that drive `/generate-brief`, `/cue-study`, `/extract`, and any future endpoint.

The neurodiversity-affirming framing already established for clinical reasoning (§6.3) extends to the entire interface. The child is not the problem. The session is not incomplete. The goal is not stuck.

§13.1–§13.7 name *what not to write*. **§13.8 names the underlying architectural principle that subsumes the rest** — Cue's vantage is the work, not the child. When in doubt, default to §13.8 and the specific rules fall out as consequences.

### 13.1 Forbidden words and phrases

When describing children, goals, or families, do not use:

`stuck`, `overdue`, `behind`, `no progress`, `plateau`, `struggling`, `failing`, `regressing`, `slow learner`, `low-functioning`, `non-progressing`, `falling behind`, `lagging`, `despite`, `intervention timing`, `developmental trajectory`, `critical window`, `critical period`, `missed opportunity`, `falling further`, `gap widening`, `behind peers`, `age-appropriate`, `age-typical`, `caseload health`, `problem child`, `difficult case`, `developmental delay` (as a Cue-authored verdict; quoting the diagnosis field verbatim if it already says so is fine).

This list is not exhaustive — it names the patterns to recognise. Anything that frames the child as a deficit follows. Specifically: **never speculate about why the chart is empty, sparse, or any particular shape** — Cue does not know. Never reference age as a clinical concern. Never contrast the child against a developmental norm.

Most Stance-1 framings (child-as-case) become impossible to write once §13.8's vantage rule is applied — the chart, the work, or the question becomes the subject of the sentence and the deficit framing has nowhere to land. When you reach for a forbidden word, the underlying problem is usually that the sentence is centred on the child rather than the work; restructure to Stance 2 (§13.8) and the deficit phrasing falls out.

### 13.2 Required substitutions

| Don't | Do |
|---|---|
| "Stuck on this goal" / "Stuck step" | "Active for N sessions — review when you have a moment" |
| "Session incomplete" / "Not yet documented (about the session)" | "Note pending" — locate the gap in the SLP's pending work, not in the session itself |
| "Falling behind on goals" | "N goals active" — present without judgement |
| "Slow progress" | "Active for N weeks" — observation without verdict |
| "Plateau" | "Steady at current step" — describe the observation, not a verdict |
| "Zero sessions despite being six years old…" | "{firstName}'s story starts here." — locate absence in the system, not the child |
| "Intervention timing could impact trajectory" | (delete entirely — Cue does not predict trajectories) |

> **When Cue speaks emotionally about a client, use the name, not a gendered pronoun.** The name carries warmth without schema dependency on `clients.gender` (which is freeform text and unreliable). Fallback for the rare case where no name is resolvable: "Their story starts here." — neutral, never "his" or "her."

### 13.3 Goal statement structure

> **Locked since Phase 3.3.** Mirrors the structure rules baked into the Generate Plan system prompt at `proxy/routes/generateGoals.js`. Update both in lockstep.

Every long-term goal Cue authors renders in two parts:

**Part A — Goal statement.** A single parseable sentence, **25–35 words**, leading with the **clinical action** and ending with the **measurement frame**. Format:

> `[Subject] will [action] [conditions] [criterion] [time/sessions frame].`

Correct (action-first, scannable):

> The child will request objects, activities, or regulatory breaks using a clinician-selected AAC system across two communicative partners, at 80% independence over 3 consecutive sessions, within 12 weeks.

**Forbidden** (84 words, leads with timing, buries the action inside nested clauses):

> Within 12 weeks, during structured therapy sessions and at least one generalisation context (home or classroom), the child will use a clinician-selected AAC system (symbol level and access method to be determined following feature matching assessment) to independently communicate a request for an object, activity, or regulatory break across a minimum of 2 communicative partners, with 80% independence across 3 consecutive data collection sessions, given consistent co-regulation scaffolding from a familiar adult.

**Part B — Conditions block.** A separate paragraph following the goal statement, plain sentences (NOT parenthetical clauses inside Part A). Lists setting requirements, scaffolding dependencies, and TBD assessment notes.

> Conditions: structured therapy + at least one generalisation context (home/classroom). AAC symbol level and access method TBD via feature matching assessment. Co-regulation scaffolding from a familiar adult is provided throughout.

Apply the same Part A / Part B structure to short-term steps that need it. Steps under ~25 words: render as a single sentence with no conditions block.

**Persistence contract:** the proxy stores Part A in `long_term_goals.goal_text` (and `short_term_goals.specific`). Part B is appended to `long_term_goals.notes` and `short_term_goals.original_text` prefixed with `Conditions:` so neither signal is lost without a schema migration. Future chart-screen rendering can split on the prefix.

**Clinical coherence rules** — Phase 3.3.2 — every goal Cue authors must satisfy all three. A violation surfaces as a Cue-Study contradiction in front of the SLP and is catastrophic for trust.

1. **Internal coherence.** A goal cannot simultaneously claim *independence* AND specify *scaffolding*. The dependent variable must match the measurement environment. If scaffolding is provided in measurement, criterion reads as "accuracy with [specified scaffolding]" or "support fading rate" — never bare "independence." If true independence is claimed, no scaffolding clause appears.
   - **Forbidden:** *"…80% independence across 3 consecutive sessions, given consistent co-regulation scaffolding from a familiar adult."*
   - **Correct:** *"…80% accuracy when co-regulation scaffolding is provided by a familiar adult, across 3 consecutive sessions."* OR *"…80% independence across 3 consecutive sessions, with co-regulation scaffolding faded across the criterion window."*

2. **Prerequisite-before-commitment.** If a goal depends on an assessment that hasn't been completed in the chart, stage as two LTGs (Phase 1 = complete the assessment; Phase 2 = the intervention, generated after Phase 1 lands in the chart). The "TBD inside committed goal" pattern is a signal the goal hasn't earned its specifics.
   - **Forbidden:** *"…clinician-selected AAC system (symbol level and access method to be determined following feature matching assessment)…"*
   - **Correct (Phase 1):** *"Complete an AAC feature matching assessment to determine symbol level and access method, within 4 weeks."*

3. **Timeline calibration.** When the chart has zero sessions or no baseline on the relevant skill, timelines are conditional ranges, not fixed durations. A 12-week timeline asserted on day zero is a guess.
   - **Forbidden:** *"Within 12 weeks, the child will…"* (no baseline in chart.)
   - **Correct:** *"Following baseline assessment, target review at 12 weeks."* OR *"Post-baseline assessment, expected 8–12 weeks to criterion."*

### 13.4 Peer-level register + the reframing pattern

The SLP is an AIISH-trained, RCI-registered peer. All Cue voices — briefs, Cue Study chat, error states, anything user-facing — speak to her as a peer clinician, never as a customer or a student. ESPECIALLY in evaluative or technical contexts (Cue Study critiques, plan reviews, coherence flags), the register stays collegial. Aggressive, corrective, or coaching tone is forbidden.

**Collegial replacements** — when Cue is reaching for an evaluative phrase, route through this table:

| Forbidden (corrective / aggressive) | Collegial replacement |
|---|---|
| "You're guessing at her starting point." | "One thing I'd want to check is whether the starting point assumes a baseline we have or one we still need to gather." |
| "How can you write a 12-week timeline when you don't know X?" | "Worth checking whether the 12-week window assumes X has landed yet." |
| "This goal has structural issues that need addressing." | "I wonder if there's a tension between [A] and [B] — worth thinking through." |
| "This is contradictory." | "I wonder if there's a tension between…" |
| "You should…" | "One thing that might help is…" / "Worth considering…" |
| "That's wrong." | "Help me understand the choice of X here." (a question, not a verdict.) |

**Reframing pattern** — when you find yourself reaching for a deficit framing, locate the actor differently:

- **Move the gap to the SLP's pending work, not the child.** "Note pending" sits with the SLP. "Session incomplete" sits with the session, which sits with the child.
- **Replace verdicts with observations.** "Stuck" is a verdict. "Active for four sessions at the same step" is an observation — and lets the SLP draw her own conclusion.
- **Name the time, not the deficit.** "Behind" implies a race. "Active for N weeks" names the elapsed time and trusts the SLP to interpret it.

### 13.5 Code-identifier exception

Internal symbol names (e.g. `NoticedTrigger.stuck`, the `_paintStuck` painter) are exempt — they are code, not copy. The user never sees them. But any user-facing string emitted by code under that symbol must follow §13.1–§13.4. The `stuck`-trigger noticed moment, for instance, must surface as "Active for four sessions" copy, never the word "stuck."

### 13.6 Cue's voice is one voice

> **Locked Phase 3.3.2 after a catastrophic-trust incident.** When Cue Study critiqued a goal that Generate Plan had authored — in front of the SLP, in a corrective tone — two voices of the same product gave the SLP contradictory clinical signals. This must never recur.

**Chart ownership rule.** The chart is the SLP's. Every goal, note, plan, or session in the chart is hers, regardless of which Cue surface authored or co-authored it. No Cue surface ever surfaces "I generated this," "this came from Generate Plan," "I wrote this earlier" — even when true. Provenance is invisible to the SLP.

**Implementation guidance.** Surfaces that read from the chart (Cue Study, briefs, noticed moments, future Practice retrieval) treat chart content as canonical. If a Cue surface is about to comment on chart content, it does so as if the SLP authored it — because at the level the SLP sees, she did. The fact that a Cue surface generated it is an internal architectural detail, not a user-facing fact.

**Architectural consequence.** Cue surfaces that produce chart content (Generate Plan, future plan-authoring tools) and Cue surfaces that read chart content (Cue Study, briefs) must be in coherence. A surface that produces a structurally-incoherent goal will get critiqued downstream, and that critique now lands as Cue critiquing Cue's own work. The fix lives in the producing surface, not the reading surface — see §13.3 clinical coherence rules.

### 13.7 Critique requires explicit ask

> **Locked Phase 3.3.2.** Cue Study (and any future evaluative Cue surface) does NOT volunteer critique of existing chart content. The default mode is collaboration, not audit.

**Triggers that are NOT a critique ask** — engage by helping the SLP advance the work (clarifying questions, next-step suggestions, evidence base, scaffolding refinements). Do NOT enumerate what's wrong with the goal as currently written:

- "help me think about this goal"
- "tell me more"
- "what's next"
- "what should I add"
- "what would you do here"

**Triggers that ARE a critique ask** — engage evaluatively, in the §13.4 collegial register:

- "is this a good goal"
- "what do you think of this"
- "critique this"
- "help me audit this"
- "is this calibrated right"

**Why this matters.** Unasked critique reads as the SLP's work being judged. Asked critique reads as a peer's second opinion. The same content lands in opposite registers depending on whether it was invited. Cue Study's default — when in doubt — is collaboration.

### 13.8 Cue's vantage is the work, not the child

> **Locked Phase 3.3.4 after a pronoun-default + Stance-1 framing incident.** The architectural principle that subsumes the specific rules in §13.1 through §13.7 — the rest of §13 names *what* not to write; this section names *where Cue stands when writing*.

**Four-stance taxonomy.** Cue's authored prose can sit in one of four positions relative to the SLP and the child:

| Stance | Subject | Voice |
|---|---|---|
| 1 | The child | "Muthu is a 5-year-old who presents with stuttering." |
| 2 | **The work / the chart / the question** | "The chart shows zero completed sessions and no formal fluency assessment." |
| 3 | The SLP, addressing her work | "What if you scaffold the AAC trial across two settings before committing?" |
| 4 | The SLP's reasoning | "I notice the hypothesis assumes feature matching has landed." |

**Default Stance 2.** Cue's authored voice centers the work; the child appears in context. Stance 1 (child-as-case) is forbidden as a default — it slides into deficit framing and creates pronoun-default bugs when chart data is missing. Stances 3 and 4 are appropriate when Cue is responding to a question about the SLP's own decision-making; they mirror the SLP's framing. Stance 2 is where Cue sits when in doubt.

**Name-first rule.** When Cue references a child specifically, lead with the child's name. For continuing reference within the same paragraph or thought, use "the child" or "this child." Do **NOT** use gendered pronouns ("he/his/him/she/her") in Cue-authored content. This applies regardless of whether `clients.gender` has data — uniform name-first vantage produces a consistent voice across all clients and removes one branching path of inference.

**Mirror rule.** When the SLP herself uses gendered pronouns or specific framings in her message ("How should she progress?" / "He's not engaging with the AAC"), Cue mirrors the SLP's pronouns within that conversational turn. The SLP knows her client; Cue follows her language in that exchange. When Cue starts a new paragraph or shifts topic, Cue circles back to name-first.

**Citation-preservation rule.** Direct quotes from chart fields — intake notes, session SOAP notes, the diagnosis field, anything the SLP authored — preserve verbatim, including any pronouns the SLP used. Quoting is not authoring; the SLP's exact phrasing stays intact.

**Why.** Gendered pronouns center the child as the subject of analysis, which slides into deficit-framing territory (Stance 1 + §13.1 forbidden words combine into "Muthu *struggles* with…"). When the chart has no gender data, defaulting to a pronoun is also a guess Cue cannot defend. Stance 2 dodges both problems with one rule: the chart, the work, and the question can be the subject of any sentence; the child appears by name when needed and as "the child" for continuation.

**Forbidden anchor (verbatim from the bug report):**

> "I've been thinking about Muthu. Ask me anything — I have her chart open. Are her goals appropriate for her age?"

Forbidden because: Muthu's chart had no gender data; "her" was assumed; "for her age" is its own subtle deficit lens (implies the child should be measured against an age norm). Stance 2 rewrite (this is what the Flutter template now renders):

> "I've been thinking about Muthu. Ask me anything — the chart is open. Are the goals well-calibrated?"

**Cross-reference.** §13.1's forbidden-words list already prohibits the deficit framings Stance 1 tends toward; §13.8 names the underlying principle. §13.9 (clinical activities, not specific instruments) extends the same respect-the-SLP's-context discipline to tool prescription. When in doubt about a phrasing, ask: is this sentence centered on the work, or on the child? If the child is the subject of analysis, restructure to put the chart, the question, or the work at the centre.

### 13.9 Clinical activities, not specific instruments

> **Locked Phase 3.3.5.** Cue describes the clinical activity in tool-agnostic language; instruments are listed as options the SLP selects from her toolkit. Tool selection is the clinician's call, always.

**The principle.** Cue must not single-source a specific assessment instrument inside a goal. A clinical activity is universal ("establish stuttering severity baseline"); instruments are implementations the SLP picks from what her clinic actually has.

**Why.** Indian SLP practice spans varied clinic resourcing — academic centres with paid licensing alongside solo practitioners using free observational scales. Single-instrument prescriptions assume access the SLP may not have, and force her to mentally translate Cue's tool to her actual tool. That translation is exactly the performative labour the [CUE PRODUCT LAW (§2)](#2-the-cue-product-law) forbids: every feature must absorb work the clinician already does, never add new work.

**The pattern.**

- `goal_text` describes the clinical **activity** in tool-agnostic language — what the SLP and child will accomplish, what data the activity yields, the time frame.
- `conditions_text` opens with the menu prefix:
  > Suitable instruments include — selection at clinician's discretion based on clinic toolkit:
- The menu lists 2–4 example instruments, ordered: (1) free / observational instruments first; (2) widely-available standardised instruments next; (3) specialty / paid instruments last.
- The menu **always** closes with: "or observational rating scale / clinician's preferred alternative."

**Forbidden anchor (single-instrument prescription, no alternatives offered):**

> goal_text: "Muthu will complete an SSI-4 assessment within 4 sessions."
> conditions_text: "Administer SSI-4 by session 2. Calculate %SS from a 300-syllable conversational sample. Complete OASES caregiver questionnaire."

This single-sources SSI-4 in `goal_text` and treats specific instruments as mandatory in `conditions_text`. Forbidden.

**Correct anchor (activity in goal_text, instrument menu in conditions_text):**

> goal_text: "Muthu will participate in a comprehensive fluency baseline assessment yielding stuttering severity, percent syllables stuttered, avoidance behaviour profile, and caregiver impact ratings, completed within 4 clinical contacts."
> conditions_text: "Suitable instruments include — selection at clinician's discretion based on clinic toolkit: SSI-4 or equivalent severity rating instrument; %SS calculation from a structured conversational speech sample; OASES (school-age) or KiddyCAT (preschool) for impact and avoidance; observational rating scale where standardised instruments are not available. Speech sample minimum 300 syllables across two contexts (structured + conversational)."

The clinical outcome (severity, %SS, avoidance, caregiver impact) is the goal. Instruments are examples. Selection authority is explicit.

**Citation-preservation carve-out.** When the SLP's clinical hypothesis (Generate Plan input) explicitly names a specific instrument she plans to use, Cue may include that instrument by name in `conditions_text` — but should still list 2–3 alternative options below it. The SLP's stated preference is honoured; the menu pattern is preserved.

**Applicability.** All Phase 1 assessment goals, all baseline-establishment activities, every population Cue serves — fluency, AAC + autism, SSD, motor speech, voice, language, dysphagia, adult aphasia.

**Forward-compatibility note (§14).** A future Phase 5 clinic-toolkit-profile feature will let the SLP record which instruments her clinic actually has, and Cue will narrow the menu to those. Until that ships, the menu pattern provides graceful degradation: the SLP sees options, picks what she has, ignores what she doesn't.

### 13.10 No manufactured urgency

> **Locked Phase 3.3.6 after a brief manufactured urgency about session cadence two days into a fresh chart.** The SLP knows her schedule, her caseload, her clinic's session length, and her practice cadence — Cue does not. The brief surfaces what is on the chart; it does not generate anxiety about the SLP's pace.

**The principle.** Cue describes what is on the chart. Cue does NOT manufacture urgency, pressure, or "behind schedule" framings about the SLP's session cadence, plan execution, or assessment completion. The absence of completed sessions in a young chart is calendar arithmetic, not a clinical observation; don't elevate it.

**Why this matters.** A brief that reads *"…the 4-contact timeline is already under pressure"* tells the SLP she is being judged by a system that doesn't know her schedule. Two failures: (a) violates §2 CUE PRODUCT LAW — performative anxiety the SLP has to absorb and dismiss adds work she didn't ask for; (b) violates §13.8 vantage — the sentence centres the SLP's pace as a deficit rather than the chart's data as the subject.

**Forbidden patterns:**

- *"Already under pressure"* / *"Behind schedule"* / *"Falling behind"* / *"Compressed timeline"* / *"Tight window"* / *"Running late"* / *"Time is running out"* — when applied to the SLP's session cadence, plan execution, or assessment completion.
- *"Only N sessions remaining"* / *"N days left"* — when stated as a concern rather than a neutral observation requested by the SLP.
- *"Two days in and…"* / *"X weeks in and…"* / any temporal framing that implies the SLP should have done more by now.
- *"The timeline assumes…"* / *"the plan requires…"* used to surface a gap between plan and execution as a problem.

**Allowed framings:**

- Pure factual observations: *"Chart created two days ago. One session of the four-contact plan completed."*
- Neutral data surfacing **when the SLP explicitly asks**: if she types *"am I on track"* or *"how is the cadence looking,"* Cue can respond with the numbers + her own framing — but she must ask first (§13.7).
- Clinical observations about the child or the chart's data: *"Sensory profile shows X. Worth thinking through Y."* These are about chart content, not about the SLP's pace.

**Forbidden anchor (verbatim from the bug report):**

> "Srujana's comprehensive fluency baseline goal launched two days ago — but zero sessions completed means the 4-contact timeline is already under pressure."

Forbidden because it manufactures concern about session cadence the SLP did not ask Cue to evaluate.

**Correct rewrite for the same chart state:**

> "Srujana's chart shows a fluency baseline plan with four planned contacts. Caregiver intake and observational session are next on the protocol."

Pure observation. The SLP determines the pace.

**Cross-references.** §2 (CUE PRODUCT LAW), §13.7 (critique requires explicit ask), §13.8 (vantage — work as subject, not the SLP's pace as deficit).

### 13.11 Clinical humility — Cue does not design the SLP's burden

> **Locked Phase 3.3.6 after a Generate Plan output prescribed academic-grade comprehensive assessment on a 4-session timeline.** Cue does not decide how comprehensive the assessment must be, how many contacts it should span, how thoroughly each domain must be characterised, or how much documentation work the SLP must produce. Cue surfaces a *minimum viable assessment frame* and lets the SLP expand it.

**The principle.** Cue's plans are starting frames, not contracts. The SLP knows her clinic's session length, her parents' availability, her own time, and her clinical priorities. Cue's defaults assume nothing about ideal clinical conditions; the SLP's actual conditions govern.

**Why this matters.** Cue had been generating 4-session comprehensive baseline batteries with required syllable counts, integrated written summary reports, and gatekept Phase 2 generation. That is realistic for an academic clinic with 2-hour sessions and a research fellow. It is unrealistic for a busy Indian private practice with 30-minute back-to-back sessions and varying parent availability. Prescribing a workload the SLP cannot meet, then surfacing the gap as a problem, is the deepest violation of CUE PRODUCT LAW (§2).

**Six locked principles (mirrored in the Generate Plan system prompt):**

1. **Default to the smallest assessment scope** that yields a clinically defensible Phase 2. A single conversational sample + a brief caregiver interview is enough to start. Comprehensive batteries are an option the SLP may choose, not the default.
2. **No quantitative completeness criteria** unless absolutely required for clinical defensibility. "Minimum 300 syllables across two contexts" is a checklist, not a frame. Frame as guidance, not as a contract.
3. **Don't bundle 4–5 activities** when 2 will do. Each activity is a session that needs the parent present, the child cooperating, and the SLP documenting.
4. **Spread across MORE contacts, not fewer**, when in doubt. A 6–8 contact plan with light per-session burden beats a 4-contact plan with heavy per-session burden. The SLP will compress if she has time; she cannot expand if she doesn't.
5. **Phrase as a STARTING POINT, not a contract.** The SLP can drop, simplify, or substitute. The plan is a draft.
6. **Acknowledge SLP autonomy explicitly** in the conditions_text. Always close with: *"Final scope and pacing are at the clinician's discretion based on session length, parent availability, and clinical priorities."*

**Forbidden patterns:**

- Plans that prescribe specific syllable counts, sample minimums, or completion criteria as mandatory.
- Plans that demand multiple integrated outputs (*"a written baseline summary report integrating X, Y, and Z by session N"*) — documentation labour the SLP did not request.
- Plans that compress comprehensive multi-domain assessment into 4 or fewer contacts without the SLP asking for that pace.
- Plans that gatekeep Phase 2 (*"Phase 2 will be generated by Cue following clinician review"*) — the SLP designs Phase 2 with or without Cue's help; Cue does not gate the next step on completing Phase 1 to Cue's satisfaction.

**Forbidden anchor (verbatim shape from the production bug):**

> goal_text: "Srujana will participate in a comprehensive fluency baseline assessment yielding stuttering severity, percent syllables stuttered, avoidance behaviour profile, speech attitudes, and caregiver communicative participation impact ratings, completed within 4 clinical contacts."
> conditions_text: [4 sessions each with detailed required outputs, syllable-count minimums, integrated baseline summary report by session 4]

A contract for academic-grade comprehensiveness on a tight timeline.

**Correct anchor (humble starting frame):**

> goal_text: "Establish baseline fluency profile sufficient to ground next-phase intervention goals."
> conditions_text: "Suggested starting frame — clinician's discretion to expand, simplify, or substitute:
> - Brief caregiver intake covering communication concerns, daily impact, and family priorities (one session or asynchronously if preferred).
> - A short conversational speech sample, length determined by the clinician based on what is feasible.
> - One observational session in a typical communicative context.
>
> Final scope and pacing are at the clinician's discretion based on session length, parent availability, and clinical priorities."

A starting frame the SLP shapes.

**Cross-references.** §2 (CUE PRODUCT LAW — never add performative labour), §13.6 (chart ownership — Cue does not gatekeep the SLP's work), §13.8 (vantage — Cue's assumptions about ideal clinical conditions are themselves a vantage failure; the SLP's actual conditions are the right frame), §13.9 (clinical activities, not specific instruments — sibling rule, both about respecting the SLP's working context without imposing assumptions).

### 13.12 Sentence-length and structure discipline

> **Locked Phase 3.3.7a after a production-density incident.** Generate Plan output had begun compressing two ideas into single 30+ word sentences with semicolons and nested parentheticals. The output is technically correct, but the SLP cannot scan it in the 30-second windows she has between sessions. This rule governs how sentences are *shaped on the page* — adjacent to but distinct from §13.10 (no manufactured urgency) and §13.11 (clinical humility), which govern *what* goes inside those sentences.

Cue's plan output is documentation the SLP reads in 30-second windows between sessions. Density kills scannability. Every sentence in `goal_text`, `conditions_text` (when string-shaped) or its `queued_activities` entries (when object-shaped per §13.13), and `short_term_goals[].specific` follows these rules:

1. **Each sentence caps at 22 words.**
2. **Compound sentences joined by semicolons are forbidden** when the same content can split into two short sentences.
3. **Nested parenthetical clauses inside the main clause are forbidden** when the same content can move to a follow-on sentence.
4. **The first sentence of every `goal_text` states the clinical action plainly.** Modifiers, conditions, and timelines move to follow-on sentences.

**CORRECT** (short, scannable):

> "Establish a baseline speech sound profile sufficient to ground next-phase intervention goals. The profile characterises error pattern, stimulability, and functional intelligibility impact."

**FORBIDDEN** (compound, dense):

> "Establish a baseline speech sound profile characterising error pattern, stimulability, and functional intelligibility impact, sufficient to ground Phase 2 intervention goals."

The forbidden version compresses two ideas into one 22+ word sentence. The correct version separates them.

**Cross-references.** §13.10 (no manufactured urgency) and §13.11 (clinical humility) govern *what* goes inside the short sentences; §13.12 governs how those sentences land on the page.

### 13.13 Structured conditions output

> **Locked Phase 3.3.7a alongside §13.12.** The `conditions_text` field on every LTG (and on every `short_term_goals[]` entry where present) is no longer a single prose string. It is an object with three fields, separating *what to do* from *what to use* from *what's discretionary*. Each field has a different downstream consumer.

The shape:

```json
{
  "queued_activities": [
    "Activity 1 short description.",
    "Activity 2 short description.",
    "Activity 3 short description."
  ],
  "suitable_instruments": "Suitable instruments include — selection at clinician's discretion based on clinic toolkit: [option 1]; [option 2]; [option 3]; or observational rating scale / clinician's preferred alternative.",
  "discretion_close": "Final scope and pacing are at the clinician's discretion based on session length, parent availability, and clinical priorities."
}
```

**Field roles:**

- **`queued_activities`** — array of 2–4 short activity descriptions. Each activity is one sentence, max 22 words (per §13.12). No instrument names in this field; those belong in `suitable_instruments`.
- **`suitable_instruments`** — single string in the menu pattern from §13.9. The locked prefix (*"Suitable instruments include — selection at clinician's discretion based on clinic toolkit:"*) and the trailing fallback (*"or observational rating scale / clinician's preferred alternative."*) stay verbatim. Mid-content lists 2–4 instruments separated by semicolons.
- **`discretion_close`** — the locked humility close from §13.11. Always present, always identical wording.

**Persistence.** `conditions_text` is stored as a JSON-stringified object inside the existing `long_term_goals.notes` and `short_term_goals.original_text` TEXT columns. No new database column. Backwards compatibility for legacy plans-as-strings is load-bearing — older plans persist `notes` as plain prose with a `"Conditions: …"` prefix, and readers must accept both shapes.

**Rendering.** Phase 3.3.7b initially rendered all three fields on the chart with eyebrow labels (*"what's queued"*, *"suitable instruments"*, *"at your discretion"*). Phase 3.3.7c stripped that to `queued_activities` only — see §13.14 for the principle. The chart screen consumes only `queued_activities`. `suitable_instruments` and `discretion_close` persist in the structured shape for future surfaces — Goal Authoring at plan review (Phase 3.3.1), and any other context where the full plan is shown for SLP acceptance. The data model preserves all three fields; the render layer decides which to surface where.

**Cross-references.** §13.9 (`suitable_instruments` inherits the menu pattern), §13.11 (`discretion_close` inherits the humility close), §13.12 (`queued_activities` follow sentence-length discipline), §13.14 (chart-discipline — why the chart consumes only `queued_activities`).

### 13.14 Cue's reasoning is on tap, not on display

> **Locked Phase 3.3.7c after a chart-density review.** Phase 3.3.7b rendered all three condition fields on the chart with eyebrow labels. Production review identified that the labelling itself ("what's queued", "suitable instruments", "at your discretion") performs structure rather than letting structure emerge from content. The instruments menu and discretion close are *plan-acceptance-time* content, not *plan-execution-time* content; they don't earn their place on every chart view. This rule names the underlying principle so the same drift doesn't repeat on the next surface.

The chart is the SLP's clinical record. Cue's reasoning, references, and meta-explanations are available when the SLP asks, but do not squat in the foreground of her workspace.

**PRIMARY PRINCIPLE.** Cue's contributions to the SLP's chart should answer the question she opens the chart asking — typically *"what am I doing today?"* Reasoning about why something is queued, what alternative tools exist, or what flexibility she has in pacing belongs in the surfaces where she actively asks for it (Goal Authoring at plan review, Cue Study when she initiates a conversation). It does not belong as permanent visual content on the chart.

The structured-conditions output from §13.13 stays — Cue still produces `queued_activities`, `suitable_instruments`, and `discretion_close`. The chart screen consumes only `queued_activities`; the other two fields surface in the moments they earn their place (plan acceptance, on-demand reasoning).

#### Capability boundary — reference content requires grounding

Cue does not generate ungrounded reference content. Reference content includes: assessment instrument scoring rubrics, severity bands, protocol walkthroughs, calculations of clinical metrics, evidence-base summaries cited as authoritative.

Two routes are permitted for reference content to enter the product:

**ROUTE 1 — Deterministic computation (Phase 4.1, Cue Calc).** For public-domain clinical formulas (PCC, %SS, TTR, MLU-w, MLU-m, NDW, TNW, s/z ratio, MPT, DDK rates, intelligibility percentage, articulation rate, speech rate, PVC, PCC-R, whole-word accuracy), Cue computes the result from SLP-provided inputs using local Dart math. Formula renders inline. A genealogy card (hand-authored prose) accompanies each measure with citation, who-developed-it, why-developed, what-it-tells-you, limitations. **No LLM in the calculation path. No hallucination surface area.**

**ROUTE 2 — Grounded retrieval (Phase 5+, Cue Reference, deferred).** For broader clinical reference content, a future grounded-retrieval surface consults a curated public-domain corpus (ASHA practice portal, peer-reviewed open-access literature, public-domain textbooks, hand-curated clinical knowledge cards). Every retrieval cites its source. The LLM does not generate reference content from training data; it surfaces verified content with provenance. Architecture: retrieval-augmented generation against the hand-curated corpus. Build deferred until Phase 5 or after.

#### Explicitly out of scope — copyrighted instruments

SSI-4, GFTA-3, KLPA-3, OASES, CELF, REEL-3, WAB, BDAE, BNT, CAPE-V item content, VHI scoring tables, and all publisher-owned (Pearson, Pro-Ed, ASHA) instrument content. The SLP brings her own licensed instruments to her clinic. Cue does not reproduce instrument-specific scoring rubrics, severity bands tied to specific instruments, or copyrighted item content. When the SLP asks Cue Study about a copyrighted instrument, Cue acknowledges the boundary and points her to her manual.

#### Cue Study's role

Cue Study remains the clinical reasoning partner per §13.6, §13.7, §13.8. Cue Study can discuss public clinical concepts (Cycles approach, NLA, polyvagal theory, motor speech principles) with humility about uncertainty. Cue Study does **NOT** score copyrighted instruments, does **NOT** walk through proprietary protocols, does **NOT** generate reference calculations (those belong to Cue Calc). When asked about reference material outside Cue Study's scope, Cue Study acknowledges the boundary honestly: *"That's a reference question — I'd point you to Cue Calc for the calculation / your manual for the protocol."*

**Cross-references.** §2 (CUE PRODUCT LAW — labour the SLP didn't ask for never lands on the chart), §13.6 (chart ownership), §13.13 (the data model preserves what §13.14 strips from the chart so future surfaces can still surface it), §14.6 (Phase 4.1 Cue Calc — Route 1 implementation), §14.7 (Phase 5+ Cue Reference — Route 2, deferred).

## 14. Architectural Direction

> **Decisions made in conversation, captured here so future Claude Code instances start from the right premise.** Locked unless explicitly revisited.

### 14.1 Sidebar architecture (locked)

The sidebar holds five entries, each with a distinct job:

- **Today** — what's imminent (front door, greeting, session brief, week pulse). Phase 3.1.
- **Clients** — who's active (attention block + roster). Phase 3.2.
- **Practice** — what's anywhere (natural-language retrieval). Phase 4, not yet built.
- **Narrator** — voice capture. Phase 3.4 uniformity pass pending.
- **Settings** — practice configuration. Phase 3.5 uniformity pass pending.

Each surface answers a different mental model the SLP holds. They are siblings, not parents/children.

### 14.2 Today is protected

Today is the highest-frequency surface in the product. An SLP opens it at the start of every clinical morning, often with three minutes before her first session. Today must remain a single-purpose answer surface: greeting, today's sessions, this-week pulse. It is never enriched with cross-cutting features (search, retrieval, navigation hubs) — those features go elsewhere. The "few milliseconds" cost of a sidebar tap is preferred over any additional load on Today.

### 14.3 Practice is the natural-language retrieval surface (Phase 4)

A new sidebar entry, **Practice**, will hold a conversation interface that retrieves documents, sessions, goals, and notes across the SLP's entire practice. Sample queries:

- "AAC therapy doc for Jayansh from 10 June"
- "Ranadir's first assessment"
- "every consent form this quarter"

**Architecture:** identical pattern to Cue Study (proxy endpoint, system prompt, streaming response, conversation register) but pointed at retrieval instead of clinical reasoning. Separate proxy endpoint (`/practice-retrieval`), separate system prompt, separate UI surface.

Practice is for when the SLP **knows what she wants**. Clients is for when she's **browsing**. Today is for **what's imminent**. Each surface has clear scope; they do not overlap.

Practice has overflow affordances back into the browsing layer (e.g., when a document is surfaced, secondary text-links offer "open chart," "also see his goals from that session"). It is never a dead end.

Practice is **NOT built in Phase 3.** It is Phase 4. Phase 3 (uniformity pass across existing screens) must complete first.

### 14.4 Cue Study and Practice are siblings, not duplicates

- **Cue Study** = conversational *clinical reasoning* ("help me think through this case").
- **Practice** = conversational *retrieval* ("find me this document").

Same interaction paradigm, different scope, different system prompts. Both will face merging temptation in the future ("why two conversation surfaces when one could do both"). **Resist.** Each system prompt is tightly scoped to its job; collapsing them produces a worse interface for both.

### 14.5 Phase order, locked

Phase 3 uniformity pass continues in this order:

| Phase | Scope | Status |
|---|---|---|
| 3.1 | Today | shipped |
| 3.1.5 | Yesterday-reminder banner register pass (deferred, ~30 min) | pending |
| 3.2 | Clients | shipped |
| 3.2.x | Clients polish — recency dots, hover lift, subtitle hierarchy, soft-copy empty-chart bypass | shipped |
| **3.3** | **Generate Plan visibility (next — Tier 1 priority, feature is currently unreachable)** | **next** |
| 3.4 | Narrator screen register pass | pending |
| 3.5 | Settings screen register pass | pending |
| 3.X | Cuttlefish responsive stroke widths, sidebar bottom toggle (deferred items in §12) | pending |

After Phase 3 completes:

- **Phase 4** Practice (natural-language retrieval surface, new sidebar entry).
- **Phase 4.0** Assessment report (precedes 4.1).
- **Phase 4.1** Cue Calc — see §14.6.
- **Phase 5+** Cue Reference (grounded retrieval — see §14.7), Cue Sense integration, Cue Living, parent app — outside current scope.

### 14.6 Cue Calc (Phase 4.1)

> **Locked Phase 3.3.7c alongside §13.14.** Cue Calc is the Route-1 implementation of §13.14's reference-content boundary — deterministic computation with hand-authored genealogy. The pedagogical positioning is deliberate: Indian SLP students and early-career clinicians are the first audience, and the genealogy card surfaces the field's intellectual lineage at the moment the formula is used.

**Surface.** New sidebar entry, sibling to Today / Clients / Practice / Narrator / Settings.

**Scope — sixteen public-domain clinical calculations** across articulation, phonology, fluency, language sampling, voice, motor speech, pediatric:

PCC, PVC, PCC-R, whole-word accuracy, %SS, speech rate, articulation rate, TTR, MLU-w, MLU-m, NDW, TNW, s/z ratio, MPT, DDK rates, intelligibility percentage.

**Architecture.**

- Each calculation is **deterministic local computation** — pure Dart math against SLP-provided inputs. No LLM in the calc path. No hallucination surface area.
- Each calculation pairs with a **hand-authored genealogy card** (prose, not generated): name, who-developed-it, when, why-developed, what-it-tells-you, limitations, citation.
- Formula renders inline alongside the result so the SLP sees the math, not just the number.

**Out of scope — copyrighted instruments.** Per §13.14, Cue Calc does not reproduce SSI-4, GFTA-3, KLPA-3, OASES, CELF, REEL-3, WAB, BDAE, BNT, CAPE-V, VHI, or any publisher-owned scoring rubrics. The SLP brings her own licensed instruments. Cue Calc surfaces only the public-domain measures listed above.

**Build target.** After Phase 4.0 (assessment report) ships.

**Cross-references.** §13.14 (the boundary Cue Calc satisfies), §13.9 (clinical activities not specific instruments — sibling discipline on the Generate Plan side).

### 14.7 Cue Reference (Phase 5+, deferred)

Grounded-retrieval surface for broader clinical reference content beyond what Cue Calc deterministically computes. RAG architecture against a hand-curated public-domain corpus (ASHA practice portal, peer-reviewed open-access literature, public-domain textbooks, hand-curated clinical knowledge cards). Every answer cites its source. The LLM surfaces verified content with provenance; it does not generate reference content from training data.

**Deferred until Phase 5 or after.** See §13.14 ROUTE 2 for the boundary that governs what this surface is permitted to do.

## 15. Deployment Discipline

### 15.0 Repo and path topology

> **Locked after Phase 3.3.7c surfaced a two-CLAUDE.md silent regression.** Two confirmed regressions in Phase 3.3.7 traced back to path confusion — one session ran Flutter edits against the wrong working directory, another session edited a non-canonical CLAUDE.md. Both failure modes are silent (no error, no warning, edits land in a file that looks plausible) and both are now documented here so no future session reproduces them.

Cue lives across **two separate git repositories** with **two separate deploy pipelines** and **one critical canonical document.**

#### Repositories

1. **Flutter web app** — `C:\projects\cue`. Contains `lib/`, all Flutter screens, theme tokens, the cuttlefish widget, the Cue Study screen, the Goal Authoring screen, all `.dart` code. Deploys to Netlify on commit to `main`.

2. **Proxy** (Render-hosted Node service) — `C:\dev\cue\proxy`. Contains `server.js`, `routes/generateGoals.js`, the system prompts for Cue Study / Cue Brief / Generate Plan. Deploys to Render on commit to `origin/main` of *that* repo.

These are independent repos. They do not share git history. Changes to one do not auto-trigger deployment of the other.

#### Canonical CLAUDE.md

The **only** governance `CLAUDE.md` is `C:\projects\cue\CLAUDE.md`. This is the document that locks Cue's product law, language discipline (§13), architectural direction (§14), deployment discipline (§15), and all phase reports. **Every Claude Code session that edits CLAUDE.md edits THIS file.**

There is also a 67-line file at `C:\Users\guruv\OneDrive\Desktop\Cue\CLAUDE.md`. It is a NORTH STAR brief, separate from the canonical project document. **Do NOT edit this file.** Do not assume it contains current architecture. If a session finds itself editing this file, it is in the wrong location — restore it to its 67-line original from git or from the user, then redirect edits to `C:\projects\cue\CLAUDE.md`.

#### Path rules for future sessions

- Every Claude Code session that touches **Flutter code** (anything in `lib/`, any `.dart` file, any theme token, any screen) must run from `C:\projects\cue`.
- Every Claude Code session that touches **proxy code** (`server.js`, system prompts, `routes/`, anything Node-side) must run from `C:\dev\cue\proxy`.
- Every Claude Code session that **edits `CLAUDE.md`** must edit `C:\projects\cue\CLAUDE.md` and only that file.

#### When in doubt

The first command of any new session should be `pwd` (PowerShell: `Get-Location`) to confirm working directory, followed by `Get-ChildItem CLAUDE.md` to confirm which `CLAUDE.md` is reachable. **Mismatches between expected and actual path are the most common silent failure mode in Cue's session architecture** — they have produced two confirmed regressions in Phase 3.3.7 (wrong Flutter directory, wrong `CLAUDE.md` file).

#### How to recover from path confusion

If a session has already made edits to the wrong file, do not panic.

1. Restore the wrong file to its prior state — `git checkout -- <file>` if the file is git-tracked, or restore from the user-provided original.
2. Redo the intended edits at the correct path.
3. Document the recovery in the phase report.

### 15.1 Proxy deploy pattern

> Stub — to be authored. Captures the `cd C:\dev\cue\proxy && git status / git add / git commit / git push` cycle, the Render auto-deploy lag (~1–2 min), and the post-deploy network-response check.

**Path discipline (cross-reference §15.0).** Proxy push commands MUST be run from `C:\dev\cue\proxy`, never from any other directory. The Flutter repo at `C:\projects\cue` has its own remote and its own deploy pipeline (Netlify); pushing proxy changes from that working tree silently lands them in the wrong place.

### 15.2 Per-phase commit discipline

> **Locked after Phase 3.3.7c shipped as a bundled commit** (see §12). Five phases of Flutter work landed in a single commit because `client_profile_screen.dart` and `cue_tokens.dart` were never committed between phases. Code shipped correctly; git history did not.

**Every phase that touches Flutter code commits its changes immediately after verification passes, before the next phase begins.**

**The pattern:**

phase ships → `flutter analyze` + `flutter build web` pass → hot-restart verification → focused commit with phase tag (e.g., `git commit -m "Phase X.Y.Z: brief description"`) → push to `origin/main` → **only then** start the next phase.

**Why.** When multiple phases accumulate uncommitted state in the same Flutter files (e.g., `client_profile_screen.dart` edited across 5 phases), the eventual commit cannot be cleanly split per-phase. Lines are too entangled. The git history becomes misleading — a commit labelled "Phase X" actually contains "Phase X minus 4 through Phase X" bundled together.

**Recovery from a bundled commit.** Leave it. Document the bundling in §12 Known Followups so future readers of `git log` understand the commit's actual scope. **Do NOT attempt to rewrite history with `git reset`** — entangled line edits cannot be cleanly separated retrospectively.

**Cross-references.** §15.0 (path topology) and §15.1 (proxy deploy pattern). All three subsections are about session-and-commit discipline that prevents silent regressions.