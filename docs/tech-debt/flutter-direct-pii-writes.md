# Tech Debt — Flutter-Direct PII/PHI Writes

**Filed:** 2026-05-13
**Source:** grep audit of `lib/**/*.dart` for `supabase.from(...)` write paths
**Companion:** `docs/settings-architecture.md` (the RPC pattern that resolves this debt)

---

## Why this exists

The Cue Settings module v0.3 brief assumes PII writes route through a server-side path that holds the encryption key. Reality: most clinical writes go **directly from Flutter Web to Supabase**, with no server-side mediation. Flutter Web ships to the user's browser, so any key it could hold is trivially extracted from devtools.

The Settings module ships under a new pattern — `SECURITY DEFINER` RPCs — documented in `docs/settings-architecture.md`. **This file lists every existing direct-write call site** that will eventually need to migrate to the same pattern. The audit is grep-level (call-site identification), not field-level (which columns are touched). Per-call-site field-level review is required before each RPC migration.

This is not blocking Settings ship. It is the backlog for the larger refactor.

---

## Classification

- **PII-grade (Settings v0.3 scope)** — must use RPC pattern when Settings ships. These tables are within the v0.3 brief and the new SECURITY DEFINER pattern applies to them by default.
- **PHI-grade (separate refactor)** — client/clinical data, DPDP-stringent, currently direct-write. Eventually needs the same RPC pattern but not blocking Settings.
- **Operational** — non-PII non-PHI (rare in this codebase; nearly everything Cue stores is one or the other).

---

## PII-grade — Settings v0.3 scope

These call sites either touch tables the v0.3 brief renames/migrates, or write fields that become PII-flagged once Settings schema lands. They are the primary migration target.

| Call site | Table | Notes |
|---|---|---|
| [`lib/screens/slp_profile_screen.dart:93`](../../lib/screens/slp_profile_screen.dart) | `slp_profiles` (read) | Read path — not blocking, but should migrate to a paired read RPC if PII fields are added. |
| [`lib/screens/slp_profile_screen.dart:153`](../../lib/screens/slp_profile_screen.dart) | `slp_profiles` (`.upsert`) | **High priority.** Currently writes SLP profile. Once Settings v0.3 Identity Block 2 lands, this `.upsert` would write `legal_first_name`, `legal_middle_name`, `legal_last_name` — all PII-flagged. Must move to `update_slp_legal_identity` RPC before those fields are added to the table. |
| [`lib/screens/goal_authoring_screen.dart:1925`](../../lib/screens/goal_authoring_screen.dart) | `slp_profiles` (read) | Read of SLP context for goal authoring. Should migrate to a read RPC if it pulls PII columns. |
| [`lib/screens/narrate_session_screen.dart:262`](../../lib/screens/narrate_session_screen.dart) | `slp_profiles` (read) | Read in narration flow. Same. |
| [`lib/screens/report_screen.dart:162`](../../lib/screens/report_screen.dart) | `slp_profiles` (read) | Read for report rendering — likely needs `legal_*` + RCI for signed PDFs. Becomes a forensic-read path through the RPC pattern. |
| [`lib/screens/settings_screen.dart:76`](../../lib/screens/settings_screen.dart) | `clinic_profile` (`.upsert`) | **Pre-existing Settings predecessor.** Likely overlapping with the new `slp_practice_setup` table. Migration question: is `clinic_profile` retired in favour of `slp_practice_setup`, or does it persist? Either way, any writes that touch clinic logo, phone, or address (potential PII) need RPC mediation. |

### Action

Before the Settings v0.3 schema migration touches `slp_profiles`, the writes from `slp_profile_screen.dart:153` and any other `.upsert('slp_profiles')` call must be rewritten to call the appropriate `update_slp_*` RPC. Otherwise the brief's "all PII writes mediated by RPC" guarantee is immediately violated by existing code.

---

## PHI-grade — separate refactor

Client and session data. DPDP-stringent. Currently direct-write. Migration to RPC pattern is a separate, larger task — out of Settings scope but tracked here.

