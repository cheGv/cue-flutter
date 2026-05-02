# Phase 4.0 — Master Spec

**Load-bearing for the next 8–12 build sessions.** Every Phase 4.0.x session inherits from this document.

> Cross-references: [CLAUDE.md §7](CLAUDE.md) (canonical schema, rewritten in this phase), [§13.13–§13.16](CLAUDE.md) (structured-conditions + vantage + legacy), [§14.8–§14.9](CLAUDE.md) (Phase 4.0 announcement + six-layer architecture), [PHASE_4_GAP_ANALYSIS.md](PHASE_4_GAP_ANALYSIS.md) (the read-only inspection this spec acts on).

---

## Section 1 — Phase 4.0 V1 scope and shape

**V1 ships developmental stuttering only, end-to-end across six layers.** This is the moment Cue stops being a single-population product. The architectural commitment is to ship one population fully — Layer 01 through Layer 06, plus three derived outputs — before any second population begins.

**What ships in V1:**
- Six-layer architecture wired for `population_type = 'developmental_stuttering'`:
  - Layer 01 — Core Profile (population-agnostic, reusable across every population)
  - Layer 02 — Case History (population-specific, fluency-shaped)
  - Layer 03 — Assessment Data, three sub-modes: live entry, debrief, parent interview
  - Layer 04 — Pre-therapy Planning (family goals, priority focus, readiness)
  - Layer 05 — Lesson Plan Inputs (approach, techniques, session structure)
  - Layer 06 — Progress Tracking (per-session structured fluency metrics)
- Three derived outputs:
  - Assessment Report (composes layers 01–03)
  - Progress Report (composes layer 06 longitudinally + the goal plan from layer 05)
  - Baseline Snapshot (structured snapshot at end of layer 03 lock)
- Existing ASD/AAC clients render unchanged through entire Phase 4.0 build (`population_type` defaults to `asd_aac`; their surfaces stay on the legacy AAC-shaped path).

**What does NOT ship in V1:**
- Other fluency sub-types — acquired adult, neurogenic, psychogenic, cluttering. These are V1.1–V1.4 and ship as separate phases AFTER V1.
- Other populations — SSD/phonological, voice, language, dyslexia, CP, HI. These are Phase 4.1+.
- Co-occurring populations on a single client. V1 is single-population-per-client.
- ASD/AAC re-architecture into the six-layer model. ASD/AAC stays on the legacy surface for all of Phase 4.0; its restructuring is Phase 4.x.
- Voice-capture for parent-concern field. Phase 4.0.1 enhancement.
- Audience-specific report versions (parent / school / insurance). Phase 4.0.2+.

**Build order:** strict 1 → 2 → 3 → 4 → 5 → 6, no leap-frog. Layer 06 metrics are meaningless without Layer 05's technique frame; Layer 04 inputs are meaningless without Layer 03's baseline. The order is the dependency graph.

**Target:** 6–8 weeks across 8–12 focused build sessions.

---

## Section 2 — Schema additions

All migrations are additive. No drops, no destructive renames. Every existing read path keeps working with null payloads. See [CLAUDE.md §15.0](CLAUDE.md) for path discipline — schema migrations apply to Supabase project `cgnjbjbargkxtcnafxaa` via Supabase MCP `apply_migration`.

