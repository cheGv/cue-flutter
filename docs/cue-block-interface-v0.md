# The Cue Block Interface

*What every framework block must declare, so a detector can route to it and the engine can render it.*

**Status:** living draft, v0 — reverse-engineered from ONE block (CAS: READ-proven; CAPTURE built and sandbox-proven end-to-end — write → dirty trigger → brief — 2026-07-09; the clinician-through-the-UI tap path remains unproven pending a running app). Every field is tagged `[solid]` (confident it's universal) or `[provisional]` (a CAS assumption not yet confirmed by a second block). The provisional fields are the ones feeding/fluency will prove or break. That's the point: this spec's job is not to be right — it's to be explicit enough that the second block fails *loudly* against it, not silently.

**Lockstep rule:** this document updates in the same commit as the code that changes what it describes. The rot this prevents is already in the repo: `client_brief_phrasing.dart` still says "Cue holds no gender field" — false since `clients.gender` existed, doubly false since `clients.pronoun` landed (2026-07-05). A spec that drifts from schema becomes a liability that *sounds* authoritative. This one is either current or it is deleted.

---

## Why this document exists

Cue does not hand-build a brief per disorder. It runs a fixed **engine** (the slot-driven brief skeleton — read half built and committed for CAS, `3297b58` on intern-scaffold) fed by a swappable **block** (the disorder's validated clinical logic). A **detector** reads incoming patient data and routes it to the right block.

The detector is impossible to build until a "block" has a defined shape — otherwise it's a router with one road, classifying everything into the single block that exists. This document defines that shape. CAS is filled in as instance #1 — both halves now built. The capture surface (`CasSessionDials` in `session_capture_screen.dart`, gated `pediatric-cas` + active STG) writes `cas_session_progress` through `upsertLevels`, and the full loop is sandbox-proven end-to-end (the exact capture payload → rows → dirty trigger → assembled brief, 2026-07-09). Remaining honest caveat: no clinician has captured a dial through the running UI yet — the capture *ergonomics* are unvalidated, the capture *path* is not.

**The non-negotiable floor:** blocks are human-authored and grounded in validated sources (ASHA, and ISHA/AIISH for Indian practice). The detector *matches* incoming data to a block's signature; it NEVER invents a block, a ladder, or a clinical position. Detection, not generation. Same law as everywhere else in Cue: the system reads back what's real, or stays silent.

---

## The interface — every block declares these fields

### 1. `dials` `[solid that they exist; provisional what they are]`
The small set of things captured per session — the raw observations that accumulate as memory.
- **Universal:** every block has a small set of per-session dials. `[solid]`
- **Varies:** how many, and what type (ordinal? enum? free-text evidence line?). `[provisional]`
- **CAS:** `complexity` (which level worked), `accuracy` (accurate | partial | inaccurate), `cue_level` (independent | minimal | moderate | maximal | hand_over_hand).
- **Caveat (narrowed 2026-07-10):** the dial write path is sandbox-proven end-to-end; the dial *capture ergonomics* (a clinician tapping through the running UI) are still unvalidated.

### 2. `progression_type` `[solid that it's a variable — this is the field we built as first-class BECAUSE disorders differ here]`
How the dials organize into "where they are." **This is the field most likely to break a naive interface, so it is a variable from line one.**
- **`ladder`** — an ordered climb; higher = harder = later. Movement is "advanced a rung." (CAS: syllable complexity. Feeding: texture grades — *provisional, confirm with feeding block*.)
- **`set`** — a spread across contexts with no inherent order; progress is "carried the skill into more/harder contexts," not "climbed." (Fluency: fluency across situations — calm, structured, novel, high-pressure. Voice: good vocal behavior across pitch/loudness/contexts. Pragmatics.)
- **CAS:** `ladder`.
- **Note:** a third value (`hybrid`) may emerge — a laddered core with situational overlay. Do NOT add it speculatively; add it only if a real block needs it.

### 3. `progression_structure` `[provisional — the concrete rungs or contexts]`
The actual ordered rungs (if `ladder`) or the set of contexts (if `set`).
- **CAS (`ladder`):** CV → CVC → bisyllabic → trisyllabic → polysyllabic. The rung list is the app-side constant `kCasComplexityLevels` in `lib/constants/cas_levels.dart` — extracted from `cas_assessment_surface.dart`'s private copy when the session-dial capture surface became its second consumer (assessment seeds `cas_length_gradient`; capture writes `cas_session_progress`). Not a DB enum — `level_label`/`level_order` are free per-row, so the structure is editable per practice without a migration.
- **As-built nuance:** the brief engine never consumes this field declaratively — it infers order from `level_order` arriving in the data. A block *declaring* its structure vs. the engine *inferring* it from rows is an open seam; the declarative form becomes necessary the moment the detector needs to describe a block it hasn't seen data for.
- **Open question for `set` blocks:** what defines the context set for fluency? Situations by demand level? This is unanswerable from CAS — it's exactly what the fluency block will define.

### 4. `promotion_rule` `[solid that it exists; provisional what it is; safety-gating is solid-that-it-must-be-a-field]`
When does a position count as *held / mastered / advanced* — the rule that turns raw dials into "where they are."
- **Universal:** every block needs a rule for "did-it-once vs. does-it-reliably." `[solid]`
- **CAS:** a level promotes to floor only when accurate in the **2 most recent consecutive** sessions. Accurate-once stays frontier, flagged `breakthrough`. Reads the two MOST RECENT, so a regression (accurate→accurate→partial) does NOT promote — it can't hide a slip.
- **THE CONSECUTIVENESS AXIS** `[provisional — found in the as-built SQL, not in the first draft of this spec]`:
  - Consecutive over **what**? CAS counts consecutive *sessions*, and a level not recorded in the previous session breaks the chain (in `assemble_cas_progress_brief`, the `acc2` CTE joins latest×prev on level). Correct for CAS, where every worked level gets a dial each session.
  - For a `set` block, contexts **rotate** — nobody probes "high-pressure situation" every session. Under consecutive-over-sessions, a rotated context could *never* promote. Set blocks likely need consecutive-over-**observations-of-that-position**.
  - So the axis is: `consecutive_over: sessions | observations`. CAS: `sessions`. **FLUENCY is this axis's hardest test** — it will hit it before feeding does.
- **THE SAFETY-GATING FLAG** `[solid that this field must exist — two blocks already differ on it, and the structure already exists in code]`:
  - `safety_gated: bool` — does a hard safety signal OVERRIDE progress regardless of performance?
  - **CAS:** `false` — no safety off-ramp; progress is purely performance.
  - **Feeding:** `true` — aspiration signs (wet vocal quality, cough, distress) HALT advancement no matter how well tolerance looks. A safety-gated block's promotion rule has a veto layer a non-gated block doesn't.
  - **This is not hypothetical — the structure already shipped.** The feeding assessment surface's off-ramp binding clause (CLAUDE.md; `feeding_assessment_surface.dart`) is `safety_gated: true` in built form: trigger signals (airway signs), a veto layer (self-gating card reading the FULL row set, display filters never affect the trigger), and a can't-mount-without-it guarantee (the bare content is library-private; every public mount builds the off-ramp in unconditionally, no opt-out parameter exists). Expect this interface field to be that structure, not a bare bool.
  - **The hard law this implies for the detector:** safety binding must NEVER depend on detector routing. A misrouted feeding child must still hit the off-ramp. The veto belongs to block CONTENT, not to the router — exactly the off-ramp clause's "bound to the content that can trigger it, never left to a router's discretion," now inherited by the block architecture.
  - This flag is why blocks are NOT interchangeable, and why the interface had to exist: an engine that rendered feeding with CAS's non-gated logic could show "advancing!" on a child who is aspirating.

### 5. `breakthrough_vs_solid` `[solid — engine, universal]`
The did-it-once vs. does-it-reliably distinction. Proven not CAS-specific — every disorder has "the thing they managed once" vs. "the thing they own."
- **CAS:** `breakthrough` (accurate in newest session only) vs. `emerging` (still partial/inaccurate) vs. promoted-to-floor (2 consecutive).
- **Universal shape:** provisional-success → consistent-success. The *bar* is per-block (framework); the *distinction* is engine.

### 6. `detection_signature` `[the NEW field — the detector forces this into existence]`
**What in incoming patient data marks this as this framework.** A block must declare not just how it *works* but how it's *recognized*. This field did not exist before the detector idea — it is the artifact the intelligence layer produces.
- **CAS:** motor-speech markers (inconsistent errors on repeats, disrupted coarticulatory transitions, inappropriate stress), groping/searching behavior, DDK findings, complexity-graded error patterns, vowel errors.
- **How the detector uses it:** reads incoming history → checks against each block's signature → proposes "this looks like CAS" (or feeding, or fluency). The clinician confirms. The detector matches signatures; it never invents a diagnosis or a framework.
- **The confirm-loop is already schema, not aspiration:** `clients` carries `domain_detection_confidence`, `domain_detection_source`, `domain_detector_version`, and `is_slp_authoritative` — detector-proposes/clinician-confirms reified as columns, shipped by the domain-detection work. The block detector inherits this provenance pattern: every routing proposal records source, confidence, version, and whether the SLP has overridden it.
- **A second detection mode already exists in-code:** the SSD surface's motor-flag→CAS handoff is block-to-block *referral* — block A's captured data raising block B's signature. Distinct from cold classification of incoming data, and possibly the more common mode in practice; the interface should not assume detection only happens once, at intake.
- **`[provisional]`** how signatures are represented (keyword sets? structured markers? a small classifier per block?) — undecidable from one block. The SECOND signature (feeding's) is what makes "distinguish between two signatures" a real, testable operation.

### 7. `neuroaffirming_frame` `[solid — engine, universal, already in the widget]`
Child as subject, strength slot, support slot, fork-not-recommendation. Lives in the engine (the `ProgressBrief` widget), not per-block. Every block inherits it for free.
- Slot labels are universal ("where <name> is", "where <pronoun> is strong", "what helps <pronoun>", "where you could go next — your call"). The *values* come from the block's dials, verbatim.

### 8. `the_law` `[solid — non-negotiable, universal]`
The brief reads back exactly what was captured. Empty stays empty. No fabrication — not by invention, not by inference, not by kindness (no translating clinical values into softer words). Enforced by construction: assembly is deterministic (SQL for CAS), never generative.

### 9. `memory_slots` `[provisional — which capture fields the block feeds]`
Which of the brief's memory slots this block has capture fields for — the inventory of what *can* be written, distinct from the dials (field 1) that *must* be.
- **Why it's a block declaration:** blocks differ on which capture fields exist. CAS's `what_helps` is plausibly cues-that-unlock; feeding's is textures/positioning/pacing. `watch_for` may be central for one block and absent for another.
- **CAS today:** `what_helps` = not captured (renders empty-but-inviting); `watch_for` = not captured (null + note in the assembled jsonb, by law — the slot exists in the shape, nothing feeds it, nothing is fabricated).
- The engine renders every slot it's given and renders declared-but-empty slots as invitations; a block simply doesn't declare slots it will never feed.

---

## What CAS taught us about the split (the running ledger)

**Read this table as a conceptual ledger validated by one instance — NOT a description of code.** The split does not exist in code today: `assemble_cas_progress_brief` interleaves engine logic (sticky promotion, the window, breakthrough state) and framework values (the cue ordering, accuracy ranks, next-move vocabulary) in one SQL function's CTEs. Only the **widget** (`ProgressBrief`) is genuinely block-agnostic as built. Extracting a parameterized engine is future work — likely at block #2, when the second instance shows which seams are real.

| Field | Verdict | Notes |
|---|---|---|
| Neuroaffirming frame | **engine** | universal, in the widget |
| The no-fabrication law | **engine** | universal, non-negotiable |
| breakthrough vs. solid distinction | **engine** | every disorder has it |
| "read the 2 most recent, not any-2" recency rule | **engine** | universal; safety-critical for feeding |
| promotion-requires-consistency principle | **engine** | the *principle*; the *bar* is framework |
| consecutive-over-sessions vs. -observations | **engine** (the axis) / **framework** (the value) | CAS: sessions; set blocks likely observations |
| next_move fork SHAPE (name options, never pick, equal weight) | **engine** | in the widget; structurally can't recommend |
| next_move fork DERIVATION + vocabulary | **framework** | CAS's "fade cue / advance work" is hardcoded SQL; meaningless to a set block; feeding's fork must be able to say "hold — airway sign present," not derivable from performance dials |
| The specific dials (complexity × accuracy × cue) | **framework** | CAS-specific |
| The ladder rungs (CV→CVC→…) | **framework** | CAS-specific |
| The 2-consecutive bar | **framework** | CAS-specific |
| `safety_gated` flag | **engine** (the field) / **framework** (the value) | CAS: false; feeding: true — structure already shipped as the off-ramp clause |
| `progression_type` | **engine** (the field) / **framework** (the value) | CAS: ladder; fluency: set |
| `memory_slots` inventory | **engine** (the field) / **framework** (the declared slots) | CAS: what_helps/watch_for exist unfed |

More than half of what felt like "CAS work" is engine — inherited free by every future block. That's the ratio that makes the detector worth building: each new disorder is a *block definition filling this schema*, not a bespoke rebuild.

**Fork-derivation bug, found by the first real capture (2026-07-09, fixed 2026-07-10 — `20260710160000_fix_cas_brief_floor_null_fork.sql`).** The next_move floor-null branch fired for *every* no-floor window and hardcoded "no level accurate in the most recent session" — self-contradictory for a first-session breakthrough (the sentence printed the frontier's own 'accurate') and offering only the down-fork to a child who had just broken through. Floor-null has two causes the branch conflated: genuinely nothing accurate, and a breakthrough inside a window too short to promote (every first session lands there). Fixed by splitting on `frontier_state`. The general lesson for every block's fork derivation: **branch conditions must be stated in terms of what the data shows, not in terms of which engine artifacts (floor/frontier) happen to be null** — engine-artifact nullability overloads causes.

---

## The four fields the second block will test hardest

When the next block gets built, watch these — they are where this one-example interface is most likely to be wrong. Feeding is the maximally-different second instance for three of them; fluency owns the fourth.

1. **`progression_type`** — is feeding's texture progression truly a `ladder`, or is it gated differently (safety overriding order)? If safety-gating reorders how "where they are" works, the interface may need progression and safety to interact, not just coexist.
2. **`safety_gated`** — feeding is the first `true`. The off-ramp binding clause says the answer is a structure (trigger signals + veto layer + structural binding), not a bool — the feeding block will confirm whether that structure generalizes into the interface or stays surface-local.
3. **`detection_signature`** — feeding's signature (swallow/texture/aspiration language) is the first *contrast* signature. Only with two can we test whether "match against signatures" actually discriminates, or whether CAS and feeding data blur.
4. **`consecutive_over` (sessions vs. observations)** — **fluency's test.** Rotating contexts break consecutive-over-sessions promotion entirely (a context not probed in a session snaps the chain). If fluency needs consecutive-over-observations, the recency rule splits into an engine principle (most-recent, no cherry-picking) and a framework denominator (recent *what*).

---

## The build order this implies

1. **CAS block** — instance #1, both halves built: read path committed (`3297b58`) and proven; capture surface (`CasSessionDials` + save-seam wiring) built and sandbox-proven end-to-end (2026-07-09). Still owed: a clinician capturing dials through the running UI.
2. **This interface** — this document. Instance #1 filled in, guesses marked, as-built caveats stated.
3. **Feeding block (or a stub)** — instance #2, deliberately the most different (safety-gated, first `true`). Confirms or breaks the provisional fields. Even a thin stub gives the detector a second signature to route against.
4. **The detector** — reads incoming data, matches against the ≥2 declared `detection_signature`s, proposes a block. Inherits the domain-detection provenance pattern already on `clients` (confidence / source / version / `is_slp_authoritative`). Testable only once step 3 gives it a second shape.

Building the detector before step 3 = a router with one road. This document + a second signature is the minimum that makes detection real.
