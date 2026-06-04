# Mirror Format Corpus

Real clinic reports collected to **validate** Cue's Mirror format-understanding
against genuine, varied formats — per
[`../mirror-format-understanding-decision.md`](../mirror-format-understanding-decision.md)
and [`../phase-e-findings.md`](../phase-e-findings.md). This is a validation
corpus, not training data.

## ⚠ Privacy — read first

These are REAL clinical documents containing children's and practitioners'
names (PHI). They must **never** be committed or pushed.

- `files/` — the actual PDFs / `.docx` — **gitignored**.
- `_corpus-key.md` — the code → clinic / practitioner / child / filename map —
  **gitignored**.
- `CATALOGUE.md` (redacted — codes only, no names) and this README are the
  only committable files here.

The folder `.gitignore` enforces this. Do not override it, and never paste a
real name into `CATALOGUE.md` or any other committable file.

## Adding a report

1. Drop the file in `files/`.
2. Add a row to `CATALOGUE.md` with the next code (`R4`, `R5`, …) and its
   characteristics — **no names**.
3. Record the code → source mapping in `_corpus-key.md` (stays local).

## Status

Collecting (3 so far; target ~5–15 varied). The engine has **not** been run
against these, and the vision layer is **not** built — that work begins once
the corpus is fuller. This folder is organizing + gap-spotting only.