| Table | Change | Shape | Approach | Backwards-compat note |
|---|---|---|---|---|
| `clients` | add column | `population_type text not null default 'asd_aac'` | extend in place | All existing rows auto-default to `asd_aac` — no read-path change. |
| `clients` | add column | `primary_language text` | extend in place | Generate Plan already references `client.primary_language`; no Flutter writer today. |
| `clients` | add column | `additional_languages text[]` | extend in place | Same. Null/empty array tolerated. |
| `clients` | add column | `primary_concern_verbatim text` | extend in place | Parent's words, captured at intake. New field; legacy clients have null. |
| `sessions` | add column | `population_payload jsonb` | extend in place | Holds Layer-03 live-entry data and Layer-06 progress data, keyed by population. Null for legacy AAC sessions. |
| `goal_plans` | add column | `lesson_plan_inputs jsonb` | extend in place | Layer-05 approach + techniques + session structure. Null for legacy plans. |
| `stg_evidence` | resurrect + add column | add `population_payload jsonb` | extend in place | Existing read paths in [pre_session_brief.dart](lib/widgets/pre_session_brief.dart) and [today_screen.dart](lib/screens/today_screen.dart) tolerate null payloads. Layer 06 fluency metrics live as keys inside this JSONB, NOT as new top-level columns. |
| `case_history_entries` | new table | see below | new | Layer 02 case history, population-specific, JSONB payload. |
| `assessment_entries` | new table | see below | new | Layer 03 assessment data across three sub-modes (live entry, debrief, parent interview). |

**Plural naming convention** (decision 4.6): tables holding many rows per parent are plural. New tables are `case_history_entries`, `assessment_entries`. JSONB columns extend existing tables for layers 04, 05, 06 (no new tables for those layers).

### `case_history_entries` (new)

```
id            uuid primary key default gen_random_uuid()
client_id     uuid not null references clients(id) on delete cascade
population_type text not null
payload       jsonb not null
created_at    timestamptz not null default now()
updated_at    timestamptz not null default now()
created_by    uuid references auth.users(id)
```

Indexes: `(client_id, population_type)`, `(client_id, created_at desc)`.
RLS: deferred per [§11](CLAUDE.md). Policy template (per-clinician isolation through `clients`) follows the §11 pattern.

### `assessment_entries` (new)

```
id            uuid primary key default gen_random_uuid()
client_id     uuid not null references clients(id) on delete cascade
session_id    bigint references sessions(id) on delete set null
mode          text not null check (mode in ('live_entry','debrief','parent_interview'))
population_type text not null
payload       jsonb not null
created_at    timestamptz not null default now()
updated_at    timestamptz not null default now()
created_by    uuid references auth.users(id)
```

`session_id` is nullable because Layer-03c parent-interview can pre-date a session row. `live_entry` and `debrief` rows must reference a session.
Indexes: `(client_id, mode, created_at desc)`, `(session_id)`.
RLS: deferred per §11.

### Developmental-stuttering V1 payload shapes

**`case_history_entries.payload` for `population_type = 'developmental_stuttering'`** — keys with explicit types (every key optional unless noted; Layer 02 captures incrementally):

```
onset                    : { age_or_date_text: text, what_prompted_concern: text }
development_pattern      : 'variable' | 'persistent' | 'cyclic' | null
variability_across_contexts : [
  { context: text, ease_label: 'easier_in' | 'harder_in', notes: text }
]
awareness_level          : 'none' | 'some' | 'high' | null
comfort_level            : 'high' | 'mixed' | 'low' | null     // affirmative wording per §13.15
secondary_behaviours     : text[]                              // free-list, e.g., 'eye_blinking'
previous_intervention    : [
  { where: text, when_text: text, approach: text, outcome: text }
]
family_history           : text
languages_spoken_at_home : text[]
notes_freeform           : text
```

**`sessions.population_payload` for live-entry (Layer 03a) under developmental stuttering:**

```
mode               : 'live_entry'
samples            : [
  {
    context        : 'reading' | 'conversation' | 'monologue' | 'play' | 'narrative'
    duration_seconds : int
    total_syllables   : int        // SLP-counted or Cue-Calc-derived
    stuttered_syllables : int
    percent_ss        : numeric    // computed deterministically — see Cue Calc §14.6
    audio_ref         : text       // optional pointer to a narrator transcript row
    notes             : text
  }
]
```

**`sessions.population_payload` for debrief (Layer 03b) under developmental stuttering:**

