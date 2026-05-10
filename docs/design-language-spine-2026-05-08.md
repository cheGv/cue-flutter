# Cue design language spine — locked 8 May 2026

Phase 4.0.8 design language work begins from this baseline.
Authored after the friend-tester signal of 8 May 2026 where 5 of 5
SLPs identified Cue's visual presentation as undercutting clinical
credibility ("looks like a prototype, not a trustable app yet").

This document is the locked spine. Implementation specifics
(per-surface refactor order, exact size/weight tables, color
token names) get authored in follow-up docs as Phase 4.0.8 ships.

---

## The synthesis

Cue's visual language is a fusion of three references, each
contributing what it does best:

- **Sonoma (macOS)** — the surface and chrome. Cream paper,
  restrained sidebar, calm at idle. The default register.
- **Logic Pro** — the typography discipline. Monospace for
  data, sans for content, tight type scale, density done right
  in clinical-work surfaces.
- **Things 3** — the warmth, deployed sparingly. Editorial
  serif moments. Italic register for family-facing copy. Never
  on a clinical-action surface.

Single-spine pick: **Sonoma surface as default**. Logic Pro
typography applied throughout. Things 3 warmth reserved for
moments that earn it.

---

## The type system

| Role | Font | Size | Weight | Letter-spacing | Used for |
|---|---|---|---|---|---|
| Eyebrow / metadata | JetBrains Mono | 10.5px | 500 | +0.14em | Dates, status pills, section headers, all data labels |
| H1 / editorial | Iowan Old Style (Georgia fallback) | 28px | 400 | -0.02em | One serif moment per screen — greeting, client name, report title |
| H2 / primary content | Inter | 14.5px | 500 | -0.011em | Names, primary clickable items, what the eye lands on first |
| Body | Inter | 13.5px | 400 | -0.005em | Descriptions, secondary content, the bulk of the interface |
| Data / mono | JetBrains Mono | 12px | 500 | tabular-nums | Times, trial counts, percentages, IDs |
| Italic / family-facing | Iowan Old Style italic (Georgia italic fallback) | 13.5px | 400 | -0.005em | Editorial closes, parent summaries, Cue Living. Never on clinical-action surfaces. |

Fonts ship via Google Fonts CDN: Inter weights 400/500/600,
JetBrains Mono weights 400/500. Iowan Old Style is system-only
on Apple devices; Georgia is the universal serif fallback.

---

## Three locked discipline rules

### Rule 1 — Monospace is the data language

Every time the SLP's eye scans something quantitative or
column-shaped (times, trial counts, percentages, dates, IDs,
status pills, file counts, session counts), it's monospace.
Sans is reserved for content the SLP reads, not scans. This
single rule does most of the "world software" work.

### Rule 2 — Serif appears at most once per screen

The serif typeface is the one warmth moment. Used once, never
twice on the same surface. Today's greeting. Chart's client
name. Report's title. Settings's "My Profile". Each surface
gets exactly one. Scarcity is what makes it feel like a real
moment instead of decoration.

### Rule 3 — Italic is family-only

Italic register lives in parent summaries, Cue Living copy
(when it ships), celebratory moments (goal mastered, milestone
reached), editorial closing notes. Never on a clinical-action
surface where the SLP is doing focused work. This discipline
is what prevents Things 3 warmth from sliding toward
"child app" territory.

---

## Surface palette (Sonoma)

| Token | Hex | Used for |
|---|---|---|
| `kCuePaper` | `#FAF7F0` | Primary background — every main surface |
| `kCueInk` | `#1B2B4B` | Primary text, active accents |
| `kCueAmber` | `#B45309` | Restrained accent — active sidebar, hover state, single CTA |
| `kCueAmberDeep` | `#854F0B` | Pending pill text, warning state |
| `kCueBorder` | `#E8E4DC` | Hairline borders on all cards and dividers |
| `kCueInkSecondary` | `#5F5E5A` | Body text, secondary content |
| `kCueInkTertiary` | `#888780` | Eyebrow labels, metadata |
| `kCueSurfaceWhite` | `#FFFFFF` | Card backgrounds (one shade lighter than paper) |

Sidebar uses `#1B2B4B` (Cue ink) as background. Active sidebar
item: `#E89441` text on `rgba(180, 83, 9, 0.18)` ground —
the only place the brand orange shows in active state.

---

## Surface implementation order (Phase 4.0.8)

The design language gets applied to surfaces in this order,
each its own commit:

