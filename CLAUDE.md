# CLAUDE.md — Cue (Flutter app)
Cue is a clinical operating system for Speech-Language Pathologists. Solo founder: Guru.
**Clinical correctness and memory continuity take priority over code elegance.**
This file is a ROUTER. Read it fully at the start of every session.
**Before anything else, load `flutter/repo-and-path-topology` — path confusion has caused real regressions.**
---
## SESSION-OPEN RITUAL (do this first, every time)
```
pwd                      # confirm you're in C:\projects\cue
Get-ChildItem CLAUDE.md  # confirm canonical CLAUDE.md, NOT the OneDrive Desktop decoy
git remote -v            # confirm cheGv/cue-flutter
```
---
## HARD INVARIANTS (never violate)
1. **JARVIS test:** every feature makes the SLP feel more capable at no extra cost, or it's killed. (`_shared/north-star`)
2. **CUE PRODUCT LAW:** never add performative labor to the SLP. (`_shared/product-law`)
3. **The product is "Cue," never "Cue AI"** in any user-facing surface. (`_shared/north-star`, `_shared/product-law`)
4. **Language discipline (§13):** all copy presumes competence; vantage is the work, not the child. Governs all UI copy AND all AI output. (`_shared/language-discipline`)
5. **No AI clinical content without `clinician_attested`.** (`_shared/clinical-invariants`)
6. **Never translate the child's productions; preserve code-switching verbatim.** (`_shared/clinical-invariants`)
7. **No monetary figures in the SLP dashboard UI.** (`_shared/product-law`)
8. **`LayoutBuilder`, never `MediaQuery`, for width-responsive UI.** (`flutter/flutter-layout`)
9. **Flutter calls the proxy via `http.post`, never `functions.invoke()`.** (`flutter/flutter-layout`)
10. **RLS is currently DISABLED on goals tables; re-enabling is a hard gate before onboarding.** (`flutter/supabase-data-layer`)
11. **Prod migrations via `supabase db push` only; MCP `apply_migration` is sandbox-only.** (`flutter/migration-discipline`)
12. **Read the design spine doc before visual work; introduce no new hex/token/font without approval.** (`flutter/design-system`)
---
## SKILL ROUTING
Load the skill BEFORE writing code for a triggered task.
| Task touches… | Load |
|---|---|
| Any non-trivial work | `_shared/north-star` (the why) |
| New feature, scope, phase boundary, SLP-facing action | `_shared/product-law` |
| ANY user-facing text OR any AI output | `_shared/language-discipline` |
| Goals, notes, attestation, clinical vocab, evidence | `_shared/clinical-invariants` |
| Which repo / which file / before any commit | `flutter/repo-and-path-topology` |
| Width-responsive UI, layout, screens, routes, motion | `flutter/flutter-layout` |
| Typography, color, cuttlefish, logo, components | `flutter/design-system` |
| Supabase queries, schema, RLS, tables | `flutter/supabase-data-layer` |
| Schema changes, migrations, backfills | `flutter/migration-discipline` |
| Six-layer model, populations, reports, Cue Calc, surfaces | `flutter/clinical-architecture` |
| Spec / TDD / review / debugging / API design / security | `_imported/*` (+ each one's `cue-addendum.md`) |
---
## ENVIRONMENT
- **This repo:** Flutter app, `C:\projects\cue`, `cheGv/cue-flutter` → Netlify / GitHub Pages
- **Proxy repo (separate):** `C:\dev\cue\proxy`, `cheGv/cue-ai-proxy` → Render
- **Prod Supabase:** `cgnjbjbargkxtcnafxaa`
- **Sandbox Supabase:** `uuqhusmgoiaxdvtgbmwh`
- **Proxy URL:** `https://cue-ai-proxy.onrender.com`
- ⚠️ **Decoy — never edit:** `C:\Users\guruv\OneDrive\Desktop\Cue\CLAUDE.md`
---
## DECISION RECORDS
The "why" behind locked decisions lives in `docs/decisions/DECISIONS.md` — read it when a rule's reasoning matters, not on every task.
## WHEN UNSURE
Ask Guru. Do not invent: clinical vocabulary, domain tags (read the live DB constraint + detector spec), normative data, attestation rules, a final logo mark, or migration steps. Do not resolve the two-domain-vocabulary tension (DR-009) — surface it.
