# PedLanguageAssessmentReader — adversarial review, completed

**Status: COMPLETE.** The automated run (`wf_6cab44a1-11d`) produced 10 candidate
findings from 4 finder agents, then lost all 8 verification agents to a session
limit — zero verified, zero refuted. This document is the verification, done by
hand against the code. Every verdict below cites the site I actually read.

**Outcome: 10 candidates → 7 distinct defects. All 7 CONFIRMED. None refuted.**

That none were refuted is worth stating plainly rather than presenting as a clean
sweep: the finders were pointed at a file whose failure mode is subtle, and
duplicates aside they did not manufacture noise. Three candidates were
restatements of one defect (D) and one was a duplicate of another (B).

---

## Verdicts

| # | Verdict | Defect | Site |
|---|---|---|---|
| 1 | **CONFIRMED** (critical) | A — absence without declaration | reader, coverage/anomaly block |
| 2 | **CONFIRMED** (high) | B — norm computed over all rows | reader, norm block |
| 3 | **CONFIRMED** (high) | C — post-declaration rows flagged as failed fill | reader, anomaly block |
| 4 | **CONFIRMED — duplicate of #2** | B | same |
| 5 | **CONFIRMED** (high) | D — envelope anomalies have no consumer | envelope / gate / assembler |
| 6 | **CONFIRMED — duplicate of #5** (critical) | D | same |
| 7 | **CONFIRMED** (high) | E — band + age derivation dropped | reader `read()` |
| 8 | **CONFIRMED** (medium) | F — `recorded == 0` boundary untested | reader test |
| 9 | **CONFIRMED — duplicate of #5** (high) | D, plus a second harm | same |
| 10 | **CONFIRMED** (high) | G — `observed` is a pre-selected default | capture surface, not the reader |

### A (#1) — an absence the clinician was told had failed, emitted as clean data

`PedLanguageAssessmentService.completeSection` issues **two non-transactional
PostgREST updates**: milestone rows to `absent`, then the parent stamp. I read
both. `SectionalCaptureController.complete`'s catch reverts only **in-memory**
state (`revertCompletionFill`, `_completedAt[sectionId] = null`) and issues **no
compensating DB write**. So when the second update fails, the rows stay `absent`
with no stamp, permanently — after the clinician was shown "Could not save
section completion".

Under the capture contract `absent` is only ever writable once a section is
declared done (`_tapCard` / `_tapEmerging`: `completed ? 'absent' : null`, plus
the completion fill). So **an `absent` row with no stamp is a contradiction with
exactly one cause.** The reader guards the direction that under-reports (declared
+ unmarked → anomaly) and leaves the direction that over-reports wide open: it
emits N affirmative "not yet doing this" judgements about a child, with
`anomalies: []`.

### B (#2, #4) — an unmarked row voided the ASHA caveat

Confirmed, and **already fixed** in `fafbc68`: the norm sets are now collected
inside the findings loop, after the emptiness check, so only rows that produce a
finding vote. The finders' reasoning was better than my original comment's — a
row that contributed no finding cannot make any finding's version ambiguous.

### C (#3) — a milestone she was never shown, labelled a failed write

A row seeded **after** a section was declared done (self-heal, once the dataset
gains a milestone) is unmarked in a stamped section, so it trips
`incomplete_completion_fill`. The only repair the codebase offers writes
`absent` — fabricating a judgement about a question never asked.

**Scope correction the finders missed:** the fabricating repair is driven by
`SectionalCaptureController._recomputeAnomalies`, which has the identical blind
spot and **cannot** be fixed the same way — `PedLanguageMark` carries no
`created_at`, so the controller has no way to tell the two cases apart. Fixing
the reader is the smaller half; the dangerous half needs the mark model to carry
the row's creation time.

**Residual risk in the reader-side fix:** `*_completed_at` is generated on the
CLIENT (`DateTime.now().toUtc()` inside `completeSection`) while `created_at` is
a server `now()` default. A badly skewed client clock could misorder them and
suppress a real defect. The fix therefore fails **toward** reporting: a row counts
as post-declaration only when both timestamps parse and the row is strictly
newer. A server-side stamp is the durable answer.

