# Skill: clinical-invariants
> **Shared core.** Binds both repos. The clinical correctness that earns the trust `north-star` assumes. Clinical correctness and memory continuity take priority over code elegance.
## When to use
Triggered when code or prompts touch: goals (LTG/STG), session notes, Narrator output, the attestation flow, clinical vocabularies, evidence rows, patient/client data, or any AI-generated clinical content.
## The clinical model
### LTG / STG
- **Long-Term Goal (LTG):** directional, 6–12 months, narrative but categorized (domain + framework). "Where is this client going?"
- **Short-Term Goal (STG):** the **measurable operational unit**, 4–12 weeks. An STG is **not a static record** — it is a living object that accumulates session-level evidence. The same STG row at week 1 vs week 6 carries different clinical meaning because of accumulated evidence. **This accumulation is the moat.**
Every STG has: a target behavior (what), a context (where/how), a mastery criterion (accuracy %, consecutive sessions, trials), a support level (current + initial), a domain, and a framework.
### Evidence
A row in `stg_evidence` is one session's measurable contribution to an STG. May be manually entered or AI-extracted from the Narrator transcript / session note. **Every AI-extracted row carries a confidence score and a `clinician_verified` flag.**
## Controlled vocabularies — never use free-form strings where these exist
### Support level (least → most scaffolding)
`independent` → `minimal` → `moderate` → `maximal` → `hand_over_hand`
> **Neurodiversity-affirming framing:** support level describes the scaffolding the *clinician brings* to a communicative moment, not a behaviorist prompt hierarchy. "Maximal support" is NOT a failure state — it reflects the current co-regulation the client needs to access a target skill. (This is the same vantage discipline as `language-discipline` §13.15, applied to clinical vocabulary.)
### STG status
`active` | `mastered` | `on_hold` | `discontinued` | `modified`
### Framework
`PROMPT`, `OPT`, `AAC`, `NLA`, `DIR`, `Hanen`, `PECS`, `Core_Word`, `Motor_Speech`, `Phonological_Process`, `Interoception_Informed`, `Polyvagal_Informed`, `Other`
### Domain — READ THE SOURCE OF TRUTH, DO NOT HARD-CODE FROM MEMORY
Cue currently carries **two overlapping domain vocabularies**, and they have **not been formally reconciled**:
1. **Clinical-goal vocabulary** (used to tag LTGs/STGs): `articulation`, `phonology`, `expressive_language`, `receptive_language`, `pragmatics`, `fluency`, `voice`, `motor_speech`, `feeding_swallowing`, `AAC_operational`, `AAC_linguistic`, `AAC_social`, `literacy`, `cognitive_communication`.
2. **Domain Detector vocabulary** (live in the proxy `/cue-domain-detect` endpoint + DB constraint, operationalized 2026-05-13): `dysphagia`, `aac`, `motor_speech`, `language`, `fluency`, `voice`, `aphasia`, `asd_regulatory`, `cognitive_communication`.
**Rule:** before adding, changing, or referencing any domain tag, read the *actual* source of truth — the database enum/CHECK constraint in Supabase, and (for detector work) the detector spec in the proxy repo (`prompts/reviews/domain_detector_v1.3.x.md`). **Never invent a domain that isn't in one of those two live sources.** The lists above are documentation and may lag the code; the database constraint and the detector prompt are authoritative.
> **Open reconciliation (tracked decision, not a code-session call):** the two vocabularies overlap but differ (14 clinical-goal domains vs 9 detector domains; e.g. `feeding_swallowing` vs `dysphagia`, the AAC split vs flat `aac`). Reconciling them is a product decision recorded in the decision archive — a code session must NOT silently pick one or invent a third. If a task seems to require choosing, stop and surface it to Guru.
## The hard invariants
### Anti-hallucination (all clinical generation)
- Never invent clinical observations not grounded in the Narrator transcript or session-note input.
- If data is missing, say **"not documented"** — never fabricate.
- Structured fields (trials, accuracy, support level) must be `null` if unextractable from source.
- `ai_confidence` must be populated for every `stg_evidence` row with `source = 'ai_extracted_*'`.
### Clinician attestation (liability gate)
- **No AI-generated session note enters the clinical record without `clinician_attested = true`.**
- The attestation action is explicit in the UI — never a pre-checked box.
- Attestation stores `attested_at` + `attested_by` for audit.
- There is no auto-attest path. Ever.
### STG mastery is proposed, never auto-set
When evidence accumulates, the AI updates `current_accuracy` (rolling mean, N=5 default), `sessions_at_criterion`, and `total_sessions_worked`. If `sessions_at_criterion >= mastery_criterion.consecutive_sessions`, the AI **proposes** `status = 'mastered'` — it requires clinician confirmation and **never auto-sets.**
### Multilingual fidelity (non-negotiable)
- Telugu, Kannada, Hindi, and English code-switching must be preserved in Narrator output **verbatim**.
- **Do NOT translate the child's productions** — clinical evidence depends on the exact form produced.
- Parent summaries may be translated only on explicit SLP opt-in (Phase 2+).
### Legacy data is never AI-re-extracted without attestation
See `language-discipline` §13.16. Clinicians own their authored content; silent re-extraction into new structured fields is re-authoring. Migration ships with explicit per-field SLP attestation or it does not ship.
## Anti-rationalizations
| Excuse | Counter |
|---|---|
| "I'll hard-code the domain list, it's faster." | The two lists aren't reconciled and may lag code. Read the DB constraint + detector spec. Never invent a domain. |
| "The model is confident, skip the confidence score." | Every AI-extracted evidence row carries `ai_confidence`. No exceptions. |
| "Auto-mastering a clearly-met goal saves a click." | AI proposes, clinician confirms. Never auto-set status. |
| "Translating the child's production makes the note cleaner." | Forbidden. The exact form produced IS the clinical evidence. |
| "Re-extracting legacy notes would populate the new fields nicely." | Silent re-authoring (§13.16). Attestation gate or don't ship. |
| "A free-text support level is more expressive." | Use the controlled vocabulary. Free-form breaks the evidence model. |
## Evidence of compliance
- For any AI clinical generation: a test with deliberately thin input → "not documented," not a fabricated value.
- For attestation paths: a draft (unattested) note does NOT enter the clinical record or any export.
- For domain work: confirmation the tag exists in the live DB constraint / detector spec, not invented.
- For Narrator/transcript work: child productions preserved verbatim, untranslated.
- For evidence rows: `ai_confidence` and `clinician_verified` present on every AI-extracted row.
