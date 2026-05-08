# Cue backlog

Last updated: 8 May 2026

This is the active phase queue maintained across the
4.0.7.31x sprint and the 8 May audit. Items are listed in
intended-execution order. A phase moves up the queue when a
friend-tester signal or audit finding promotes it; otherwise
order holds.

---

## Active queue (intended execution order)

| # | Phase | Scope | Status |
|---:|---|---|---|
| 1 | **4.0.7.31e** | Chart brief notes-aware. Patch the 9th `soap_note`-as-sole-content site at `client_profile_screen.dart:303-318` — the LLM brief context that drops notes-only sessions from the "last 3" shipped to `/generate-brief`. Last open site in Theme 1's main payload. | ⏳ queued |
| 2 | **4.0.7.37** | Section header / content mismatch sweep. Goals umbrella ("Goals X is working toward" over active + celebrating + archive) is the seed; sweep for analogous patterns across the chart, today, roster. | ⏳ queued |
| 3 | **4.0.7.38** | Browser-refresh data loss audit. 5 surfaces have non-zero exposure between SLP input and DB persistence (Narrate, Goal Authoring, Report SOAP edit, SessionCapture pre-30s, AddClient brain-dump). Pattern fix candidates: `beforeunload` warning OR localStorage write-through OR shorter auto-save intervals. | ⏳ queued |
| 4 | **4.0.7.39** | Deep-link coverage. Currently 2/11 surfaces survive browser refresh (`/new-assessment`, `/assessing/:clientId`). Replicate `_AssessmentCaseDeepLinkLoader` pattern for `/clients/:id` and `/sessions/:id` at minimum. | ⏳ queued |
| 5 | **4.0.7.31g** | Render proxy cold-start UX. "Warming up..." snackbar when WS connection takes >3s. Conditional ship — only if friend tester signals it. | ⏳ conditional |
| 6 | **4.0.7.30** | Context warmth pass on SessionCaptureScreen. Bundles 3 deferred items: `primary_concern_verbatim` family-quote surfacing, active STG focus reminder, session sequence number. | ⏳ queued (post friend tester) |
| 7 | **4.0.7.29** | AAC clinical_area mapping. Route `aac` from the ALL OTHERS default into the autism-developmental field set (or a bespoke AAC set). | ⏳ queued |
| 8 | **4.0.7.32** | App-wide register sweep. ~17 reachable teal sites identified (chart, narrator, intake, app_layout, cue_theme, goal_achieved_overlay). Scope reduced slightly by 4.0.7.31i (Settings dev entry block removed 3 off-register colors). Needs design review for the chart-screen clinical-action lock per CLAUDE.md. | ⏳ queued |
| 9 | **4.0.7.33** | Narrate-handoff date gap. Synthetic session map handed to ReportScreen `{id, transcript}` lacks `date` → triggers "Unknown date" downstream. Fix the synthetic map. | ⏳ queued |
| 10 | **4.0.7.34** | Incomplete-session surfacing on roster. New attention trigger for `status='complete' + soap_note=null` rows so the SLP sees "wrote prose, never generated AI report" surfaced as a Trigger 2 variant. | ⏳ queued |
| 11 | **4.0.7.35** | PDF export notes format. Discrete design pass: do raw notes print? Distinct "Notes-only" PDF format? Stay screen-only? | ⏳ queued |
| 12 | **4.0.7.40** | Mastered-goal anticipation. Layer 1 substrate for Phase 4.1. Surface what's clinically obvious from a child's longitudinal data when the SLP marks a goal achieved — without generation, just summary. | ⏳ queued |
| 13 | **4.0.8a/b/c** | Today screen evolution. Spec content not yet retrievable from chat history; doc deferred to a separate commit. | ⏳ queued (spec pending) |
| 14 | **4.0.8** design language lock | Combined: app-wide register sweep + voice-input pipeline consolidation (4 pipelines → 1) + orphaned-screen cleanup pass (6 sites per Theme 7). | ⏳ queued |
| 15 | **4.1.0+** | Clinical intelligence architecture. See `docs/clinical-intelligence-architecture.md` for thesis. Begins after 4.0.8 ships and friend-tester (c)-class product-articulation signal lands. | ⏳ thesis only |

---

## Open product questions (not commits)

These are decisions that need human-level discussion before
becoming code:

- **`clinic_profile` vs `slp_profiles` table** — which is canonical? Two tables hold overlapping clinician metadata. One should be deprecated, or Settings should grow to surface both.
- **Restore-archived UI** — soft-delete shipped 4.0.7.10; restore UI still missing. Either build it or pivot to hard-delete.
- **CLAUDE.md teal lock for chart clinical actions** — predates the Phase 4.0 register pivot. Friend tester may not parse "teal = clinical action" if the rest of the app is amber. Worth a register-sweep design decision before 4.0.8 lands.
- **`population_type` column** — is it still load-bearing? AddSessionScreen and SessionCaptureScreen post-31h fetch it through the legacy column. The column itself may have downstream consumers worth verifying.
- **Friend-tester (c)-class signal articulation** — see `clinical-intelligence-architecture.md`. What specifically counts as the trigger to begin Phase 4.1 spec writing?

