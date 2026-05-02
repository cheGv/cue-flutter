# Phase 4.0 — Gap Analysis

**Read-only inspection of current Cue state vs. the six-layer Phase 4.0 architecture.**

V1 scope = developmental stuttering. The current codebase is shaped almost entirely around ASD/AAC + regulatory framing; this analysis names that drift explicitly.

---

## Section 1 — Current state inventory

### Schema reality vs. CLAUDE.md §7 canonical

§7 documents `patients` / `sessions.id uuid` / `short_term_goals.target_behavior + mastery_criterion jsonb`. The prototype actually uses `clients` / `sessions.id bigint` / `short_term_goals.specific + measurable + target_accuracy + time_bound_sessions`. Schema drift is acknowledged in §7's preamble. Every analysis below uses prototype column names since that is what the Flutter layer reads and writes.

### Layer 1 — Core Profile

| Surface / table | Fields present |
|---|---|
| `clients` table (write side: [add_client_screen.dart:362–383](lib/screens/add_client_screen.dart)) | `name`, `age`, `date_of_birth`, `diagnosis` (single text), `secondary_diagnosis`, `uses_aac` (bool), `communication_modality`, `additional_notes`, `guardian_name`, `guardian_whatsapp`, `school_setting`, `referral_source`, `previous_therapy` (bool), `previous_therapy_duration`, `regulatory_profile`, `baseline_summary` |
| Read side | [client_profile_screen.dart:212](lib/screens/client_profile_screen.dart), [client_roster_screen.dart:193](lib/screens/client_roster_screen.dart), [today_screen.dart:141](lib/screens/today_screen.dart) — all `select()` with no column projection, so they pick up whatever the DB returns. |
| Population shape | **ASD/AAC-shaped.** `uses_aac`, `communication_modality`, `regulatory_profile` are first-class columns. Languages (mentioned in §7 canonical: `primary_language`, `additional_languages`) are referenced in [generateGoals.js:263](C:/dev/cue/proxy/routes/generateGoals.js) (`client.languages`, `client.primary_language`) but I found no Flutter write path setting them. |

### Layer 2 — Case History

| Field/surface | Where |
|---|---|
| `regulatory_profile` (text), `baseline_summary` (text), `previous_therapy_duration` (text) | `clients` table; free-text. Captured in [add_client_screen.dart:71–77](lib/screens/add_client_screen.dart) under "Clinical intake fields". |
| `additional_notes` (text) | `clients` table; free-text. |
| Brain dump / PDF extract output | Both `_brainDumpSystem` and `_extractSystem` prompts ([add_client_screen.dart:21–40](lib/screens/add_client_screen.dart)) extract these same text fields from voice or uploaded reports. No structured case-history fields anywhere. |
| Population shape | **No structured case history.** Stuttering-specific fields (onset, variability, awareness, comfort, secondary behaviours) do not exist anywhere in schema or UI. The "regulatory profile" framing is itself ASD-shaped — not what a fluency clinician would write. |

### Layer 3 — Assessment Data (live entry / debrief / parent interview)

| Sub-mode | Status |
|---|---|
| (a) Live entry (during-session structured battery, %SS, taps/counts) | **Does not exist.** No live-entry surface, no per-trial structures, no fluency-specific counters. |
| (b) Debrief (post-session severity / impressions) | Partial: per-session `soap_note` JSON ([report_screen.dart:441–460](lib/screens/report_screen.dart)) and per-session structured fields in [session_note_screen.dart:94–120](lib/screens/session_note_screen.dart) (`barrier_motor`, `barrier_linguistic`, `barrier_cognitive`, `barrier_sensory`, `barrier_environmental`, `barrier_motivational`, `barrier_device_access`, `target_behaviour`, `condition`, `criterion`, `activity_name`, `activity_rationale`, `prompt_approach`, `prompt_level_used`, `attempts`, `independent_responses`, `prompted_responses`, `client_affect`, `goal_met`, `home_programme`, `next_session_focus`). These fields are ASD/AAC + prompt-hierarchy shaped; nothing fluency-specific. |
| (c) Parent interview | **Does not exist** as its own mode. Voice intake ([add_client_screen.dart:151–161](lib/screens/add_client_screen.dart)) exists but feeds Layer 1 + free-text Layer 2 only. |
| Baseline snapshot | Single `baseline_summary` text column; not structured. |
| PDF parser fields | The 14 keys in `_extractSystem`: `name`, `age`, `date_of_birth`, `diagnosis`, `secondary_diagnosis`, `primary_communication_modality`, `uses_aac`, `guardian_name`, `school_setting`, `referral_source`, `previous_therapy`, `previous_therapy_duration`, `regulatory_profile`, `baseline_summary`. **All Layer 1 + a thin slice of Layer 2.** No assessment-instrument scores extracted. |

