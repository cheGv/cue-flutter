# Skill: design-system
> **Flutter repo.** Visual language for `C:\projects\cue`. The governing principle: **information density under cognitive load is the north star, not aesthetic flourish.** "Apple-clinical minimal."
## When to use
Triggered by typography, color, component styling, focus/hover states, the goal ladder, the cuttlefish, brand/logo work, or any "make it look nicer" request.
## CRITICAL: Typography and palette are governed by the spine doc, not this skill
> **The source of truth for all typography and palette decisions is `docs/design-language-spine-2026-05-08.md`** — the original lock plus its appended revisions (2026-05-09 post-friend-tester, 2026-05-10 post-Roster + animation layer, 2026-05-11 Ask Cue panel). **Read the spine before any visual work.**
This skill deliberately does **NOT** enumerate font families, sizes, or hex values, because the spine has revised them more than once and an inline copy here would go stale and lie. The doctrine document contains *historical* font/palette bullets (an earlier Playfair/Syne/DM Sans system, and a later Inter/JetBrains Mono/Iowan spine) that are in tension precisely because they were written at different phases. **Do not resolve that tension from memory — read the spine doc; it is current.**
Hard rule: **do not introduce new hex values, font sizes, design tokens, or surface treatments without explicit founder approval.** When a needed value isn't in the spine or the token file, that's a redesign decision to surface — not an inline improvisation.
## What this skill DOES lock (stable, not in the spine's churn)
### The cuttlefish — Cue's ambient brand creature (in production)
The cuttlefish is the small living mark *inside* Cue. It is **not the logo** (see below). It is shipping across primary surfaces and its placement is locked:
- **64px `CueState.softWave` in an 80px left-margin column** — carried across Today, Roster, and future Profile.
- **Sidebar:** ambient brand mark, idle only, static.
- **The Hold** (CueTopBand top-right pill): the state surface for Cue's working state. Idle ↔ Whisper shipped; Thinking/Listening/Done are expansion work. **Suppress all animation in this widget when `isClinicalWorkInFlight = true`.**
- Known deferred polish: below ~120px render size, absolute stroke widths thin out — a stroke-width scale function in `_CuttlefishPainter` is parked (`lib/widgets/cue_cuttlefish.dart`). Touch only the stroke helpers; keep SVG path data unchanged.
### The logo itself is NOT locked
The wordmark / logo mark is a separate, open decision from the cuttlefish creature. **Do not produce a "final" logo mark.** Logo decisions are made by Guru visually, from side-by-side specimens only — never from description. Forbidden in any mark: puzzle pieces, ribbons, triumph imagery, anything contradicting the neurodiversity-affirming stance. The brand does not perform "fixing" the child.
### Card grammar (stable patterns)
- **Flat rows with hairline dividers** for lists (Clients roster). No boxed cards, no left accent stripes, no shadows.
- **Warm-surface cards** for chart pillars (Active Steps, Next Session, Last Session). No shadows.
- **The Cue card** (italic editorial prose, "Cue · what's in the chart") is a unique surface — its italic register and amber mark are reserved; do not generalize them to other cards.
- **Hero block:** one italic line, then a gap, then content. One italic line per landing screen, no subtitle stack.
- **Search row:** full-width input with ⌘K hint + a ghost-square `+` button at the end. No bright filled primary buttons.
- **Right column in list rows:** fixed `SizedBox(width: 100)`, not `spaceBetween` — anchors pill+date close to the prose line.
### Domain rendering in the UI (ties to language-discipline)
- List-row meta: lowercase diagnosis as stored ("stroke", "B/L vocal cord paralysis").
- Prose state line: uppercase first segment, olive, weight 500 ("STROKE", "VOI", "AAC", "MOTOR", "DYSPH").
- If diagnosis is null, **skip the "in {DOMAIN}" segment entirely** — render just "{N} active steps · last seen {date}". (Never fabricate or speculate — `language-discipline` §13.1.)
### Fixture filter
`is_fixture` boolean on `clients`. Service layer filters `is_fixture = false` only when `kReleaseMode == true`. Debug builds show fixtures with a "DEV · N FIXTURE VISIBLE" banner.
## The dual-accent meaning (stable, but defer to spine for exact hexes)
Two accents carry *meaning*, not just color: an **olive** register for the calm/steady default (sidebar active, brief-card stripe, inline counts) and an **amber** register for the urgent/attention exception (up-next, primary actions, reminders). The exact hex values and the eyebrow/numeric-register doctrine live in the spine — but the *semantic split* (olive = steady, amber = attention) is stable. Don't invert it.
## Anti-rationalizations
| Excuse | Counter |
|---|---|
| "I'll just use Playfair, the doc mentions it." | The doc's font bullets are historical and in tension. Read the spine doc; it's current. |
| "A new hex would look better here." | No new hex without founder approval. Use spine tokens or surface a redesign. |
| "Let me mock a final logo for the demo." | Logo is not locked. The cuttlefish is the creature, not the logo. Wordmark only. |
| "I'll animate the Hold while Cue is thinking." | Suppress animation in the Hold when `isClinicalWorkInFlight`. |
| "A subtle gradient would liven this up." | Clinical-minimal register. No decorative gradients. |
## Evidence of compliance
- Confirmed typography/palette decisions came from the spine doc, not memory.
- No new hex/token/font introduced without approval.
- Cuttlefish placement matches the 64px/80px-margin spec; Hold animation suppressed during clinical work.
- Null diagnosis skips the domain segment (no fabrication).
