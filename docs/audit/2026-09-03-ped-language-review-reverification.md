# PedLanguageAssessmentReader — independent re-verification (resumed run)

**Date:** 2026-09-03. **Verifier:** resumed adversarial-review session, by hand
against the code at `d999b33`.

## Why this document exists

The prior record (`2026-08-02-ped-language-reader-review.md`, committed
`db499c5`) declares itself COMPLETE — "10 candidates → 7 distinct defects, all
CONFIRMED." But that verification was itself never independently checked: the
automated run (`wf_6cab44a1-11d`) lost all 8 verifier agents to a session limit
(zero verified, zero refuted), and the "done by hand" pass that followed was
written and committed in the same interrupted stretch that also committed the
fixes (`d999b33`). So the confident doc is a *candidate artifact*, not a
verified one. This pass re-derives every verdict from the code, treating all 10
as unexamined — including the ones already acted on.

**Outcome: all 7 distinct defects RECONFIRMED, none refuted — same conclusion
as the prior doc, reached independently.** Three material corrections to its
*narrative* follow the table.

## Verdicts — each cites the site I actually read

| # | Verdict | Defect | Verified at |
|---|---|---|---|
| 1 | **CONFIRMED** (critical) | A — orphaned `absent` rows emitted as clean data | root cause `ped_language_assessment_service.dart:379–400`; controller revert `sectional_capture.dart:586–600`; reader detection `ped_language_assessment_reader.dart:256–283` |
| 2 | **CONFIRMED** (high) | B — norm computed over all rows | reader `:123–127, :144–148` (provenance sets gated inside the findings loop, after the emptiness `continue`) |
| 3 | **CONFIRMED** (high) | C — post-declaration row flagged as failed fill | reader half `:235–242, :419–424` (`_seededAfter`, fails toward reporting) |
| 4 | **CONFIRMED — dup of #2** | B | same |
| 5 | **CONFIRMED** (high) → **now FIXED** | D — envelope anomalies had no consumer | consumer `assessment_context_assembler.dart:101–103`, reached `format_drafter_service.dart:248` → caught `assessment_case_screen.dart:283` |
| 6 | **CONFIRMED — dup of #5** (critical) | D | same |
| 7 | **CONFIRMED** (high) | E — band + age derivation dropped | reader `read()` `:103–225` never emits `band_key`/`derived_age_months`/`age_source`; envelope has no slot |
| 8 | **CONFIRMED** (medium; fixed+tested) | F — `recorded == 0` boundary | test `ped_language_assessment_reader_test.dart:278–293` |
| 9 | **CONFIRMED — dup of #5** + 2nd harm | D — anomaly `detail` reached the drafter as sourced material | closed by the assembler refusing before building the payload; test `ped_language_reader_review_fixes_test.dart:230–242` |
| 10 | **CONFIRMED** (high) | G — `observed` pre-selected default | capture surface `ped_language_capture_surface.dart:247–273` (no default); reader promotion `ped_language_assessment_reader.dart:350–365` |

## Three corrections to the prior doc's narrative

1. **D's premise is stale — it is already wired *and reached*, not open.**
   `assembleFromEnvelope` throws `AssessmentRecordDefectException` when
   `envelope.hasAnomalies` (`assessment_context_assembler.dart:101–103`), on the
   one path every draft crosses (`FormatDrafterService` `:248`, surfaced by the
   case-screen catch `:283`). It is covered by 7 tests
   (`ped_language_reader_review_fixes_test.dart:167–278`). The genuine residual
   is **documentation**: `assessment_envelope.dart:248–253` still asserts
   "nothing consumes `AssessmentEnvelope.anomalies`," and `:284–288` attributes
   the refusal to the draft gate. Both are now false/misleading — corrected in
   the accompanying fix commit.

2. **G's test already exists.** The requested "marking present writes no
   provenance value" test is
   `ped_language_anomaly_render_test.dart:258–311` (`group('G — marking writes
   no provenance')`, both cases green). It lives in the widget file because it
   needs the capture surface; no duplicate was added. (The pure
   `ped_language_reader_review_fixes_test.dart` header lists G but pins it there
   — a cross-reference was added so the header stops over-claiming.)

3. **The 0-row sandbox premise was not re-counted live.** Both Supabase projects
   (`uuqhusmgoiaxdvtgbmwh` sandbox, `cgnjbjbargkxtcnafxaa` prod) are currently
   INACTIVE/paused, so a `count(*)` could not connect. The premise is accepted
   from the task and prior memory; the sandbox was **not** resumed (an
   unrequested state change). The actionable answer below depends only on code.

## Answers

### 1. Dropped age band vs `client_meta.age` — risk, and reader or data-model?

**A reader omission, enabled by an envelope-model gap. The database is fine.**

`ped_language_assessments` carries `band_key`, `derived_age_months`, and
`age_source` (migration `20260725094455`; `age_source` check `('dob',
'stated_years')`), and the service already loads them
(`resolveParent` `:223–231`). Migration `20260725110229` even names the
derivation honestly (`stated_years_midpoint`). Nothing is missing from the
schema. The **reader** `read()` uses the assessment row only for its id and the
three `*_completed_at` stamps and drops the rest; and **`AssessmentEnvelope` has
no slot** to carry administration context, so there is nowhere for it to go.

**Risk — unanchored findings plus a contradicting anchor.** A milestone
judgement is meaningful only against the band it was made in. The bundle pairs
band-specific findings (e.g. 2–3y) with `client_meta.age`, which
`ClientChartState.toJson` supplies as the age at **draft** time
(`client_chart_state.dart:70–75`). A record captured at 30 months and drafted
eight months later invites the model to read "absent: uses 2-word phrases" as a
statement about a 3;2-year-old — an age-appropriate non-finding reframed as
delay. Losing `age_source` compounds it: a stated-age midpoint arrives
indistinguishable from an exact DOB-derived age, so an assumption reads as
precision.