1. **Today** — first surface every friend tester sees. The
   proof point. If Today reads right under the new system,
   the rest follows.
2. **Client roster** — second-most-traffic'd surface.
3. **Client chart (profile)** — most complex, biggest
   typography density challenge. Logic Pro discipline tested
   at scale here.
4. **Report screen** — the surface where AI output lives.
   Critical that it reads as professional clinical document.
5. **Session capture** — the SLP's primary writing surface.
6. **Goal authoring + Cue Reasoning panel** — the dark right
   panel needs reconciliation with the light left surface.
7. **Settings (SLP profile)** — chrome parity sweep.
8. **All remaining surfaces** — narrate, assessment, etc.

Each surface ships as its own commit. After surface 1 (Today)
ships and friend testers re-test, the locked rules above may
get refined based on signal — that's expected. The spine is
locked; the implementation refines.

---

## What stays from current Cue

This phase is amplifying what's working, not erasing Cue's
identity. These existing decisions stay:

- The "Cue" wordmark in serif (Iowan Old Style or Georgia)
- The cream paper background (`kCuePaper`)
- The eyebrow microcopy register pattern from 4.0.7.31d
- The voice register in copy ("to finish today" not "tasks: 1")
- The dark left sidebar
- The italic prose in timeline cards (already on-system)
- The Cue Reasoning right panel's dark surface — *but with
  reconciled typography that matches the spine's mono/sans
  rules*

## What goes from current Cue

