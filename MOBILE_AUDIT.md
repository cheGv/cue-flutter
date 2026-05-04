# MOBILE_AUDIT.md

Phase 4.0.7.22a — mobile-readiness audit for screens touched in this commit.
Findings only. Fixes scheduled in 4.0.7.22b through 4.0.7.22n.

Severity legend:
- **BREAKING** — feature is unusable on mobile, blocks the SLP's daily flow.
- **DEGRADED** — feature works but is awkward, slow, or visually broken.
- **COSMETIC** — visual blemish or polish gap; doesn't block usage.

Breakpoint: `_kMobileBreak = 768` ([app_layout.dart:15](lib/widgets/app_layout.dart)).
Below 768 → bottom nav + compact header. Above → desktop sidebar.
Above 1024 → full sidebar (label + icon).

---

## lib/widgets/app_layout.dart

The shared shell. Already had `_MobileBottomNav` + compact `_TopBar`
infrastructure shipped in a prior phase; this commit only bumped the
breakpoint 600 → 768.

### BREAKING
- None observed. Bottom nav routes correctly via
  `Navigator.pushAndRemoveUntil` to TodayScreen / ClientRosterScreen /
  NarratorScreen / SlpProfileScreen.

### DEGRADED
- **Cue Study FAB collides with bottom nav**: the global
  `CueStudyFab` is positioned `bottom: 72, left: 16` ([app_layout.dart:133-137](lib/widgets/app_layout.dart)).
  56-px nav + 16-px gap = 72 ✓ — clears the nav, but only by 0 px.
  On Android with display-cutout / gesture-bar adjustments this can
  overlap. Add `+ MediaQuery.of(context).padding.bottom`.
- **Per-screen FAB stack collision**: when both `floatingActionButton`
  and `cueStudyFab` are present they sit at the same `bottom: 72`
  but on opposite sides — fine for narrow screens, but on a 600-px
  viewport the labels under each can overlap visually if either
  button grows beyond ~140 px wide.

### COSMETIC
- The mobile bottom nav has hard-coded `Color(0xFF0A1A2F)` and
  `Color(0xFF1D9E75)` instead of the canonical `CueColors.sidebarDark`
  / `CueColors.amber`. Visual register matches but the tokens drift.
- Nav labels are absent from the bottom nav (icon-only). Apple HIG
  / Material 3 both recommend label + icon for nav at this density.

---

## lib/screens/today_screen.dart

The Today screen. Body replaced with the production Today's Brief
card stack in this commit; greeting block + +Add affordance + day-state
machinery (Good Night Cue, reopened pill) retained.

### BREAKING
- None observed in the brief stack flow. Brief cards render correctly
  at 320-px viewport (smallest practical phone) — tested mentally
  against the Container's full-width default.

### DEGRADED
- **Week pulse zone removed.** The "this week — N sessions /
  N documented / N goals achieved" pulse strip is gone. The methods
  are kept as `_buildWeekPulse` (annotated `// ignore: unused_element`)
  for recovery. Loses the SLP's at-a-glance week stats.
- **Legacy session brief card removed** (`_buildSessionBriefCard`).
  The pre-22a card showed "Last session: documented yesterday",
  "Start session →" CTA, and amber middle-dot links to "open last
  note" / "review goals". The new TodayBriefCard does the morning
  "what / where / today" framing but loses those direct CTAs.
  Worth restoring as a row of action chips below the brief on
  4.0.7.22c.
- **Yesterday-missed-sessions amber banner** still renders above the
  brief stack ([today_screen.dart:752-755](lib/screens/today_screen.dart)) but its
  layout pre-dates mobile-aware design — at 320 px it can wrap
  awkwardly when N > 2 missed sessions.

### COSMETIC
- The brief card's tap target is the entire card (44+ px), but the
  visual affordance for tappability is implicit. A small "→" or
  "View chart" sub-action could clarify.
- TodayBriefCard's `clientLensSubtitle` field is currently fed only
  the diagnosis string; the Variant B preview also showed a
  `gestalt processor · autism + AAC` lens. This commit doesn't
  surface clinical_lens because it's not on the existing client
  query selects. Worth a follow-up join.
- TodayBrief's `todayTimeLabel` is always passed null right now —
  daily_roster doesn't have a session_time column today. Either
  add the column or drop the field from the model.

### Tap targets / inputs
- Greeting block: read-only, no tap target. ✓
- +Add roster button (`_buildAddRosterButton`): 36×36 px — **below
  the 44-px target**. Acceptable on web but at 320 px on phone is
  thumb-fumbly. Bump to 44.
