# Phase E — Universal Ingestion Audit Findings

Findings logged as Phase E (Universal Ingestion — Cue accepts whatever format
the clinician shares) components are built and proven. Newest entries appended
at the end. Phase E extends the Cue Mirror engine documented in
[phase-c-findings.md](phase-c-findings.md); the canonical geometry, slot
identifier and renderer are shared across every entry point.

---

## 2026-05-27 — Week 1: PDF-digital ingestion (vertical slice)

**What landed.** A digital PDF (one with a selectable text layer) can now be
fed through the SAME pipeline as a .docx. New module `proxy/lib/extractPDFGeometry.js`
parses a PDF buffer into the canonical `format_geometry` shape; the
`/format-extract-v2` endpoint dispatches on file type (`isPdf ? extractPDFGeometry
: extractGeometry`) and everything downstream — media upload, persistence, slot
identification, drafting, the .docx renderer — is reused unchanged. Library:
`pdfjs-dist@4.2.67` (legacy/Node build, pinned) for glyph + vector + image
extraction; `pngjs@7.0.0` (pinned) to re-encode recovered image bitmaps to PNG.

### Finding E-1 — Visual fidelity, not byte-equivalence, is the PDF audit standard

PDF-derived geometry is **visually faithful but not byte-faithful** to
.docx-derived geometry. Coordinate drift up to **±5000 EMU (~0.5 mm)** is
expected and acceptable. This is an inherent property of PDF CTM→EMU conversion
(a PDF stores a content-transformation matrix per drawn object, not the source
application's layout integers, so reconstructing EMU anchors round-trips through
floating-point geometry). Clinical output remains visually indistinguishable.

**Future audits of the PDF path should measure visual fidelity, not
byte-equivalence to a hypothetical .docx ground truth.** Asserting exact integer
equality against the .docx pipeline's numbers is the wrong test for any
non-.docx entry point and will produce false failures. The correct gate is: does
the rendered output look the same to the clinician?

> Operational consequence: the .docx round-trip's ±10 EMU tolerance does not
> apply to a PDF source. BUT a coordinate residual is NOT automatically "E-1
> noise" — a deterministic offset (e.g. the image anchor's initial 19700 EMU
> gap) must be ROOT-CAUSED before it is accepted (see Finding E-3 + the Issue-2
> resolution in E-5). E-1 covers genuinely irreducible sub-pt residuals (font
> line-leading), not fixable extractor bugs. The leak-check and
> `render_mode=content_fill` safety boundary are UNCHANGED — visual-fidelity
> tolerance applies to geometry, never to the clinical-content safety boundary.

### Finding E-2 — Cue is building an inference engine, not a PDF parser

The central architectural trade-off of PDF ingestion is that **.docx provides
structure explicitly while PDF requires inference from glyph clustering.** A
.docx hands us paragraphs, tables, cells, runs and image anchors as labelled
OOXML. A PDF hands us a flat stream of positioned glyphs, vector paths and
images with no block/cell/paragraph model at all — that structure must be
*inferred* (lines from baseline clustering, paragraphs from gap/indent
heuristics, tables from drawn ruling lines).

**The slot identifier consumes canonical structure, not raw geometry. Therefore
inference quality determines pipeline quality.** `identifySlots.js` and
`buildReportDocxV2.js` read only the canonical block model (paragraph runs;
table grid/rows/cells); they never see fonts, anchors or any PDF-specific field.
So the canonical geometry IS the contract — and the only thing the PDF path can
get *wrong* is the inference. The parser code can be perfect and the output
still poor if the clustering misreads the layout.

**As Phase E expands to image / photo / scanned-PDF paths in later weeks, the
inference layer is what scales the architecture.** Those entry points have even
less explicit structure than a digital PDF (an image has no text layer at all —
structure plus text both come from vision-LLM inference). The investment that
compounds is the canonical-structure inference layer, shared by every entry
point, not any one format's parser. **Cue is building an inference engine, not
just a PDF parser.**

### Honest limitations carried into week 2 (to validate against the real PDF)

- **Empty spacer paragraphs are not recoverable.** A .docx may use blank
  paragraphs for vertical spacing; a PDF has no glyphs there. The PDF path
  encodes spacing as `paragraph.spacing.after` (derived from inter-line gaps)
  instead, so the PDF block count will run *lower* than the .docx's 154 — the
  ±5% block-count target is optimistic for this reason and is a soft check, not
  a gate (Part C re-runs slot identification fresh on the PDF geometry).
