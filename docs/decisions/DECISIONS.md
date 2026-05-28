# Cue — Decision Records
> Resolved history and the reasoning behind locked decisions. This is **not active governance** — a code session does not need to load these every time. They are preserved so that "why did we decide this?" always has an answer. When a rule's reasoning matters, it lives here; the rule itself lives in a skill.
---
## DR-001 — Deprecated "canonical target" schema (never migrated to)
An early schema design named `patients` (not `clients`), `sessions.id uuid` (not `bigint`), and `short_term_goals.target_behavior + mastery_criterion jsonb` (not `specific + measurable + target_accuracy + time_bound_sessions`). **The prototype never migrated to this shape.** The Flutter data layer and the proxy both write the prototype shape documented in `supabase-data-layer`. The deprecated DDL survives only in git history. Do not reintroduce its column names. Phase 4.0 committed to prototype reality as canonical.
---
## DR-002 — The catastrophic-trust incident (locked language-discipline §13.6)
Cue Study once critiqued — in a corrective tone, in front of the SLP — a goal that Generate Plan had authored. Two surfaces of the same product gave the SLP contradictory clinical signals about her own chart. This was a trust breach, not a cosmetic bug. It locked the **one-voice rule** (§13.6: provenance is invisible; the chart is hers regardless of which surface authored it) and the **critique-requires-ask rule** (§13.7: critique is collaboration by default, evaluation only when invited). The architectural fix lives in the *producing* surface (coherence rules, §13.3), never in softening the reading surface.
---
## DR-003 — The pronoun-default + Stance-1 incident (locked §13.8)
Cue authored: *"I've been thinking about Muthu… I have her chart open. Are her goals appropriate for her age?"* — for a client whose chart had no gender data ("her" was a guess) and with an age-as-deficit lens. This locked the **four-stance vantage taxonomy** (default Stance 2: the work is the subject, not the child) and the **name-first / no-gendered-pronouns** rule. See `language-discipline` §13.8.
---
## DR-004 — Manufactured-urgency and over-burden incidents (locked §13.10, §13.11)
Two related production outputs: (a) Cue manufactured urgency about session cadence two days into a fresh chart ("the 4-contact timeline is already under pressure"); (b) Generate Plan prescribed academic-grade comprehensive assessment on a tight timeline. Both violated the Product Law by adding labor/anxiety the SLP didn't ask for. Locked **no-manufactured-urgency** (§13.10) and **clinical-humility / minimum-viable-frame** (§13.11).
---
## DR-005 — Phase 3.3.7c bundled commit (locked per-phase commit discipline)
Five phases of Flutter work (3.3.4 VANTAGE pronoun discipline, 3.3.5.1 LateInit hotfix, 3.3.7a structured conditions, 3.3.7b three-block render, 3.3.7c chart strip) landed in a single commit `d343788` because `client_profile_screen.dart` accumulated changes across all five without intermediate commits and `cue_tokens.dart` was untracked throughout. Code shipped correctly; git history was muddied. **Recovery: left as-is** (entangled line edits can't be cleanly split retrospectively; never `git reset` to rewrite). **Lesson locked:** every phase touching Flutter code commits immediately after verification, before the next phase begins. (Now in the `code-review-and-quality` addendum.)
---
## DR-006 — Two-CLAUDE.md / wrong-directory regressions (locked repo-and-path-topology)
Two confirmed regressions in Phase 3.3.7 traced to path confusion: one session ran Flutter edits against the wrong working directory; another edited a non-canonical CLAUDE.md (the 67-line decoy at the OneDrive Desktop path). Both failure modes are silent. Locked the **repo-and-path-topology** guard: two repos (`cue-flutter` at `C:\projects\cue`, `cue-ai-proxy` at `C:\dev\cue\proxy`), the canonical CLAUDE.md vs the never-edit decoy, and the `pwd`-first session-open ritual.
---
## DR-007 — Resolved bugs (do not reintroduce)
- Supabase project URL typo (the sandbox-ID `b`-vs-`x` error was a later, separate instance of the same class — verified `x` is correct: `uuqhusmgoiaxdvtgbmwh`).
- CORS whitelist must include the GitHub Pages / Netlify origin on the proxy.
- JWT ES256/HS256 mismatch — use plain `http.post` to Render, never `functions.invoke()`.
- RLS silently blocking goals reads — RLS currently disabled for prototype (see `supabase-data-layer`; re-enable is a hard gate before onboarding).
---
## DR-008 — Phase ordering and surface architecture (locked §14)
The sidebar holds five sibling surfaces (Today / Clients / Practice / Narrator / Settings), each answering a distinct mental model. Today is protected (single-purpose, never enriched). Practice (NL retrieval) and Cue Study (clinical reasoning) are siblings, not duplicates — resist merging. Phase order: Phase 3 uniformity pass → Phase 4 Practice → Phase 4.0 assessment report / multi-population → Phase 4.1 Cue Calc → Phase 5+ Cue Reference / Sense / Living. Detail in `clinical-architecture` and `PHASE_4_SPEC.md`.
---
## DR-009 — Open reconciliation: two domain vocabularies
Cue carries two overlapping, unreconciled domain vocabularies: a 14-item clinical-goal vocabulary (§6.4 of the old doctrine) and a 9-item Domain Detector vocabulary (live in the proxy `/cue-domain-detect` + DB constraint since 2026-05-13). They differ (e.g. `feeding_swallowing` vs `dysphagia`; the AAC three-way split vs flat `aac`). **Reconciling them is an open product decision — a code session must not silently pick one or invent a third.** Until reconciled, `clinical-invariants` instructs reading the live DB constraint + detector spec as the source of truth. Resolve and record here when decided.
