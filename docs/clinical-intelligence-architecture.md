# Clinical intelligence architecture

**Phase: 4.1 — speculative.** Not yet specced. Not yet built.

**Authored 7 May 2026 (late evening) during the post-4.0.7.31f
shipping discussion. Revised 8 May 2026 incorporating
substantive critique on schema-locked extraction discipline,
Layer 3 deferral, similarity attribution, and the Layer 1 /
Layer 2 dependency asymmetry.**

This document captures the thesis for how Cue becomes the
"second brain" of the clinician. It commits to nothing
implementable. It is a forcing function for future architecture
decisions to be tested against.

---

## Thesis

**Cue summarizes what's already true.**

That's the entire product positioning. The SLP wrote the notes.
The SLP attested the goals. The SLP captured the family quote.
Cue is the layer that makes everything they've already given
the system *navigable* — not the layer that invents new
clinical claims on top of it.

If Cue is the second brain of the clinician, every
architectural decision in 4.0.x has been infrastructure for
that claim to become true:

- Prose-first capture (4.0.7.28)
- The regulatory state primitive (Cue Sense, queued)
- Mastered-goal anticipation (4.0.7.40, queued)
- Family-quote field at intake (`primary_concern_verbatim`)
- LTG ladder structure
- Notes column as the SLP's narrative substrate

These are data-acquisition scaffolds. Phase 4.1 is the layer
that makes the data navigable and predictive — without
hallucination.

---

## The dangerous version (what NOT to ship)

A pretrained LLM with a clinical-sounding system prompt,
generating goal suggestions from a child's name and diagnosis.
Astrology with citations. Confident, ungrounded,
indistinguishable from clinical reasoning to a tired SLP. Every
existing "AI for SLPs" tool is some version of this.

If Cue ships this version, the second-brain claim becomes a
betrayal. **We do not ship this version.**

---

## The beautiful version: three layers

### Layer 1 — Within-child longitudinal model

For each child individually, Cue maintains a structured history:

- Every typed observation (schema-locked extraction into
  clinical concepts — vocabulary use, regulation events,
  environmental contexts, communicative function categories)
- Every regulation snapshot from Cue Sense (when it ships)
- Every mastered/active/abandoned goal
- Every parent-reported home observation

When the SLP opens the next-goal anticipation panel, the system
isn't generating from training-data averages. It's reading
*this specific child's* longitudinal pattern and surfacing what
is clinically obvious from the data the SLP has already given
Cue.

**Example:** "Vignesh has used 'more' spontaneously in 7 of the
last 12 sessions across snack and play contexts. Cue suggests
the next rung: expand to 2-word combinations during play."

The genealogy is visible. The SLP can verify against memory.
The system isn't predicting; it's summarizing what's already
true.

This is the version that earns its keep. It's not AI replacing
clinical judgment; it's clinical data made navigable. The SLP
knew Vignesh used "more" 7 times — they wrote those notes —
but they couldn't hold all 12 sessions in working memory
simultaneously. Cue can.

#### Layer 1 quality is load-bearing

Layer 1's trustworthiness is the gate to everything else. If
the SLP looks at a Layer 1 summary and finds the genealogy
incoherent — Cue claiming "more" was used 7 times when the SLP
remembers writing it 4 times — the second-brain claim collapses
on the first interaction.

That trust is also what earns the right to ever ship Layer 2.
Cohort intelligence depends on attestation discipline. If
clinicians don't trust Layer 1's within-child summaries, they
won't attest enough sessions cleanly to seed Layer 2's cohort.
Bootstrap fails. Phase 4.1 v1 is therefore an explicit Layer-1
trust-building exercise — not a launchpad for Layer 2.

The 200-child bootstrap window (see "Bootstrap honesty" below)
is the period where Layer 1 has to be *so good* that
attestation becomes habit, not an extra step. The cohort
follows from that. The cohort cannot precede that.

### Layer 2 — Cross-clinician evidence-base map

Once N clinicians attest M sessions for K children, Cue knows:

> "For non-speaking autistic children with documented gestalt
> language processing patterns, when 'more' appears
> spontaneously in 2-word combinations within snack context,
> the typical next progression observed across the cohort was
> [X]."

