# cue-addendum.md — spec-driven-development
Overlay on Addy Osmani's spec-driven-development skill. Read both. Skill names below refer to Cue's skills in `_shared/` and `flutter/`.
## When a written spec (`/docs/specs/`) is mandatory in Cue
- Vision-for-AAC (photo → AAC layout + vocab) — highest leverage, highest fabrication risk
- The SLP style-learning-by-observation system
- The three-tier report architecture (Assessment / Progress / Baseline — see `clinical-architecture`)
- Any new population under the six-layer model
- Any feature crossing a product-phase boundary (`product-law`)
- Anything touching the attestation flow or any new parent-facing surface
- Any new domain tag (also needs a decision record — see DR-009; never invent)
## Cue spec additions (beyond Addy's sections)
- **Clinical impact statement:** what changes for the SLP, the child, the parent. If you can't write it, the feature isn't ready.
- **Vantage check:** does any SLP-facing or AI-facing copy in the spec obey `language-discipline`? No deficit framing baked into the design.
- **Attestation flow:** draft state, who attests, what invalidates it, where unattested content may/may not appear.
- **Phase + Product-Law check:** which product phase; what the SLP *gets* from any new action right now.
- **Layer check (if clinical):** which of the six layers (01–06) this touches; build order respected.
## Anti-rationalizations
| Excuse | Counter |
|---|---|
| "Vision-for-AAC is too complex to spec, I'll figure it out as I build." | Exactly why it needs a spec. Highest-stakes feature; a fabricated AAC vocab harms a non-speaking child. |
| "The clinical impact is obvious." | Then the paragraph takes 5 minutes. Write it. |
| "I'll bolt the new domain on now, decide later." | Domains are a recorded decision (DR-009). Never invent. Surface to Guru. |