```
mode                   : 'debrief'
severity_rating        : { instrument_used: text, score_text: text }   // §13.9 menu pattern; instrument is SLP's choice
clinical_impression    : text
naturalness_rating     : 1..7 | null                                   // optional
observed_avoidance     : text[]                                        // free-list of observed avoidances
secondary_behaviours_observed : text[]
notes_freeform         : text
```

**`assessment_entries.payload` for parent_interview (Layer 03c)** — same shape as `case_history_entries.payload` for developmental_stuttering, augmented with a recurrence index:

```
recurrence_index : int      // 1, 2, 3 — supports multi-pass parent interviews across the assessment phase
captured_at_text : text     // SLP's framing of when this interview happened
... (all developmental_stuttering case-history keys, additive)
```

**`goal_plans.lesson_plan_inputs jsonb` for developmental stuttering** (Layer 05):

```
approach             : 'fluency_shaping' | 'stuttering_modification' | 'hybrid' | null
techniques           : text[]                  // SLP-selected, e.g., 'easy_onset', 'pull_outs', 'cancellations'
session_structure    : {
  duration_minutes_typical : int
  frequency_per_week_typical : numeric
  target_support_level     : 'independent' | 'minimal' | 'moderate' | 'maximal' | 'hand_over_hand' | null
}
family_involvement_plan : text
notes_freeform          : text
```

**`stg_evidence.population_payload jsonb` for developmental stuttering** (Layer 06, per-session-per-STG):

```
stuttered_syllables   : int | null
total_syllables       : int | null
percent_ss            : numeric | null         // computed deterministically by Cue Calc
naturalness_rating    : 1..7 | null
support_level         : 'independent' | 'minimal' | 'moderate' | 'maximal' | 'hand_over_hand' | null
self_report_rating    : 1..7 | null            // child's self-rating
technique_practised   : text                   // one of Layer 05's techniques[] menu
notes_freeform        : text
```

The trigger from [CLAUDE.md §9.4](CLAUDE.md) (rolling current_accuracy etc.) continues to apply on the structured columns of `stg_evidence`. Population-specific metrics live in JSONB and do not feed §9.4 — they feed the Progress Report composer (Section 4.3).

---

## Section 3 — Surface inventory

Every Flutter screen Phase 4.0 V1 touches.

