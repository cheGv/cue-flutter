# cue-addendum.md — code-review-and-quality
Overlay on Addy Osmani's code-review skill. Read both. Guru is solo — self-review must be MORE rigorous, not less.
## Solo review protocol
1. Wait ≥4 hours (overnight better) before self-review.
2. Review as if reviewing a contractor's code, not your own.
3. Read the PR diff, not the editor — familiarity hides bugs.
## The Cue review axes
1. **Correctness** vs the spec (if one exists).
2. **Clinical safety:** could this surface fabricated info, leak unattested content, or lose clinical history? (`clinical-invariants`)
3. **Vantage:** does any new/changed copy or prompt output obey `language-discipline`? Run the forbidden-words scan.
4. **Attestation integrity:** drafts stay out of clinical surfaces; post-edit re-attestation works.
5. **Path safety:** correct repo, correct CLAUDE.md, not the decoy (`repo-and-path-topology`).
## Per-phase commit discipline (locked — DR-005)
Every phase touching Flutter code commits immediately after verification (`flutter analyze` + `flutter build web` + hot-restart check), with a phase-tagged message, BEFORE the next phase begins. The Phase 3.3.7c bundled commit (`d343788`) happened because five phases accumulated uncommitted in `client_profile_screen.dart`. Recovery from a bundle: document it, do NOT `git reset` to rewrite entangled history.
## Escalate to an external reviewer (don't merge solo)
- First vision-for-AAC implementation
- Any change to the attestation flow or the anti-fabrication preamble
- Any DPDP-affecting change (de-identification, export, erasure)
- Any code deciding what parents see
## Self-review checklist
```
[ ] Spec referenced (if applicable)
[ ] Five axes considered
[ ] Failing tests existed before implementation
[ ] language-discipline forbidden-words scan run on new copy/prompt output
[ ] No MediaQuery in width-responsive logic; no functions.invoke()
[ ] No "Cue AI" string; no money figure in dashboard
[ ] Migration (if any) ran on sandbox first; prod via db push
[ ] Correct repo + canonical CLAUDE.md confirmed
[ ] Committed this phase before starting the next
```