- "Good night Cue" button on the day-state footer (4.0.7.5): same
  36-px height as the +Add button. Below 44.
- Brief card tap target: full card, ~140-180 px tall × 100% wide.
  Easy to hit. ✓

### Hover-only affordances
- None on the new brief stack. The mouse-region hover lift on the
  client roster's `_AllClientsList` is on a *different* screen and
  not in scope for this audit.

### Scroll regions
- Top-level `ListView` in the open-state body — single scroll
  region, no nesting. ✓

### Font sizes
- Brief card body 13.5 px DM Sans on white — readable at 320-px
  viewport. ✓
- Eyebrow 10 px Syne — small, but per design intent (label-style,
  letter-spaced 1.6). At 320 px this is right at the bottom of
  legibility. Consider 11 px on narrow viewports.

---

## lib/widgets/today_brief_card.dart

The new production card.

### BREAKING
- None.

### DEGRADED
- **Card overflow on very long target_behaviour text.** The
  `_buildTodayBriefStack` helper passes the full
  `target_behaviour` string (no truncation) into the
  TodayBriefCard's `lastTargetBehavior` param, which the
  "TODAY'S MOVE" fallback ("Continue: <target>") can render
  unbounded. A 200-char target wraps fine but eats vertical space.
  Add a max-line / truncation to the `Text` rendering in
  `_section`.
- **No skeleton state.** While `_load()` is in flight, the brief
  stack shows nothing (the open-state ListView gates on `!_loading`,
  which lives upstream). On a slow connection this looks broken.
  Add a Cue resting cuttlefish or three skeleton cards.

### COSMETIC
- The teal-tinted "TODAY'S MOVE" border uses a flat `_tealSoft`
  color. Subtle elevation (one-pixel inner shadow) would help the
  zone read as the action target.
- Card border is `_line` (#E6DDCA, parchment-warm). On the white
  card surface this is invisible at low DPI. Bump to 0.5-px border
  with `_line` slightly darker.
- Section spacing within the card is uniform 14 px — consider
  tighter spacing (10 px) between the two non-tinted zones and
  larger space (18 px) before the teal-tinted today zone, to
  visually mark "now".

### Tap targets / inputs
- Card surface is fully tappable, full-width × 140-180 px tall.
  ✓ on all viewports.
- No nested tap targets that could conflict with the card's
  overall onTap.

### Scroll regions / overflow
- The card never scrolls internally; all content is bounded by
  `Text.overflow: TextOverflow.ellipsis` in the header and natural
  wrap in the section bodies. ✓
- The header row uses two `Flexible` children for name + subtitle;
  on a narrow viewport with a long subtitle ("Tuesday, 6 May ·
  age 12 · gestalt processor · autism + AAC"), the subtitle
  ellipses cleanly. ✓

### Font sizes
- 16 px header (DM Sans w600), 13.5 px body, 10 px Syne eyebrow.
  Readable at 320 px. ✓

---

## Recovery roadmap (next commits)

| Phase | Scope | Severity addressed |
|---|---|---|
| 4.0.7.22b | Restore week pulse strip below brief stack | DEGRADED (today_screen) |
| 4.0.7.22c | Restore "open last note" / "review goals" row chips on TodayBriefCard | DEGRADED (today_screen) |
| 4.0.7.22d | Bump +Add roster + Good Night Cue tap targets to 44 px | COSMETIC (today_screen) |
| 4.0.7.22e | Yesterday-missed-sessions amber banner mobile re-layout | DEGRADED (today_screen) |
| 4.0.7.22f | Card skeleton state + slow-connection cuttlefish | DEGRADED (today_brief_card) |
| 4.0.7.22g | Plug `clinical_lens` into TodayBrief subtitle | COSMETIC (today_brief_card) |
| 4.0.7.22h | CueStudyFab safe-area padding (bottom + cutout) | DEGRADED (app_layout) |
| 4.0.7.22i+ | ClientProfileScreen audit + fix | OUT OF SCOPE for 22a |
| 4.0.7.22j+ | LtgEditScreen audit + fix | OUT OF SCOPE for 22a |
| 4.0.7.22k+ | NarrateSessionScreen audit + fix | OUT OF SCOPE for 22a |
| 4.0.7.22l+ | Settings screen audit + fix | OUT OF SCOPE for 22a |
| 4.0.7.22m+ | GoalAuthoringScreen audit + fix | OUT OF SCOPE for 22a |
| 4.0.7.22n | Final regression sweep at 320 / 600 / 768 / 1024 / 1440 | All severities |