| Screen | Action | Changes | Layer | Notes |
|---|---|---|---|---|
| [add_client_screen.dart](lib/screens/add_client_screen.dart) | refactor | split into Layer-01 + Layer-02 sections; add `population_type` dropdown; remove gendered-pronoun field if present (§13.15); add `primary_concern_verbatim` text field; add `primary_language` + `additional_languages`; route Layer-02 case-history capture to a new fluency-shaped form when `population_type == 'developmental_stuttering'` | 01 + 02 | Brain-dump and PDF-extract prompts become population-aware in 4.0.3. |
| [goal_authoring_screen.dart](lib/screens/goal_authoring_screen.dart) | refactor | `clarifying_answers` becomes population-aware; existing ASD-shaped flags (`processor_type`, `aac_primary`, `regulation_first`) become the `asd_aac` branch; new fluency-shaped clarifiers (approach lean, family stance on awareness, presence of avoidance) for developmental stuttering; add Layer-04 family goals + priority focus + readiness section; add Layer-05 approach-and-techniques section (writes `goal_plans.lesson_plan_inputs`) | 04 + 05 | One screen with population-branched body. |
| [add_session_screen.dart](lib/screens/add_session_screen.dart) | branch by population | for `population_type == 'developmental_stuttering'`, surface a Layer-03a live-entry sub-form embedded inside Add Session (decision 4.7); session row anchors the data, `sessions.population_payload jsonb` holds live-entry data | 03a | Existing `asd_aac` flow unchanged. |
| [session_note_screen.dart](lib/screens/session_note_screen.dart) | branch by population | unchanged for `asd_aac`; for `developmental_stuttering` route to new `session_note_screen_fluency.dart` (Layer-03b debrief surface) | 03b | Population router lives in this file. |
| `session_note_screen_fluency.dart` | new | post-session severity rating (instrument-menu pattern §13.9), clinical impression, naturalness rating, observed avoidance, secondary behaviours; writes `sessions.population_payload` with `mode = 'debrief'` | 03b | New file. |
| Layer-03c parent-interview surface | new | recurrent surface usable across the assessment phase; writes `assessment_entries` with `mode = 'parent_interview'` | 03c | Standalone screen accessible from client profile during assessment phase. Supports multiple recurrences (`recurrence_index`). |
| Assessment Report viewer/composer | new | reads layers 01–03 structured data; calls report composer endpoint; renders prose + metric tiles + disfluency-profile chart + clinical impression + recommendations + footer disclosure | 01–03 derived | See Section 4.2. |
| Progress Report viewer/composer | new | reads layer-06 structured data across multiple sessions + the goal plan from layer 05; renders longitudinal prose + deltas + goal-status pills + trajectory sparklines + clinical impression + recommendations + footer disclosure | 06 derived | See Section 4.3. |
| Baseline Snapshot | new (lightweight) | structured read-only snapshot of layers 01–03 at end of Layer 03; surfaced inside the chart timeline at the assessment-lock moment | 01–03 derived | Persisted as `assessment_entries` payload with `mode = 'baseline_snapshot'` extension OR as a distinct mode value — finalize in 4.0.5 build session. |
| `today_screen.dart` | untouched | — | — | — |
| `client_roster_screen.dart` | untouched | — | — | — |
| `cue_study_screen.dart` | untouched | — | — | Cue Study reads chart context — chart context builder must be extended to surface fluency data; that change lives in `chart_context.dart`, not the screen. |
| `narrator_screen.dart` | untouched | — | — | — |
| `settings_screen.dart` | untouched | — | — | — |
| `slp_profile_screen.dart` | untouched | — | — | — |

---

## Section 4 — System prompts

Three prompts Phase 4.0 V1 needs. Each prompt's contract is documented at the level a future Claude Code session needs to actually write it.

### 4.1 — Generate Plan, fluency branch

Extends existing `/api/generate-goals` SYSTEM_PROMPT (`C:\dev\cue\proxy\routes\generateGoals.js`) with a population dispatcher. Decision 4.5: **one endpoint**, internal dispatch.

**Prompt structure:**
- Shared preamble (vantage §13.8, language discipline §13.1–§13.12, humility §13.11, urgency §13.10, instruments §13.9, structured conditions §13.13).
- Population dispatcher: reads `client.population_type` from server-side chart payload, selects sub-prompt.
- Two sub-prompts: existing ASD/AAC sub-prompt (renamed `regulatory_asd`) + new `developmental_stuttering` sub-prompt.
- `framework_router` enum extends to: `regulatory_asd | developmental_stuttering | generic_fallback`.

**Input contract (Flutter → proxy):**
- Existing: `client_id`, `clarifying_answers`, optional `clinician_hypothesis`.
- New: `clarifying_answers` is now a population-tagged object. For developmental stuttering: `{ approach_lean, family_stance_on_awareness, presence_of_avoidance, ... }`.
- Server-side: proxy reads `clients.population_type`, `case_history_entries` (most recent for client), `assessment_entries` (all three modes), and pushes the assembled chart payload into the system prompt.

**Output contract (proxy → Flutter):**
- Same shape as today: `framework_router`, `router_confidence`, `data_sources`, `reasoning_trace`, `data_gaps`, `goals[]`.
- Each goal carries `goal_text`, `conditions_text` (structured per §13.13), `time_frame_weeks`, `evidence_rationale`, `evidence_tags`, `short_term_goals[]`.
- `population_payload jsonb` rides INSIDE `goals[].conditions_text` per §13.13 — fluency-specific lesson plan hints (approach lean, suggested techniques) are ONE of the structured-conditions sub-objects, not a separate top-level field.