Not model hallucination. Empirical pattern-matching against
attested clinical decisions made by other SLPs.

#### Discipline lock — cohort attribution must surface composition, not just size

Every cross-clinician suggestion must cite the cohort it draws
from. **And cohort size is not enough.** "23 children with
similar profiles" is honest about scale but opaque about
*what made them similar*. Similarity is itself a clinical
claim that needs surfacing.

Every Layer 2 suggestion must show:

1. **Cohort size** — how many children
2. **Similarity definition** — what fields were matched
   (clinical_area, age band, regulatory profile, gestalt-vs-
   analytic flag, multilingual status, family-quote pattern,
   prior-goal sequence). The match must be inspectable.
3. **Time window** — over what period the cohort's decisions
   were attested
4. **Convergence ratio** — what fraction of the cohort
   progressed to the suggested goal vs. alternatives

Without all four, Layer 2 becomes "cohort grouped by an
opaque similarity heuristic" — same black-box problem in a
thinner disguise.

This is where Cue becomes the dataset that doesn't exist
anywhere else. **Indian SLP clinical decisions on multilingual
gestalt processors with regulatory dysregulation have never
been systematized.** That gap is the moat — but only if the
evidence is collected with attestation discipline from the
start, and surfaced with similarity discipline at the
interrogation point.

### Layer 3 — Literature-grounded reasoning surface

Pretrained model + RAG over evidence-based practice papers.

> "Per Hanen's More Than Words framework, after 'more'
> generalizes across contexts, the typical progression is..."

Useful as *context* alongside Layers 1 and 2. **Never the
primary signal.** The literature describes populations; the
child is one specific person. Layer 1 wins when they conflict.

#### Layer 3 ships LAST — not bundled with v1

Phase 4.1 v1 ships **Layer 1 only**. Layer 2 dormants until
cohort scale is real (6–12 months minimum). **Layer 3 ships
last** — only after Layer 1 has earned trust in real SLP
hands across at least 6 months of friend-tester signal.

Reasoning: Layer 3 is the highest-risk surface in the entire
architecture. RAG over EBP papers is exactly the surface that
produces hallucinated citations in every existing clinical AI
tool. It scores well in demos and corrupts in production. The
temptation to ship "literature-grounded suggestions" early
because it makes pitch decks compelling is real and corrosive.

The discipline: Layer 3 doesn't exist until Layer 1 has been
boring and trustworthy for half a year. If Layer 3 never
ships because Layer 1 keeps being the work that matters,
that's a fine outcome.

---

## Three concrete learning mechanisms

### Mechanism 1: Read what the SLP wrote

**Phase candidate: 4.1.0-clinical-concept-extraction.**

When a session note is saved, an LLM pipeline reads the prose
and extracts: linguistic targets used, contexts, communicative
functions, regulation observations, family-reported behaviors,
prompt levels, environmental factors. Stored as structured
tags on the session row.

**Discipline: schema-locked extraction with strict validation.**
The model returns structured fields against a predetermined
taxonomy. Any value not derivable from the SLP's prose gets
dropped. No free-form generation. No "the model thinks the
child also showed X" — if X isn't in the prose, X doesn't get
tagged. Validation runs on every return; rejected returns
don't persist.

The SLP types prose; Cue indexes prose. Neither side does
extra work. *Same data, queryable shape.*

This is not "AI generating clinical insights." This is
structured search applied to the SLP's own writing. The model
is a parser, not an author.

### Mechanism 2: Remember what worked

**Phase candidate: 4.1.1-mastery-trajectory-capture.**

When a goal hits Mastered, Cue captures: how many sessions to
mastery, what the prior goal was, what the SLP's prose
patterns were across the journey, what changed in the last 3
sessions before mastery.

This becomes the within-child evidence base. **Not "the AI
predicted mastery"; "the SLP reached mastery, and Cue
remembers the path."**

### Mechanism 3: Listen to the family

**Phase candidate: 4.1.2-family-voice-thread.**

The `primary_concern_verbatim` field at intake is the family
quote — *"he doesn't talk much when we go out."* That sentence
is gold.

Every parent message via the Cue Living layer (when it ships)
gets indexed alongside SLP observations. When the system
suggests next goals, it can check: does this goal address what
the family asked for? That's the loop nobody else closes.
Western tools treat the family as a marketing surface; Cue
treats the family as a clinical signal source.