---

## Audit themes (cross-reference)

See `docs/audit-theme-tracker.md` for the structural themes
this backlog descends from. Active themes that map to queued
phases:

- Theme 1 (`soap_note` as sole content source) → 4.0.7.31e
- Theme 2 (section header / content mismatch) → 4.0.7.37
- Theme 5 (browser-refresh data loss) → 4.0.7.38
- Theme 6 (deep-link coverage gap) → 4.0.7.39
- Theme 7 (orphaned screen files) → 4.0.8 cleanup pass
- Theme 3 (voice input pipelines) → 4.0.8 consolidation

---

## Recent commits (8 May 2026, in reverse chronological order)

| Commit | Phase | Summary |
|---|---|---|
| `8c7cea7` | 4.0.7.36b-tracker-update | Audit theme tracker through state of `a01ff77`. Theme 4 closes; Themes 5/6/7 added. |
| `a01ff77` | 4.0.7.36 + 31h/i/j bundle | Timeline refresh after edit (1 site genuinely needed; `_refreshSpine` extended to bust `_sessionsFuture`). AddSessionScreen dead-state cleanup (`_populationType`, `_saving`, skeleton, spinner). Settings dev entry point + import removed. ReportScreen `_bg` → `kCuePaper`. Net –64 LOC. |
| `cc43833` | 4.0.7.31f | Goal authoring hint suppressed during Deepgram interim overlay. 2-line conditional. Theme 4. |
| `bf73903` | 4.0.7.31c | ReportScreen renders notes prose at top of summary card with Continue editing → link. SessionCaptureScreen edit mode (`existingSessionId`). `_extractSoapPreview` 3-tier fallback. +170 LOC. |
| `d4d0753` | 4.0.7.31d | Roster copy register cleanup. Three string flips + one ignore directive. |
| `45e0a51` | 4.0.7.31b | Timeline binary now treats `soap_note` OR `notes` as documentation. ~5 LOC. |
| `1ee37ba` | 4.0.7.31a | `_sessionIsEmpty` counts notes as content. autoGenerate gate fires correctly for unified-flow shape. 8 LOC. |
| `aec81a9` | 4.0.7.31 | Unified Save & Generate flow. ReportScreen becomes review-only. Notes-column proxy fix. 9 teal sites in ReportScreen → kCueAmber/kCueInk. +358 LOC. |
| `bf3d151` | 4.0.7.28 | SessionCaptureScreen replaces 6-step wizard. Prose-first capture, auto-save, domain-aware optional fields, VoiceNoteSheet dictate. 832 LOC + 14-line routing diff. |
| `ddbc295` | 4.0.7.27e-cue-noticed-copy-revise | Indian English clinical register on draft-aware brief copy. |
| `b28b33d` | 4.0.7.27e-cue-noticed-draft-aware | BriefThoughtCard honors pending_attestation drafts. |
| `539433a` | 4.0.7.27d-defer-session-insert | NarrateSessionScreen owns row creation via INSERT-or-UPDATE on first save. Empty-draft accumulation killed. |
| `fb4bf97` | 4.0.7.27d-stg-focus-resolver-fix2 | Drop non-existent `goal_text` column from STG select. |
| `63bc333` | 4.0.7.27d-typed-notes-routing-fix | Route `_addManually` to SessionNoteScreen (later replaced by SessionCaptureScreen in 4.0.7.28). |
| `bb2ae7a` | 4.0.7.27d-stg-focus-resolver-fix | STG focus resolver fallback chain (silently 400'd, fixed in fix2). |
| `030fb52` | 4.0.7.27d-population-router-removal | Fluency-coded routing removed from new-session and Build with Cue. Friend tester unblocker for `aarif` and other developmental_stuttering clients. |
| `31f97ef` | 4.0.7.23c-deploy | Build with Cue v2 system prompt parser + render. Three render states added: safeguarding halt, clarifying question, pending_attestation goals. |

---

## Documents that live in `docs/`

- `docs/audit-theme-tracker.md` (8 May 2026) — structural themes across the codebase. 7 active, 1 closed.
- `docs/audit-2026-05-08.md` — empty grid template. Findings authored separately during the 8 May audit pass.
- `docs/clinical-intelligence-architecture.md` (Phase 4.1 thesis) — speculative, revised 8 May.
- `docs/today-screen-evolution.md` — pending; spec content not yet retrievable from chat history.

---

## How this backlog gets maintained

When a phase ships, its row moves out of "active queue" and
into "recent commits." When a new phase is identified
(typically through audit findings or friend-tester signals),
it slots into the queue at a position justified by an
explicit reason. The "Last updated" date in the header is
bumped on every change.