### Layer 4 — Pre-therapy Planning

| Field/surface | Where |
|---|---|
| Family goals (verbatim) | **Does not exist** as a structured field. May land in `additional_notes` or `baseline_summary` at SLP discretion. |
| Priority focus / drag-to-reorder | Sequence preserved via `long_term_goals.sequence_num` ([client_profile_screen.dart:347](lib/screens/client_profile_screen.dart)) but no Layer-4 "priority focus" UI; reorder is implicit in plan generation. |
| Child's readiness, family involvement | **Do not exist.** |
| Generate Plan clarifying answers | [goal_authoring_screen.dart:139–143](lib/screens/goal_authoring_screen.dart): `processor_type` (gestalt/analytic), `aac_primary` (bool), `regulation_first` (bool). Plus `clinician_hypothesis` free-text. **All three are ASD/AAC framing.** Nothing fluency-relevant. |

### Layer 5 — Lesson Plan Inputs

| Field/surface | Where |
|---|---|
| Therapy approach (fluency shaping / stuttering modification / hybrid) | **Does not exist.** |
| Techniques to include | **Does not exist.** STG `specific` is free-text per goal; nothing structured at lesson-plan level. |
| Session structure (duration / frequency / target level) | Partial: `sessions.duration_minutes` referenced in §7 canonical, but Flutter writes only `client_id`, `date`, `user_id` ([add_session_screen.dart:71–77](lib/screens/add_session_screen.dart)). No frequency or target-level fields anywhere. |
| Generate Plan output | [generateGoals.js:171–199](C:/dev/cue/proxy/routes/generateGoals.js) returns `framework_router`, `router_confidence`, `data_sources`, `reasoning_trace`, `data_gaps`, `goals[]` with each goal carrying `goal_text`, `conditions_text` (structured per §13.13), `time_frame_weeks`, `evidence_rationale`, `evidence_tags`, `short_term_goals[]`. The `framework_router` enum is `regulatory_asd | generic_fallback` — **fluency is not a routing target.** |

### Layer 6 — Progress Tracking

| Field/surface | Where |
|---|---|
| Per-session structured data | `session_note_screen.dart` writes the barrier-axis + prompt-level + trial-count fields listed under Layer 3(b) above. Same row in `sessions`. |
| `stg_evidence` (the canonical table per §7) | Read-side only: [pre_session_brief.dart:126](lib/widgets/pre_session_brief.dart), [today_screen.dart:332](lib/screens/today_screen.dart). I found **no Flutter write path** that inserts into `stg_evidence`. The §8 additive migration to create the table exists in CLAUDE.md but is not consumed by any session-write flow I found. |
| %SS, naturalness rating, support level, self-report | **Do not exist** in any column or surface. |
| Soap note | `sessions.soap_note` — JSON-stringified `{s, o, a, p}` text. Manual entry via [report_screen.dart](lib/screens/report_screen.dart) or AI-generated via narrator. |
| Parent update | `sessions.parent_update`, `sessions.parent_update_generated_at` ([report_screen.dart:572](lib/screens/report_screen.dart)). |
| Attestation | `sessions.ai_generated`, `clinician_attested`, `attested_at`, `attested_by`. |
| Population shape | **Generic-prompt-hierarchy shaped, not fluency-shaped.** Counts independent vs. prompted responses; no stuttered-syllable counts, no naturalness scale, no self-rating. |

### Derived outputs

| Output | Status |
|---|---|
| Assessment report | **Does not exist.** No surface composes Layer 1–3 into a report. |
| Progress report | **Does not exist** as a separate construct. The chart timeline ([client_profile_screen.dart:1663+](lib/screens/client_profile_screen.dart)) renders sessions and goal events but is a chart-side affordance, not a report. |
| Baseline snapshot | Closest analogue: `clients.baseline_summary` (free text). No structured snapshot. |

### Generate Plan input contract (current)

