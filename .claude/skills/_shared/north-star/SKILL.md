# Skill: north-star
> **Shared core.** This skill binds both repos (cue-flutter and cue-ai-proxy). It is the "why" beneath every other skill. When any other skill's rule seems ambiguous, resolve it toward this one.
## When to use
Read this at the start of any non-trivial task. It is not triggered by a file type — it is the lens every feature passes through before it is built. If you are about to add, change, or remove anything the SLP will see or feel, read this first.
## The North Star
**JARVIS for SLPs. Expanding to all of rehabilitation.**
JARVIS doesn't wait to be asked. JARVIS reads the room. JARVIS knows what the clinician needs before she knows she needs it. JARVIS makes the SLP feel like the smartest, most prepared version of herself.
Every feature passes this test:
> Does this make the clinician feel more like a JARVIS-assisted clinician, or more like a form-filler?
If the answer is form-filler — **kill it.**
## The Interface Motto
> "You have one user. The SLP. What is the one thing she needs to feel when she opens this? Until you know that feeling, you're just building features. Start over from the feeling, not the features."
The feeling Cue must produce:
> "This system knows my client better than my paper notes ever could, and it took me no extra work to get there."
Every UI decision passes this filter before any other. The enemy of that feeling: clutter, ambiguity, anything that makes the SLP hunt for a number or re-read a label.
## Product identity
**Cue** is India's first Clinical Operating System for Speech-Language Pathologists. It is **not** a telehealth platform, **not** a note-taker, **not** an EMR. It is the **memory and intelligence layer** for an SLP's full caseload.
- Solo founder: Guru — AIISH-trained SLP (PROMPT / OPT L1 / COSMI).
- The product is named **Cue**. Never "Cue AI" — not in UI, not in footer, not in any user-facing surface. (Internal repo names like `cue-ai-proxy` are git identifiers, not the product name.)
- Community and top-of-funnel: The Engrams (Instagram EBP platform).
## The thesis
> A *cue* is the smallest possible unit of intervention and the highest possible act of belief in a person with a communication disorder.
This is not marketing. It is the reason the product is shaped the way it is. The whole system exists to let the SLP give better cues to the people she serves — and to do so without the system itself becoming one more thing she has to tend.
## How this governs the rest
Three skills descend directly from this one and should be read as its operational arms:
- **product-law** — the CUE PRODUCT LAW (never add performative labor) is how the JARVIS test becomes a hard rule.
- **language-discipline** — how Cue *speaks* so the SLP feels assisted by a peer, never judged by a system.
- **clinical-invariants** — the clinical correctness that earns the trust the North Star assumes.
When those skills and this one ever seem to disagree, this one wins, and the disagreement is a signal that the descendant skill was written slightly wrong. Flag it.
## The single question
When in doubt about anything — a label, a feature, a flow, a sentence Cue speaks — ask:
> Does this make the SLP feel like the smartest, most prepared version of herself, at no extra cost to her?
If yes, build it. If no, or if it adds cost she didn't ask to pay, redesign or kill it.
