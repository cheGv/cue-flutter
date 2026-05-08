# Audit theme tracker

A theme is a structural assumption that lives in multiple places
in the codebase. When a theme is identified, every site where the
assumption manifests gets logged here. Patches close sites one by
one. The tracker survives across phases.

Last updated: 8 May 2026

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

## Theme 6: Deep-link coverage gap

**Pattern:** Browser refresh on most URLs bounces the SLP to
Today; only 2 of 11 surfaces survive refresh.

| Surface | Status |
|---|---|
| `/new-assessment` | ✅ via `onGenerateRoute` |
| `/assessing/:clientId` | ✅ via `_AssessmentCaseDeepLinkLoader` |
| `/clients/:id` (chart) | ⏳ 4.0.7.39 |
| `/sessions/:id` (report or capture) | ⏳ 4.0.7.39 |
| Today, Roster, Settings, GoalAuthoring | ⏳ 4.0.7.39 partial scope (some intentional) |

2 / 11 sites covered. Pattern is established
(`_AssessmentCaseDeepLinkLoader`); 4.0.7.39 replicates it for
chart + sessions at minimum.

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

6 sites. Cleanup pass deferred to Phase 4.0.8 (or earlier if a
sweep is wanted). Notable: the four fluency-related files were
preserved by 4.0.7.27d's commit message — *"Fluency-specific
screens kept in repo as dead code; Phase 2 multi-domain rebuild
will adapt them."* Conscious orphans, not accidental.

---

## Audit method

When a theme is identified, log:
1. The pattern (one paragraph)
2. Every site where the assumption manifests
3. Patched / queued / deferred status with phase number

When patching, sweep all sites in one phase if possible. If not,
patch the highest-traffic site first; queue the rest with
explicit phase numbers.