**Encoded rules** the fluency sub-prompt must explicitly carry:
- §13.1–§13.4 forbidden-words and collegial-replacement tables.
- §13.6 chart-ownership (no provenance leaks).
- §13.8 vantage (Stance 2 default, name-first, no gendered pronouns).
- §13.9 instruments-as-menu pattern — applies to severity rating instruments (SSI-4, OASES, KiddyCAT — list as menu, never single-source).
- §13.10 no-manufactured-urgency — fluency plans never imply the SLP is "behind" on assessment cadence.
- §13.11 clinical humility — fluency plans default to smallest viable assessment scope (single conversational sample + brief caregiver intake is enough to start).
- §13.12 sentence-length discipline.
- §13.13 structured-conditions output.
- §13.15 affirmative language: "easier in / harder in" not "better/worse"; "comfort level" not "frustration".

### 4.2 — Assessment Report composer

New endpoint OR new system prompt within existing endpoint — finalize in 4.0.8 build session. Reads structured layers 01–03 data and composes the report prose.

**CRITICAL constraints to encode:**
- Every prose paragraph maps 1:1 to a structured input field. No invented findings.
- Blank or missing fields render as "not assessed" — never fabricated content.
- The clinical impression and recommendations sections are the SLP's territory: composer drafts a starting frame from structured data; SLP edits before release.

**Section anatomy (rendered, in order):**
1. **Header** — client name (Playfair Display), date of assessment, clinician name, RCI.
2. **Summary** — short Stance-2 paragraph composed from layer-01 + opening of layer-02 (population, primary concern verbatim, languages).
3. **Metric tiles** — %SS, severity rating, naturalness rating, support level — surfaced from layer-03a + 03b structured data. Cue Calc renders %SS (deterministic).
4. **Disfluency profile chart** — visual summary of layer-03a samples (per-context %SS bars).
5. **Clinical impression** — composer drafts from layer-03b `clinical_impression` + secondary_behaviours_observed + observed_avoidance. Editorial register (sans body, serif italic for the impression paragraph).
6. **Recommendations** — composer drafts Layer-04/05 starting frame from family goals + approach lean. Per §13.11, frame as starting point not contract.
7. **Footer disclosure** (verbatim per §13.14): *"Composed from structured data. Prose synthesised by Cue. Clinical impression and recommendations reflect the clinician's clinical judgement and may be edited prior to release."*

