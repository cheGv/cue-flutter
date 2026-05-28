# cue-addendum.md — spec-driven-development
This addendum overlays Addy Osmani's spec-driven-development skill with Cue-specific requirements. Read both files together.
## When the spec discipline is mandatory in Cue
A written spec in `/docs/specs/` is required before code for:
- Vision-for-AAC (photo → AAC layout + vocab)
- The SLP style-learning-by-observation system
- The three-tier report architecture
- Any feature that crosses a phase boundary (Cue AI → Sense → Living → Home)
- Any feature that touches the attestation flow
- Any new clinical surface visible to parents
- Any new domain or sub-domain tag (also requires a `/docs/decisions/` entry)
Smaller bug fixes, UI polish, and internal refactors don't need a spec. Use judgment, but err toward writing one if the feature touches clinical data.
## Cue spec template additions
In addition to Addy's spec sections, every Cue spec includes:
### Clinical impact statement
One paragraph answering: what changes for the SLP, the child, and the parent because this feature exists? If you can't write this paragraph, the feature isn't ready to spec.
### Attestation flow
If AI generates content this feature touches, document:
- What draft state looks like.
- Who can attest (clinician role check).
- What invalidates attestation (content edit, source change).
- Where unattested content can and cannot appear.
### Phase boundary check
Which product phase does this belong to (Cue AI / Sense / Living / Home)? If the answer is "AI" but the feature requires wearable data, the spec is wrong — push the feature to Sense.
### Parent-surface impact
Even if the feature is clinician-only, document whether it eventually surfaces to parents and under what conditions. This forces the Phase 1 → 2 boundary thinking early.
### Performative-labor audit
For any SLP-facing interaction in the spec, answer: "what does the SLP get from this action, right now, for this child?" If the answer is "the system learns," redesign before coding.
## Spec lifecycle in Cue
- Spec lives in `/docs/specs/YYYY-MM-DD_short-name.md`.
- Spec is reviewed (by Guru, even if solo — read it the next day with fresh eyes).
- Code references the spec in commit messages and PR descriptions.
- Spec is updated when scope changes, not deleted.
- Shipped specs move to `/docs/specs/shipped/` with a date and a 1-line outcome note.
## Anti-rationalizations (Cue-specific)
| Excuse                                                          | Counter |
|-----------------------------------------------------------------|---------|
| "Vision-for-AAC is too complex to spec, I'll figure it out as I build" | Exactly why it needs a spec. High-stakes features without specs ship as half-features. |
| "The clinical impact is obvious"                                | Then writing the paragraph takes 5 minutes. Write it. |
| "Phase boundary doesn't matter, we can move it later"           | Moving phase boundaries breaks pricing, regulatory, and product narrative. Decide upfront. |
| "It's just a small AI feature, spec is overkill"                | Any AI feature touching clinical surfaces gets a spec. The size of the feature ≠ the size of its blast radius. |
