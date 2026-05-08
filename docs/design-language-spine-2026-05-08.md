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