---

## What the SLP sees at the mastered-goal anticipation moment

The suggestion is grounded in:

- Their own writing about this specific child (Layer 1)
- Patterns across attested decisions for similar children
  (Layer 2, once N is sufficient — and only with the four-
  field similarity attribution shown)
- Evidence-based practice frameworks (Layer 3, light context,
  shipping last)
- What the family asked for (intake quote + Cue Living
  messages)

Each layer is interrogable. The SLP can ask "Why this
suggestion?" and get a real answer:

> "Because Vignesh used 'more' spontaneously in 7 of 12
> sessions, mother reported 3 home occurrences, your last note
> flagged readiness for 2-word combinations, and the cohort of
> 23 similar children (matched on clinical_area=
> autism-developmental, age band 3–5, gestalt processor flag,
> Hindi-English bilingual; attested between Jan and Apr 2027;
> 19 of 23 progressed to this goal) typically did so within
> 4–8 sessions of where you are."

Not a black-box recommendation. **A staff meeting where the AI
has done the prep work.**

---

## What's already in place that Phase 4.1 will read from

The data substrate is significantly more 4.1-ready than the
phase number suggests. Eight schema artifacts shipped across
4.0.x have been quietly bootstrapping Layer 1's substrate
without being named as such:

| Substrate | Where it lives | Phase landed | Layer it serves |
|---|---|---|---|
| `sessions.notes` (prose substrate) | sessions table | 4.0.7.28 | Layer 1 + Mechanism 1 |
| `primary_concern_verbatim` (family seed) | clients table | 4.0.1 | Mechanism 3 |
| `goal_evidence_tags` (LTG → framework provenance) | dedicated table | pre-4.0.7 | Layer 3 attribution |
| `framework_tag` on LTGs | long_term_goals | pre-4.0.7 | Layer 3 attribution |
| `attest-goals` flip from `pending_attestation` → `active` | proxy + DB | 4.0.7.23c | Layer 2 entry gate (only attested goals count) |
| `goal_attestations.plan_snapshot` (immutable historical state) | dedicated table | pre-4.0.7 | Layer 2 cohort mining |
| `clinical_area` taxonomy (16 codes) | clients table + constants | 4.0.7.23 | Layer 2 similarity dimension |
| `sessions.population_payload` (jsonb structured fields) | sessions table | 4.0.1 | Layer 1 + Layer 2 secondary signal |

Phase 4.1 doesn't need to design data acquisition. It needs to
design the *reading layer* over data already accruing. The
storage model has been quietly correct for months.

---

## The bootstrap honesty

Layer 2 (cross-cohort evidence) doesn't exist for the first
~200 children Cue sees. You can't bootstrap a cohort with no
data. Phase 4.1 v1 ships with **Layer 1 only**. Layer 2 is
dormant scaffolding for 6–12 months. Layer 3 doesn't ship at
all in v1.

**This is fine.** Layer 1 is enormously valuable on its own.

The truthful framing for v1: *"Cue remembers everything you've
written about this child and surfaces it when you need it."*
That sentence is provable from session 1. Cohort intelligence
comes when it comes. Literature-grounded context comes after
that or never.

---

## Sequencing

Phase 4.1 begins after:

1. The 8 May audit completes
2. 4.0.7.36 ships (timeline refresh) ✅
3. 4.0.8a/b/c ships (Today screen evolution)
4. 4.0.8 design language lock completes
5. **Friend tester signal #1 lands — specifically (c)-class.**

The friend-tester gate is sharper than "completed without
confusion" or "completed 5+ sessions coherently." Those are
necessary but not sufficient. The gate is **product-
articulation signal**: the friend tester says, unprompted,
something equivalent to *"I want Cue to remember X across
sessions"* or *"I wish I could see what I wrote about this
child last month all in one place."*

That's the moment where the user articulates the second-brain
claim before Cue builds it. (a) and (b) are observational —
they prove the user can use the tool. (c) proves the user
*wants* the next layer. Phase 4.1 is built for users who pull
it, not for users who tolerate it.

Spec writing for 4.1.0 begins as a separate session, with
evidence in hand from the above. This document is the thesis,
not the spec.