**Encoded rules:**
- §13.8 vantage (Stance 2 default).
- §13.13 structured-conditions consumption (read `queued_activities` + `suitable_instruments` + `discretion_close` for the recommendations section).
- §13.14 reasoning-on-tap (the report does NOT walk through Cue's reasoning; it presents structured findings).
- §13.15 affirmative language at the structured-display layer.
- §13.16 legacy data is never AI-re-extracted — if `case_history_entries` is null but legacy `clients.regulatory_profile` text exists, the report renders the legacy text in a clearly-labeled "previous intake notes (verbatim)" block, never re-interprets it.

### 4.3 — Progress Report composer

New prompt, parallel architecture to 4.2. Reads structured layer-06 data across multiple sessions (the per-session `stg_evidence.population_payload` rows) plus the goal plan from layer 05 (`goal_plans.lesson_plan_inputs`). Composes longitudinal prose.

**Section anatomy:**
1. **Header** — client name, reporting period, clinician.
2. **Summary of progress with delta numbers** — "%SS at start of period: X. Most recent sample: Y. Delta: Z." Composed from `stg_evidence.population_payload.percent_ss` first vs. last in window.
3. **Goal status pills** — current `short_term_goals.status` values: `active | mastered | on_hold | discontinued | modified`.
4. **Trajectory sparklines** — `percent_ss` over time, `naturalness_rating` over time, `support_level` over time (deterministic render — no LLM).
5. **Clinical impression** — composer drafts from observed pattern across the longitudinal data + technique-practised distribution.
6. **Recommendations** — composer drafts Layer-04/05 next-step frame from current state + remaining goal-plan elements.
7. **Footer disclosure** — same verbatim §13.14 disclosure as 4.2.

**Encoded rules:**
- All §13 rules from 4.2 apply.
- Specifically §13.10 (no manufactured urgency about progress pace) — sparklines and deltas are observations, never verdicts about whether progress is "on track."
- Specifically §13.11 (no contracts about next-period scope).

---

## Section 5 — Build sequence

Eight to twelve focused build sessions. Each fits cleanly in one Claude Code context. Session sizes: small ≈ 2–3 hours, medium ≈ 4–6 hours, large ≈ 6–8 hours of focused work.

| Phase | Description | Layer(s) | Files | Schema | Verification gate | Size |
|---|---|---|---|---|---|---|
| 4.0.1 | Schema migration — all columns + new tables in one migration | — | supabase migration only | all of Section 2 | migration applies cleanly to `cgnjbjbargkxtcnafxaa`; existing reads unaffected; new tables visible | medium |
| 4.0.2 | Layer 01 core profile refactor | 01 | `add_client_screen.dart`, `chart_context.dart` (read-side) | none (uses 4.0.1) | new fields capture and persist; legacy clients render unchanged; pronoun field removed | medium |
| 4.0.3 | Layer 02 case history for developmental stuttering | 02 | `add_client_screen.dart` (Layer-02 section), new fluency case-history form, brain-dump prompt population-routing | none | fluency case history captures and persists to `case_history_entries`; ASD/AAC clients route to legacy free-text path | medium |
| 4.0.4 | Layer 03 live-entry surface | 03a | `add_session_screen.dart` (population branch), live-entry sub-form, Cue Calc %SS path | none | fluency client's Add Session shows live-entry sub-form; %SS computes deterministically; data persists to `sessions.population_payload` | medium |
| 4.0.5 | Layer 03 debrief + parent-interview + Baseline Snapshot | 03b + 03c + snapshot | `session_note_screen.dart` population branch, new `session_note_screen_fluency.dart`, parent-interview surface | none | debrief writes `mode='debrief'`; parent interview writes `mode='parent_interview'`; baseline snapshot rendered at lock moment | large |
| 4.0.6 | Layer 04 pre-therapy planning | 04 | `goal_authoring_screen.dart` (Layer-04 section: family goals, priority focus, readiness) | none | Layer-04 inputs capture and persist | small |
| 4.0.7 | Layer 05 lesson plan inputs + Generate Plan fluency branch | 05 | `goal_authoring_screen.dart` (Layer-05 section), proxy `routes/generateGoals.js` (population dispatch + fluency sub-prompt) | none | Generate Plan routes by `population_type`; fluency sub-prompt produces fluency-shaped goals; `goal_plans.lesson_plan_inputs` persists | large |
| 4.0.8 | Assessment Report composer + viewer | 01–03 derived | new proxy endpoint or extension, new viewer screen | none | report composes only from structured fields; "not assessed" renders for blanks; footer disclosure verbatim | large |
| 4.0.9 | Layer 06 progress tracking surface | 06 | `session_note_screen_fluency.dart` extension for per-STG metrics, Flutter writer for `stg_evidence` | none | per-session per-STG fluency metrics persist to `stg_evidence.population_payload`; §9.4 trigger works on standard fields | medium |
| 4.0.10 | Progress Report composer + viewer | 06 derived | new proxy endpoint or extension, new viewer screen | none | longitudinal report composes from `stg_evidence` rows; sparklines render; footer disclosure verbatim | large |
| 4.0.11 | Polish + legacy-fallback rendering audit + visual language conformance | all | every Phase 4.0 surface | none | every new screen passes visual conformance gate (Section 6); every read path tolerates null `population_payload`; ASD/AAC clients verified unchanged end-to-end | medium |
| 4.0.12 | Final §7 cleanup + CLAUDE.md updates + Phase 4.0 close | — | `CLAUDE.md` (post-build state notes), phase report | none | §7 reflects final shipped state; phase report committed; Phase 4.0 closed | small |

Sessions can be split or merged at build-time if a context window dictates. The order is locked.

---

## Section 6 — Verification gates

For each layer, the layer is "done" when ALL of the following pass.

### Schema verification
- Migration applied successfully to `cgnjbjbargkxtcnafxaa`.
- Indexes built (every new index in Section 2).
- Foreign keys enforced.
- RLS policies set OR explicitly noted as deferred per [§11](CLAUDE.md) — Phase 4.0 may defer RLS, but every deferral is logged in §11 known issues.

### Surface verification
- Screen renders without errors for both `population_type = 'developmental_stuttering'` and `'asd_aac'`.
- Fields capture and persist (round-trip verified — write, refresh, re-read).
- Legacy rendering still works for `asd_aac` clients (no regression on Today, Clients, Chart, Goal Authoring for ASD/AAC).

### Trust architecture verification
- No LLM in any Cue Calc path. %SS, naturalness aggregates, deltas all computed deterministically in Dart.
- No invented content in any report. Every prose paragraph traces to a structured input field. Spot-check by manually nulling a field and confirming the corresponding paragraph renders "not assessed."
- Footer disclosure renders verbatim on every report (Assessment, Progress).
- Legacy free-text data renders in clearly-labeled "previous intake notes (verbatim)" blocks, never re-interpreted into structured form (§13.16).

### Visual conformance
- Paper background `#FAF7F0`, white cards `#FFFFFF`, 12px radius, 0.5px border at `rgba(0,0,0,0.08)`.
- Ink `#1A1A1A`; subtitle ink at 0.55α; eyebrow ink at 0.45α (lowercase, 11px, 0.06em letter-spacing).
- Amber primary `#EF9F27`, amber surface `#FAEEDA`, amber text on surface `#633806`.
- Body sans (Inter or equivalent). Editorial serif (Playfair Display) for client names and clinical-voice italic moments.
- Sentence case everywhere. No Title Case, no ALL CAPS except in tracked eyebrows.

### Backwards compatibility verification
- Every existing ASD/AAC client renders unchanged through entire Phase 4.0 build.
- No destructive migrations. No `regulatory_profile` or `baseline_summary` data is silently re-extracted.
- New read paths tolerate null `population_payload` and null new columns.

---

## Section 7 — Open items deferred to V1.1+

- Acquired adult fluency — Phase 4.0 V1.1.
- Neurogenic fluency — Phase 4.0 V1.2.
- Psychogenic fluency — Phase 4.0 V1.3.
- Cluttering — Phase 4.0 V1.4.
- Co-occurring populations on a single client (`secondary_population` array on `clients`) — Phase 4.x.
- Voice-capture for `primary_concern_verbatim` — Phase 4.0.1 enhancement.
- ASD/AAC re-architecture into the six-layer model — Phase 4.x.
- SSD/phonological — Phase 4.1.
- Voice — Phase 4.2.
- Language (expressive/receptive) — Phase 4.3.
- Dyslexia, CP, HI — Phase 4.4+.
- Audience-specific report versions (parent / school / insurance) — Phase 4.0.2+.
- RLS re-enable across new Phase 4.0 tables — gated on first external user onboarding per §11.
- PDF parser becoming population-aware — Phase 4.0.x enhancement; the V1 PDF parser remains the existing 14-key extraction, augmented to also capture `population_type` if detectable.
- Backfill tooling for migrating existing free-text Layer-2 data into structured shape — Phase 4.x, opt-in only with SLP attestation per §13.16.

---

**End of master spec.** Next session: 4.0.1 — schema migration. That session reads Section 2 and ships exactly that schema migration, nothing more.