- **Table detection is ruling-line based.** Bordered tables reconstruct from
  drawn rules; borderless layout tables fall back to paragraphs. The stacked-
  table separation threshold (140 pt) and the 2.5 pt rule-clustering tolerance
  are first guesses to be tuned against the real Word-exported PDF at the
  mid-build gate.
- **`gridSpan` / `vMerge` are not yet inferred** (every grid cell is emitted as
  span 1). Acceptable for the week-1 test template; revisit when a real source
  needs merged cells.
- **Image bytes are best-effort.** RGBA / RGB / 1-bpp grayscale re-encode to PNG;
  other color models capture the anchor but no bytes (the renderer skips
  byte-less media). The anchor is the structural win regardless.

### Calibration pass (post-gate, 2026-05-27)

The first ingestion of the real 5-page PDF validated the architecture and
surfaced four tunables, all closed without touching the dispatch or downstream:
font warming (run `getOperatorList` before `getTextContent` so `commonObjs`
fonts resolve to real embedded names like Arial, not pdfjs's `sans-serif`
fallback); table refinement (drop single-column detections — boxed headings,
not tables; suppress the page-1 letterhead region so its lines flow back as
paragraphs; merge sub-`MIN_COL_PT` sliver columns from gutter/edge rules);
header recovery (a side-effect of suppressing the letterhead table — the three
centered/bold AIISH lines return via the normal paragraph path); and image
anchor frame normalization (below).

#### Finding E-3 — The .docx image-anchor convention (verification)

Inspecting both `extractGeometry.js` and the real `vrishin PT.docx` XML:

(a) **What the .docx extractor emits today.** `parseDrawing` reads
`wp:positionH/V > wp:posOffset` as raw EMU and **discards the `relativeFrom`
attribute entirely.** For the AIISH logo the source declares
`positionH relativeFrom="column" posOffset=5555615` and
`positionV relativeFrom="paragraph" posOffset=-172718`; the extractor stores
`{x:5555615, y:-172718}` verbatim — the frames (column / paragraph) are dropped,
never normalized.

(b) **Invariant or source-dependent?** SOURCE-DEPENDENT and unrecorded. The
stored numbers mean whatever the source's `relativeFrom` declares; another .docx
could say `page` or `margin` and the extractor would store those differently-
framed numbers identically. The .docx path has **no** canonical anchor frame.

(c) **Is the PDF `anchor − margin` normalization consistent with that?**
Consistent *for this letterhead*, by layout coincidence — not by construction:
- **H:** a single-column page's column origin **is** the left margin, so
  column-relative == margin-relative. PDF page-absolute 6470015 − left margin
  914400 = 5555615 == the .docx value. **Exact.**
- **V:** the logo is paragraph-anchored to the first (header) paragraph, whose
  top sits at the top margin, so paragraph-relative ≈ margin-relative **here**.
  Anchored to a mid-page paragraph it would diverge.

**Conclusion / debt:** neither extractor establishes a true canonical frame — the
.docx drops `relativeFrom`; the PDF normalizes to margin-relative; they align on
this document because column-origin = left-margin and the anchor paragraph =
top-margin. The principled end state (post-week-1) is for BOTH paths to resolve
anchors to one frame (page-absolute), which requires the .docx extractor to read
`relativeFrom` and resolve the referenced column/paragraph position. Logged as
.docx-path debt; not required for the week-1 slice.

> **Finding E-3 follow-up (tracked debt).** The .docx extractor's discarding of
> `relativeFrom` is pre-existing debt that Phase E surfaced. `.docx` anchor frame
> canonicalization is required before the corpus broadens beyond single-column,
> top-of-page letterhead layouts. Both paths must resolve to page-absolute
> coordinates with the source `relativeFrom` recorded. The current PDF
> normalization works by **layout coincidence, not by construction** (column
> origin = left margin, and the anchor paragraph = top margin); a multi-column
> page, or a logo anchored to a mid-page paragraph, breaks it.
> **Deadline: before the second SLP template lands in production.**
>
> This is a **system-wide** anchor-canonicalization invariant, not a one-path
> fix: the PDF path shares the same debt — neither the .docx nor the PDF
> extractor records the source `relativeFrom`, and both currently assume a
> single-column, top-of-page layout class. Canonicalization (resolve to
> page-absolute, record the source frame) must land on BOTH extractors together.

