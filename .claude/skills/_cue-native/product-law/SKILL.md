# Skill: product-law
## When to use
Triggered when the task involves:
- Adding a new feature or surface to Cue AI
- Any decision that touches the parent-facing layer
- Sequencing decisions across Cue AI / Sense / Living / Home
- Anything that asks the SLP to do extra work (logging, tagging, rating, confirming, choosing)
- Phase boundary questions ("can this ship in Phase 1?")
## The invariants
### P1. Cue Product Law: never add performative labor to the SLP
Performative labor = work the SLP does for the system's benefit, not the child's. Examples:
- Asking the SLP to tag a session with 5 dropdowns before saving
- Requiring the SLP to rate AI output on a 1-5 scale to "train the model"
- Asking the SLP to confirm something the system could infer
If a feature requires the SLP to do extra work AND the benefit accrues to the system or to parents rather than to this child's clinical outcome, the feature does not ship in its current form.
The test: would a 15-year-experienced SLP, mid-session with a non-speaking child, accept this interaction? If no, redesign.
### P2. Phase 1 is clinician-only
The parent-facing layer (Cue Living routine prompts, parent dashboards, parent reports) does not ship until Cue Sense ships. Reason: parents need wearable-derived regulatory signal to act on prompts intelligently. Shipping parent features without Sense data creates anxiety, not outcomes.
### P3. Product sequencing is locked
Cue AI (anchor, shipping now) → Cue Sense (Phase 1 wearable, wellness launch, direct-to-parent) → Cue Living (Phase 2, routine-embedded therapy) → Cue Home (Phase 3+, ambient hardware, post 18–24mo data).
A feature request from a later phase does not jump forward without an explicit product decision recorded in `/docs/decisions/`.
### P4. Sub-1s utterance-to-action budget
Any clinician-facing interaction (recall, intent-to-action, voice commands) must complete in under 1 second from utterance end to visible action. This is non-negotiable because it determines whether the SLP can stay present with the child or has to context-switch to the tool.
### P5. The SLP attention-protection thesis
Cue exists so the SLP can be fully present with the child. AI handles navigation, documentation, and evidence. The SLP handles relationship. If a feature pulls the SLP's attention toward the screen instead of away from it, redesign or kill.
## Anti-rationalizations
| Excuse                                                          | Counter |
|-----------------------------------------------------------------|---------|
| "It's just a small tag, the SLP won't mind"                     | Small tags compound. 5 tags × 8 sessions/day × 200 days = 8000 micro-interruptions/year. Kill it. |
| "Parents are asking for this feature now"                       | Parents always ask. Phase 2 exists because parents need Sense data to act on prompts well. Don't bend sequencing for vocal users. |
| "We can add a quick parent view, it's just one screen"          | One screen becomes two becomes a product. Parent surface stays gated until Sense ships. |
| "1.2 seconds is basically 1 second"                             | No. The budget is sub-1s including network. Profile or redesign. |
| "The clinician can rate this output to help the model improve"  | That's performative labor for system benefit. Find passive signal instead (edits, deletions, re-runs). |
| "This feature is so useful, the SLP will tolerate the friction" | The SLP tolerates nothing. Tolerated friction = next telehealth tool they abandon. |
## Evidence of compliance
Before considering a Phase-or-product-law-affecting change complete, produce:
- A 1-line written justification of which phase this feature belongs to and why
- For SLP-facing interactions: a measured timing from a real session recording or a benchmark showing sub-1s utterance-to-action
- For any new SLP action (tap, type, choose): explicit answer to "what does the SLP get from this action, right now, for this child?" — if the answer is "the system learns" or "data quality improves," redesign
- For parent-facing additions: a decision record in `/docs/decisions/` justifying why this doesn't wait for Sense
## Open product questions (do not invent answers)
- Logo: not locked. Three finalists (Ictus, Measure, Ariadne's Thread). Never produce a "final" logo.
- Cue Home device name: candidate "Phora" — not confirmed.
- Cue Sense pricing tiers: ₹599 / ₹1,199 / ₹1,799 confirmed; Pro tier emerges Year 1.
