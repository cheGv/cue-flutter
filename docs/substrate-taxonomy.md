# Cue Substrate Taxonomy

**Version:** 0.1
**Authored by:** Guru
**Date:** May 2026
**Status:** Locked for Phase A. Editable only by version bump.

This document defines the substrate — the structured clinical evidence model that underlies every clinical-reasoning surface in Cue: chart view, goal-authoring, review mode, handover, export. The substrate is shape-stable across all child presentations. Same layers, same sub-categories. Per-patient variation lives in which cells have content, not in which cells exist.

The substrate enforces CUE PRODUCT LAW: Cue assembles evidence; the clinician reasons. No layer, no sub-category, no attribute permits Cue to author conclusions, rank hypotheses, or recommend clinical action.

---

## Layer order (UI rendering, fixed)

1. Safety and regulation
2. Cognitive-linguistic substrate
3. Communication-pragmatic substrate
4. Motor-speech substrate
5. Family system and environment
6. Developmental trajectory

Regulation always first. This encodes the polyvagal-informed paradigm — regulation gates everything above. The order is paradigm, not preference.

---

## Layer 1 · Safety and regulation

The foundational core. Surfaces what is available for self-regulation and what threatens safety.

Sub-categories:
- Recovery time from dysregulation
- Co-regulation responsiveness
- Sensory-seeking and avoidance profile
- Arousal range and baseline
- Self-injurious or unsafe behavior  *[safety_flag default]*
- Sleep stability  *[safety_flag when severe]*
- Feeding stability  *[safety_flag when severe]*

---

## Layer 2 · Cognitive-linguistic substrate

Symbol readiness, comprehension, conceptual base. The cognitive ground on which language and communication are built.

Sub-categories:
- Joint attention quality
- Gestural inventory
- Referential pointing
- Symbol comprehension
- Play schemes
- Receptive-expressive gap
- Imitation across modalities
- Response to name

---

## Layer 3 · Communication-pragmatic substrate

How the child uses communication in social context. Most sub-categories activate from developmental readiness onward; minimally-verbal children render only the first two cells until pragmatic substrate emerges.

Sub-categories:
- Communicative functions inventory
- Initiation rate
- Conversational repair
- Turn-taking
- Topic maintenance
- Narrative coherence
- Theory of mind in interaction
- AAC modality readiness  *[when AAC is in the clinical question]*
- Symbol-set selection criteria  *[when AAC]*
- Partner-assisted vs independent access  *[when AAC]*
- Generative vs pre-programmed messaging  *[when AAC]*

---

## Layer 4 · Motor-speech substrate

What is available for volitional speech production. The motor-speech mechanism examined as a clinical system.

Sub-categories:
- Vowel inventory
- Consonant inventory
- Syllable shape inventory
- Volitional vs automatic speech contrast
- Oromotor imitation
- Jaw-lip dissociation
- Tongue lateralization and elevation
- Diadochokinesis  *[age_conditional: 4+]*
- Prosodic features
- Regression history  *[prognostic]*

---

## Layer 5 · Family system and environment

The implementation engine and ecological context. Goals are authored to be implementable in this system, not in the abstract.

Sub-categories:
- Caregiver composition and roles
- Language ecology (per-caregiver mapping)
- Stated family priorities
- Family beliefs about intervention
- Daily routines (anchor moments)
- Implementation capacity and bandwidth
- Cultural context
- Financial sustainability
- Sibling integration

---

## Layer 6 · Developmental trajectory

Where the child is in time. Prognostic, historical, contextual. Calibrates how ambitious the goal can be.

Sub-categories:
- Age and developmental presentation
- Prognostic indicators
- Therapy history
- Standardized assessment results  *[assessment_fit attribute required]*
- School and educational context
- Cross-discipline involvement (OT, PT, psychology, medical)
- Disability certification status

---

## Cell attributes

Attributes are cross-cutting flags that can apply to any cell across any layer.

- `safety_flag` — cell content has safety implications; rendered with warm sienna left border and "Safety" tag in UI.
- `prognostic` — cell content carries prognostic weight; surfaces in review mode and at re-authoring time.
- `age_conditional` — cell renders only when patient age meets the condition specified in the cell definition. Otherwise renders as not-applicable, not as gap.
- `assessment_fit` — required on Standardized assessment results cells. Records whether the chosen instrument is fit for the child's profile. A floor score on the wrong instrument is not assessment evidence; it is an artifact.

---

## Empty cell semantics

A cell with empty content is not missing data. It is an open clinical question, attended to. UI renders empty cells with the em-dash treatment: *— not yet on file —* in italic serif, warm sienna. Empty cells participate in threading and surface during goal-authoring as gaps the clinician may want to close before signing.

---

## Threading

Threading lives in `substrate_relations`, a global graph independent of any patient. Each relation:
- Connects two tags (clinical concepts, not sub-categories directly).
- Carries strength (strong, moderate, weak).
- Carries direction (mutual, source_to_target).
- Carries a one-line clinical reasoning note explaining why the thread exists.

Cells reference tags via `substrate_tags`. Threading is computed by tag overlap traversed through relations.

The threading graph is the clinical intelligence layer of Cue. Each relation is a clinical claim and must be authored, not generated. Initial batch curated by Guru. Future additions require version bump.

---

## What this taxonomy does not do

- Does not rank cells by importance.
- Does not score the chart.
- Does not recommend which gaps to fill.
- Does not author goals, conclusions, or interpretations.
- Does not encode any single clinical framework as exclusive (SCERTS, PROMPT, NDBI, Hanen, polyvagal-informed practice all map onto these layers without conflict).

This is the substrate. The clinician reasons.