#### Finding E-4 — Missing-block classification (154 .docx vs 133 PDF)

The 21-block net deficit is **not** lost content. Decomposing the .docx's 152
top-level paragraphs (+ 2 tables = 154):

| Category | Count | In PDF? |
|---|---|---|
| (a) empty paragraph (no runs) | 34 | impossible — no glyphs |
| (b) whitespace-only paragraph | 2 | impossible — no glyphs |
| (c) content paragraph | 116 | **all 116 present** |

Content coverage = 100%: every one of the 116 content paragraphs' text was found
in the PDF extraction, so **category (c) missing = 0**. The PDF drops the 36
empty/whitespace spacer paragraphs (unrecoverable by design — encoded instead as
`paragraph.spacing.after`) and ADDS 15 net paragraphs (it splits some content
finer and surfaces content the .docx held inside table cells, since the PDF
infers different table boundaries). Net −36 + 15 = −21. **No clinical content is
lost in the PDF path.**

#### Finding E-5 — Normalize coordinate + naming conventions at the extraction boundary (was E-3)

**Rule: the PDF extractor reconciles every format-specific convention to the
.docx convention at the boundary. The canonical geometry abstraction requires
format-agnostic downstream code; format-specific conventions are translated in
the extractor, NOT propagated downstream.** Two instances:

1. **Image anchor frame.** Per E-3, `extractPDFGeometry` subtracts the page
   margin so the PDF's page-absolute anchor lands on the .docx's (column /
   paragraph ≈ margin) frame. After the Issue-2 fix below, anchor X is exact and
   anchor Y is within 5730 EMU (0.16 mm).
2. **Font family naming.** The PDF carries the PostScript family
   (`TimesNewRomanPSMT`); the .docx carries the friendly family
   (`Times New Roman`). `cleanFontFamily` strips the subset tag + PS suffixes and
   splits camelCase so both paths emit `Times New Roman` and the renderer picks
   the installed face instead of substituting.

**Issue-2 resolution — top-margin root cause (corrected, not hand-waved).** The
image anchor Y was initially 19700 EMU off — a deterministic offset, not E-1
noise. Root cause: margin inference computed each glyph's top as
`baseline − 0.8·em`, but Times New Roman's real ascent is `0.891·em`; the 0.8
guess under-counted ascent by ~1.6 pt, inflating the inferred top margin to 1472
DXA vs the true 1440. (Horizontal had no such error — a glyph's left edge
coincides with the left margin, no ascent analog — which is why anchor X was
always exact.) Fix: `extractPageGlyphs` now uses the font's own `ascent` /
`descent` from pdfjs text-style metrics. Inferred top margin 1472 → 1450 DXA;
anchor Y residual 19700 → **5730 EMU (0.16 mm)**. The 10-DXA / 0.16 mm remainder
is the sub-pt line leading between the glyph cap-top and the paragraph-box top —
irreducible without full line-box metrics, and THIS is legitimate E-1 territory.
(Snapping inferred top/left margins to the nearest 1/20″ would zero it, but a
0.16 mm heuristic isn't worth the risk; deferred unless desired.)

#### Operational — local `proxy/.env` now carries both credential sets

**The .env footgun is closed.** `proxy/.env` now has BOTH prod (unsuffixed
`SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY`) and sandbox (`_SANDBOX`-suffixed)
credentials. `resolveAuthEnvironment.js` logic is unchanged — the proxy still
routes to sandbox when the token issuer demands it. **Local scripts must
explicitly load the `_SANDBOX` vars; never default to the unsuffixed ones,
which are PRODUCTION.** A Part C store script that grabbed the unsuffixed
service key would have written client data to prod — the kind of cross-project
write the §7 chain exists to prevent.

#### Operational — jsonb key ordering in diff/comparison scripts

**Any script that reads `jsonb` from Postgres and compares nested objects must use
ORDER-INSENSITIVE key comparison.** Postgres `jsonb` reorders object keys by
length on storage (e.g. a stored `{block,row,cell}` location comes back as
`{row,cell,block}`), so an order-sensitive `JSON.stringify` comparison against a
freshly-generated object produces a FALSE-POSITIVE diff on every nested-key
location. Caught during the 8a04fd1e regression guard — it falsely reported 8
"lost" cell slots (cell locations whose keys jsonb had reordered); the fix is a
canonical key like `` `${l.block}|${l.row}|${l.cell}` ``. This would have shipped
silently without the guard step.

### Finding E-9 — Table structural equivalence deferred to a post-Part-E gate (added 2026-05-27)

**Table structural equivalence between the PDF-inferred and the .docx-explicit
table models is deferred to a post-Part-E gate. The render reveals the actual
visual impact; fixing in advance speculates without evidence.** The PDF infers
`linguistic_skills` as a 4-col header table (block 51) + a 3-col test-material
table (block 63), yielding 20 `linguistic_skills` slots vs 8a04fd1e's 8 (.docx:
a 2×2 + a 1×7). Rather than re-engineer the table inference now, Part E renders
Asha's substrate against the current inference; the side-by-side visual
divergence becomes the concrete signal that scopes the table-inference fix in a
follow-up gate.