- The cuttlefish illustration on Today (or moves to a
  position where it doesn't undercut clinical register)
- The current amber-button overuse — restraint applied per
  the new rule that amber appears once per primary action
- Inconsistent border-radius across surfaces (locking to
  6px for cards, 8px for medium containers, never larger
  unless explicitly editorial)
- Material green success states, slate-grey error states
  — replaced with the locked palette
- Any font that isn't Inter, JetBrains Mono, or
  Iowan/Georgia (current Cue uses Playfair Display, Syne,
  DM Sans across different surfaces — collapsing to one
  type system)

---

## Captured for later (NOT Phase 4.0.8)

- **Apple OS widgets** — macOS Notification Center widgets,
  iOS home-screen widgets. Founder noted interest 8 May 2026.
  Captured as future phase candidate (likely 4.2 or 4.3).
  Premise: glanceable Cue surfaces — today's session count,
  next session, recent attestations needed — without opening
  the app. Not specced. Not committed.

---

## Sequencing

Phase 4.0.8 begins after:
- Phase 4.0.7.40 (proxy rebuild + navigation fix) is verified
  in production. Currently shipped to GitHub at b5dd144 +
  731227e. Awaiting Netlify deploy budget reset to land in
  production.
- Friend tester re-test on the post-4.0.7.40 build to confirm
  the typed-notes flow works end-to-end and surface any new
  issues that should fold into 4.0.8 scope.

Once those two clear, Phase 4.0.8 begins with surface 1
(Today) as the proof-point commit. Estimate: 2-3 weeks of
focused work to apply the system across all 8 surfaces with
real care.

---

## Authoring note

This spine was selected on 8 May 2026 evening after a
~14-hour build day that shipped 4.0.7.36 / 36b / 36c / 39 /
40 (proxy + Flutter). The decision was made when the founder
was self-described "fresh" rather than tired. Spine locked
tonight; implementation deferred to fresh-day work. This is
the discipline of "decide when fresh, build when fresh —
never rush either."

---

# Revision 2026-05-09 (post-friend-tester signal)

After surface 1 (commit `15eceff`, since superseded) shipped
locally, friend-tester signal landed: typography read coder-y
in places, names didn't pop, single-amber-accent register felt
shouty without restraint, big numerics in Inter weight 600
read game-y / scoreboard-like. This revision incorporates the
signal as a delta on top of the original spine. Surface 1.2
(this commit) is the first implementation of the revised
spine.

The original spine above remains the lock for **roles and
stack** (Sonoma surface + Logic Pro typography + Things 3
warmth, Inter / JetBrains Mono / Iowan, surface implementation
order). This revision **adds**: olive accent, eyebrow
doctrine, numerics rule, cuttlefish placement learning,
yesterday-reminder visual lock.

## Olive accent — dual-accent semantic system

The single-amber-accent register from the original spine is
refined to **two accents**:

- **Amber `#B45309`** — urgent register. Reserved for:
  attention deadlines, primary actions, "Up next" indicators,
  the yesterday-reminder bar, the Pending Notes widget count.
- **Olive `#5C6E3B`** — calm/steady register. The default UI
  accent. Used for: sidebar active state (desaturated to
  `#B8C572` for contrast on the dark navy ground), brief-card
  left stripe, "Today's move" clinical-label, inline trial
  counts in card prose, non-urgent state pill grounds, the
  Tomorrow widget count.

Olive supporting tones:

| Token | Hex | Used for |
|---|---|---|
| `kCueOlive` | `#5C6E3B` | calm/steady accent |
| `kCueOliveSurface` | `#EDEBD8` | pill grounds, optional tint |
| `kCueOliveDeep` | `#3F4A28` | text on olive surface |

The semantic asymmetry is the point: amber is the exception,
olive is the default. Friend-tester signal: this produces a
patrician calm register that doesn't slip toward
outdoor/military.

## Eyebrow doctrine — typography rule split

Original Rule 1 ("Monospace is the data language") sharpens.
Three-way split:

- **Mono uppercase tracked = data ONLY.** Dates ("FRI · 09 MAY
  2026"), state pills ("UP NEXT"), section counts ("03"),
  trial numbers ("7/10"), timestamps ("09:00"). Built via
  `CueTypeV3.dataEyebrow()`.
- **Sans sentence-case = ALL human content labels.** Clinical
  card eyebrows ("Today's move", "Where we left off",
  "Context"), section headers ("Today's sessions", "At a
  glance"), widget titles ("This week", "Pending notes"),
  widget internal labels ("Sessions", "Documented", day names
  Mon/Tue/Wed). Built via `CueTypeV3.clinicalLabel()`,
  `widgetTitle()`, `widgetLabel()`, `sectionTitle()`.
- **Sans uppercase tracked is FORBIDDEN everywhere except
  state pills.** This is what reads as "code-language" to
  clinicians. The state-pill carve-out exists because state
  pills *are* data tags — short, status-like, scanned-not-read.
- **Iowan serif = editorial moments + big numerics** (see
  Numerics rule below).

## Numerics rule (Rule 4 — added 2026-05-09)

Big plaque-style numerics in widgets — pending count (38px),
tomorrow count (36px), pulse stats (22px), end-of-day stat
pill (12px) — render in **Iowan Old Style 400** with
`-0.025em` letter-spacing. Built via
`CueTypeV3.numericDisplay(size: …)`.

Inter weight 600 is **forbidden** for plaque-style numerics.
The Inter weight 600 register read game-y / scoreboard-like in
the friend-tester signal; Iowan numerics read like financial-
report headlines — editorial register, calm, authoritative.

Inline data numerics (trial counts "7/10", times "09:00", IDs)
remain JetBrains Mono with tabular figures via
`CueTypeV3.dataMono()`. The mono / Iowan split is by size and
context: plaque-style → Iowan; inline-with-prose → mono.

## Cuttlefish placement learning

Five anchored sizes, locked: **96 / 64 / 32 / 22 / 14**.

- 96px — end-of-day resting state, goal-achieved overlay
  (hero treatment).
- 64px — Today greeting block, in her own 80px column at the
  left margin (parallel companion, not inline with greeting
  text). New in 1.2.
- 32px — Cue Noticed widget, inline-leading.
- 22px — sidebar brand mark, Cue Study app-bar.
- 14px — chart action pill (inline brand mark).

The middle ground (24-60px) is the failure zone — explicitly
avoided. A 32-60px cuttlefish reads ambiguous: not small
enough to be a brand mark, not large enough to be a hero
companion. Commit to one register or the other.

## Yesterday-reminder visual lock

The yesterday-reminder bar at the top of Today is **urgent
register**, not paper register. Lock:

- Background: `#FBE9D2` (light amber surface).
- Border: `#E8DCB8` (amber-tinted hairline).
- Text: `kCueAmberDeep` (`#854F0B`).

Surface 1's "no amber fill, paper bg" choice is superseded by
this lock — friend-tester signal said the urgent intent didn't
read on a paper-on-paper bar. The dual-accent system applies:
yesterday's missed sessions are urgent, so the bar gets the
amber register.

## State pill register

State pills on session brief cards are **the one carve-out**
from "sans uppercase tracked forbidden." State pills are data
tags — short, status-like, mono uppercase tracked via
`CueTypeV3.dataEyebrow()`.

Pill backgrounds vary by state:

- **Up next** — amber surface (`#FBE9D2`) + amber-deep text.
  Synced with the amber left-stripe on the same card.
- **Active** — `kCueOliveSurface` ground + `kCueOliveDeep` text.
- **Baseline** — `kCuePaper` ground + `kCueInkTertiary` text
  (subtle).
- **Phase 1 / Follow-up** — reserved; map to olive ground in
  v1.2.

## Sidebar active state

Sidebar active state (`app_layout.dart`'s `_AppSidebar`)
shifts from amber (`CueColors.amber`) to olive. Dual-accent
system applied: navigation is calm-register → olive. The
saturated `kCueOlive #5C6E3B` reads muddy on the dark navy
sidebar; a desaturated lift `#B8C572` is used inline at the
single call site (sidebar-specific, not a token).

Active item: ground `rgba(92, 110, 59, 0.22)`, text `#B8C572`.

## Surface 1.2 reference

This revision is implemented for the first time in Phase
4.0.8-step-B-surface-1.2 (Today screen full refactor folding
the original surface-1 commit `15eceff`). Surfaces 2-8 retain
prior register; per-surface migration proceeds in spine-doc
order, each surface incorporating the revised spine
above.

---

# Revision 2026-05-10 (post-Roster surface 2 design)

This revision codifies typography corrections learned during
the Clients Roster (surface 2) design exploration. The
Revision 2026-05-09 doctrine holds; this revision narrows
the rules where surface 2 surfaced ambiguity.

## Inter tabular numerics for inline human-context counts

Mono uppercase tracked is for **data tags**, not data
numbers in human contexts. Inline counts that scan with
prose ("3 sessions", "21 active goals", "age 5") use
Inter weight 700 with `FontFeature.tabularFigures()` for
column-aligned scanning when stacked.

The friend-tester signal that flagged Inter weight 600 as
"game-y" applies to **plaque-style numerics on widgets**
(big standalone counts) — those still use Iowan via
`numericDisplay()`. Inline counts inside row content are
different: they're prose elements, not plaques. Inter 700
tabular at 18px reads as a confident clinical number, not
a scoreboard digit. This is the "numbers as game changers"
register — bold weight makes the count the eye-anchor of
its row, with the label trailing in lighter weight Inter.

New role: `rosterDataNum` — Inter 18 / 700 / tabular figures.
Default color `kCueInk`. The active-goals variant overrides
to `kCueOlive` so the calm accent threads through clinical
quantities the SLP reviews at a glance.

## Mono uppercase tracked — data tags only

`dataEyebrow` (JetBrains Mono 10.5 / 500 / +0.14em uppercase)
is now strictly limited to:

- State pills on **clinical-task** surfaces (Today brief
  cards: "UP NEXT", "ACTIVE", "BASELINE", "REOPENED")
- Date eyebrows ("FRI · 09 MAY 2026")
- Version strings, debug tokens, code/build identifiers
- Section counts when the count is a pure data tag
  ("03" preceding a list)

Forbidden: human-content labels, widget headers, focus
strips, recency lines, prose numerics. Those use Inter
sentence-case at the appropriate role.

## State pill register split — clinical-task vs library-browse

Surface 1.2 locked the brief-card state pills as mono
uppercase tracked (data-tag carve-out). Surface 2 introduces
a second register: **library-browse pills**.

Library-browse pills (the Roster's "Active" / "Discharged"
indicators) use **Inter 11 / 500 / sentence-case**, not mono
uppercase. The clinician scanning a roster of 50 clients is
in a browse posture, not a clinical-task posture — softer
register reduces visual noise across many rows. Mono
uppercase on every row would shout.

Rule:
- Clinical-task surface (Today, in-session screens) →
  mono uppercase pill via `dataEyebrow`.
- Library-browse surface (Roster, archive, list views) →
  Inter sentence-case pill, hand-built with the appropriate
  ground tint (`kCueOliveSurface` for active states,
  `kCueGraySurface` for discharged/archived states).

## Iowan italic — page identity moments only

`editorialItalic` (Iowan italic 13.5 / 400) was already
locked for editorial closes and parent summaries. Surface 2
adds a separate role for **page identity**:

`rosterPageTitle` — Iowan italic 44 / 500 / -0.005em. One
per screen. Carries the page's editorial register: "Your
case file." on Roster. Never used for numerics, never used
for clinical labels. Future surfaces with their own page-
identity moment add their own builder at the same scale.

Iowan **non-italic** (`rosterClientName` — Iowan 26 / 500)
is the row-level name treatment. Italic reads as voice;
non-italic reads as identity. The Roster row name is
identity (the client themselves), not voice (Cue speaking
about them).

## Recency labels — Inter sentence-case at varying weights

The Roster row's right-rail recency stack uses two roles:

- `rosterRecencyRelative` — Inter 13.5 / 600 / -0.005em.
  Default color `kCueInk`. The relative-time anchor:
  "Today", "Yesterday", "{N} days ago", "{DD MMM}".
- `rosterRecencyContext` — Inter 11.5 / 400 / -0.005em.
  Default color `kCueInkTertiary`. The trailing context:
  "last session", "enrolled".

The "Today" line gets a **single amber moment** —
`kCueAmber` color override on the relative line only — when
a session was logged today. This is the Roster's only amber
register exception per Rule 2's dual-accent system.

## Cuttlefish placement — left margin column lock

Cuttlefish placement learned on Today carries across all
primary surfaces: **64px `CueState.softWave` in an 80px
left margin column**, anchored independently of content.
The cuttlefish reads as a parallel companion, not inline
with the text.

Lock for primary surfaces:
- Today greeting block — 80px column, 64px softWave (1.2)
- Roster page header — 80px column, 64px softWave (2)
- Future Profile page header — same pattern (deferred)

The 24-60px middle ground remains forbidden. 96px softWave
is the empty-state anchor (e.g. "Your case file is empty").

## Token additions

`kCueGraySurface` — `#F1EFE8`. Quiet gray fill for
discharged pills, archived items, deactivated states.
**Distinct from `kCueBorder`** which is hairline color
only (never a fill). Lives at
`lib/theme/cue_phase4_tokens.dart`. Available to any
surface that needs a "present but recessed" register.

## Surface 2 reference

This revision is implemented for the first time in Phase
4.0.9-step-B-roster-surface-2 (full replacement of the
Phase 3.2 ClientRosterScreen). The seven new
`CueTypeV3.roster*` builders land alongside. Surfaces 3-8
incorporate this revision as they migrate per the
spine-doc order.

---

# Revision 2026-05-10 (animation layer)

This revision adds Cue's voice in motion. Three behaviors
codify Cue's posture toward the SLP: (1) the page entering
in choreographed beats so the SLP's eye lands on the
right element first, (2) hover feedback that lifts and
darkens so the SLP knows what's clickable, (3) the
cuttlefish glancing toward the hovered client so the
identity mark feels alive instead of a static logo.

## Banked principle — motion lives where it earns its keep

Motion lives where the user benefits from it, not on every
interaction. Click transitions stay default
`MaterialPageRoute`; we don't paint custom theatre on
navigation. Page entrance, hover rise, and cuttlefish
glance are the v1 motion vocabulary. Everything else stays
still on purpose.

## Page entrance choreography

Each major page section fades up + translates 12px on
first build. Stagger 80ms between sections; 350ms per
element; `Curves.easeOutCubic` (no overshoot — entrance
is calm, not bouncy).

Today sequence:
- Greeting block:                       0 ms
- Yesterday-reminder (if present):     80 ms
- "Today's sessions" eyebrow:         160 ms
- Brief cards (capped staggered):     from 240 ms
- "At a glance" section:              480 ms

Roster sequence:
- Page header:                          0 ms
- Summary plaque:                      80 ms
- Search row:                         160 ms
- Filter chips + sort:                240 ms
- List rows (capped staggered):       from 320 ms

Trigger semantics: fires once on the wrapper's first
build, not on parent setState. Wrappers sit inside
`if (!loading) ...content` so the choreography runs the
first time data is present, not during the loading
spinner.

## 12-card stagger cap

List rows beyond index 11 share the cap's delay rather
than continuing the stagger. An SLP with 30 sessions in a
day shouldn't watch each card pop in over 1800+ ms — the
bottom of the list would still be animating after she's
scrolled past it. Cap applies to:
- Today's brief card stack
  (`_buildTodayBriefStack` / `_wrapBriefCardEntrance`)
- Roster list rows (`_buildList`)

Constant: `kMotionStaggerMaxIndex = 11` in
`lib/animation/cue_motion.dart`.

## Hover rise

Cards / rows lift `kMotionHoverLiftY` (-2px) on hover. The
stripe widens, lengthens, and darkens; background tints to
`kCuePaper`; border darkens to `kCueInkTertiary`. 200ms with
mild overshoot via `kMotionHoverCurve = Cubic(0.34, 1.1,
0.64, 1.0)` — responsive without crossing into "playful."

Applied to:
- `TodayBriefCard` (lib/widgets/today_brief_card.dart)
- `ClientsRosterRow` (lib/widgets/clients_roster_row.dart)
- Yesterday-reminder rows (would benefit; deferred — the
  rows live inline in today_screen.dart and a stateless
  rewrite is more invasive than v1 needs)

Stripe color shift: `kCueOlive → kCueOliveDeep` for active
clients; `kCueAmber` stays `kCueAmber` (the urgent register
doesn't need a hover-darken; amber is already at maximum
weight). Discharged stripes (`kCueInkTertiary`) stay
unchanged on hover — those rows aren't active, so the
hover signal there is the bg tint + lift only.

## Material splash + MouseRegion lift composition

Cards that need both tap ripple AND hover transform compose
the two registers cleanly:

```
MouseRegion (handles desktop hover state)
  └─ TweenAnimationBuilder<double> (lifts via Transform)
      └─ Material (renders splash on tap)
          └─ InkWell (handles tap event)
              └─ AnimatedContainer (bg + border + stripe color)
                  └─ ... card content ...
```

The two systems are orthogonal: Material's hover splash
is a circular ripple bound to the InkWell's bounds; the
MouseRegion + Transform.translate adds a vertical lift
outside that bound. They don't conflict. This is the
canonical "cards that lift on hover and ripple on tap"
pattern.

## Cuttlefish glance — Today only

The cuttlefish in Today's greeting block tilts her body
and shifts her eyes toward the hovered card. Down-right
convention (geometric truth, not spec text):

```
        cuttlefish
        ────●────►   glanceAngle = 0     (neutral)
             ╲
              ╲─►    glanceAngle = +1.0  (max down-right)
               ╲
              hovered yesterday row / first brief card
```

Why down-right: the cuttlefish lives at the top of the page
in the greeting block; hover targets (yesterday rows + first
brief card) sit BELOW her in actual page geometry. Negative
glanceAngle is reserved for future above-cuttlefish targets
(none in v1).

Painter applies:
- Body rotation: `canvas.rotate(glance * 12° * π/180)` —
  positive = clockwise = head tilts right
- Eye offset (within the rotated head):
  - x: `+glance * 2.0`  (canvas +x = right)
  - y: `+glance * 1.5`  (canvas +y = down)

Both effects compound: head turns AND eyes look further in
that direction within the new pose.

400ms duration; `kMotionGlanceCurve = Cubic(0.34, 1.56,
0.64, 1.0)` — stronger overshoot than hover (1.56 vs 1.1)
because the glance is an expressive gesture, not a UI
feedback signal. The cuttlefish "leans in" toward the
target before settling — that's what makes her feel alive.

Glance is Today only. The Roster surface dropped its
cuttlefish in 4.0.9 amend #3; future surfaces decide
independently whether the cuttlefish belongs (and only
those that include her get the glance behavior).

Calibrated angles in `CueGlanceTargets`:
- Yesterday-reminder row: `0.85` (~10° tilt)
- First brief card (`isUpNext`): `0.60` (~7° tilt — sits
  further down the page, less head-tilt is needed because
  the eye-track-down already does much of the work)
- Hover-out / no target: `0.0` (neutral)

Subsequent brief cards (i ≥ 1) do NOT trigger glance —
they sit further down the page, often below fold, and
having the cuttlefish tilt at off-screen targets would
just look broken.

## Reduced-motion (accessibility gate)

`kReduceMotion(context)` reads `MediaQuery.disableAnimations`.
Each animated widget reads it at build time and degrades:
- Entrance:  snap to final state immediately (no fade,
  no translate)
- Hover:     static color shifts only (no transform,
  duration zero)
- Glance:    `glanceAngle` forced to 0.0 in CueCuttlefish's
  build; the cuttlefish never tilts

Plumbing: `lib/animation/cue_motion.dart` exports
`kReduceMotion(BuildContext)` as the canonical gate.
Always read at build time; don't cache.

## Surface reference

Implemented for the first time in Phase 4.2. Three new
files: `lib/animation/cue_motion.dart` (tokens + helper),
`lib/widgets/cue_animated_entrance.dart` (entrance
wrapper), `lib/widgets/cue_glance_target.dart` (glance
target wrapper). Five files modified:
`cue_cuttlefish.dart` (+glanceAngle param + 9 _drawEyes
call sites + painter rotate + shouldRepaint),
`today_screen.dart` (entrance + glance threading),
`client_roster_screen.dart` (entrance), `today_brief_card.dart`
(StatelessWidget → StatefulWidget + MouseRegion + hover
state), `clients_roster_row.dart` (hover lift + stripe
color augment, duration alignment).
