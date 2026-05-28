# Skill: clinical-architecture
> **Flutter repo** (but conceptually shared — the proxy's plan-generation must respect it too). The canonical structural model for how Cue serves multiple clinical populations. Locked Phase 4.0.
## When to use
Triggered by: anything touching the six-layer model, `population_type`, `population_payload`, new populations, the assessment/progress/baseline reports, Cue Calc, or the Practice / Cue Study / Cue Reference surfaces.
## The core commitment
Phase 4.0 is the moment Cue stops being a single-population (ASD/AAC) product and becomes a **multi-population platform.** First population shipped end-to-end under the new architecture: **developmental stuttering.**
**Build order is strict: ship one population fully — Layer 01 through 06 plus the three derived outputs — before any second population begins.** The load-bearing spec is `PHASE_4_SPEC.md`; read its relevant section before writing Phase 4.0.x code.
## The six layers (canonical for EVERY population)
| Layer | Purpose | Where it lives |
|---|---|---|
| 01 | **Core Profile** — population-agnostic identity: name, age, primary concern verbatim, languages, `population_type` | `clients` table |
| 02 | **Case History** — population-specific (e.g. stuttering: onset, development pattern, variability, awareness, comfort level, secondary behaviours, prior intervention) | `case_history_entries.payload jsonb` keyed by `population_type` |
| 03 | **Assessment Data** — three sub-modes: (a) live entry, (b) debrief, (c) parent interview | `sessions.population_payload jsonb` for a/b; `assessment_entries` (with `mode` discriminator) for c |
| 04 | **Pre-therapy Planning** — family goals, priority focus, child readiness, family involvement | `goal_plans` metadata |
| 05 | **Lesson Plan Inputs** — approach, techniques, session structure | `goal_plans.lesson_plan_inputs jsonb` |
| 06 | **Progress Tracking** — per-session per-STG structured metrics | `stg_evidence.population_payload jsonb` |
**Three derived outputs** compose from the layers: **Assessment Report** (layers 01–03), **Progress Report** (layer 06 longitudinal + layer 05 plan), **Baseline Snapshot** (at layer-03 lock).
## The JSONB generalization pattern
Schema generalizes across populations via `population_payload`: the **column shape is identical** across populations (`population_type text` + `payload jsonb`); the **JSONB key set is population-specific.** New populations add a new key set to the same column — they do **NOT** add new tables or alter layer ordering.
Population-specific metrics in `population_payload` do **NOT** feed the §9.4 STG-state trigger (that rolls only the standard structured columns). Population metrics feed the Progress Report composer instead.
## Build order is the dependency graph — no leap-frog
Strict 1 → 2 → 3 → 4 → 5 → 6 for every population. Layer 06 metrics are meaningless without Layer 05's technique frame; Layer 04 inputs are meaningless without Layer 03's baseline. The order is not a preference — it's the dependency chain.
Phase 4.0 V1 ships developmental stuttering only. Other fluency sub-types are V1.1–V1.4 (separate phases after V1). Other populations (SSD, voice, language, etc.) are Phase 4.1+. ASD/AAC re-architecture into the six-layer model is Phase 4.x — for the duration of Phase 4.0, ASD/AAC clients render unchanged on legacy AAC-shaped surfaces.
## Reference content boundary (ties to language-discipline §13.14)
Cue does not generate ungrounded reference content. Two permitted routes:
- **Cue Calc (Phase 4.1, Route 1):** sixteen public-domain clinical calculations (PCC, PVC, PCC-R, whole-word accuracy, %SS, speech rate, articulation rate, TTR, MLU-w, MLU-m, NDW, TNW, s/z ratio, MPT, DDK rates, intelligibility %) computed in **local Dart math** — no LLM in the calc path — each paired with a hand-authored genealogy card (name, who/when/why developed, what it tells you, limitations, citation). Formula renders inline.
- **Cue Reference (Phase 5+, Route 2, deferred):** RAG against a curated public-domain corpus; every retrieval cites its source.
**Out of scope — copyrighted instruments:** SSI-4, GFTA-3, KLPA-3, OASES, CELF, REEL-3, WAB, BDAE, BNT, CAPE-V, VHI, and all publisher-owned content. Cue does not reproduce their scoring rubrics, severity bands, or items.
## Surface architecture (locked)
- **Today** = what's imminent (protected, single-purpose).
- **Clients** = who's active (browsing).
- **Practice** = natural-language retrieval (Phase 4, "find me this document") — same paradigm as Cue Study, separate endpoint/prompt, pointed at retrieval not reasoning.
- **Cue Study** = conversational clinical reasoning ("help me think through this case").
- **Cue Calc** = deterministic computation (Phase 4.1).
**Cue Study and Practice are siblings, not duplicates** — same interaction paradigm, different scope, separate system prompts. There will be a recurring temptation to merge them ("why two conversation surfaces"). **Resist** — collapsing them produces a worse interface for both.
## Anti-rationalizations
| Excuse | Counter |
|---|---|
| "I'll add a new table for this population." | New populations add a JSONB key set to `population_payload`, not new tables. |
| "Let me build Layer 06 metrics first, they're the interesting part." | No leap-frog. 06 is meaningless without 05's frame. Build in order. |
| "Cue Calc can just ask the LLM for the formula." | No LLM in the calc path. Local Dart math + hand-authored genealogy. Zero hallucination surface. |
| "Merge Practice into Cue Study, one chat surface." | Siblings, not duplicates. Separate prompts. Resist the merge. |
| "Population metrics can feed the §9.4 trigger." | They feed the Progress Report composer. The trigger rolls only standard columns. |
## Evidence of compliance
- New population work confirmed to use the JSONB key-set pattern, not new tables.
- Layer work confirmed to follow 1→6 order.
- Reference content confirmed to come via Cue Calc (deterministic) or grounded retrieval — never ungrounded LLM generation.
- Read the relevant `PHASE_4_SPEC.md` section before Phase 4.0.x code.