### D (#5, #6, #9) — the containment mechanism does not exist

`grep` across `lib/`: `AssessmentEnvelope.anomalies` and `hasAnomalies` have
**zero** consumers outside their own declaration. `evaluateDraftGate` takes
`List<SectionalCompletionAnomaly>` from the live capture controller — a different
type, from a different source, computed from in-memory rows, that cannot express
norm provenance or vocabulary at all.

Three of the reader's four anomaly kinds therefore enforce nothing. Only
`incomplete_completion_fill` is gated, and only because the controller happens to
recompute that one condition — which it cannot do when bootstrap failed.

**#9's distinct second harm, which #5 and #6 missed:** the anomaly's `detail`
string is embedded verbatim in `canonical_data` and POSTed to the drafter, which
is told that payload is its sourced material. `assessment_envelope.dart` states
"The proxy is never called and the REPORT never mentions it." Both halves of that
sentence were false.

The false doc comment was corrected in `fafbc68`. The gap itself is closed in the
fix commit — see the decision below.

### E (#7) — findings without their frame

Confirmed. `read()` takes the parent for its id and stamps only, so `band_key`,
`derived_age_months` and `age_source` never reach the envelope, while
`ClientChartState.toJson()` supplies `age` and `date_of_birth` — the child's age
at DRAFT time. Analysis in the answers below.

### F (#8) — confirmed, fixed, and proven

Already fixed in `fafbc68`. I proved the new test is load-bearing by applying the
exact mutation the finder named — `if (declared && rec > 0 && rec < exp)` — which
killed precisely the `recorded == 0` test and nothing else. Reverted; file
byte-identical after.

### G (#10) — ruled confirmed by Guru; independently verified

`ped_language_capture_surface.dart:238` and `:254` run `m.evidence ??= 'observed'`
on the marking tap; the toggle at `:601` renders `selected: m.evidence ==
'observed'`. So a milestone marked present on a parent's account persists as
clinician-observed without the toggle ever being touched, and the reader promotes
it to a typed "the clinician saw it herself" claim. This is the default trap both
sibling readers refuse by exclusion, inverted. Fixed in the surface per the
ruling: no default at all.

---

## Answers

### 1. The dropped age band — reader bug or data-model bug?

**A reader omission, enabled by an envelope gap. The data model is fine.**

Every fact needed is already on the parent row and already loaded: `band_key`,
`derived_age_months`, `age_source`. Nothing is missing from the schema, and
migration `20260725110229` went out of its way to name the derivation honestly
(`stated_years_midpoint` — "a stated age never was exact").

The risk is **unanchored findings plus a contradicting anchor**. A milestone
judgement is meaningful only against the band it was made in; the bundle instead
pairs band-2-to-3y findings with `client_meta.age` from draft time. A record
captured at 30 months and drafted eight months later invites the model to read
"absent: uses 2-word phrases" as a statement about a 3;2-year-old. Losing
`age_source` compounds it: an assumed midpoint arrives indistinguishable from an
exact DOB-derived age.

Why it is not a one-line fix, and why I did not build it: the envelope has no slot
for administration context, and `band_key` is stored as `2_to_3y` — the human
label lives in the dataset asset, which the reader deliberately does not load.
Carrying the raw key into a clinical document is not acceptable, and inventing a
humaniser duplicates the asset. **This needs a design call on where the band label
comes from.** Proposal: extend `AssessmentNormStatement` with the band key,
`derived_age_months` and `age_source`, and resolve the label at render time where
the asset is available.

### 2. `envelope.anomalies` — wire it or remove it?

**Wire it, in `AssessmentContextAssembler`.**

Removing loses real safety. The reader is the **only** report-time check once the
capture surface is closed — the controller's parallel computation is empty
whenever bootstrap failed, or whenever the draft is reached by a path that never
mounted the surface. Defect A above is detectable *only* by the reader; no
controller recomputation would find it.