**Why not a one-line fix.** `band_key` is stored as e.g. `2_to_3y`; the human
label lives in the dataset asset the reader deliberately does not load. Carrying
the raw key into a clinical document is unacceptable; inventing a humaniser
duplicates the asset. **Needs a design call.** Proposal: extend the envelope
(on `AssessmentNormStatement`, or a new administration-context member) with
`band_key` + `derived_age_months` + `age_source`, and resolve the label at
render time where the asset is available. Reported, not built.

### 2. `envelope.anomalies` — wire it or remove it?

**Wire it — and it is already wired, in `AssessmentContextAssembler`.** Do not
remove.

Removing loses real safety. The reader is the **only** report-time defect check
once the capture surface is closed. The draft gate refuses on the controller's
`SectionalCompletionAnomaly` — a different type, computed from live in-memory
rows — which is empty whenever bootstrap failed or the draft is reached without
mounting the surface. Defect A is detectable **only** by the reader; no
controller recomputation finds it (`_recomputeAnomalies`,
`sectional_capture.dart:343–362`, has no `created_at` and no closed-record
view).

The assembler is the right site, not the gate: the gate refuses pre-tap on live
state and structurally cannot see envelope anomalies; the assembler is the one
chokepoint every draft path crosses and it holds the envelope. Refusing there
makes it impossible to build `canonical_data` from a defective record — which
also closes #9's second harm for free (a payload never built cannot carry a
defect sentence to the LLM). Two layers, different jobs: the gate refuses early
where it can; the assembler refuses structurally in every case. **Keep both.**
The only remaining task is the stale comment, fixed alongside.

### 3. Real-data gate — what to create, and does a trial run count?

Sandbox holds **0** `ped_language_assessments` / `ped_language_milestones` (per
task premise + memory; not re-counted live — sandbox paused). One client is
enough:

1. A client with a **real `date_of_birth`** (or stated age ≥ 1) inside birth–5.
   **This is the actual blocker:** `add_client_screen.dart:608` writes `'age':
   int.tryParse(ageText) ?? 0`; `resolveAge` treats age ≤ 0 as `noAge`
   (`ped_language_assessment_service.dart:182, 189–193`); so a blank/zero age →
   `resolveParent` returns `noAge` (`:245–250`) and **no assessment row is ever
   created**. Nothing to read.
2. Open Assessing → the client → **Pediatric Language**. That creates the parent
   and seeds the band's rows.
3. To exercise every reader path in one case: mark one milestone **present /
   Observed**; one **present / Parent-reported**; one **Emerging**; leave ≥2
   unmarked; press **Done** on exactly one section (writes `absent` to that
   section's remainder); leave the other two sections undeclared.

That single case exercises all four statuses, both provenance values, the
not-recorded third state, coverage with a real denominator, `declaredComplete`
true and false side by side, and the norm statement.

**A trial-run case satisfies it — with one precondition, and it is the better
choice.** A trial case is a `clients` row with `is_trial_case = true`; the
capture path reads by `client_id` and never consults that flag (`resolveParent`
selects only `date_of_birth, age` — `:234–238`), so its rows are shape-identical
to a real client's. Everything the reader can be wrong about — row shapes,
nulls, vocabulary, stamps, denominators — is flag-independent. Precondition:
**give the trial case a real DOB**, because the trial path is exactly where the
`age = 0` placeholder originates, and age 0 stops the surface before any row
exists. It is the better choice because the sandbox still has an outstanding
real-child document purge; this gate needs no new real child's data. What a
trial case does **not** verify is whether the clinical content reads sensibly —
which the sibling gates never verified either.

## Manifest test: moved, not weakened — CONFIRMED (git-verified, `ca5e836..fafbc68`)

- **Zero `expect(` lines removed** from `test/protocols/protocol_manifest_test.dart`
  or `test/protocols/draft_gate_test.dart` (removed-line grep returns nothing).
- `protocol_manifest_test.dart`: **30 → 33** expects. The only removal is the
  test *name* `four capture-only protocols` → `three remaining capture-only
  protocols` (ped-language left that list), replaced by `test('ped-language
  draws its whole binding from real references')` asserting `isDraftable, isTrue`
  plus a **new** assembler-dispatch invariant. Coverage changed sides and got
  stronger.
- `draft_gate_test.dart`: **33 → 38** expects, none removed.

## Disposition

**Fixed in the accompanying fix commit (this session):** the stale
anomaly-consumer comments in `assessment_envelope.dart`; the G cross-reference
in the review-fixes test header. Documentation only — no behaviour change; the
consumer and the G test already exist and are green.

**Reported, not fixed (unchanged from prior doc; each needs a decision or a
larger change the task did not authorise):**
- **A root cause** — the non-transactional `completeSection`
  (`ped_language_assessment_service.dart:379–400`). The reader detects the
  wreckage; only an RPC performing both writes in one transaction prevents it.
- **C controller half** — `PedLanguageMark` carries no `created_at`
  (`:80–98`), so `_recomputeAnomalies` cannot tell a post-declaration self-heal
  row from a failed fill. Needs the mark model (and its load) to carry the
  row's creation time.
- **E band label** — needs the envelope-extension + render-time-label design
  call above.

**Load-bearing tests re-run green this session:** the review-fixes, anomaly-
render (incl. G), reader, manifest, draft-gate, and assembler suites — 89/89.
