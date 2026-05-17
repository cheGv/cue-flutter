# Known Debt

Pre-existing issues identified but deliberately not fixed in the work that surfaced them. Each entry: location, what's wrong, why we're not fixing it now.

---

## MediaQuery use in `cue_reasoning_panel.dart`

- **Location:** [`lib/widgets/cue_reasoning_panel.dart:355`](../lib/widgets/cue_reasoning_panel.dart)
- **What:** `MediaQuery.of(context).size.width * 0.78` used to constrain message bubble width.
- **Violates:** `CLAUDE.md` — "Never use `MediaQuery` — always `LayoutBuilder`."
- **Found during:** 2026-05-13 framework-chip extraction scoping (task subsequently deferred).
- **Why not fix now:** the chip extraction itself was deferred. Touching the message bubble layout for an unrelated cleanup risks regressing the reasoning panel without test coverage on this surface. Fix it when the panel is next opened for substantive work, or pair with the deferred framework-chip extraction task.

---

## `chart_action_bar.dart` Row width slack at the 320 px floor

- **Location:** [`lib/widgets/chart/chart_action_bar.dart:61`](../lib/widgets/chart/chart_action_bar.dart)
- **What:** The outer `Row` (`+ Session | Reports | ⋯`) has only ~18 px of horizontal slack at Cue's 320 px supported web minimum. Row natural width ≈ 254 px (two labeled action items + two dividers + the overflow menu); plus the Container's 48 px horizontal padding ≈ 302 px Container natural. The action bar is mounted via `Positioned(left: 0, right: 0)` + `Center` in `client_profile_screen.dart`, so its max width equals the viewport. At 320 px viewport → 18 px slack, no overflow. Below 302 px viewport → `RenderFlex overflowed` fires.
- **Found during:** 2026-05-17 chart-screen visual refinement. Surfaced by a DevTools device-emulator preset narrower than 302 px — not a real user viewport (smallest supported real device is iPhone SE 1st gen at 320 CSS px; Cue's own `_kMobileBreak`/`_kDesktopBreak` floor matches this).
- **Why not fix now:** The action bar fits at every real-world target viewport. The defensive options I evaluated — `SingleChildScrollView` (hides primary clinical CTAs behind an invisible scroll), `FittedBox(scaleDown)` (shrinks touch targets below 44 px usable), `OverflowBox` (bleeds past viewport edges) — each trades the dev-tool overflow exception for a worse real-user problem. The current code is correct for every targeted device.
- **Harden when:** any of these conditions arrive — (a) i18n adds longer labels (e.g. German "Sitzung", "Bericht" — pushes Row natural past 320 px); (b) a third visible action is added; (c) label copy grows beyond "Session" / "Reports"; (d) Cue's supported floor drops below 320 px. At that point the structural fix is a width-aware fallback that collapses the labeled actions into the existing `⋯` overflow menu at narrow widths, not a wrap/scroll on the Row itself.

---

## Unguarded `auth.currentUser?.id` null at ALL insert sites

- **Pattern:** `final userId = _supabase.auth.currentUser?.id;` followed by an unguarded `'<owner-column>': userId` (or equivalent) in an INSERT payload. Same shape as the `add_client_screen.dart` bug that surfaced as the cryptic `42501 / new row violates row-level security policy` error during a real save attempt.
- **Sites known to have the pattern (non-exhaustive — found via `grep -rn currentUser?.id` and `clinician_id|user_id` insert wiring):**
    - `lib/screens/add_session_screen.dart` and `lib/screens/session_capture_screen.dart` — `sessions` table (`user_id`)
    - `lib/screens/goal_authoring_screen.dart`, `lib/screens/ltg_edit_screen.dart`, `lib/screens/add_goal_screen.dart` — `long_term_goals` / `short_term_goals` (`user_id`)
    - `lib/screens/new_assessment_case_screen.dart` and the assessment service layer — assessment + case-history tables (`clinician_id`)
    - `lib/services/ald_assessment_service.dart`, `lib/services/ped_dysarthria_assessment_service.dart` — assessment tables (`clinician_id`)
    - `lib/screens/slp_profile_screen.dart` — `slp_profiles` (`clinician_id`)
- **Two failure modes, depending on RLS state on the target table:**
    1. **RLS ON (`clients`, `long_term_goals`, `short_term_goals`):** the row is rejected at INSERT with the cryptic Postgres `42501`. The SLP sees the raw error string. Loud but inactionable.
    2. **RLS OFF (`sessions`, `slp_profiles`):** the row **lands** with `user_id: null` / `clinician_id: null`. No error. But every subsequent SELECT joins on `auth.uid() = user_id` (in app code, not via RLS), so the orphaned row is invisible to its writer the moment the auth-aware page reloads. The SLP sees their work silently vanish. **This is the more dangerous mode** — clinical data is written, accepted, then lost.
- **Found during:** 2026-05-17 RLS triage on the `add_client_screen` save path. Recon confirmed the four `clients` policies, the missing `ENABLE ROW LEVEL SECURITY` on `sessions`, and the systemic nature of the unguarded `userId` read across screens.
- **What's guarded today:** `add_client_screen.dart:584` — auth-null short-circuits before the insert with a directive SnackBar. That single site only.
- **What's still open:** every other insert site listed above. Same fix applies (null-check userId before the network call; SnackBar + return). Cheap individually, tedious in aggregate — needs a sweep, not a one-off.
- **Why not fix all sites now:** the immediate symptom was the client-add screen; widening the diff to ~10 files unrelated to the surfacing bug courts regression in surfaces that aren't currently broken (most of the sites haven't hit a null userId in observed use). A coordinated sweep — ideally paired with enabling RLS on `sessions` so the silent-write mode becomes a loud `42501` instead — is the right shape, and that's bigger than a single bug-fix turn.
- **Revisit before:** the founding-cohort launch. Silent-write loss of session/goal data to logged-out users is a clinical-trust-breaker that must not survive into real-user hands. Pair the sweep with `ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;` (and any other RLS-off tables with `user_id`/`clinician_id` columns) so the failure mode is uniformly loud + recoverable, not silent + lossy.