The assembler is the right site, not the gate. The gate refuses **pre-tap**, which
is the good clinician-facing behaviour, but it runs on live surface state and
structurally cannot see envelope anomalies. The assembler is the one place every
draft path must pass through, and it holds the envelope. Refusing there makes it
**impossible to build `canonical_data` from a defective record** — which also
fixes #9's second harm for free, since a payload that is never built cannot carry
a defect sentence to the LLM. `_draftInMyFormat` already catches and toasts, so
the clinician sees the anomaly's own sentence, which is written to be
clinician-facing and actionable.

That leaves two layers with different jobs: the gate refuses early where it can
see the defect; the assembler refuses structurally in every case.

### 3. Real-data gate — what to create, and does a trial run count?

The sandbox holds **0** `ped_language_assessments` and **0**
`ped_language_milestones`, against 3 each for CAS and voice.

**What to create through the UI** — one client is enough:

1. A client with a **real `date_of_birth`** (or a stated age of at least 1) landing
   inside birth–5. **This is the precondition that actually blocks you:**
   `add_client_screen.dart:608` writes `'age': int.tryParse(ageText) ?? 0`, and
   `resolveAge` treats age ≤ 0 as `noAge` — so a client saved with a blank age gets
   the 0 placeholder, `resolveParent` returns `noAge`, and **no assessment row is
   ever created**. Nothing to read.
2. Open Assessing → the client → **Pediatric Language**. That alone creates the
   parent and seeds the band's rows.
3. To exercise every path the reader has: mark one milestone **present /
   Observed**; one **present / Parent-reported**; one **Emerging**; leave at least
   two unmarked; press **Done** on exactly one section (which writes `absent` to
   that section's remainder); leave the other two sections undeclared.

That single case exercises all four statuses, both provenance values, the
not-recorded third state, coverage with a real denominator, `declaredComplete`
true and false side by side, and the norm statement.

**Would a trial-run case satisfy it? Yes — with one precondition, and it is
actually the better choice.** A trial case is just a `clients` row with
`is_trial_case = true`; the capture surface reads by `client_id` and never
consults that flag, so the rows it produces are shape-identical to a real
client's. Everything the reader can be wrong about concerns row shapes, nulls,
vocabulary, stamps and denominators — none of which care whether the child is
real. The precondition is the same one above: **give the trial case a real DOB**,
because the trial-run path is exactly where the `age = 0` placeholder comes from,
and age 0 stops the surface before any row exists.

It is the better choice because the sandbox still has an outstanding real-child
document purge; this gate does not need another real child's data added to it.

What a trial case does **not** verify is that the clinical content reads sensibly.
That was never what the sibling gates verified either.

---

## Manifest test: moved, not weakened

Checked by diffing `ca5e836..fafbc68`, not by recollection.

- `protocol_manifest_test.dart`: assertions **30 → 33**. The only removal is
  `ped-language` from the capture-only list — replaced by a new test asserting
  `isDraftable, isTrue` and that the binding points at the real reader class. The
  coverage changed sides; it did not vanish. `expect(advertised, supported)` is
  still exact set equality, and `supported` is still built from reader classes
  that must compile for the test to build.
- Strictly **added**: the assembler-dispatch invariant, which the group was
  already named for and had never actually asserted.
- `draft_gate_test.dart`: assertions **33 → 38**, with **zero** `expect` lines
  removed (verified by sorted diff). The readerless exemplar moved from
  `pediatric-language` to `pediatric-dysarthria` and gained a guard test that
  fails loudly if that one ever gains a reader — so the exemplar cannot rot into a
  vacuous assertion the way the old one silently would have.

---

## Disposition

**Fixed in the following commit:** G (the ordered fix), D (the ordered decision),
A, and the reader half of C.

**Not fixed, reported for decision:**

- **E** — needs the band-label design call above.
- **The controller half of C** — needs `PedLanguageMark` to carry `created_at`.
  This is the half that drives the fabricating repair, and it is the more
  dangerous half.
- **The non-transactional `completeSection`** — the root cause of A. The reader
  now detects the wreckage; it does not prevent it. An RPC performing both writes
  in one transaction would.

**Still open: the real-data gate.** Nothing in this review was verified against a
real captured ped-language record, because none exists.
