# cue-addendum.md — code-review-and-quality
This addendum overlays Addy Osmani's code-review-and-quality skill with Cue-specific requirements. Read both files together.
## Solo review protocol
Guru is solo. There is no second reviewer. This means self-review must be more rigorous, not less. The protocol:
1. **Time delay.** After implementation, wait at least 4 hours (overnight is better) before self-review.
2. **Role switch.** Review as if reviewing a contractor's code, not your own. The cognitive switch matters.
3. **Read the diff, not the code.** Open the PR diff view. Reading line-by-line in the editor lets familiarity hide bugs.
4. **The five-axis framework specialized for Cue.**
## The Cue five-axis review
Apply each axis explicitly. Don't aggregate them into a vague "looks good."
### Axis 1: Correctness
Does the code do what the spec says? Compare against `/docs/specs/` entry if one exists.
### Axis 2: Clinical safety
- Could this code cause an SLP to act on fabricated information?
- Could this code surface unattested content to a parent or to billing?
- Could this code lose clinical history (notes, goals, attestation records)?
- If yes to any, the change does not merge until mitigated.
### Axis 3: RLS correctness
- Every new query against a patient-scoped table: confirm RLS coverage.
- Every new policy: confirm tested as the affected role.
- Every new table: confirm RLS enabled by default with deny-by-default.
### Axis 4: Attestation integrity
- Any new path that creates AI-generated content: confirm default state is unattested.
- Any new query that exposes clinical content: confirm it filters `clinician_attested = true` unless explicitly a draft-review surface.
- Any new edit path: confirm post-edit attestation invalidation works.
### Axis 5: AI fabrication risk
- Any new LLM call: confirm anti-fabrication preamble applied.
- Any new prompt: read it as if you were trying to make the model hallucinate. Where would it slip?
- Any new structured output: confirm "insufficient information" path is representable and tested.
## Self-review checklist (run through every time)
```
[ ] Spec referenced (if applicable)
[ ] All five axes explicitly considered
[ ] Failing tests existed before implementation (commit history)
[ ] No MediaQuery in width-responsive logic
[ ] No raw hex colors in widget files
[ ] No inlined LLM prompts as string literals
[ ] No direct Anthropic API calls bypassing the proxy
[ ] No hard-delete paths in app code
[ ] No PHI in LLM prompt bodies
[ ] Migration (if any) has run on sandbox first
[ ] Golden tests updated and visually reviewed (if visual contract touched)
[ ] Contract tests pass via the Render proxy (if Edge Function touched)
[ ] Anti-fabrication test exists (if LLM call touched)
```
## When to escalate to an external reviewer
Even solo, some changes warrant pulling in a clinician collaborator or another developer before merge:
- First implementation of vision-for-AAC.
- Changes to the attestation flow itself.
- Changes to the anti-fabrication system prompt.
- DPDP-affecting changes (de-identification, data export, right-to-erasure).
- Any code that decides what parents see.
Don't merge these solo. Find a reviewer, even if it slows you down by a day.
## Anti-rationalizations (Cue-specific)
| Excuse                                                          | Counter |
|-----------------------------------------------------------------|---------|
| "I just wrote it, I remember every line, no need to re-review"  | That's exactly when bugs hide. Time delay + role switch is the discipline. |
| "Solo means no review possible"                                 | Solo means review is harder and more important, not absent. |
| "The five axes are overkill for this small change"              | Then it's a 30-second check. Run it. |
| "I'll get an external reviewer next time, ship this now"        | The "next time" for attestation changes never arrives. Find the reviewer. |