`POST /api/generate-goals` ([goal_authoring_screen.dart:131–146](lib/screens/goal_authoring_screen.dart)) sends only `client_id` + `clarifying_answers` (3 ASD-shaped flags) + optional `clinician_hypothesis`. The proxy ([generateGoals.js:227–275](C:/dev/cue/proxy/routes/generateGoals.js)) builds the chart payload server-side from `clients`, `clinical_sessions`, and existing `goals`. Flutter does **not** push Layer 2/3/4/5 inputs through the API surface — they don't exist to push.

### Tables actually persisted to (write paths confirmed in lib/)

`clients`, `sessions`, `long_term_goals` (via proxy + Flutter inline edits), `short_term_goals` (via proxy + chart-screen add), `clinic_profile` (RCI number, settings), plus the proxy-only writes to `goal_plans`, `goal_attestations`, `goal_evidence_tags`. **No Flutter write paths to `stg_evidence` or `narrator_transcripts`.**

---

## Section 2 — Gap inventory

### Layer 1 — Core Profile

- **Missing.** `primary_language` and `additional_languages` columns are referenced by Generate Plan but no UI captures them.
- **ASD/AAC-shaped.** `uses_aac`, `communication_modality`, `regulatory_profile` are first-class. For fluency these are noise; for AAC they are signal.
- **Recommendation.** Keep core profile minimal and population-agnostic. Move `uses_aac` / `communication_modality` / `regulatory_profile` into a population-specific case-history sub-record (Layer 2). Add `primary_concern_verbatim` (parent's words) as Layer-1.

### Layer 2 — Case History

- **Missing entirely.** No structured case-history table exists. All case-history-shaped data lives as free text on `clients`.
- **New table needed.** `case_history` keyed by `client_id` with population discriminator (e.g., `population_type text` — `developmental_stuttering`, `asd_aac`, `ssd`, etc.) and a JSONB `payload` keyed by population.
- **V1 (developmental stuttering) payload shape needed:** `onset` (when noticed, what prompted concern), `development_pattern` (variable/persistent/cyclic), `variability_across_contexts` (home, school, with whom), `awareness_level` (none/some/high), `comfort_level` (affirmative wording — replaces "frustration"), `secondary_behaviours` (eye blinking, head movement, etc., free-list), `previous_intervention` (structured: where, when, what approach, outcome).
- Migrating ASD/AAC `regulatory_profile` + `baseline_summary` into a population-aware payload is non-trivial — the existing free text doesn't decompose cleanly. Open question 4.4.

### Layer 3 — Assessment Data

- **Three sub-modes all missing as first-class surfaces.**
- **Live entry (a):** no structured per-trial battery. For fluency V1 needs at minimum: syllable counter (total + stuttered), context tag (reading/conversation/monologue), duration, sample audio reference, computed %SS. Per §13.14 / §14.6, %SS is a Cue Calc target.
- **Debrief (b):** the existing post-session `session_note_screen.dart` fields are barrier-axis + prompt-hierarchy shaped. Need a fluency debrief surface: severity rating (clinician's framework — SSI-4 is copyrighted per §13.14 so menu pattern from §13.9 applies), impressions, naturalness, observed avoidance.
- **Parent interview (c):** voice intake exists but is single-pass and feeds Layer 1. Needs to become a recurrent surface usable across the assessment phase, with the structured Layer-2 case-history payload as its target.
- **Baseline snapshot:** end-of-Layer-3 derivative; needs a structured representation (read-only after lock) so Layer 4–5 can reference it.

### Layer 4 — Pre-therapy Planning

- **Missing entirely.** Nothing for family goals, priority focus, readiness, family involvement.
- **New surface needed.** A "plan inputs" screen between Layer 3 lock and Layer 5 plan generation.
- The current `clarifying_answers` (`processor_type`, `aac_primary`, `regulation_first`) is the closest analogue but is ASD-shaped. For developmental stuttering V1 the clarifiers are different (e.g., approach lean: shaping/modification/hybrid; family stance on awareness; presence of avoidance).

### Layer 5 — Lesson Plan Inputs

- **Missing entirely.** Generate Plan currently produces LTGs + STGs directly without an intermediate "approach + techniques + session structure" object.
- **`framework_router` is binary** (`regulatory_asd | generic_fallback`). Fluency-specific routing does not exist. V1 needs at least `developmental_stuttering` as a router target with its own system-prompt branch.
- The plan generator lives in one monolithic [generateGoals.js](C:/dev/cue/proxy/routes/generateGoals.js) SYSTEM_PROMPT (~200 lines). Adding fluency = adding a routing layer + a fluency-shaped sub-prompt. Open question 4.5.

### Layer 6 — Progress Tracking

- **Missing fluency fields.** No %SS, no naturalness, no support-level, no self-report ratings.
- **`stg_evidence` table dormant.** Schema-defined but no Flutter writer. Either resurrect it (and route the per-session metrics through it) or rebuild atop a different structure that fits Phase 4.
- **Existing per-session `session_note_screen.dart` fields are AAC-shaped** (barrier axes, prompt levels). They will not generalise to fluency without renaming and re-typing. A population-aware per-session payload (JSONB on `sessions` keyed by population) is probably the cleaner path. Open question 4.1.

### Cross-cutting

- **Population awareness is absent everywhere.** No `population_type` column on `clients`. Every Generate Plan call routes through the same prompt regardless of population.
- **PDF parser is not population-aware.** Same 14-key extraction prompt used for every uploaded report. A fluency clinician uploading a stuttering severity report gets nothing structured back about onset, %SS, severity rating.
- **No assessment-report or progress-report composer.** Both are listed as Phase 4.0 derived outputs with no current implementation.

---

## Section 3 — Migration plan outline

### Tables: extend in place vs. add new

| Decision | Tables |
|---|---|
| **Extend in place.** | `clients` — add `population_type`, `primary_language`, `additional_languages`, `primary_concern_verbatim`. Existing ASD-shaped columns deprecate-but-retain (read-compat). |
| **Extend in place.** | `sessions` — add `population_payload jsonb` for population-shaped per-session data. Existing AAC-shaped columns retain for backwards compatibility. |
| **New table.** | `case_history` (Layer 2, JSONB keyed by `population_type`). |
| **New table.** | `assessment_entries` (Layer 3 live + debrief, with `mode` discriminator and a JSONB payload). |
| **New table.** | `plan_inputs` (Layer 4 — pre-therapy planning record, written before Generate Plan is called). |
| **New table or extension.** | Layer 5 lesson-plan inputs — could live as a JSONB on `goal_plans` rather than a new table. Open question 4.2. |
| **Resurrect or replace.** | `stg_evidence` for Layer 6 progress tracking — open question 4.1. |

### Flutter screens: refactor vs. new

| Decision | Screens |
|---|---|
| **Refactor.** | [add_client_screen.dart](lib/screens/add_client_screen.dart) — split into Layer-1 (core profile) + Layer-2 (case-history, population-aware). Brain dump and PDF extract become routable per population. |
| **Refactor.** | [goal_authoring_screen.dart](lib/screens/goal_authoring_screen.dart) — clarifying_answers becomes population-aware; today's three flags become the ASD branch only. |
| **Refactor.** | [session_note_screen.dart](lib/screens/session_note_screen.dart) — currently AAC-shaped. Either branch by population or replace with a new population-aware surface. |
| **New screen.** | Layer-3 live-entry surface (during-session structured battery — fluency syllable counter for V1). |
| **New screen.** | Layer-3 debrief surface (post-session severity/impressions for fluency). |
| **New screen.** | Layer-4 pre-therapy planning. |
| **New screen.** | Layer-5 lesson-plan inputs (likely a sub-step of Goal Authoring rather than a standalone screen). |
| **New screen.** | Assessment report viewer; progress report viewer. |
| **Untouched.** | [today_screen.dart](lib/screens/today_screen.dart), [client_roster_screen.dart](lib/screens/client_roster_screen.dart), [cue_study_screen.dart](lib/screens/cue_study_screen.dart), [narrator_screen.dart](lib/screens/narrator_screen.dart), [settings_screen.dart](lib/screens/settings_screen.dart), [slp_profile_screen.dart](lib/screens/slp_profile_screen.dart) — Phase 4.0 doesn't touch these. |

### Migration ordering for existing ASD/AAC clients

1. Ship `population_type` column with default `asd_aac` for all existing rows. No client-visible change.
2. Ship case-history table empty; existing `regulatory_profile` and `baseline_summary` text remain on `clients` and continue to render via legacy fallback in [client_profile_screen.dart](lib/screens/client_profile_screen.dart) (same pattern as Phase 3.3.7c structured-conditions migration).
3. Ship Layer-3 / Layer-4 / Layer-5 / Layer-6 surfaces guarded by `population_type == 'developmental_stuttering'`. ASD/AAC clients see no change.
4. Backfill existing ASD/AAC clients into the new structure incrementally — opt-in by SLP, not bulk-migration. Some clients may stay on legacy shape indefinitely if they're nearing discharge.

### Backwards compatibility strategy

The Phase 3.3.7c precedent (legacy plain-string vs. structured-JSON conditions, both readable) is the template. Every new render path tries the new structured shape first, falls back to legacy free-text on parse failure or shape mismatch. No destructive migrations.

---

## Section 4 — Open questions

**4.1 — `stg_evidence` resurrect or replace?**
The §7 canonical schema includes `stg_evidence` for per-session per-STG measurement. It is read by `pre_session_brief.dart` and `today_screen.dart` but no Flutter writer exists. Phase 4.0 needs a per-session per-STG metric surface. Question: extend `stg_evidence` (add fluency fields like `stuttered_syllables`, `total_syllables`, `naturalness_rating`, `self_report_rating`), or build a new `progress_entries` table with population-aware JSONB payload? The latter parallels the case-history / assessment-entries pattern; the former preserves §7's stated direction.

**4.2 — Layer-5 lesson plan: new table or JSONB on `goal_plans`?**
Goal Authoring already inserts into `goal_plans` ([generateGoals.js:308–321](C:/dev/cue/proxy/routes/generateGoals.js)) carrying `framework_router`, `router_confidence`, `clarifying_answers`, `reasoning_trace`, `data_sources`. Layer 5 (approach + techniques + session structure) is conceptually the same scope of object — the plan's metadata. A `lesson_plan_inputs jsonb` column on `goal_plans` is probably right; new table feels like over-engineering. Confirm.

**4.3 — Population discriminator placement.**
Should `population_type` live on `clients` (one population per client, simple — but a single child may have co-occurring fluency + SSD), on `case_history` (one population per case-history record — but a child has one chart, not multiple charts), or on `goal_plans` (the plan declares its population — but Layer-1/2 still need to know what intake form to render)? Recommend on `clients` for V1 with `secondary_population` array as a Phase 4.x extension.

**4.4 — Migrating existing free-text Layer-2 data.**
`regulatory_profile` and `baseline_summary` are free-text columns currently used by every existing chart. New schema asks for structured Layer-2 payload keyed by population. For ASD/AAC clients, decompose the existing free text into the structured payload how? Options: (a) leave legacy free text on `clients` and never structure it, render it in legacy mode forever; (b) prompt SLP at first visit-after-Phase-4-ship to migrate; (c) AI-assisted re-extraction from the original PDF if still on file. Recommend (a) with optional (b) — never (c) without explicit SLP attestation.

**4.5 — Generate Plan routing for fluency.**
Current `framework_router` is binary. Adding `developmental_stuttering` requires a fluency-shaped system-prompt branch (~200 lines, comparable to the existing one). Question: does the V1 ship a separate `/api/generate-fluency-plan` endpoint, or extend `/api/generate-goals` with a routing layer that selects the prompt? The latter is closer to today's architecture; the former is cleaner per-population. Recommend extending the existing endpoint with a population dispatch — keeps one generation surface.

**4.6 — Naming.**
Tables proposed above (`case_history`, `assessment_entries`, `plan_inputs`, `progress_entries`) need final names. CLAUDE.md §7 uses singular table names where some Postgres conventions prefer plural. Existing tables are mixed (`clients`, `sessions` plural; `clinic_profile` singular). Pick one rule for Phase 4 and document.

**4.7 — Layer-3 live entry: where does it sit in the navigation?**
Live entry happens *during* a session. Options: (a) gate behind "start narrator" so it's a sibling of the narrator surface; (b) make it a Layer-3-only surface that the SLP opens before-or-during a session and that links to a session row; (c) embed it in the existing Add Session flow ([add_session_screen.dart](lib/screens/add_session_screen.dart)). Each has different chart-timeline implications.

**4.8 — Existing `session_note_screen.dart` — keep, replace, or branch by population?**
Currently AAC-shaped (barrier axes, prompt hierarchy). Three options: (a) deprecate entirely; (b) keep only for ASD/AAC clients via population branch; (c) replace with one population-aware surface that switches its body per `population_type`. (b) is the lowest-disruption route and matches the no-destructive-migration principle.

**4.9 — Layer-6 ordering vs. Layer-4/5 dependency.**
Layer-6 progress tracking ships per-session for the developmental stuttering plan. Strictly speaking, Layer-6 metrics are only meaningful once Layer-4/5 set the "what to measure" frame. Can Layer-6 ship before Layer-4/5? Probably no — the SLP doesn't know which technique was practised if Layer-5 hasn't named the technique set. Confirm ordering: Layer 1 → 2 → 3 → 4 → 5 → 6, no leap-frog.

---

## Section 5 — Files inspected

| File | Relevance |
|---|---|
| [CLAUDE.md §7](CLAUDE.md) (canonical schema) | §7 is the target schema; prototype drift is acknowledged. Source of `patients`/`sessions.id uuid`/`stg_evidence` truth. |
| [CLAUDE.md §8](CLAUDE.md) (additive migration) | Confirms `stg_evidence`, `goal_attestations` migrations were specified for Phase 1; Flutter writers never landed. |
| [CLAUDE.md §13.14](CLAUDE.md), [§14.6](CLAUDE.md), [§14.7](CLAUDE.md) | Phase 4.1 Cue Calc / Phase 5+ Cue Reference boundaries — sets the rule that fluency severity calculations (%SS, etc.) belong in Cue Calc, not in the plan generator. |
| [lib/screens/add_client_screen.dart](lib/screens/add_client_screen.dart) | Layer 1 + Layer 2 capture surface; PDF/voice extract prompts; current 14-field extraction list. |
| [lib/screens/client_profile_screen.dart](lib/screens/client_profile_screen.dart) | Chart render; reads `clients`, `long_term_goals`, `short_term_goals`, `sessions`. Confirms prototype column names. |
| [lib/screens/client_roster_screen.dart](lib/screens/client_roster_screen.dart) | `clients` + `sessions` + `long_term_goals` consumer. |
| [lib/screens/today_screen.dart](lib/screens/today_screen.dart) | `stg_evidence` reader (no writer found). |
| [lib/screens/goal_authoring_screen.dart](lib/screens/goal_authoring_screen.dart) | Generate Plan input contract; clarifying_answers shape; `clinic_profile` (RCI). |
| [lib/screens/add_session_screen.dart](lib/screens/add_session_screen.dart) | Confirms session insert payload is `{client_id, date, user_id}` only. |
| [lib/screens/session_note_screen.dart](lib/screens/session_note_screen.dart) | AAC-shaped post-session structured fields (barriers, prompt hierarchy, trial counts). |
| [lib/screens/report_screen.dart](lib/screens/report_screen.dart) | `sessions.soap_note` JSON shape; attestation columns; parent-update fields. |
| [lib/screens/narrator_screen.dart](lib/screens/narrator_screen.dart) | Session insert from narrator: `transcript`, `soap_note`, `parent_summary`, `duration_seconds`, `status`. |
| [lib/widgets/pre_session_brief.dart](lib/widgets/pre_session_brief.dart) | `stg_evidence` consumer; tolerates missing tables/columns gracefully. |
| [lib/utils/chart_context.dart](lib/utils/chart_context.dart) | Chart-context builder consumed by Cue Study; documents how Phase 1+ narrative is composed for the LLM. |
| [C:/dev/cue/proxy/routes/generateGoals.js](C:/dev/cue/proxy/routes/generateGoals.js) | Generate Plan input → output contract; `framework_router` enum; `goal_plans`/`goal_attestations`/`goal_evidence_tags` writes. |
| [C:/dev/cue/proxy/server.js](C:/dev/cue/proxy/server.js) `/extract` | Confirms PDF/DOCX/image extraction is content-block-shape-only — no structured Layer-3 extraction logic in the proxy. |
| [lib/models/short_term_goal.dart](lib/models/short_term_goal.dart), [lib/models/stg_evidence.dart](lib/models/stg_evidence.dart), [lib/repositories/](lib/repositories/) | Phase 1 STG-memory models — defined but not actively wired in Phase 3 surfaces. |

---

**End of gap analysis.** Awaiting review before any commits, schema migrations, or code changes. No edits made; only this file added.
