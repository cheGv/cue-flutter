# Mirror Format Understanding — Architecture Decision

**Date:** 2026-06-03
**Status:** Decided — not yet built. Plan of record for closing the Mirror
format-fidelity gaps found in Phase E.
**Companion:** `docs/audit/phase-e-findings.md` — the Inside Out / Ikansh
second-clinic recon that surfaced the gaps this note responds to.

## The goal

Cue must mirror real, varied, messy clinic reports robustly — it must not
depend on clinics handing us clean, simply-formatted files. The clinician's
format adapts to her; she never reformats to suit Cue. The engine should
understand a report the way a person looking at it would, so it generalizes to
formats it has not seen — rather than to a handful of known clinic conventions.

## The two-sided frame (don't conflate these)

Reproducing a format is two separate problems that fail for different reasons:

- **Input side** — reading a document and understanding what its marks *mean*
  (is that a table, a decorative bar, a logo, a heading?).
- **Output side** — drawing those things back into a new document (can the
  writer actually emit a colored band?).

Perfect understanding of the input is useless if the output writer can't draw
the result, and vice-versa. Diagnose and fix the two sides separately.

## The gap classes (from the Phase E Inside Out test)

**Capability gaps — finite, buildable now, no corpus needed:**

- The renderer can't draw gradients or colored bands. This is a *soft* ceiling
  of the writing library (docx-js), not a hard wall in the Word format itself —
  a *solid* band is achievable (a full-width shaded row, or the band rendered
  as an image).
- Some PDF images come back blank — an image-encoding coverage gap, fixable
  with a "rasterize the region to PNG" fallback.

**Understanding gaps — need a corpus to do well:**

- Decorative lines misread as a table, so clinical prose gets shredded into a
  phantom grid.
- Header and section conventions vary across clinics; heuristics tuned to one
  clinic mis-parse another.

## The decision

Adopt a **vision-guided understanding layer that augments — does not replace —
the deterministic geometry extractor.**

- **Vision** answers *"what does this region mean?"* (table vs decoration vs
  band vs logo vs heading). A pretrained multimodal model generalizes this to
  unseen layouts, which directly attacks the overfit root cause.
- **Geometry** answers *"what are the exact values?"* (fonts, colors,
  positions, the logo's actual pixels). Vision can't measure to the
  point/pixel; geometry can.

Three-step shape:

1. **Geometry (keep)** — precise measurement, as today.
2. **Vision pass (new)** — send the page to Claude; get back a semantic region
   map.
3. **Reconciliation (new)** — overlay vision's "meaning" onto geometry's
   "measurements," correcting misclassifications (don't treat a letterhead's
   strokes as table rules; do record a colored-band region).

Keep **both** engines: vision for meaning, geometry for measurement.

## Key de-risk

The proxy *already* calls Claude multimodally — the `/extract` route sends PDFs
and images to Claude (`server.js`, the `/extract` handler). The vision plumbing
therefore already exists: this is a **medium feature reusing existing
patterns**, not a re-architecture, and not a new vendor or model. For PDFs —
where the misclassification lives — the page can go straight to Claude with no
new image-rendering dependency.

## What vision fixes vs. doesn't

**Fixes (interpretation):** decoration-vs-table, colored-band detection,
header/convention variety, and locating the logo / signature / headings.

**Does NOT fix:**

- The **output renderer** — vision *detects* a band; the renderer still needs
  the solid-band capability to *draw* it. Separate gap.
- **Exact measurements** — that stays geometry's job.
- **The logo's actual pixels** — that's the image-encoding gap; vision locates
  a logo, it doesn't extract its bytes.

Vision also brings its **own error modes** — fuzzy region boxes, the occasional
miss or hallucinated region. This is a deliberate robustness-for-precision
trade: more general, slightly less exact.

## Validate, don't train (important)

The vision layer uses a **pretrained model via prompting — no training, no
labeled dataset.** But real reports are still needed, to **test/validate** and
to tune the prompt and the reconciliation step. The overfitting risk **moves
from rules to the prompt** — a prompt can be overfit to one report just as
easily as a rule — so corpus discipline still applies. We need roughly **5–15
varied real reports** (variety over volume) to validate that it generalizes —
not to train it.

## The honest ceiling

"Pixel-perfect reproduction of any report" is a forever-chase — the same
unsolved problem as general PDF↔Word conversion fidelity. The right, bounded,
achievable bar is **"recognizably *your* report"**: text, voice, section order,
headings, lists, tables, logo, signature, fonts, margins, plus one solid
colored band.

**Consciously do NOT chase:** true gradients (approximate them), watermarks,
infographics, magazine / multi-column layouts, scanned or photographed (OCR)
PDFs. These are rare in clinic reports and low adoption value.

## The sequence

1. **Collect 5–15 varied real clinic reports — first.** Highest leverage; costs
   outreach, not engineering; gates and validates everything below.
2. **Cheap capability wins, in parallel (no samples needed):** the
   image-rasterize fallback (which also yields logo pixels for the vision pass),
   and the solid colored-band renderer capability.
3. **Build the vision understanding layer once samples are in hand,**
   validating generality across the corpus as you go.
4. **Keep both engines** — vision for meaning, geometry for measurement.

## Current status

Nothing is built for this yet — this note is the decision and the plan. Today
the Mirror engine reliably reproduces text, voice, structure, headings, lists,
tables, logo, and signature for **.docx** input. The gaps above are tracked and
**deliberately deferred** per this plan: don't tune to one or two examples;
gather the corpus first.
