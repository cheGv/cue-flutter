# Audit theme tracker

A theme is a structural assumption that lives in multiple places
in the codebase. When a theme is identified, every site where the
assumption manifests gets logged here. Patches close sites one by
one. The tracker survives across phases.

Last updated: 8 May 2026 (Theme 6 closed 4.0.7.39; Theme 7 inventory updated 4.0.7.39)

---

## Theme 1: `soap_note` as sole content source

**Pattern:** Pre-4.0.7.28, the codebase assumed session content
lived in `soap_note` (or `transcript` for narrator sessions).
4.0.7.28 introduced a third location (`notes` column) for
prose-first capture, retroactively breaking every legacy reader.

| Site | Status |
|---|---|
| `report_screen.dart:196` (proxy body) | ✅ 4.0.7.31 (aec81a9) |
| `report_screen.dart` `_sessionIsEmpty` getter | ✅ 4.0.7.31a (1ee37ba) |
| `client_profile_screen.dart` timeline binary | ✅ 4.0.7.31b (45e0a51) |
| `client_profile_screen.dart` `_extractSoapPreview` | ✅ 4.0.7.31c (bf73903) |
| ReportScreen render tree (notes prose display) | ✅ 4.0.7.31c (bf73903) |
| `client_roster_screen.dart` Trigger 2 dual-aware | ✅ already correct |
| `today_screen.dart` all sites | ✅ already correct |
| `client_profile_screen.dart:303-318` (chart brief context) | ⏳ 4.0.7.31e |
| `chart_context.dart:201-219` (ordering polish) | ⏳ low priority |
| PDF export (notes format) | ⏳ 4.0.7.35 |

7 / 10 sites patched.

---

## Theme 2: Section header / content mismatch

**Pattern:** Section headers make claims the content contradicts.
First found on client profile: "Goals Girish is working toward"
displays mastered goals.

| Site | Status |
|---|---|
| `client_profile_screen.dart` Goals umbrella | ⏳ 4.0.7.37 |

1 site found. Audit (8 May) to sweep for others.

---

## Theme 3: Voice input scattered across surfaces

**Pattern:** Three distinct voice pipelines coexist with no shared
primitive. Different ergonomic contexts, but the consolidation
burden grows with each new surface.

| Surface | Pipeline | Status |
|---|---|---|
| `SessionCaptureScreen` | `VoiceNoteSheet` (Web Speech API) | ✅ working |
| `NarrateSessionScreen` | Deepgram WS, inline state machine | ✅ working |
| `GoalAuthoringScreen` | Deepgram WS, private `_MicButton` | ✅ working |

Consolidation deferred to Phase 4.0.8 design language pass.

---

## Theme 4: Hint vs. overlay z-order/baseline mismatch

**Pattern:** Custom textfield implementations with overlay
rendering on top of native hint can produce dual-text overlap
during interim states. Specifically when font-size between hint
and overlay differs by ≥1px.

| Site | Status |
|---|---|
| `goal_authoring_screen.dart` clinical hypothesis | ✅ 4.0.7.31f (cc43833) |

1 / 1 patched. Sweep complete 8 May — Narrate and VoiceNoteSheet
don't share Goal Authoring's Stack-overlay-on-TextField-with-hint
architecture, so the baseline-mismatch pattern can't manifest
there. Theme closes.

---

## Theme 5: Browser-refresh data loss

**Pattern:** Surfaces with non-zero exposure between SLP input
and DB persistence. Friend tester closes a tab → loses work.

| Site | Exposure | Status |
|---|---|---|
| `NarrateSessionScreen` | Full transcript window (worst — no DB write until Generate Report tap) | ⏳ 4.0.7.38 |
| `GoalAuthoringScreen` | Full hypothesis + clarifying answers + lens-chip selections | ⏳ 4.0.7.38 |
| `ReportScreen` | SOAP edit window + parent-update edit window (no auto-save) | ⏳ 4.0.7.38 |
| `SessionCaptureScreen` | First 30s of typing before auto-save tick | ⏳ 4.0.7.38 |
| `AddClientScreen` | Brain-dump pre-`/extract` window | ⏳ 4.0.7.38 |

0 / 5 sites patched. Pattern fix candidates: `beforeunload`
warning OR localStorage write-through OR shorter intervals.

---

## Theme 6: Deep-link coverage gap — CLOSED

**Pattern:** Browser refresh on most URLs bounced the SLP to
Today; only 2 of 11 surfaces survived refresh pre-39.