### Finding E-10 — LLM free-text `notes` are load-bearing but not canonicalized (added 2026-05-27)

LLM free-text `notes` (e.g. `"Label prefix: …"`) are **load-bearing for render
output** (the renderer keeps the label and fills only the value for label-prefix
slots) but are **not canonicalized post-LLM**, causing render-affecting drift
across `identifySlots` runs. E-8 canonicalized `slot_id`; `notes` remain LLM
free-text. Surfaced in the 8a04fd1e re-identification: slot identity (slot_id +
label + location + static membership) was bitwise-stable across two runs, yet 3
label-prefix `notes` flickered (e.g. Receptive/Expressive Language Age cells:
`"Label prefix: …Age:"` vs `"…Age result"`). **Deferred to a post-Part-E gate:**
derive label-prefix notes deterministically from each cell's verbatim text. Does
NOT block Part E because the confirm-lock principle freezes `notes` at store time
— the stored map is never re-identified.

### Finding E-11 — Section headings must be static_text, never slots (visual audit; week-2 scope)

Surfaced in the Part E visual audit of both rendered .docx outputs: the slot
identifier labels a declared section heading's TEXT (e.g. "I. Background
Information:") as the content slot itself. When the drafter returns empty for
that slot (no per-client value), `content_fill` blanks the location and **the
entire heading vanishes** from the rendered .docx. Confirmed in **both**
e20412d1 (PDF-derived) and 8a04fd1e (.docx-derived) — the "I. Background
Information" section heading is missing from both rendered outputs. **Fix
(week 2):** the slot-identifier prompt must treat declared section headings
(Roman-numeral, numbered, lettered) as `static_text` scaffolding — reproduced
verbatim — NOT as fillable slots; the per-client VALUE beneath the heading is
the slot. Re-run `identifySlots` on both templates after the prompt fix;
expected diff is the heading blocks shifting slot → static_text. NOT implemented
here (week-2 scope).

### Finding E-12 — PDF slot fragmentation lowers drafter fill rate (visual audit; week-2 scope)

PDF-derived templates carry higher slot fragmentation (e20412d1 **119** slots vs
8a04fd1e **99**) and showed a **lower drafter fill rate on identical substrate**:
the "Identification of Effective Reinforcement" and "V. Recommendations" slots
filled in 8a04fd1e but stayed EMPTY in e20412d1. **Hypothesis:** finer-grained,
fragmented slots reduce the drafter's ability to match a client's substrate to
the right position (more positions, narrower labels → weaker matches).
**Mitigations to investigate (week 2):** (a) coarser slot grouping at the
extractor level; (b) drafter-side semantic merging of adjacent slots with
related labels; (c) richer `semantic_label` context in the drafter prompt. This
ties to E-9 (table fragmentation) — both stem from the PDF inferring finer
structure than the .docx declares. NOT implemented here (week-2 scope).

### Part E pass criteria — structural equivalence (added 2026-05-27)

Part E (render the PDF-derived template → .docx, compare against the .docx-path
output) must gate on STRUCTURE, not only text:

- **Rendered .docx tables must match the source .docx tables in row count,
  column count, and merged-cell (`gridSpan` / `vMerge`) structure — not only text
  content. Visual equivalence requires structural equivalence at the table
  level.** The Part C gate surfaced a table-structure mismatch that was only
  *labeled* ("PDF infers / .docx is explicit"), never resolved: .docx Linguistic
  skills is 2×2 vs the PDF-inferred 4×1; .docx Test material is 1×7 vs the
  PDF-inferred 3×11. A table whose cell grid differs from the source is **NOT a
  pass**, even if every character of text is present. Part E is the gate that
  must catch this.
