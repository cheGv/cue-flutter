# Mirror Format Corpus — Catalogue (redacted)

Index of the real clinic reports used to validate Cue's Mirror
format-understanding. **Reports are referenced by code only — no client or
practitioner names appear in this file.** The documents and the code→source
map live in this folder but are gitignored (see `README.md`).

Status: **collecting — 3 of a target ~5–15 varied reports.** Engine not yet run
against these; vision layer not yet built. Organizing / gap-spotting only.

## Index

| Code | Practice type | Letterhead | Structure | Special elements | File |
|------|---------------|------------|-----------|------------------|------|
| **R1** | Large institutional speech-&-hearing centre | Round **image logo**; otherwise plain/minimal | **Deeply nested numbered** (I/II/III → a/b/c → i/ii/iii) | Two-column receptive/expressive **table** | PDF — *want .docx* |
| **R2** | Branded private clinic | Heavy branding: colored **block logo** + **purple gradient sidebar band** + contact-info header | Prose + **bulleted lists** | **Gradient band**, colored logo, contact header | PDF — *want .docx* |
| **R3** | Independent solo practice | **Text-identity** header (styled name + credentials, **no logo image**) | Numbered sections + bullets; **framework-specific ontology** (PROMPT / Motor Speech Hierarchy stages) | **Handwritten signature image** | PDF — *want .docx* |

## Per-report notes

- **R1** — institutional, minimal-styling baseline; the deepest *nested-numbered*
  structure so far. Its 2-column table is the only table in the corpus. (This is
  the "first clinic" the original geometry heuristics were tuned to.)
- **R2** — the heavy-branding case. The gradient band + decorative letterhead are
  exactly what tripped the geometry heuristics in Phase E (phantom tables, blank
  page-2/3 images). The branding-fidelity stress test.
- **R3** — a third identity style (text letterhead, no logo) **and** a different
  clinical ontology (PROMPT motor-speech stages) — so it tests generalization on
  the letterhead **and** structure axes at once. Adds the signature-image element.

## Variety covered so far (3 reports)

- **Letterhead:** image-logo (R1) · gradient-brand block-logo (R2) · text-identity,
  no-logo (R3) — three distinct identity styles. Good spread.
- **Structure:** deeply-nested-numbered (R1) · bulleted-prose (R2) ·
  framework-specific ontology (R3) — three distinct conventions. Good spread.
- **Special elements:** table (R1) · gradient band (R2) · signature image (R3) ·
  logo image (R1, R2) — the main element types each appear at least once.
- **Clinical format:** pre-therapy PT assessment (R1) · SALT progress report (R2) ·
  PROMPT motor-speech assessment (R3) — some domain spread.

## Gaps — what to collect next (priority order)

1. **A native `.docx` original — highest priority.** All three are PDFs. The
   decision note makes `.docx` the cleanest, most reliable input path, and
   validation needs at least one to confirm that path works. Ask a clinic for the
   original Word file — **not** a PDF→Word conversion (that mangles logos/bands
   and would contaminate the test).
2. **A table-heavy report.** Only R1 has a single 2-column table. A report
   dominated by score/data tables stresses table detection — where the
   phantom-grid bug lives — far harder.
3. **More clinics / conventions generally.** Target ~5–15 total for a credible
   "handles most clinics." Each new clinic adds convention variety the vision
   layer must generalize across.
4. **Nice-to-have:** a full-width colored header band (vs R2's sidebar); one true
   multi-column page flow (a known hard case — to confirm graceful degradation,
   not to perfect); a school/IEP or discharge-summary format (different document
   shape).
5. **Out of scope — do NOT prioritize:** scanned / photographed PDFs (OCR —
   explicitly not chased per the decision note); infographic / magazine layouts.
