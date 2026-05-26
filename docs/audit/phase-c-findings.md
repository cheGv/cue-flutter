# Phase C — Cue Mirror Audit Findings

Findings logged as Phase C (Cue Mirror, format adaptation) components are
built and proven. Newest entries appended at the end.

---

## 2026-05-25 — Proxy issuer-aware auth refactor closes two bugs

**Architectural change:** `requireAuth` middleware and inline auth in `generateGoals.js` refactored to be JWT-issuer-aware. Token's `iss` claim decoded (without signature verification) and used to route auth verification + DB client construction to the correct Supabase project (prod `cgnjbjbargkxtcnafxaa` or sandbox `uuqhusmgoiaxdvtgbmwh`).

**Reference:** Proxy commit `1c41c8f` on `C:\dev\cue\proxy`, deployed to Render with `SUPABASE_URL_SANDBOX`, `SUPABASE_ANON_KEY_SANDBOX`, `SUPABASE_SERVICE_ROLE_KEY_SANDBOX` env vars added alongside prod values.

**Bugs closed by this fix:**
- Phase C Component One format extraction blocker: "Invalid or expired token" on `/format-extract` when app pointed at sandbox.
- Saturday goal authoring bug (logged 2026-05-23): "Invalid or expired token" on `/api/generate-goals` from sandbox-authed sessions.

Both bugs were the same root cause — proxy verified all tokens against a hardcoded prod `SUPABASE_URL`. Sandbox-issued JWTs failed at GoTrue membership check. The issuer-aware refactor resolves both at the architectural layer; no per-feature patches needed.

**Status:** Closed. Prod path is byte-identical post-fix. Sandbox testing now works end-to-end.

---

## 2026-05-25 — Component One (Cue Mirror format extractor) proven against real AIISH PT format

**What was tested:** Real AIISH Pre-Therapy Report uploaded via `/settings/formats/new` upload screen. Single DOCX, ~6 pages, full AIISH institutional structure with deep sub-sub-sections.

**Extraction results:**
- 9 top-level sections identified in correct order: Header, Client Information Block, History, Assessment Information, Provisional Diagnosis, Summary, Recommendations, Goals, Signature Block.
- Sub-sections preserved with length conventions per sub-section. History sub-sections: Prenatal History, Birth History, Birth Weight, Neonatal Jaundice, Postnatal History, Developmental History (bulleted list), Family History, Educational History. Assessment Information sub-sections: 10 entries including Oro Facial Examination, Vegetative Skills, Pre-requisite Skills, Linguistic Skills (correctly typed as "table"), Informal Motor Assessment, Social/Pragmatic Skills, Behavioral Assessment, Observed Behavior and Skills, Identification of Effective Reinforcement, OT Consultation.
- 33 placeholders captured: client_name, registration_number, age, gender, supervisor_name, language_used, date_of_report, clinician_name, provisional_diagnosis, chief_complaints, prenatal_history, birth_history, birth_weight, neonatal_jaundice_details, postnatal_history, motor_milestones, speech_language_milestones, family_history, educational_history, oro_facial_examination_findings, vegetative_skills_findings, prerequisite_skills_findings, receptive_language_findings, expressive_language_findings, test_materials_administered, motor_assessment_findings, social_pragmatic_skills_findings, behavioral_assessment_findings, sensory_assessment_findings, reinforcement_strategies, ot_consultation_findings, summary_text, recommendations_list.
- Canonical primitive mapping per section (Header → static_clinician_authored; History → substrate + static_clinician_authored; Linguistic Skills sub-section → substrate; Summary → observation + clinical_reasoning; Goals → goals + next_session_intent + recommendations).
- Voice register: 14 common verbs (exhibits, demonstrates, comprehends, expresses, responds, attends, shows, engages, participates, understands, indicates, presents, appears, reveals), 10 common phrasings ("The child was brought to," "The child predominantly expresses," "Articulators appear structurally and functionally adequate," etc.), and sentence rhythm captured ("Mix of flowing clinical paragraphs for narrative sections and short bulleted statements for assessment findings; uses passive voice frequently for objective descriptions").
- Forbidden vocabulary observed and surfaced to SLP: delay, poor, decline, deficit. UI shows note "Cue will replace these with neutral language by default. You can override per-report when drafting."

**Significance:** Component One's architecture survives contact with real Indian clinical reports. Extraction quality is usable on first attempt, not just demonstrable. AIISH PT — the most structurally complex Indian SLP report format — extracts cleanly. The lexicon swap layer renders correctly to the SLP, making §language discipline visible and overrideable per report.

**Status:** Component One closed. Ready to ship to Component Two (drafter).

---

## 2026-05-25 — Cue Mirror naming locked

The format adaptation feature — Cue's flagship differentiator that absorbs the clinician's reporting labor in her own format — is named **Cue Mirror**.

**Positioning line:** "Cue Mirror — your format, your voice, given back to you."

**Reasoning:** Mirror positions Cue as infrastructure of fidelity to the clinician's identity rather than a category-derivative writing tool (which "Scribe" would have implied). Mirror captures that the SLP's voice and format survive Cue's involvement — Cue doesn't impose its own format or voice. The mild dishonesty about Cue's lexicon mediation (Cue is a mirror that *corrects* the reflection via language discipline) is acknowledged and resolved through clear messaging.

**Status:** Internal use only until Phase C closes. External announcement deferred until Component Four (PDF rendering) ships and the full upload→draft→sign→print flow works end-to-end.

---

## 2026-05-26 — Session-capture wiring restored in Phase B-revised chart (Path ALPHA-2)

