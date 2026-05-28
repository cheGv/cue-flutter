# Skill: product-law
> **Shared core.** Binds both repos. This is the JARVIS test (see `north-star`) made into a hard, checkable rule. When a feature is in question, this skill decides.
## When to use
Read before adding, changing, or removing any feature, surface, or SLP-facing interaction. Triggered by: new features, anything that asks the SLP to do work, phase-boundary questions, parent-facing surfaces, anything that would display in the dashboard UI.
## The CUE PRODUCT LAW
> **Cue never adds performative labor to the SLP.**
Every feature passes this filter before it is built. If a feature requires the SLP to do *additional* work to serve the system — extra data entry, extra review steps, extra parent coaching, extra translation — it is rejected or redesigned.
**Corollaries:**
- AI output slots into the SLP's existing clinical workflow; it never adds a new one.
- Parent-facing artifacts are generated *automatically* from clinician work, never re-typed by the SLP.
- Structured data capture is a *byproduct* of what the SLP already does (documentation, Narrator sessions), never a new form she fills for the system's benefit.
**The test for any SLP-facing action:** what does the SLP get from this action, right now, for this child? If the answer is "the system learns" or "data quality improves," it is performative labor — redesign so the benefit is hers and immediate, or kill it.
## Phase scope
| Phase | Scope | Status |
|---|---|---|
| **Phase 1** | Clinician OS — caseload, goals (LTG + STG), sessions, SOAP + parent summary AI, Narrator, memory layer | Active build |
| **Phase 2** | Clinical AI depth, billing, Cue Living parent routine layer | 3–6 mo |
| **Phase 3** | Multi-clinician, full revenue stack | 6–12 mo |
| **Phase 4** | Data moat, B2B API | 12–24 mo |
**Phase 1 is strictly clinician-only.** The parent portal does NOT ship in Phase 1. But Phase 1 schema must include forward-compatible fields (`parent_visible`, `parent_friendly_label`, `parent_routine_anchor`) so Phase 2 migration is trivial.
> Note on phase numbering: the doctrine carries two phase-numbering systems — the product-phase ladder above (Phase 1–4) and a build-sequence ladder (Phase 3.x uniformity pass, Phase 4.0.x multi-population, Cue Calc at 4.1, etc.). They are not the same axis. The build-sequence detail lives in `clinical-architecture` and in the decision archive. This skill governs the product-phase scope boundaries only.
## Hard invariants
- **Never add a feature that requires extra SLP action to serve the system.** (The Product Law itself.)
- **Never display monetary figures in the SLP dashboard UI.** No revenue, no pricing, no money figures on dashboard surfaces. (Pricing is ₹999/mo Pro tier as a business fact; it does not appear in the SLP's workspace.)
- **The product is "Cue," never "Cue AI"** in any user-facing surface — UI, footer, copy, anywhere a clinician or family sees it. (`cue-ai-proxy` is an internal git repo name, not the product name. See `north-star`.)
- **Do not expose STGs to parents in Phase 1.** The schema is forward-ready; the UI is not. Parent surfaces wait for Phase 2 (Cue Living).
- **AI success metric:** SLPs edit <10% of generated report content. A feature that pushes edit rate up is failing the Product Law — it's making her redo the system's work.
## Anti-rationalizations
| Excuse | Counter |
|---|---|
| "It's just a small tag, she won't mind." | Small tags compound across a full caseload. If the benefit is the system's, kill it. |
| "Parents are asking for this now." | Phase 1 is clinician-only. Parent surfaces wait for Phase 2 by design, not by accident. |
| "A quick revenue widget would motivate her." | No money figures in the dashboard. Non-negotiable. |
| "She can rate the AI output to improve it." | Performative labor for system benefit. Use passive signal (her edits, deletions) instead. |
| "This feature is so useful she'll tolerate the friction." | She tolerates nothing. Tolerated friction is the next abandoned tool. |
| "'Cue AI' reads clearer in this label." | It is always "Cue." Always. |
## Evidence of compliance
Before considering a feature complete:
- A one-line answer to "what does the SLP get from any new action, right now, for this child."
- For parent-facing additions in Phase 1: stop — they don't ship until Phase 2; record the decision if there's a reason to revisit.
- A scan confirming no monetary figure appears on any dashboard surface.
- A scan confirming no "Cue AI" string in any user-facing copy.