| Surface | Status |
|---|---|
| `/new-assessment` | ✅ pre-39 via `onGenerateRoute` |
| `/assessing/:clientId` | ✅ pre-39 via `_AssessmentCaseDeepLinkLoader` |
| `/today` | ✅ 4.0.7.39 |
| `/clients` | ✅ 4.0.7.39 |
| `/assessing` | ✅ 4.0.7.39 |
| `/narrator` | ✅ 4.0.7.39 |
| `/settings` | ✅ 4.0.7.39 |
| `/clients/:id` (chart) | ✅ 4.0.7.39 via `_ClientProfileDeepLinkLoader` |
| `/clients/:id/study` | ✅ 4.0.7.39 via `_CueStudyDeepLinkLoader` |
| `/sessions/:id` (report) | ✅ 4.0.7.39 via `_ReportDeepLinkLoader` (autoGenerate hardcoded false on deep-link path) |
| `/sessions/:id/edit` (capture edit-mode) | ✅ 4.0.7.39 via `_SessionCaptureEditDeepLinkLoader` |
| GoalAuthoring, Narrate, SessionCapture create-mode | 🚫 intentional Category 3 in 39 — refresh-during-flow loses unsaved input regardless of URL; exposure tracked under Theme 5 / 4.0.7.38 |

11 / 11 live surfaces covered. Pattern: per-surface loader (4
new in 39) with shared `_DeepLinkSpinner` + `_DeepLinkErrorCard`
helpers. Signed-out loads redirect to
`/login?return=<url>` instead of rendering an error card; the
`return` query param is validated as a relative path before
post-login navigation. Browser URL now reflects current screen
across all push sites — chrome navigation uses
`pushNamedAndRemoveUntil`, Cat 1 push sites use either
`pushNamed` or pass `RouteSettings(name: ...)` to keep the URL
accurate while preserving non-serializable constructor args
(e.g. ReportScreen's `autoGenerate: true` from the Save & Generate
flow, CueStudy's one-shot `initialMessage` seed). Theme closes.

---

## Theme 7: Orphaned screen files from prior phase rewrites

**Pattern:** Phase rewrites leave the new path live and old
screen files dead in repo, often unreachable but still
importable. Cleanup deferred indefinitely.

| File | Orphaned by | Status |
|---|---|---|
| `today_brief_preview_screen.dart` | 4.0.7.31i (a01ff77) | dead, in repo |
| `session_note_screen.dart` | 4.0.7.28 | dead, in repo |
| `debrief_fluency_screen.dart` | 4.0.7.27d | dead, in repo |
| `parent_interview_fluency_screen.dart` | 4.0.7.27d | dead, in repo |
| `pre_therapy_planning_fluency_screen.dart` | 4.0.7.27d (caller `_openPlanInputs` is `// ignore: unused_element`) | dead, in repo |
| `live_entry_fluency_screen.dart` | 4.0.7.27d (last referenced by orphaned SessionNoteScreen branch) | dead, in repo |
| `session_mode_picker_screen.dart` | 4.0.7.27d-population-router-removal (`SessionModePickerView` referenced only by removed-comment in `add_session_screen.dart:8`) | dead, in repo (added 4.0.7.39 recon) |
| `settings_screen.dart` | superseded by `slp_profile_screen.dart`; chrome routes `'settings'` → `SlpProfileScreen` (`app_layout.dart` `_routePathFor`). No external import of `SettingsScreen`. | dead, in repo (added 4.0.7.39 recon) |
| `add_goal_screen.dart` | no external `Navigator.push` call site; goal authoring routes through `GoalAuthoringScreen` and `LtgEditScreen` exclusively. | dead, in repo (added 4.0.7.39 recon) |

9 sites (6 prior + 3 surfaced during 4.0.7.39 recon). Cleanup
pass deferred to Phase 4.0.8 (or earlier if a sweep is wanted).
Notable: the four fluency-related files were preserved by
4.0.7.27d's commit message — *"Fluency-specific screens kept in
repo as dead code; Phase 2 multi-domain rebuild will adapt
them."* Conscious orphans, not accidental. The three added in
4.0.7.39 are inventory-discovery, not policy.

---

## Audit method

When a theme is identified, log:
1. The pattern (one paragraph)
2. Every site where the assumption manifests
3. Patched / queued / deferred status with phase number

When patching, sweep all sites in one phase if possible. If not,
patch the highest-traffic site first; queue the rest with
explicit phase numbers.