| Call site | Table | Operation | What's at stake |
|---|---|---|---|
| `lib/main.dart:119, 173, 229, 242, 306, 321` | `clients`, `sessions` | various reads/writes | bootstrap routing |
| `lib/screens/add_client_screen.dart:633` | `clients` | `.update(data)` | full client demographics — DOB, parent names, addresses |
| `lib/screens/add_client_screen.dart:639` | `clients` | (read after write) | — |
| `lib/screens/add_client_screen.dart:671` | `case_history_entries` | `.insert(...)` | medical history — heavy PHI |
| `lib/screens/assessing_screen.dart:58` | `clients` | read | — |
| `lib/screens/assessment_case_screen.dart:119` | `assessment_visits` | `.insert(...)` | clinical assessment data |
| `lib/screens/assessment_case_screen.dart:144, 184` | `clients` | `.update(...)` | PHI |
| `lib/screens/assessment_case_screen.dart:206` | `assessment_reports` | `.insert(...)` | assessment report content |
| `lib/screens/client_profile_screen.dart:170, 216, 346, 686, 917` | `clients`, `sessions`, `short_term_goals` | various | PHI by association |
| `lib/screens/debrief_fluency_screen.dart:127, 138, 234, 252` | `sessions`, `assessment_entries` | various | clinical observations |
| `lib/screens/goal_authoring_screen.dart:147, 164` | `clients` | various | PHI |
| `lib/screens/live_entry_fluency_screen.dart:201, 213, 221` | `sessions`, `assessment_entries` | inserts | clinical entries |
| `lib/screens/narrate_session_screen.dart:167, 648, 662` | `sessions` | various | session content |
| `lib/screens/narrator_screen.dart:241` | `sessions` | `.insert(...)` | session creation |
| `lib/screens/new_assessment_case_screen.dart:154` | `clients` | (read/write) | — |
| `lib/screens/parent_interview_fluency_screen.dart:150, 259` | `sessions`, `assessment_entries` | various | parent-interview content |
| `lib/screens/report_screen.dart:457, 746, 769, 901` | `sessions` | `.update(...)` × 3 + read | report state |
| `lib/screens/session_capture_screen.dart:288, 396, 445, 465, 474, 532, 546, 553` | `sessions`, `clients` | various | session capture flow |
| `lib/screens/session_note_screen.dart:59, 75, 248` | `clients`, `sessions` | read + insert | session note |
| `lib/screens/today_screen.dart:216, 282, 325, 383, 498, 609, 623` | `clients`, `sessions`, `daily_roster` | various incl. delete | today-view writes |
| `lib/screens/add_goal_screen.dart:82` | `goals` | `.insert(...)` | goal creation |
| `lib/services/clients_roster_service.dart:30, 47` | `clients`, `sessions` | reads | — |
| `lib/services/chart_context.dart:38` | `sessions` | read | — |
| `lib/services/today_widgets_service.dart:123, 181, 336` | `sessions` | reads | — |
| `lib/services/session_archive_service.dart:68` | `sessions` | `.update(...)` | session archive |
| `lib/widgets/pre_session_brief.dart:82` | `sessions` | read | — |

### Action

Not blocking Settings. Schedule a dedicated refactor pass once Settings ships and the RPC pattern is validated end-to-end. The migration is mechanical (each direct write becomes an RPC call) but touches ~20 files.

---

## Operational — no migration needed

None identified. Nearly every Supabase write in the current codebase touches either SLP identity (PII) or client/clinical state (PHI). Toggle-and-enum-only operational writes will appear once Settings ships (notification preferences, AI preferences, etc.) and those can stay direct.

---

## Open question

`clinic_profile` (settings_screen.dart:76) overlaps semantically with the new `slp_practice_setup` table (v0.3 brief §5A). Decide before Settings migration:

- Retire `clinic_profile`, migrate data into `slp_practice_setup`, delete the old table.
- Keep both, with `slp_practice_setup` as the canonical Settings home and `clinic_profile` as legacy.
- Rename `clinic_profile` → `slp_practice_setup` in-place if the column shape is close enough.

Recommend option 1 (clean cut) but needs Guru's call.