Session capture wiring restored in the Phase B-revised chart via a dedicated **"Capture session"** chip. Path **ALPHA-2** (port the navigation, not the widget).

**Context:** The pre-Phase-B chart (commit `8daa323` — last to touch `client_profile_screen.dart` before the rebuild) reached new-session capture through a floating pill widget, `ChartActionBar` (`lib/widgets/chart/chart_action_bar.dart`), whose "+ Session" item called `_openAddSession` → `AddSessionScreen`. The Phase B-revised rebuild (`8fc136f`) deleted that widget and its mount, orphaning `AddSessionScreen` (no route, nothing navigating to it). Production (`78e8956`, the live gh-pages build dated 2026-05-14) still shows the floating pill.

**Change (ALPHA-2):** Rather than re-mounting the floating pill — which would clash with and duplicate the new cards-on-canvas `ChartActionChips` action surface — the navigation was ported and surfaced as a new chip:
- New first chip "Capture session" in `ChartActionChips` — `CueChartButtonStyle.primary`, always visible (not gated), placed before the contextual primary (frequency-first ordering), routing via `onChipTap('capture_session')`.
- Single primary chip (Capture session). Contextual primary demoted to secondary style — the situational Plan/Document/Author-LTG action no longer competes for primary weight; one visual primary per card, carried by the universal high-frequency action.
- New `ChartNavigation.captureSession(context, clientId, clientName)` helper pushes `AddSessionScreen` via an anonymous auth-guarded `MaterialPageRoute` — matching the existing `planSession` / `authorLtg` convention. No `main.dart` named route was added: sibling chart-action-entry screens (SessionPlanning, GoalAuthoring) have none either, and the capture entry is a transient interstitial with no deep-link state worth preserving.
- Chart handler `_onChip('capture_session')` calls the helper and `_reload()`s on return, so a newly captured session appears in the trajectory + session history.
- Two-mode entry preserved: `AddSessionScreen` still routes onward to `NarrateSessionScreen` (Narrate) or `SessionCaptureScreen` (Type).

**Verification:** `flutter analyze` clean on the three changed source files; full suite green (227 passing, +1 new chip test). Interactive click-through deferred to founder rebuild on the live sandbox — Flutter CanvasKit web is not drivable by DOM-selector preview tooling.

**Status:** Sandbox only. Not committed, not deployed. Production deploy of the chip is a separate decision.

---

## 2026-05-26 — Components Three (lite) + Four (Word export) shipped; canonical-model nullability deferred to Phase D

**Component Three (lite):** the review surface is the existing read-only `FormatDraftViewScreen` — section-by-section render with source-traceability footnotes and per-instance lexicon-override toggles (report-only, never persisted). Full inline editing is intentionally NOT built; the clinician reviews + adjusts in Cue, then finishes the document in Word.

**Component Four (Word export):**
- Proxy: `POST /format-draft-export` (commit `f72ad4b` on `C:\dev\cue\proxy`, deployed to Render) — loads the draft + template by `draft_id` (ownership-scoped even under the service-role client), renders a `.docx`, uploads to the private `format_draft_exports` bucket, records `exported_at`/`export_path`/`export_format` on the draft row, returns a 1-hour signed download URL.
- DOCX render module (`lib/buildReportDocx.js`, docx-js): A4, 1" margins, Cambria 12/14, 1.5 line spacing, header (format — client) + page-number footer. Review scaffolding (source markers, lexicon-swap UI) is stripped; stored neutral content renders as-is; bracketed `[…]` placeholders render with a **yellow highlight** that deletes with the text. Section length convention drives paragraphs vs bullets (a `table` section falls back to paragraphs).
- Flutter: `FormatDrafterService.exportDraft` (§13-clean — sends only `{draft_id, format}`) + an "Export to Word" primary button on the draft view; browser download via `launchUrl`. Two sandbox-only migrations: `format_drafts` export columns + the `format_draft_exports` private per-user bucket.

**Deferred to Phase D — canonical-model nullability sweep.** A draft generation on one client surfaced a transient `type 'Null' is not a subtype of type 'String'` during canonical-data deserialization. The Mirror models (`format_draft`, `format_template`) are defensively null-safe, but the **older canonical models** — `citation` (`finding`/`author_year`), `stg_session_metric` (`metric_label`), `short_term_goal` (date casts), `session` (`client_id`) — still use **hard non-null `as String` casts** that crash on any incomplete row. The failure was not reproducible afterward and the exact field was not pinned (diagnostic instrumentation was added, used, then removed), so **no model was hardened in this pass**. The full canonical-model defensive-nullability sweep (match the Mirror models' `as String? ?? ''` / guarded `DateTime.parse`) is a **Phase D follow-up**.

**Status:** Components One–Four feature-complete for the sandbox beta. Not deployed to production — proxy push + gh-pages deploy are a separate decision.

---

## 2026-05-27 — Phase D week one verified end-to-end

Phase D week one verified end-to-end 2026-05-27.

**Smoke test on Asha:** sentence-level rendering, inline editing, autosave + explicit save, Levenshtein-based status decision, edit-to-export sync (50-word authored sentence propagated verbatim to Word document).

**First real row in corpus** (clinician_authored, source_claims cleared, substrate_snapshot captured).

**Three week-two scope items:**
- persistent lexicon overrides per template (original scope)
- LLM-explicit per-sentence source claim attribution (replaces v1 1:1 heuristic)
- Markdown table rendering in Word export (discovered today)

**Bucket one operational gate scheduled at week five.**