- Page setup, fonts, image placement, and the `render_mode=content_fill`
  leak-check criteria from the Phase D PT extension carry over unchanged.

### Finding E-7 — Slot identifier must respect declared section headers (added 2026-05-27)

**The slot identifier must treat declared section headers as AUTHORITATIVE role
labels; content-based reinterpretation is permitted only when no declared header
exists or the header is genuinely ambiguous. Non-determinism in slot identity is
unacceptable for clinical templates.**

Surfaced in Part D: the PDF run relabeled the "I. Background Information:"
section as `presenting_complaint` (its bullets — "Limited speech", "Poor
socialisation" — read as complaints), where the .docx run correctly labeled it
`background_information`. This was **not** benign LLM variance: it is a prompt
weakness (the identifier weighed bullet content over the declared Roman-numeral
heading), compounded by `temperature` being unset (API default 1.0). A slot map
that drifts run-to-run would map the same client's substrate to different report
fields on different runs — a clinical-stability bug. Fixes: (1) the
`identifySlots` system prompt now states declared headings (Roman-numeral or
named) are authoritative for their section's role, reinterpretation only when the
header is absent/generic; (2) the call sets `temperature: 0`. Stability is
verified by running the identifier twice on identical geometry and confirming the
slot/static_text/repeatable_table payload is identical.

**E-7 extensions (added 2026-05-27) — two structural invariants of the
declared-header-authoritative principle**, added after the canonicalized
stability test still flipped two borderline locations:
1. **Demographic boundary.** Fields appearing BEFORE the first declared section
   heading are demographic header information — labeled with a specific
   demographic role (`client_name`, `registration_number`, `date`,
   `clinician_name`, `age_gender`, `supervisor_name`, …) or `other`, and NEVER
   with a clinical-section role (`background_information`, `presenting_complaint`,
   any `*_history`, any assessment role). (Fixes the "Language used:" line that
   one run mislabeled `background_information`.)
2. **Label-list syntactic boundary.** A colon-terminated fragment with no inline
   value, followed by entries of a different role, is a STATIC label introducing
   those entries — `static_text`, not a slot. (Fixes "Test material
   administered:" flipping slot↔static.) Both are general layout invariants, not
   template-specific. A regression guard runs them against the .docx-derived
   8a04fd1e first: no clinical→demographic relabel and no slot→static may occur
   there before the rules touch the PDF template.

**E-7 follow-up — pre-existing mislabel class (revealed 2026-05-27).** Confirmed
templates predating the E-7 declared-header rule may carry the same
`background_information` / `presenting_complaint` mislabel class the 8a04fd1e
guard run surfaced (blocks 14–16: stored `presenting_complaint`, correct
`background_information`). **Follow-up required:** run `identifySlots` against all
confirmed templates in the corpus, surface label diffs for clinician re-review,
do NOT auto-rewrite (confirmed maps are clinician-owned). Block 14–16 in 8a04fd1e
is the first known instance. **Part E note:** rendering Asha's substrate against
8a04fd1e must account for the substrate's `background_information` field landing
in slots currently labeled `presenting_complaint` in 8a04fd1e's stored map.

### Finding E-8 — Decouple slot identification from the substrate-fill join key (added 2026-05-27)

**Slot identification and the substrate-fill join key must be decoupled. The LLM
emits semantic labels only; `slot_id` is computed deterministically POST-LLM from
(semantic_label, document position). Bitwise determinism at temperature 0 is not
achievable from Anthropic models alone — stability must be engineered on top of
the LLM, not assumed from it.**

The E-7 fixes (authoritative headers + `temperature: 0`) corrected the
`background_information` mislabel but a two-run stability test still diverged:
~98% of locations (115/117) carried the same `semantic_label`, but 36 differed
only in the LLM's free-form `slot_id` (e.g. `background_complaint_1` vs
`background_bullet_1`), `static_text` swung 35↔52, and the slot count drifted
±1 — all from (a) inherent temp-0 API nondeterminism and (b) prompt latitude on
the slot-vs-static boundary. Since `slot_id` is the key the drafter uses to map a
client's substrate onto slots, drifting ids silently break fill. Fix, in
`identifySlots`:
1. **Canonicalize post-LLM** — `slot_id = ${semantic_label}_${block}[_${row}_${cell}]`,
   a pure function of (label, position); never the LLM's output.
2. **Drop empty locations** — gutter cells / spacer rows / blank columns are
   neither slot nor static_text (also enforced in the prompt).
3. **Sort into document order** — so two runs serialize identically.
After canonicalization, two runs are byte-identical except for genuinely
ambiguous semantic labels (a tiny residual resolved by Cue Mirror's one-time
clinician confirmation, which locks the map — it is never re-identified once
confirmed). The general principle for every Phase E entry point: the LLM
proposes semantics; deterministic code owns identity.

---

## Phase E Week 1 — Closed (2026-05-27)

**Architectural premise VALIDATED.** A Word-exported PDF flows end-to-end through
the existing pipeline: **PDF input → canonical geometry → slot map → drafted
.docx** with the AIISH logo, section structure, summary, and demographics
correctly rendered. The canonical geometry is the contract; the slot identifier
and renderer consumed PDF-derived geometry unchanged. PDF-digital is the first of
six Universal-Ingestion entry points.

**Validation artifacts (2026-05-27):** Asha's substrate rendered against **both**
templates — `e20412d1` (PDF-derived) and `8a04fd1e` (.docx-derived) — produced in
the sandbox Flutter app and audited side-by-side. Logo embedded, page setup /
fonts preserved, slot identity bitwise-stable.

**Findings status (E-1 … E-12):**
| # | Finding | Status |
|---|---|---|
| E-1 | Visual fidelity (not byte-equivalence) is the PDF audit standard | **Resolved** — adopted as audit rule |
| E-2 | Inference engine, not a PDF parser | **Adopted** — guiding principle |
| E-3 | .docx anchor convention verified (relativeFrom dropped) | **Resolved** + follow-up (system-wide anchor canonicalization before 2nd prod template) |
| E-4 | 154→133 block deficit = empty/whitespace spacers; 0 content lost | **Resolved** |
| E-5 | Normalize coordinate + naming frames at the extraction boundary | **Resolved** — in extractPDFGeometry |
| E-6 | Attach PDF images to a paragraph so the renderer emits them | **Resolved** — verified (logo renders) |
| E-7 | Declared section headers authoritative for role; temperature 0 | **Resolved** |
| E-8 | Decouple deterministic slot_id from LLM free-text | **Resolved** — bitwise-stable |
| E-9 | Table structural-equivalence (PDF-inferred vs .docx-explicit) | **Deferred → week 2** |
| E-10 | LLM free-text notes load-bearing but not canonicalized | **Deferred → week 2** |
| E-11 | Section headings must be static_text, not slots | **Deferred → week 2** |
| E-12 | PDF slot fragmentation lowers drafter fill rate | **Deferred → week 2** |

Resolved: E-1…E-8. Deferred to week 2: E-9, E-10, E-11, E-12. One follow-up (E-3,
system-wide anchor canonicalization) tracked for before the second prod template.

### Phase E week 1 deploy-prep — PENDING (gate logged; checks NOT run yet)

Proxy commit `8411a81` (extractPDFGeometry + identifySlots E-7/E-8 + temp 0 +
`/format-extract-v2` PDF dispatch) is **held local-only.** Pushing the proxy
triggers a Render auto-deploy on the **shared** service — making the identifySlots
changes (temperature 0, canonicalization, E-7/E-8 rules) and the PDF dispatch
**live for PRODUCTION traffic.** That is a production deployment, not week-1
closure. Before any future proxy push, three pre-deploy checks are REQUIRED (run
at the deploy gate, not now):

1. **Re-identify-on-confirmed search.** Search prod code paths for any that re-run
   `identifySlots` on already-confirmed templates (admin re-confirmation, template
   re-import, debug regenerate, etc.). If any exists, the new canonicalized
   `slot_id` scheme will diverge from stored slot_ids and break substrate fill
   **silently.**
2. **Migration surface.** Query prod for the count of `confirmed`
   `format_templates` before deploying.
3. **Existing PDF traffic.** Confirm no prod workflow currently exercises
   `/format-extract-v2` with PDF input (should be zero — PDF was rejected before).
