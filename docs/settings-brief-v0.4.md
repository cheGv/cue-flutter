# Cue Settings — Build Brief
**Version:** v0.4 (critique-applied, schema-migration ready)
**Owner:** Guru
**Scope:** Phase 1 Settings architecture for Cue (Clinical OS for SLPs)
**Last updated:** May 2026
---
## Changelog
- **v0.4 (this revision):** Applied 27 cuts from v0.3 critique pass.
  - **Cuts (Product Law violations):** Tagline (Id Block 1), Pronouns (Id Block 1), CRE credits manual tracking (Id Block 3), Printed-name-below-signature toggle (Id Block 5 — now always-on), Required sections multi-select (Clinical Block 2 — locked to S+A+P), STG cap slider (Clinical Block 3 — locked to 3, override at Goal Authoring time), Show session timer toggle (Clinical Block 4), Auto-prompt SOAP toggle (Clinical Block 4 — collapsed into autodraft), Sentence length preference (AI Block 2 — reading level is canonical), Edit feedback prompt toggle (AI Block 4 — Phase 1.5+), Display address/contact letterhead toggles (Practice Setup Blocks 2+3 — letterhead style enum is canonical), Digest email field (Notifications Block 1 — single contact email), Cohort grouping toggle (Audit Log — always on), Marketing emails toggle (Privacy Block 3 — no marketing infra exists), Force password change cadence (Security Block 1 — security theater), Backup payment method (Billing Block 2), Active clients/sessions/signed-PDFs counters (Billing Block 4 — clinical surfaces belong elsewhere), Onboarding tour replay (Legal&Help — vapor), Keyboard shortcuts (Legal&Help — should be global, not buried), Press/brand assets (Legal&Help — aspirational), What's new inline summary (Legal&Help — attention extraction)
  - **Patches (structural):** Default session fee moved from Clinical Defaults Block 4 → Practice Setup Block 5 (billing primitive, not clinical); Critical-override notifications multi-select → read-only badge list; Annual statement marked Phase 1.5; "Five collapsible cards" globalism in §2 corrected to "between 3–5 blocks per screen"; "applies to all three screens" corrected to "applies to all ten screens"
  - **Schema additions:** `processor_customer_id_encrypted` (replaces plaintext), foreign-key cascade behavior specified per table
  - **Gates carried forward:** B5 GST registration verification (blocks Billing schema lock); §9 open questions remain
  - **Year of completion (A4) deferred** to in-context decision during Identity Block 4 build
- **v0.3:**
  - Specced all six remaining screens: Practice Setup (§5A), Notifications (§5B), Privacy & Consent (§5C), Security (§5D), Audit Log (§5E), Billing (§5F), Legal & Help (§5G)
  - GST/tax apparatus removed from Practice Setup Block 5
  - Single-logo design locked; telemetry toggle deduped
  - Audit log retention default resolved (§9.7)
  - Anchor patches landed
- **v0.2:** Audit log column-level encryption, array editing semantics, pgcrypto pre-req, Speech Therapist warning removed
- **v0.1:** Initial brief.
**Still unresolved (carried forward):**
- B5 GST registration verification (gates Billing Block 3 invoice schema)
- Open questions §9.1–§9.13 (resolved in-context during build)
- Pre-production: audit retention enforcement mechanism (column vs job)
- Pre-production: Razorpay or equivalent processor selection
---
## 0. Context
Cue Settings is organized into **three trunks** under ten screens:
**Who I am:**
1. Identity & Credentialing (§3)
**How I practice:**
2. Clinical Defaults (§4)
3. AI Behavior (§5)
4. Practice Setup (§5A)
5. Notifications (§5B)
**What's protected:**
6. Privacy & Consent (§5C)
7. Security (§5D)
8. Audit Log (§5E)
9. Billing (§5F)
10. Legal & Help (§5G)
**Principle:** Every default on these screens must be overridable per-session, per-client, or per-document. Defaults are gravitational, not deterministic.
**CUE PRODUCT LAW:** Every field on these screens must absorb work the SLP is already doing, never add new performative labor. If a field fails this test, cut it.
---
## 1. Architectural Constraints
Pulled from `CLAUDE.md` — non-negotiable for this build:
- **Stack:** Flutter Web (Netlify), Supabase project `cgnjbjbargkxtcnafxaa`, Anthropic API via Render proxy at `https://cue-ai-proxy.onrender.com`
- **Never use `MediaQuery`** — always `LayoutBuilder`
- **Anthropic calls:** plain `http.post` only, never `functions.invoke`
- **Brand:** Never label as "Cue AI" anywhere in UI
- **Typography:**
  - Playfair Display — surgical identity moments only (signed PDFs, letterhead)
  - Syne — labels, stats, buttons
  - DM Sans — body
- **Animations:** `AnimatedSize` + `AnimatedCrossFade` for collapse/expand. No `BackdropFilter` (kills Flutter Web perf)
- **RLS:** Disabled on all tables for prototype. Application-layer access controls only (patterns documented in `CLAUDE.md`)
- **Framework tokens:** `[framework: short_code]` machine tokens must render as chips, not raw text — verify on every reasoning surface
### Pre-requisites before schema migration
- **pgcrypto extension:** Run `create extension if not exists pgcrypto;` on Supabase project `cgnjbjbargkxtcnafxaa` before applying migrations.
- **PII encryption key:** Set `PII_ENCRYPTION_KEY` in Supabase env. For prototype, single symmetric key. Production key rotation strategy is out of Phase 1 scope.
- **Framework chip renderer:** Per `CLAUDE.md` (May 2026), the chip renderer is mounted on `cue_reasoning_panel.dart` but **missing on `cue_popup.dart`**. Settings Block 3 (Goal Framework) introduces new surfaces that consume framework tokens. Before shipping Settings: verify chip renderer is mounted on every surface that displays `[framework: short_code]` tokens. This is a parallel dependency, not just a verification.
---
## 2. Cross-cutting Rules (applies to all ten screens)
- **Layout:** Each screen renders as 3–5 collapsible cards. Cards are independently editable. SLP can fill any card in any order.
- **No screen-level gate:** Onboarding past Settings is always permitted with everything empty. Friction surfaces at the artifact gate (e.g., "Add your RCI number before signing this report"), never at the settings entry.
- **Save semantics:** Write per-field on blur. No batch saves. Per-field writes create granular audit log entries.
- **Immutability on signing:** When a PDF is signed and shared, snapshot the full identity profile into the document record. Future settings edits do not retroactively change signed documents.
- **Locked-once-used:** Fields that have been written to a signed PDF (legal name, RCI number, signature) remain editable. Editing triggers a confirmation: "This will not change documents already signed. A new credential cohort will be created for future documents."
### Audit log behavior
Every field write creates an entry in `settings_audit_log` — `(actor_id, timestamp, table_name, field_name, prev_value, new_value, is_pii, changed_at)`.
**Encryption rule:**
- When `is_pii = true`: `prev_value` and `new_value` are encrypted via `pgp_sym_encrypt(value, current_setting('app.pii_key'))`, stored as base64-encoded text. Forensic queries decrypt via `pgp_sym_decrypt`.
- When `is_pii = false`: plaintext storage. Examples: toggle state, enum changes, integer/duration changes, framework code selections.
**PII-flagged fields** (write with `is_pii = true`):
- Legal first/middle/last name
- RCI registration number
- All uploaded file paths (signature, logo, profile photo, certificates)
- Signature SVG path data
- Custom disclaimer text (may contain PII)
**Uploads are additionally hashed:** For file uploads, store SHA-256 hash of file contents alongside the encrypted file path. Hash proves change without preserving content. Hashes stored plaintext.
### Array editing semantics
Applies to `slp_certifications`, `slp_qualifications`, and the `section_ordering` JSONB in Clinical Defaults Block 2.
- **Adding a new entry:**
  - Row created with `status='draft'` and all fields null when SLP taps "Add entry"
  - Per-field blur writes from then on; each blur creates one audit log entry
  - Row is **hidden** from non-Settings surfaces (reports, letterheads, suffix auto-compose) until the primary identifying field (Type for certifications, Degree for qualifications) is non-null
  - When primary field is filled, status transitions to `active`
- **Editing existing entry:** Per-field-on-blur. One audit log entry per field change.
- **Deleting an entry:**
  - **Hard-delete** the uploaded file from Supabase Storage (DPDP right-to-erasure)
  - **Soft-delete** the row by setting `deleted_at = now()`
  - Single audit log entry captures full prior entry state as JSON in `prev_value`; `new_value` is null
  - Deleted rows excluded from all non-audit queries via `where deleted_at is null`
- **Reordering (e.g., `section_ordering` array):** Single audit log entry with the JSONB array delta. No per-position writes.
### DPDP-compliant deletion summary
When SLP deletes any uploaded file:
1. File hard-deleted from Supabase Storage
2. Row soft-deleted with `deleted_at` timestamp
3. Single audit log entry retains the prior full state (encrypted under `is_pii=true`)
4. Audit log entries themselves are not deletable through Settings UI
5. Audit log retention is governed by clinical record retention rules (currently unresolved — see §9.7)
Make all of this explicit in the deletion confirmation dialog.
---
## 3. Screen 1 — Identity & Credentialing
Five blocks, stakes ascending.
### Block 1 — Display (lowest stakes)
App-facing identity only. Never appears on signed documents.
| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| Display name | string, 1–60 chars | Yes | First-name token from auth | Trim whitespace, no leading/trailing specials |
| Profile photo | image, JPG/PNG, ≤2MB | No | Generated initials avatar on hash-seeded color | Crop square, compress to 512×512 WebP |
### Block 2 — Legal Identity (medium stakes)
Appears on signed PDFs and audit log entries.
| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| Legal first name | string, 1–50 chars | For signed PDFs | — | Letters, spaces, hyphens, apostrophes only |
| Legal middle name | string, 0–50 chars | No | — | Same as first name; allow single-letter + period |
| Legal last name | string, 1–50 chars | For signed PDFs | — | Same as first name |
| Salutation | enum | No | Inferred (Dr if Ph.D. in Block 4) | None / Mr / Ms / Mrs / Dr / Prof |
| Professional designation | enum | Yes | SLP | SLP / Audiologist / ASLP / Speech Therapist |
| Degree suffix string | auto-composed string | — | Auto from Block 4 | Override allowed up to 80 chars |
### Block 3 — Statutory Registration (highest stakes — required for signed reports)
Persistent coral badge until complete. Block signed-PDF generation if incomplete.
| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| RCI category | enum | Yes | Match Block 2 designation | A / SLP / ASLP |
| RCI registration number | string | For signed PDFs | — | Lenient regex by category prefix + ≥4 digits. **Validate format only, not authenticity.** Display disclaimer. |
| Date of registration | date | Yes | — | ≤ today, ≥ 1992-09-01 |
| Renewal due date | date | No | — | Warning banner 60 days pre-expiry, blocker 7 days pre-expiry. Reminder includes deep link to RCI portal for CRE-credit logging |
| Registration certificate upload | PDF, ≤5MB | No | — | Encrypted at rest, never auto-attached to external docs |
**Disclaimer to display:** "Cue validates format only. Registration authenticity is the practitioner's responsibility."
### Block 4 — Education & Certifications
Both sub-sections follow the array editing semantics in §2.
#### Primary qualification (single, required for suffix auto-compose)
| Field | Type | Required | Validation |
|---|---|---|---|
| Degree | enum with autocomplete | Yes | B.A.SLP / B.A.(SLP) / B.Sc.(SLP) / B.Sc. Hons (SLP) / M.Sc.(SLP) / M.A.SLP / M.S. (SLP) / Ph.D. (SLP) / Ph.D. (Audiology) / Other (free 30 chars) |
| Institution | free-text + autocomplete | Yes | Autocomplete against known list (AIISH, AYJNISHD, JIPMER, Manipal, NIEPMD, ISHA-recognized); free entry allowed |
| Year of completion | int | Yes | 1970 to current_year + 1 |
#### Other qualifications
Array, max 5 entries, same shape. Subject to §2 array semantics.
#### Specialized certifications
Array, max 20 entries. Subject to §2 array semantics.
| Field | Type | Validation |
|---|---|---|
| Type | enum (controlled vocabulary, **not user-editable**) | PROMPT / OPT / COSMI / DTTC / LSVT LOUD / LSVT BIG / Hanen ITTT / Hanen MTW / Hanen TalkAbility / PECS / SCERTS / DIR Floortime / ABA / Sensory Integration / AAC certification / LSL / Custom |
| Level/sub-cert | enum (shown conditionally) | PROMPT: Intro/Bridging/L1/L2/L3/Instructor; OPT: L1/L2/L3/Instructor; PECS: L1/L2; DIR: Basic/Advanced/Expert/Faculty; LSVT: Certified/Certified Clinician; ABA: BCBA/BCaBA/RBT |
| Date earned | date | Optional |
| Expiry | date | Optional; warning 30 days pre-expiry |
| Certificate upload | PDF, ≤5MB | Encrypted at rest, optional |
**Governance:** Certification taxonomy lives in `CLAUDE.md §6.3–6.6` (controlled vocabularies). Never expose to user editing. Adding new types is a deliberate vocabulary update, not a settings free-for-all.
### Block 5 — Signature & Letterhead
**Practice Setup dependency:** Letterhead "Header content" sources from Blocks 2, 3, AND Practice Setup (separate brief). Block 5 ships with a header stub: when Practice Setup is empty, the letterhead preview area displays `Add practice details to compose your letterhead →` with a deep link to the Practice Setup screen. Practice Setup screen exists as a placeholder route from day one.
**RCI display vs RCI signing gate:** RCI presence is required to *sign* a PDF (Block 3 gate). RCI *display on letterhead* is separately configurable here. Signed PDFs include RCI in their attribution block regardless of the letterhead toggle. The toggle controls only the visual letterhead surface.
#### Signature
| Field | Type | Default | Notes |
|---|---|---|---|
| Signature mode | enum | None | Drawn / Uploaded / Typed-name-only / None |
| Drawn signature | SVG path data | — | Touch/mouse pad. Store as SVG, never raster. Allow re-draw and undo |
| Uploaded signature | PNG with alpha | — | JPG rejected. Validate alpha channel. ≤500KB. Normalize to ~300×100px |
| Auto-attach to signed reports | toggle | ON | Defaulting OFF makes this block performative |
**Always-on behavior (no toggle):** Printed legal name + designation + RCI number stack renders below every signature on signed reports. Industry convention; not configurable.
#### Letterhead
| Field | Type | Default | Notes |
|---|---|---|---|
| Letterhead style | enum | Minimal text-only | Full banner / Minimal text-only / None |
| Logo | read-only mirror | — | Sourced from Practice Setup Block 1. Edit there. Only relevant for Full banner |
| Header content | auto-composed read-only preview | — | Sourced from Blocks 2, 3, and Practice Setup. Not directly editable. Falls back to stub if Practice Setup empty |
| Footer content | auto-composed + editable disclaimer | "Generated through Cue · clinical OS for SLPs" | Disclaimer editable to 100 chars or removable |
| Show RCI on letterhead | toggle | ON | Controls letterhead surface only — signed PDFs include RCI regardless. Disabling triggers informational confirmation, not a blocker |
| Live preview | re-render on every change | — | Updates when any source field in Blocks 2, 3, or Practice Setup changes |
---
## 4. Screen 2 — Clinical Defaults
Five blocks, foundational → granular.
### Block 1 — Practice Language & Communication
| Field | Type | Default | Notes |
|---|---|---|---|
| Primary clinical language | enum | English | English / Kannada / Telugu / Hindi / Tamil / Malayalam / Marathi / Bengali / Gujarati / Punjabi / Odia / Assamese / Other. Drives UI and note rendering |
| Default parent summary language(s) | multi-select, 1–3 | Matches primary | Multi-select renders stacked or side-by-side translations in PDFs |
| Default report formality | enum | Warm clinical | Formal clinical / Warm clinical / Plain. Per-document override always available |
| Reading level for parent summaries | enum | Grade 8 | Grade 6 / Grade 8 / Grade 10 / Adult professional. Drives AI rewriting |
### Block 2 — Note Structure
| Field | Type | Default | Notes |
|---|---|---|---|
| Default note format | enum | SOAP | SOAP / Narrative / Hybrid |
| Section ordering | reorderable list (JSONB) | S → O → A → P | Subject to §2 array semantics for reorder. SLP can hide sections (with confirmation if hiding "Assessment") |
| Pre-session brief on home screen | toggle | ON | Shows AI-generated pre-session brief in Today view per `CLAUDE.md` |
| Auto-include previous session summary | toggle | ON | Surfaces last 3 STG progress lines in note draft |
**Always-on behavior (no toggle):** S, A, P sections are required for any session to be marked complete. Locked clinical floor; not configurable. SLPs who want a different completion gate must override per-session, not via Settings.
### Block 3 — Goal Framework
| Field | Type | Default | Notes |
|---|---|---|---|
| Default goal hierarchy depth | enum | LTG → STG | LTG only / LTG → STG / LTG → STG → step. Drives Goal Authoring Module |
| Default EBP frameworks | multi-select | NDBI, ImPACT | NDBI / ImPACT / EMT / Hanen / PROMPT hierarchy / PECS / Core Vocabulary AAC / LSVT / Restorative aphasia / Compensatory aphasia / SCERTS / DIR Floortime / ABA / SLT-Indic. Drives framework chip suggestions in Goal Authoring |
| Default mastery criterion | enum | 80% across 3 sessions | 70/3, 80/3, 90/3, 80/5, Custom (free text) |
| Auto-suggest next STG on mastery | toggle | OFF | Phase 1.5 feature; default OFF until reasoning loop is validated |
**Always-on behavior (no toggle):** STG cap per LTG locked to 3 per `CLAUDE.md §invariants`. Override available at Goal Authoring time only ("Add 4th STG? Most LTGs cap at 3 — proceed?" with rationale prompt), never in Settings. Decision-at-decision-time, not decision-at-configuration-time.
### Block 4 — Session Defaults
| Field | Type | Default | Notes |
|---|---|---|---|
| Default session duration | enum + custom | 45 min | 30 / 45 / 60 / Custom (15–120 min) |
| Default session type | enum | Direct intervention | Assessment / Direct intervention / Parent coaching / Group / Tele-session / Re-evaluation |
| Default attendance setting | enum | In-person | In-person / Tele / Hybrid |
**Default session fee** moved to Practice Setup Block 5 (billing primitive, not clinical).
**Session timer behavior** is non-configurable: always visible during active session view (Phase 1.5+ feature).
**Auto-prompt SOAP at session end** is collapsed into AI Behavior Block 1 "Autodraft SOAP notes" — single toggle controls both generation and surface.
### Block 5 — Templates
| Field | Type | Default | Notes |
|---|---|---|---|
| Parent intake template | rich text | Cue-provided default | Editable; used for new client onboarding |
| Consent form template | rich text | Cue-provided DPDP-compliant default | Editable with warning that legal review is SLP's responsibility |
| Parent summary template | rich text with `{variable}` tokens | Cue-provided default | Tokens: `{child_name}`, `{session_date}`, `{progress}`, `{home_practice}`, etc. |
| Discharge summary template | rich text | Cue-provided default | Triggered when client is marked discharged |
| Template language | enum | Inherits Block 1 primary | Per-template override |
---
## 5. Screen 3 — AI Behavior
Five blocks. Defaults bias toward minimal AI intervention until the SLP opts in. Trust is earned, not assumed.
### Block 1 — Autodraft Behavior
| Field | Type | Default | Notes |
|---|---|---|---|
| Autodraft SOAP notes | toggle | ON | Generates draft on session end; SLP always reviews before save |
| Autodraft parent summaries | toggle | ON | Generates draft when SLP marks session complete |
| Autodraft goal suggestions | toggle | OFF | Phase 1.5; surfaces next-STG suggestions in Goal Authoring Module |
| Autodraft session prep brief | toggle | ON | Pre-session brief widget on Today view |
| Autodraft scope | enum | Current session only | Current session only / Current session + last 3 / Full client history. Affects prompt context size |
### Block 2 — Tone & Voice
| Field | Type | Default | Notes |
|---|---|---|---|
| Parent summary tone | enum | Warm clinical | Inherits Clinical Defaults; per-block override here |
| Note draft tone | enum | Clinical | Clinical / Warm clinical. Notes are SLP-facing; bias formal |
| Use of clinical terminology in parent summaries | enum | Mixed | Strict plain language / Mixed (term + plain gloss) / Clinical |
| Voice clone (write in my style) | toggle | OFF | **Phase 1.5+ feature.** Activates after 50+ SLP-edited sessions (threshold unresolved — see §9.2). Greyed out until threshold met; progress shown: "Cue has learned from N of 50 sessions" |
**Sentence length** is not a separate knob. Sentence length follows from "Reading level for parent summaries" (Clinical Defaults Block 1, Grade 6/8/10/Adult). Two metaphors for the same output dimension was redundant.
### Block 3 — Grounding & Safety
**Non-negotiable defaults — cannot be turned off:**
| Field | Type | Default | Behavior |
|---|---|---|---|
| Show AI confidence indicator | always on | — | Every AI-generated block displays confidence ribbon |
| Show source grounding | always on | — | AI cites which session data, framework, or Engrams article informed each suggestion |
| Anti-hallucination guardrails | always on | — | If model returns ungrounded clinical claim, surface as "Cue is unsure — review needed" rather than rendering |
| Auto-disclaimer on parent-shared PDFs | always on (**text editable via Block 5**) | — | Fact of AI involvement is always disclosed; exact wording is configurable in Block 5 |
**SLP-configurable:**
| Field | Type | Default | Notes |
|---|---|---|---|
| Cue Ask / Cue Study EBP retrieval source | multi-select | Engrams corpus + peer-reviewed | Engrams corpus / Peer-reviewed only / Engrams + peer-reviewed / SLP's uploaded references |
| Surface contradicting evidence | toggle | ON | When AI suggests an intervention, also surfaces published critiques or limitations |
### Block 4 — Edit Threshold & Telemetry
The success metric block. Edit threshold is the instrumentation that validates Cue's value.
| Field | Type | Default | Notes |
|---|---|---|---|
| Alert me if I'm editing >X% of generated content | int slider 5–50% | 25% | Per `CLAUDE.md` AI success metric: SLP edits <10% of generated content. Threshold defaults at 25% to be lenient; SLP can tighten |
| Show per-session edit ratio | toggle | OFF (Phase 1.5) | Privacy-respecting telemetry surfaced to SLP only |
| Share anonymized edit telemetry with Cue | read-only mirror | OFF | **Sourced from Privacy & Consent Block 3.** Edit there → |
**Edit feedback prompt** ("what did you change and why?" after save) deferred to Phase 1.5+ as opt-in research instrumentation. Asks SLP to do labor for Cue's product loop — violates Product Law if shipped as default. Edit-diff analysis (used for voice-clone training in Block 2) gets the same data without performative SLP labor.
### Block 5 — Disclaimers & Attribution
| Field | Type | Default | Notes |
|---|---|---|---|
| AI attribution on parent-shared PDFs | enum | Footer disclaimer | Footer disclaimer / Inline section markers / Both. **Cannot be set to "None"** — the fact of AI involvement is mandatory disclosure |
| AI attribution on SLP-internal notes | enum | Inline markers | Inline section markers / Metadata only / None |
| Custom disclaimer text | string, ≤200 chars | Cue default | Overrides the auto-disclaimer wording on parent-shared PDFs. Cannot disable the disclaimer entirely — only edit its text |
| Default disclaimer text (preview) | read-only | "Sections of this summary were drafted with AI assistance and reviewed by [SLP name, RCI number] before sharing" | Editable above; this row shows what gets rendered if Custom is empty |
| Show "Report a clinical concern" channel | always on | — | One-tap escalation if Cue ever generates output that worries the SLP. Routes to support + product team |
---
## 5A. Screen 4 — Practice Setup
Foundational screen of the "How I practice" trunk. Unblocks Identity Block 5 letterhead composition. Five blocks.
### Block 1 — Clinic Identity
| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| Clinic legal name | string, 1–100 chars | For invoices | — | Trim, no leading/trailing specials |
| Clinic display name | string, 1–60 chars | No | Inherits legal name | App-facing, less formal |
| Clinic type | enum | Yes | Solo practice | Solo / Group / Hospital-embedded / School-embedded / Telepractice-only / Mobile/home-based / Other |
| Year established | int | No | — | ≥1900, ≤ current year |
| Clinic logo | PNG/SVG, ≤2MB, transparent bg | No | — | Normalize to 240×80px. **Single logo** — Identity Block 5 logo becomes a read-only mirror of this |
| Clinic tagline | string, ≤80 chars | No | — | Parent portal Phase 2 only — never on PDFs |
### Block 2 — Address & Locations
| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| Address line 1 | string, 1–100 chars | For invoices | — | — |
| Address line 2 | string, 0–100 chars | No | — | — |
| Area/Locality | string, 1–50 chars | For invoices | — | Indian address convention |
| City | string, 1–50 chars | For invoices | — | — |
| State | enum (28 states + 8 UTs) | For invoices | — | Drives place-of-supply in Block 5 |
| Pincode | string, 6 digits | For invoices | — | Strict 6-digit numeric |
| Country | locked | — | India | Phase 1 India-only |
| Map pin (lat/long) | float pair | No | — | Phase 2 parent portal |
| Additional locations | array | — | — | **Deferred to Phase 2** — hidden in Phase 1 UI |
### Block 3 — Contact
| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| Clinic phone | string, Indian format | For invoices | — | +91 prefix optional; 10-digit core; **separate from SLP's personal phone** |
| Clinic email | string | For invoices | — | RFC-5322 format |
| WhatsApp Business number | string | No | — | Often differs from clinic phone in Indian practice; explicit field |
| Website | string, URL | No | — | https:// prefix auto-added if missing |
**Letterhead visibility** is governed by Identity Block 5 letterhead style enum (Full banner / Minimal text-only / None). No per-field "display on letterhead" toggles in Practice Setup — they were redundant atop the style enum.
### Block 4 — Practice Hours & Calendar
| Field | Type | Default | Notes |
|---|---|---|---|
| Working days | multi-select Mon–Sun | Mon–Sat | Indian SLP convention |
| Working hours per day | time-pair pickers | 09:00–18:00 | Per-day override allowed |
| Break/lunch block | time pair, optional | 13:00–14:00 | Single block per day |
| Time zone | locked | Asia/Kolkata | Phase 1 India-only |
| Holiday calendar source | enum | None | None / Indian national / Indian national + state. **Defaults to None** to avoid surprising auto-blocked dates |
| Custom holidays | date array | — | SLP add/remove. Subject to §2 array semantics |
### Block 5 — Receipt & Billing Defaults
Slim, non-GST. Indian SLPs are typically under GST threshold (₹20L turnover) and therapeutic services are healthcare-exempt anyway. Cue issues simple receipts, not tax invoices.
| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| Business display name | string, ≤60 chars | No | Inherits Block 1 clinic display name | Appears on receipts. Override only if billing entity differs from clinic display name |
| Default session fee | int (INR) | No | — | Auto-populates billing on session creation. Per-client override always available. (Moved from Clinical Defaults Block 4 — billing primitive, not clinical) |
| Receipt prefix | string, ≤10 chars | No | `CUE-` | Editable; warning banner if changed after receipts issued |
| Receipt numbering counter | int, read-only | — | 1 | System-incremented. **Never user-editable** (DB trigger enforces) |
| Financial year reset | toggle | — | ON | Resets counter on April 1 (Indian FY). Counter prefix becomes `FY26-27/0001` format |
### Cross-cutting (Practice Setup)
- **Letterhead header content (Identity Block 5)** sources clinic name + address + contact from this screen. The Block 5 stub `Add practice details to compose your letterhead →` routes here.
- **Single logo** lives in Block 1, mirrored read-only into Identity Block 5. Removes the v0.2 ambiguity where two logos could diverge — patches Block 5 logo field to read-only mirror.
- **Receipt counter** is the only Settings field that is system-incremented and never user-writeable. DB-level trigger blocks user UPDATE attempts.
- **No tax-invoice apparatus.** Cue Phase 1 issues receipts only, not GST tax invoices. Tax-registered SLPs (rare, typically high-volume group practices) generate compliant invoices outside Cue.
### Refused (Practice Setup-specific)
- GST tax invoices, GSTIN, PAN, HSN/SAC codes, place-of-supply (Indian SLPs are typically under GST threshold and healthcare-exempt; tax-invoice apparatus is over-engineering for Phase 1)
- Multi-currency (India-only Phase 1)
- Multi-branch hierarchical structure (use array, never separate entity)
- Staff/employee records (Phase 2 multi-clinician feature)
- Public "About Us" rich content (Phase 2 parent portal)
- Social media links
- Insurance provider integrations (no Indian SLP-market equivalent — defer indefinitely)
- Per-day staff scheduling (Phase 2)
---
## 5B. Screen 5 — Notifications
Routing layer for four legitimate signal flows: session-cycle nudges, clinical lifecycle alerts, credential & compliance reminders, operational signals. Three blocks.
### Block 1 — Channels
| Field | Type | Default | Notes |
|---|---|---|---|
| In-app inbox | always on | — | Cannot be disabled. All notifications land here regardless of other channels. Surfaces in Today view |
| Push notifications | toggle | ON | Browser/PWA push. Asks for browser permission on first enable |
| Email digest | toggle | OFF | Defaults OFF — Indian SLPs already manage email-heavy workflows. Sent to the SLP's primary contact email (single source; no separate digest email field) |
| SMS | — | — | **Deferred to Phase 2.** Hidden in Phase 1 UI |
| WhatsApp Business | — | — | **Deferred to Phase 2.** Hidden in Phase 1 UI |
### Block 2 — Per-category routing
For each signal flow, SLP chooses loudness. Enum per row: `Silent (inbox only) / In-app banner / Push / Push + email`. Email level requires Block 1 email digest toggle to be ON; greyed out otherwise.
| Signal flow | Default loudness | Notes |
|---|---|---|
| **Session-cycle nudges** | In-app banner | Pre-session brief ready (15 min before), session-end SOAP draft surfaced, missed-session follow-up, no-show flag |
| **Clinical lifecycle alerts** | Push | STG ready for mastery review, LTG approaching review date, client unseen for N weeks, mastery criterion hit but unconfirmed |
| **Credential & compliance** | Push | RCI renewal (60-day + 7-day per Identity Block 3), certification expiry (30-day per Identity Block 4), CRE credit cycle |
| **Operational signals** | In-app banner | Receipt issued, payment received, parent message arrived (Phase 2), AI edit-threshold breached (per AI Behavior Block 4) |
**Cross-cutting rule:** RCI 7-day renewal warning is **always Push regardless of this setting** — it gates signed-PDF generation, SLP must see it. Hardcoded override; flag in UI tooltip.
### Block 3 — Quiet hours & cadence
| Field | Type | Default | Notes |
|---|---|---|---|
| Do-not-disturb window | time pair | 21:00–07:00 | Push notifications held during this window. In-app inbox still receives them. Override for credential 7-day warnings |
| Working-days-only mode | toggle | ON | When ON, no push on non-working-days (sources Practice Setup Block 4 working days) |
| Digest frequency for non-urgent | enum | Daily 9 AM | Immediate / Hourly / Daily 9 AM / Weekly Monday 9 AM. Applies to email digest channel only |
| Critical-override exceptions | read-only badge list | — | These notifications bypass DND and working-days-only: `[Credential 7-day]` `[Payment received]`. **System-defined; not configurable.** |
### Cross-cutting (Notifications)
- **In-app inbox is the floor.** Every notification lands there. Other channels are amplifiers. SLP can mute amplifiers, never the inbox.
- **Per-client notification settings do not live here.** They live on the client card. This screen is account-level only.
- **No notification copy customization.** Cue owns the wording. SLPs can adjust *where* and *when*, never *what*.
- **Working-days source.** When Working-days-only mode is ON, this screen reads `slp_practice_setup.working_days`. Dependency: Practice Setup must exist for this toggle to be meaningful. If Practice Setup empty, default to Mon–Sat fallback.
### Refused (Notifications-specific)
- Flat per-event toggle list (overwhelming, performative)
- Custom notification sounds (vanity)
- Per-client notification settings on this screen (lives on client card)
- Email branding/template customization (Phase 2)
- Webhook/API forwarding (not for solo-clinician Phase 1)
- SMS in Phase 1 (Indian SLPs already drown in WhatsApp; SMS adds noise without absorbing existing work)
- Notification snooze beyond 24h (defeats the purpose of compliance reminders)
---
## 5C. Screen 6 — Privacy & Consent
First screen of the "What's protected" trunk. Covers two distinct data layers: the SLP as data principal (Cue is fiduciary over SLP's account data) and the SLP as data fiduciary (over client data they enter into Cue). DPDP-heavy by design.
Five blocks.
### Block 1 — My data rights (SLP as data principal)
| Field | Type | Default | Notes |
|---|---|---|---|
| Export my account data | action button | — | Generates full data archive (JSON + uploads). Email-delivered with download link, 7-day expiry. Audit-logged |
| Delete my account | action button | — | Two-step confirmation. Triggers 30-day grace period; permanent deletion at end. SLP can cancel any time during grace via (a) persistent in-app banner on every page, (b) email-linked cancellation URL sent at deletion request and again 7 days before scheduled deletion |
| Grievance officer contact | read-only | Cue grievance officer | DPDP-designated officer details, system-managed |
| Data principal nominee | string + email | — | DPDP §13 right to nominate someone to exercise rights after death/incapacity |
| Processing purposes summary | expandable read-only | — | What Cue does with SLP's data: clinical OS, billing, AI drafting, anonymized improvement |
### Block 2 — Client consent management (SLP as data fiduciary)
| Field | Type | Default | Notes |
|---|---|---|---|
| Default consent template | read-only mirror | — | Sourced from Clinical Defaults Block 5. Edit there |
| Consent renewal cadence | enum | Annual | None / Annual / Every 2 years / On change of treatment plan. Drives client-card renewal banner |
| Consent withdrawal workflow | enum | Pause + 30-day archive | Immediate hard-delete / Pause + 30-day archive / Pause + 90-day archive. Hard-delete honored but warned about clinical-defensibility loss |
| Minor consent (parents) | always on | — | Cue requires parent/guardian consent for any client under 18. Hardcoded. Cannot be disabled |
| Per-client consent log access | navigation link | — | Routes to per-client view, not configured in Settings |
### Block 3 — Data sharing with Cue
**Canonical home for sharing toggles.** AI Behavior Block 4's anonymized telemetry toggle is a read-only mirror of this block.
| Field | Type | Default | Notes |
|---|---|---|---|
| Anonymized edit telemetry | toggle | OFF | Helps Cue improve drafting. No client identifiers shared. Mirrored read-only into AI Behavior Block 4 |
| Crash reports and diagnostics | toggle | ON | Strict crash-only; no behavioral analytics. Stack trace + Cue version, never client data |
| Product update emails | toggle | OFF | Major releases + critical changes only |
| Engrams clinical content contribution | toggle | OFF (**Phase 2**) | Opt-in for SLP's edited notes to inform Engrams EBP research-translation corpus. Always anonymized, always per-document consent. Greyed in Phase 1 |
### Block 4 — Retention preferences
Resolves §9.7 with a sensible default. SLP-configurable.
| Field | Type | Default | Notes |
|---|---|---|---|
| Audit log retention | enum | 7 years | 1 / 3 / 7 / Indefinite. Indian medical record convention is 7y. **Reducing below 3y triggers confirmation dialog** |
| Soft-deleted client purge timeline | enum | 90 days | 30 / 90 / 180 days / Manual. After this, soft-deleted records hard-purge except where audit retention requires |
| Discharged client archive | enum | Indefinite | 1y / 3y / 7y / Indefinite. Indefinite default protects clinical defense; shortening triggers warning |
| Session note retention beyond discharge | enum | Inherits discharged client archive | Tied automatically; not separately configurable |
### Block 5 — Processing transparency (DPDP §5 disclosure)
System-managed transparency content. Not user-editable, but rendered conspicuously for DPDP compliance.
| Field | Type | Notes |
|---|---|---|
| Data processed by Cue | read-only expandable | Lists each data category: identity, clinical notes, AI drafts, billing, audit log |
| Sub-processors | read-only list | Anthropic (AI processing), Supabase (storage), Render (API proxy), Netlify (web hosting). Each row shows role + India-data-residency status |
| Data residency | read-only | "All client data stored in Supabase ap-south-1 (Mumbai). AI processing routes via Render proxy for latency; no client identifiers transmitted to Anthropic API" |
| DPDP rights notice | read-only expandable | Plain-language summary of SLP's DPDP §11–14 rights |
### Cross-cutting (Privacy & Consent)
- **Block 3 is the canonical sharing surface.** AI Behavior Block 4 telemetry toggle becomes a read-only mirror with link "Edit in Privacy & Consent →"
- **Block 4 retention preferences** drive cleanup jobs across `settings_audit_log`, soft-deleted client tables, and session note archives. Schema must include `retention_until` computed column or scheduled enforcement job.
- **Block 5 transparency content** is system-rendered. Sub-processor list changes are deployment-gated; any change creates an in-app inbox notification to all SLPs (consent re-acknowledgment surface, DPDP §6).
- **Account deletion grace period** is non-negotiable 30 days. Resists impulse deletion, allows recovery, matches DPDP §17 timelines.
### Refused (Privacy & Consent-specific)
- "Forget me everywhere" single button (Delete-my-account flow handles this with proper grace period and audit trail)
- Per-field consent (granular consent forms confuse parents; whole-record consent at intake is the right level)
- Opt-out toggles for individual sub-processors (Cue doesn't let you opt out of Supabase — that's where data lives; the choice is use-Cue or don't)
- Custom consent text per client (Clinical Defaults Block 5 templates with variable substitution does this work)
- Data portability format selection (default JSON sufficient; nobody maintains XML/CSV exports well)
- "Pause my account" as a separate flow (use Cancel Subscription in Billing screen instead)
---
## 5D. Screen 7 — Security
Auth-layer hardening. Cue owns enforcement policies (when 2FA is mandatory, what triggers re-auth, login alerts); Supabase Auth owns the credential primitives underneath.
Five blocks.
### Block 1 — Password
| Field | Type | Default | Notes |
|---|---|---|---|
| Change password | action button | — | Routes to Supabase Auth flow with current-password confirmation. Audit-logged |
| Last password change | read-only | — | Auto-populated from auth.users metadata |
| Password strength on last change | read-only indicator | — | Visual cue; no enforcement beyond Supabase Auth defaults |
**No forced password rotation.** NIST SP 800-63B explicitly recommends against periodic rotation; rotation typically reduces password strength as users adopt predictable variants. Strong-once + breach-triggered rotation is the modern stance.
### Block 2 — Two-factor authentication
| Field | Type | Default | Notes |
|---|---|---|---|
| 2FA status | read-only | Not configured | Not configured / TOTP enabled |
| Enable TOTP | action button | — | QR code + setup flow. Authenticator app (Authy, Google Authenticator, 1Password) |
| Recovery codes | action button | — | Generate / regenerate / download 10 single-use codes |
| Trusted device window | enum | 30 days | 7 / 30 / 90 days / Never. After trusting a device, skip 2FA prompts for the window |
| **Mandatory above 5 clients** | hardcoded policy | — | When SLP has 5+ active clients, 2FA enable is required. UI shows progress: "N of 5 clients — 2FA will be required at 5" |
### Block 3 — Active sessions & devices
| Field | Type | Notes |
|---|---|---|
| Active sessions list | read-only table | Columns: device + browser, IP, approximate location, last active. Current session marked |
| Sign out session | per-row action | Revokes a specific session token |
| Sign out all other sessions | action button | Revokes all sessions except current. One-tap defense if SLP suspects compromise |
| Trusted devices | read-only list | Devices currently within trusted-device window. SLP can revoke trust |
### Block 4 — Timeout & re-auth
| Field | Type | Default | Notes |
|---|---|---|---|
| Idle timeout | enum | 15 minutes | 5 / 15 / 30 / 60 minutes. **Medical-grade default is 15 min** per Cue clinical-OS spec |
| Force re-auth for sensitive actions | hardcoded list | — | Always on. List: data export, account deletion, password change, 2FA settings change, signed PDF generation, Identity Block 3 RCI edit, Privacy Block 1 nominee change |
| Remember me duration | enum | 7 days | Session only / 7 days / 30 days. Affects "stay signed in" checkbox on login |
### Block 5 — Login history & alerts
| Field | Type | Default | Notes |
|---|---|---|---|
| Login history | read-only table | — | Last N days based on Privacy Block 4 retention setting. Columns: timestamp, device, IP, location, success/failure |
| Export login history | action button | — | CSV download. Audit-logged |
| Alert on new device login | toggle | ON | Sends notification (per Notifications Block 2 credential & compliance loudness) when login from unrecognized device |
| Alert on new geographic location | toggle | ON | Coarse city-level. False positives possible (VPN, travel); notification not blocking |
| Failed login attempts (read-only) | read-only counter | — | Last 24h count. After 5 failures, account locks for 15 min; SLP can request unlock via password reset |
### Cross-cutting (Security)
- **Re-auth gate is non-configurable.** The sensitive-actions list in Block 4 is hardcoded, not user-editable. Adding to or removing from the list requires a deliberate code change. Listed in UI for transparency, not for configuration.
- **2FA mandatory threshold (5 clients)** is hardcoded policy, not a setting. UI surfaces it as inevitable, not negotiable.
- **Login history retention** sources from Privacy Block 4 audit retention preference. Same default, same SLP-configurable bounds.
- **No password complexity customization.** Supabase Auth defaults apply (8+ chars, mix of categories). Custom rules are security theater that often weaken passwords (e.g., forcing one digit produces "Password1" patterns).
### Refused (Security-specific)
- Custom password complexity rules (security theater; Supabase Auth defaults are sufficient)
- IP allow-list / deny-list (over-engineering for solo clinician Phase 1; legitimate use case is roaming SLPs in Indian semi-urban contexts where IPs shift)
- API keys / personal access tokens (Phase 2 when integrations land)
- Single sign-on / SAML (Phase 2 enterprise — irrelevant for solo SLPs)
- Biometric authentication settings (delegated to OS/browser layer, not Cue's responsibility)
- Hardware security key (FIDO2) (Phase 2 — overkill for typical Indian SLP infrastructure)
- "Login from any device" master toggle (defeats the security model)
---
## 5E. Screen 8 — Audit Log
The forensic read surface. Privacy & Consent Block 4 controls retention; this screen exposes the data. Read-mostly screen — almost no writes happen here except export requests and filter saves.
Three blocks (lighter than other screens — this is a viewer, not a configurator).
### Block 1 — Activity feed
| Field | Type | Notes |
|---|---|---|
| Feed view | virtualized list, reverse chronological | Renders `settings_audit_log` + critical event types from other audit streams (logins, signed PDFs, exports, deletions) |
| Row layout | timestamp · actor · action · object | Example: `13 May 2026, 14:32 · You · edited · Legal first name in Identity` |
| PII decryption | on-demand per row | PII-flagged rows show "🔒 Encrypted change — tap to view". Tap triggers re-auth (per Security Block 4 sensitive-actions list) and decrypts via `decrypt_pii()` |
| Cohort grouping | always on | Consecutive edits to same record within 5 min collapse into single expandable group. Not configurable — there is no scenario where ungrouped per-blur events are more useful than grouped |
| Diff view | per-row expansion | Shows prev → new for short fields; "file changed (hash differs)" for uploads |
| Retention indicator | inline banner | "Showing N events from last X years (per Privacy & Consent Block 4 retention setting)" |
### Block 2 — Filters
| Field | Type | Default | Notes |
|---|---|---|---|
| Date range | preset + custom | Last 30 days | Today / 7 days / 30 days / 90 days / 1 year / All / Custom |
| Event category | multi-select | All | Settings edits / Logins / Signed PDFs / Data exports / Deletions / Client record access / AI generations |
| Severity | multi-select | All | Routine / Significant / Critical (system-classified, not user-tagged) |
| Search | full-text | — | Searches plaintext fields only. PII-encrypted fields excluded from search index (compliance) |
| Save filter | action button | — | Named saved filters appear as chips at top of screen. Max 5 saved filters |
### Block 3 — Export & forensic actions
| Field | Type | Notes |
|---|---|---|
| Export current view | action button | CSV or JSON. Re-auth required (sensitive action). Decrypts PII fields server-side using a one-shot decrypt context. Export itself audit-logged |
| Export full audit history | action button | Generates archive with full retention-window data. 24h preparation, email-delivered, 7-day download window. Audit-logged twice (request + download) |
| Report suspicious activity | action button | Opens grievance-officer-routed report. Pre-fills with selected event IDs |
| Verify chain integrity | action button | Computes hash chain over audit entries to detect tampering. Output: "✓ No anomalies in N entries" or specific row IDs that fail. **System-internal feature; admins can run for SLP if requested** |
### Cross-cutting (Audit Log)
- **Read-mostly screen.** Only writes are: save filter (stores filter definition), export request (creates `data_export_requests` row), suspicious activity report (creates grievance ticket). Filter saves are not themselves audit-logged (preferences, not clinical events). Exports are audit-logged.
- **PII decryption is gated.** No bulk decrypt. Each PII-flagged row decrypts on individual tap with re-auth. Bulk export decryption happens server-side in a single privileged context, never streamed plaintext to the browser.
- **Search excludes encrypted fields.** Searching `settings_audit_log` only matches plaintext fields. Searching by legal name (encrypted) returns no results — by design. SLP must filter by date/category and visually scan, or request a full export for offline forensic search.
- **Hash chain integrity** is a nice-to-have for Phase 1 (the table exists, hashes can be appended), full verification UI is Phase 1.5+. Schema-ready, UI deferred.
- **Settings audit log + clinical event log are unified in this view** but live in separate tables (`settings_audit_log` already exists; clinical event log is a separate stream Cue will build for client-record access tracking).
### Refused (Audit Log-specific)
- User-editable event categorization (system owns severity classification; user-tagging corrupts forensic value)
- Bulk PII reveal (defeats the encryption purpose)
- Real-time push notifications for audit events (overwhelming; alerts surface via Security Block 5 for security-relevant subset only)
- Per-event annotations / comments (clinical record, not audit log, is the right place for SLP notes)
- Audit log deletion by user (DPDP-incompatible; retention policy in Privacy Block 4 is the only deletion lever)
- "Hide my edits from audit log" toggle (defeats the entire purpose)
- Compare-with-another-SLP view (Phase 2 multi-clinician only)
---
## 5F. Screen 9 — Billing
The SLP's relationship with Cue as a paying customer. Separate from Practice Setup Block 5 (which configures *how the SLP bills clients*). This screen is *how Cue bills the SLP*.
Phase 1 plan structure per memory: Clinician Basic ₹999/mo, Clinician Pro ₹1,499/mo (Pro emerges Year 1 tied to Cue Sense hardware layer). Founding Clinician beta rate ₹999/mo locked for first cohort.
Four blocks.
### Block 1 — Current plan
| Field | Type | Notes |
|---|---|---|
| Plan tier | read-only | Founding Clinician / Clinician Basic / Clinician Pro / Trial |
| Plan price | read-only | ₹999/mo or ₹1,499/mo. Founding Clinician shows "₹999/mo · locked for life" |
| Billing cycle | read-only | Monthly / Annual. Annual shows 2-month discount where applicable |
| Next renewal date | read-only | Auto-populated from payment processor |
| Plan started | read-only | First payment date |
| Upgrade plan | action button | Routes to plan comparison + checkout. Grey when SLP is on Founding Clinician (no upgrade path during beta) |
| Downgrade plan | action button | Confirmation: "Downgrading takes effect at next renewal. Features X, Y disabled then." |
| Cancel subscription | action button | Routes to retention flow → confirmation. Becomes "Reactivate" if cancellation pending |
### Block 2 — Payment method
| Field | Type | Default | Notes |
|---|---|---|---|
| Primary payment method | read-only summary | — | "UPI · abc@oksbi" or "Card · **** 4242, exp 12/27". **Never display full card number, full UPI ID, or CVV anywhere** |
| Update payment method | action button | — | Routes to Razorpay-hosted update flow. Cue never handles raw card data |
| Auto-renew | toggle | ON | When OFF, SLP gets renewal email 7 days before lapse instead of auto-charge |
| Failed payment policy | read-only | — | "After failed payment: 3-day grace period, then read-only access for 7 days, then account paused. Reactivate any time with new payment method." |
### Block 3 — Invoices & receipts (from Cue to the SLP)
> **⚠ Schema gate (B5 carry-forward):** Cue's GST registration status must be verified by Guru's CA before this block's invoice schema locks. Open questions: (1) Is Cue Pvt Ltd GST-registered? (2) Does SaaS-at-18% apply? Until verified, "GST-compliant format" claim below is provisional.
| Field | Type | Notes |
|---|---|---|
| Invoice history | virtualized list | Reverse chronological. Columns: date · plan · amount · status (paid/failed/refunded) · download |
| Download invoice | per-row action | PDF download. Cue generates invoices in GST-compliant format (Cue itself charges GST; the SLP doesn't, per Practice Setup decision). **Pending B5 verification** |
| Billing email | string | Where invoices are sent. Defaults to SLP's primary contact email; editable |
| GSTIN for input credit (optional) | string, ≤15 chars | If SLP has their own GSTIN and wants Cue invoices to carry it for input tax credit. **Optional, defaults empty.** Lenient format validation only. Distinct from Practice Setup decision to refuse GST apparatus for SLP→client receipts — this is Cue→SLP direction |
| Annual statement | action button | **Phase 1.5+** — generates fiscal-year summary PDF for SLP's accountant. Requires ≥1 year of billing data; not Phase 1 |
### Block 4 — Usage & limits
Phase 1 has minimal plan limits (single SLP, unlimited clients, unlimited AI within fair use). This block surfaces usage transparently rather than enforcing caps. **Clinical-operational counters (active clients, sessions, signed PDFs) belong on the Today view or clinical dashboard, not here.**
| Field | Type | Notes |
|---|---|---|
| AI generations this month | read-only counter | Pre-session briefs + autodrafts + parent summaries. **Fair-use policy: no hard cap Phase 1**, but surface usage so SLP sees the trajectory |
| Storage used | read-only progress bar | Out of plan storage limit (e.g., 5GB for Basic, 25GB for Pro) |
| Usage history | small inline chart | Last 12 months of AI generations, sparkline-style |
| Fair-use status | read-only banner | Green / yellow / red. Yellow triggers email notice; red triggers conversation, never auto-block |
### Cross-cutting (Billing)
- **Practice Setup Block 5 is the SLP→client billing surface. This screen is the Cue→SLP billing surface.** Different directions, never conflated.
- **No raw payment data in Cue's database.** Razorpay (or equivalent processor) handles all card/UPI primitives. Cue stores only: processor reference token, last-4 / UPI-handle-fragment for display, expiry month for cards. Updates always route to processor-hosted flow.
- **Founding Clinician status is permanent.** Once locked at ₹999/mo, it stays. Even if SLP cancels and reactivates within the beta window, Founding pricing should persist.
- **Cancellation creates a `subscription_cancellation_requests` row, not an immediate state change.** Cancellation takes effect at end of current billing period. SLP can rescind before that date. Forced-immediate cancel exists as separate "End service now" action with stronger confirmation, but pro-rated refund logic deferred to Phase 2.
- **Fair-use enforcement is conversational, never automatic.** A red-banner SLP gets a human conversation about their usage pattern. Cue Phase 1 does not throttle, lock, or rate-limit AI for paying clinicians. This is a deliberate trust signal.
### Refused (Billing-specific)
- Multiple payment methods queue (one primary + one backup is sufficient; more is over-engineering)
- Per-feature add-on purchases (plan tiers are the only commerce surface Phase 1)
- Gift subscriptions / referral commerce (Phase 2 once viral mechanics matter)
- Pre-paid credits / wallet model (subscription model is locked; credits add accounting complexity)
- Plan customization (configurable plans destroy the pricing surface; plans are products, not sliders)
- Visible processor name customization ("Powered by X" branding stays Cue-controlled)
- Currency switching (India-only Phase 1)
- Manual invoice generation by SLP for Cue charges (system-generated only)
- Hard usage caps in Phase 1 (fair-use conversation is the policy)
---
## 5G. Screen 10 — Legal & Help
The terminal screen of the "What's protected" trunk. Mostly static content with light interactive surfaces. Three blocks.
### Block 1 — Legal documents
| Field | Type | Notes |
|---|---|---|
| Beta Access Agreement | read-only document viewer + version | The 9-clause BAA. Shows version, acceptance date, full text. Re-acceptance flow triggers if Cue ever updates BAA |
| Terms of Service | read-only document viewer + version | Same pattern as BAA |
| Privacy Policy | read-only document viewer + version | DPDP-compliant. Sub-processor list mirrors Privacy & Consent Block 5 |
| DPDP rights notice | read-only expandable | Plain-language summary. Mirror of Privacy Block 5 content (single source — this is the read-only view from the legal-document angle) |
| Cookie policy | read-only | Cue web app uses essential cookies only. No tracking, no analytics cookies. One-paragraph statement |
| Acceptance history | read-only table | Date · document · version. Audit-logged. Each row is a tap-to-view-as-it-was-then |
### Block 2 — Help & support
| Field | Type | Notes |
|---|---|---|
| Contact support | action button | Opens email composer to support@cue (or in-app chat if Phase 2). Pre-fills with Cue version + SLP ID + browser info (collected client-side, never stored without consent) |
| Report a clinical concern | action button | One-tap escalation if Cue ever generates output that worries the SLP. **Mirrored from AI Behavior Block 5.** Routes to support + product team. Always available |
| Report a bug | action button | Pre-fills with system info; SLP describes issue. Optional screenshot attach |
| Suggest a feature | action button | Free-form. Feeds product-feedback channel |
| Knowledge base | external link | Routes to Cue docs. Opens in new tab |
| Engrams research-translation library | external link | The Engrams site. SLP-facing EBP resources |
### Block 3 — About Cue
| Field | Type | Notes |
|---|---|---|
| App version | read-only | Semantic version + build hash + release date. Tap to copy (useful when reporting bugs) |
| Release notes | action button | Routes to changelog. Newest releases first |
| Open source acknowledgments | action button | Routes to dependency licenses page. Includes Flutter packages, Supabase libs, Anthropic SDK acknowledgments |
| Built by | read-only | "Cue is built by Guru and team in Hyderabad." Short, non-marketing |
| Cue Clinic / The Engrams | read-only links | Companion ventures. Outbound links open in new tab |
### Cross-cutting (Legal & Help)
- **Legal documents are versioned and immutable.** Each version's full text is preserved. Acceptance records timestamp + version pair. If Cue ever updates a legal document, all SLPs receive a re-acceptance flow at next login; previous acceptances remain valid for previous versions' coverage periods (DPDP §6 lawful processing trail).
- **"Report a clinical concern" lives in both AI Behavior Block 5 and Legal & Help Block 2.** This is deliberate redundancy — a worried SLP shouldn't have to remember where the button is. Both routes call the same escalation endpoint.
- **No marketing content on this screen.** "About Cue" is informational, not promotional. The product law of refusing performative labor extends to refusing performative branding inside the product itself.
- **External links open in new tabs.** Settings is a working surface; users navigating away should be deliberate, not accidental.
### Refused (Legal & Help-specific)
- In-app product news feed (newsletter via email is opt-in; in-app feed is attention extraction)
- Promotional banners ("Try Cue Pro!" inside Settings is anti-pattern)
- SLP-facing analytics dashboard ("you logged in X times!" / "your most-used feature is Y") — gamification without clinical value
- Referral program inside Legal & Help (belongs in Billing if at all; Phase 2)
- Social media share buttons (off-brand for clinical software)
- Live chat widget (Phase 2 if support volume justifies)
- Self-serve refund initiation (handled in Billing, not duplicated here)
- Comparison with other clinical software (off-brand, off-purpose)
- Testimonials or case studies (marketing surface, not in-app)
---
## 6. Supabase Schema Sketch
```sql
-- ========================================
-- PRE-REQUISITE: Run before this migration
-- ========================================
-- create extension if not exists pgcrypto;
-- Set Postgres setting app.pii_key = current_setting('PII_ENCRYPTION_KEY')
-- (Supabase env var injected per-session via application layer)
-- ========================================
-- Helper functions for PII encryption
-- ========================================
create or replace function encrypt_pii(plaintext text)
returns text language sql as $$
  select encode(pgp_sym_encrypt(plaintext, current_setting('app.pii_key')), 'base64')
$$;
create or replace function decrypt_pii(ciphertext text)
returns text language sql as $$
  select pgp_sym_decrypt(decode(ciphertext, 'base64'), current_setting('app.pii_key'))
$$;
-- ========================================
-- Foreign-key cascade behavior (v0.4 addition per C2)
-- ========================================
-- CASCADE on slp_id delete: all single-row preference tables
--   slp_clinical_defaults, slp_ai_preferences, slp_notification_preferences,
--   slp_privacy_preferences, slp_security_preferences, slp_practice_setup,
--   slp_signature_letterhead, slp_rci_registration, slp_subscription,
--   slp_usage_counters, security_failed_attempts
-- CASCADE on slp_id delete: all array tables
--   slp_qualifications, slp_certifications, slp_templates,
--   security_trusted_devices, audit_log_saved_filters
-- NO CASCADE (retain history independent of account deletion):
--   settings_audit_log, signed_document_snapshots, clinical_event_log,
--   security_login_history, cue_invoices, data_export_requests,
--   account_deletion_requests, subscription_cancellation_requests,
--   slp_legal_acceptances, support_tickets, notification_inbox
-- Apply `on delete cascade` or omit it explicitly per the above when DDL is generated.
-- ========================================
-- Identity blocks 1-2
-- ========================================
create table slp_profiles (
  id uuid primary key references auth.users(id),
  display_name text,
  profile_photo_url text,
  legal_first_name text,
  legal_middle_name text,
  legal_last_name text,
  salutation text,
  designation text,
  degree_suffix_override text,
  primary_contact_email text,  -- single source for all comms; defaults to auth.users.email
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
-- Identity block 3
create table slp_rci_registration (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  rci_category text,
  rci_number text,
  date_of_registration date,
  renewal_due_date date,
  certificate_url text,
  certificate_hash text,  -- sha256 for audit
  updated_at timestamptz default now()
);
-- Identity block 4 — arrays with soft-delete + status
create table slp_qualifications (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  is_primary boolean default false,
  status text default 'draft',  -- 'draft' | 'active'
  degree text,
  institution text,
  year_of_completion int,
  deleted_at timestamptz,
  created_at timestamptz default now()
);
create table slp_certifications (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  status text default 'draft',  -- 'draft' | 'active'
  cert_type text,
  cert_level text,
  date_earned date,
  expiry date,
  certificate_url text,
  certificate_hash text,
  deleted_at timestamptz,
  created_at timestamptz default now()
);
-- Identity block 5
create table slp_signature_letterhead (
  slp_id uuid primary key references slp_profiles(id),
  signature_mode text default 'none',
  signature_svg text,
  signature_png_url text,
  signature_hash text,
  auto_attach_signature boolean default true,
  render_printed_name boolean default true,
  letterhead_style text default 'minimal',
  -- Logo is NOT stored here — single source of truth in slp_practice_setup.clinic_logo_url
  footer_disclaimer text,
  show_rci_on_letterhead boolean default true,
  updated_at timestamptz default now()
);
-- ========================================
-- Practice Setup (Screen 4)
-- ========================================
create table slp_practice_setup (
  slp_id uuid primary key references slp_profiles(id),
  -- Block 1 Clinic Identity
  clinic_legal_name text,
  clinic_display_name text,
  clinic_type text default 'solo',
  year_established int,
  clinic_logo_url text,
  clinic_logo_hash text,
  clinic_tagline text,
  -- Block 2 Address
  address_line1 text,
  address_line2 text,
  area text,
  city text,
  state text,
  pincode text,
  country text default 'IN',
  map_lat numeric,
  map_lng numeric,
  -- (display_address_letterhead + display_contact_letterhead removed in v0.4: governed by Identity Block 5 letterhead style enum)
  -- Block 3 Contact
  clinic_phone text,
  clinic_email text,
  whatsapp_business text,
  website text,
  -- Block 4 Hours
  working_days jsonb default '["mon","tue","wed","thu","fri","sat"]',
  working_hours jsonb default '{"start":"09:00","end":"18:00","break_start":"13:00","break_end":"14:00"}',
  time_zone text default 'Asia/Kolkata',
  holiday_calendar_source text default 'none',
  custom_holidays jsonb default '[]',
  -- Block 5 Receipt & Billing (slim, non-GST)
  business_display_name text,
  default_session_fee int,  -- INR; moved from slp_clinical_defaults in v0.4 (billing primitive, not clinical)
  receipt_prefix text default 'CUE-',
  receipt_counter int default 1,
  fy_reset_enabled boolean default true,
  updated_at timestamptz default now()
);
-- Block receipt_counter from user UPDATE (only system increment allowed)
create or replace function block_receipt_counter_update()
returns trigger language plpgsql as $$
begin
  if NEW.receipt_counter != OLD.receipt_counter
     and current_setting('app.role', true) != 'system' then
    raise exception 'receipt_counter is system-managed and cannot be user-edited';
  end if;
  return NEW;
end;
$$;
create trigger trg_block_receipt_counter
  before update on slp_practice_setup
  for each row execute function block_receipt_counter_update();
-- ========================================
-- Notifications (Screen 5)
-- ========================================
create table slp_notification_preferences (
  slp_id uuid primary key references slp_profiles(id),
  -- Block 1 Channels
  push_enabled boolean default true,
  email_digest_enabled boolean default false,
  -- digest_email removed in v0.4 — uses slp_profiles.primary_contact_email
  -- Block 2 Per-category routing
  -- enum: 'silent' | 'in_app' | 'push' | 'push_email'
  session_cycle_loudness text default 'in_app',
  clinical_lifecycle_loudness text default 'push',
  credential_compliance_loudness text default 'push',
  operational_loudness text default 'in_app',
  -- Block 3 Quiet hours
  dnd_start time default '21:00',
  dnd_end time default '07:00',
  working_days_only boolean default true,
  digest_frequency text default 'daily_9am',  -- 'immediate' | 'hourly' | 'daily_9am' | 'weekly_mon_9am'
  updated_at timestamptz default now()
);
-- In-app notification inbox (always-on storage, regardless of channel prefs)
create table notification_inbox (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  category text,  -- 'session_cycle' | 'clinical_lifecycle' | 'credential_compliance' | 'operational'
  subcategory text,  -- e.g. 'rci_renewal_7day', 'stg_mastery_ready', 'receipt_issued'
  payload jsonb,  -- event-specific data; renderer resolves to copy
  is_critical_override boolean default false,  -- bypasses DND + working-days-only
  read_at timestamptz,
  created_at timestamptz default now()
);
create index idx_inbox_slp_unread on notification_inbox (slp_id, created_at desc) where read_at is null;
create index idx_inbox_slp_all on notification_inbox (slp_id, created_at desc);
-- ========================================
-- Privacy & Consent (Screen 6)
-- ========================================
create table slp_privacy_preferences (
  slp_id uuid primary key references slp_profiles(id),
  -- Block 1 SLP data rights
  data_principal_nominee_name text,
  data_principal_nominee_email text,
  -- Block 2 Client consent
  consent_renewal_cadence text default 'annual',
  consent_withdrawal_workflow text default 'pause_30day',
  -- Block 3 Data sharing (canonical home)
  share_anonymized_telemetry boolean default false,
  share_crash_reports boolean default true,
  product_update_emails boolean default false,
  -- marketing_emails removed in v0.4 — no marketing email infra exists
  engrams_contribution boolean default false,
  -- Block 4 Retention
  audit_log_retention_years int default 7,
  soft_delete_purge_days int default 90,
  discharged_client_archive_years int default 0,  -- 0 = indefinite
  updated_at timestamptz default now()
);
create table data_export_requests (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  status text default 'pending',  -- 'pending' | 'processing' | 'ready' | 'expired' | 'downloaded'
  archive_url text,
  expires_at timestamptz,
  requested_at timestamptz default now(),
  ready_at timestamptz
);
create table account_deletion_requests (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  status text default 'grace_period',  -- 'grace_period' | 'cancelled' | 'executing' | 'completed'
  scheduled_deletion_at timestamptz,  -- requested_at + 30 days
  cancellation_token text,
  requested_at timestamptz default now()
);
-- ========================================
-- Security (Screen 7)
-- ========================================
create table slp_security_preferences (
  slp_id uuid primary key references slp_profiles(id),
  -- (force_password_change_days removed in v0.4 — security theater per NIST SP 800-63B)
  -- Block 2
  totp_enabled boolean default false,
  totp_secret_encrypted text,  -- pgp_sym_encrypt
  recovery_codes_hash jsonb,   -- array of sha256 hashes; consumed on use
  trusted_device_window_days int default 30,
  -- Block 4
  idle_timeout_minutes int default 15,
  remember_me_duration text default '7_days',  -- 'session' | '7_days' | '30_days'
  -- Block 5
  alert_new_device boolean default true,
  alert_new_location boolean default true,
  updated_at timestamptz default now()
);
create table security_trusted_devices (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  device_fingerprint text,
  device_label text,  -- "MacBook · Chrome · Hyderabad"
  trusted_until timestamptz,
  created_at timestamptz default now(),
  revoked_at timestamptz
);
create index idx_trusted_active on security_trusted_devices (slp_id, trusted_until) where revoked_at is null;
create table security_login_history (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  attempted_at timestamptz default now(),
  success boolean,
  ip text,
  city text,
  country text,
  device_label text,
  failure_reason text  -- 'invalid_password' | 'locked' | '2fa_failed' | etc.
);
create index idx_login_history_slp on security_login_history (slp_id, attempted_at desc);
create table security_failed_attempts (
  slp_id uuid primary key references slp_profiles(id),
  attempts_24h int default 0,
  window_started_at timestamptz default now(),
  locked_until timestamptz
);
-- ========================================
-- Audit Log (Screen 8)
-- ========================================
-- Extend settings_audit_log with severity + chain hash for forensic integrity
alter table settings_audit_log
  add column if not exists severity text default 'routine',  -- 'routine' | 'significant' | 'critical'
  add column if not exists chain_hash text;  -- sha256(prev_chain_hash || row_content) for tamper detection
create index idx_audit_severity on settings_audit_log (slp_id, severity, changed_at desc);
-- Clinical event log (separate from settings_audit_log; tracks client-record access + AI generations)
create table clinical_event_log (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  event_type text,  -- 'client_record_viewed' | 'signed_pdf_generated' | 'ai_draft_generated' | 'session_completed' | 'client_discharged'
  client_id uuid,
  document_id uuid,
  severity text default 'routine',
  metadata jsonb,
  occurred_at timestamptz default now(),
  chain_hash text
);
create index idx_clinical_event_slp on clinical_event_log (slp_id, occurred_at desc);
create index idx_clinical_event_client on clinical_event_log (client_id, occurred_at desc);
-- Saved filters for audit log view
create table audit_log_saved_filters (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  filter_name text,
  filter_definition jsonb,  -- {date_range, categories, severity, search}
  created_at timestamptz default now()
);
-- Login event audit — already exists as security_login_history; the audit log UI reads from it for unified view
-- ========================================
-- Billing (Screen 9)
-- ========================================
create table slp_subscription (
  slp_id uuid primary key references slp_profiles(id),
  plan_tier text default 'trial',  -- 'trial' | 'founding' | 'basic' | 'pro'
  plan_price_inr int,
  billing_cycle text default 'monthly',  -- 'monthly' | 'annual'
  is_founding_locked boolean default false,
  current_period_start timestamptz,
  current_period_end timestamptz,
  auto_renew boolean default true,
  -- Razorpay (or processor) references
  processor_customer_id_encrypted text,  -- pgp_sym_encrypt — high-sensitivity per v0.4 C3 threat-model decision
  processor_subscription_id text,
  primary_payment_method_display text,  -- "UPI · abc@oksbi" or "Card · **** 4242, exp 12/27"
  -- backup_payment_method_display removed in v0.4 — multi-method backup is processor-level work, not Cue's
  billing_email text,
  slp_gstin text,  -- optional, for input credit on Cue invoices
  status text default 'active',  -- 'active' | 'past_due' | 'grace' | 'read_only' | 'paused' | 'cancelled'
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create table cue_invoices (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  invoice_number text unique,
  invoice_date date,
  plan_tier text,
  amount_inr int,
  gst_amount_inr int,
  total_inr int,
  status text,  -- 'paid' | 'failed' | 'refunded' | 'pending'
  processor_invoice_id text,
  pdf_url text,
  created_at timestamptz default now()
);
create index idx_cue_invoices_slp on cue_invoices (slp_id, invoice_date desc);
create table subscription_cancellation_requests (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  requested_at timestamptz default now(),
  effective_at timestamptz,  -- end of current billing period
  rescinded_at timestamptz,
  reason text,
  status text default 'pending'  -- 'pending' | 'rescinded' | 'completed'
);
create table slp_usage_counters (
  slp_id uuid references slp_profiles(id),
  period_start date,
  active_clients int default 0,
  total_sessions int default 0,
  ai_generations int default 0,
  signed_pdfs int default 0,
  storage_bytes bigint default 0,
  primary key (slp_id, period_start)
);
create index idx_usage_counters on slp_usage_counters (slp_id, period_start desc);
-- ========================================
-- Legal & Help (Screen 10)
-- ========================================
create table legal_documents (
  id uuid primary key,
  doc_type text,  -- 'baa' | 'tos' | 'privacy' | 'cookie' | 'dpdp_notice'
  version text,
  content text,  -- full markdown / rich text
  effective_from timestamptz,
  effective_until timestamptz,  -- null if current
  created_at timestamptz default now()
);
create index idx_legal_current on legal_documents (doc_type, effective_from desc) where effective_until is null;
create table slp_legal_acceptances (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  doc_type text,
  doc_version text,
  accepted_at timestamptz default now(),
  ip text,
  user_agent text
);
create index idx_slp_acceptances on slp_legal_acceptances (slp_id, accepted_at desc);
create table support_tickets (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  category text,  -- 'support' | 'clinical_concern' | 'bug' | 'feature_request'
  subject text,
  body text,
  system_info jsonb,  -- cue version, browser, OS (collected with consent)
  status text default 'open',
  priority text default 'normal',  -- clinical_concern auto-escalates to 'high'
  created_at timestamptz default now(),
  resolved_at timestamptz
);
create index idx_support_tickets_slp on support_tickets (slp_id, created_at desc);
create index idx_support_tickets_open on support_tickets (status, priority, created_at desc) where status = 'open';
-- ========================================
-- Clinical defaults
-- ========================================
create table slp_clinical_defaults (
  slp_id uuid primary key references slp_profiles(id),
  primary_language text default 'en',
  parent_summary_languages jsonb default '["en"]',
  report_formality text default 'warm_clinical',
  reading_level text default 'grade_8',
  note_format text default 'soap',
  section_ordering jsonb default '["S","O","A","P"]',
  pre_session_brief_enabled boolean default true,
  auto_include_previous_summary boolean default true,
  goal_hierarchy_depth text default 'ltg_stg',
  default_ebp_frameworks jsonb default '["NDBI","ImPACT"]',
  default_mastery_criterion text default '80_3',
  auto_suggest_next_stg boolean default false,
  default_session_duration int default 45,
  default_session_type text default 'direct_intervention',
  default_attendance text default 'in_person',
  updated_at timestamptz default now()
);
-- v0.4 cuts from slp_clinical_defaults: required_sections (locked to S+A+P in app layer), stg_cap_per_ltg (locked to 3, override at Goal Authoring time), default_session_fee (moved to slp_practice_setup), show_session_timer (always-on Phase 1.5 feature), auto_prompt_soap (collapsed into autodraft_soap)
-- Templates (array with soft-delete)
create table slp_templates (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  template_type text,  -- 'intake' | 'consent' | 'parent_summary' | 'discharge'
  content text,
  language text,
  is_default boolean default false,
  deleted_at timestamptz,
  updated_at timestamptz default now()
);
-- ========================================
-- AI behavior
-- ========================================
create table slp_ai_preferences (
  slp_id uuid primary key references slp_profiles(id),
  autodraft_soap boolean default true,
  autodraft_parent_summary boolean default true,
  autodraft_goals boolean default false,
  autodraft_session_brief boolean default true,
  autodraft_scope text default 'current_session',
  parent_summary_tone text default 'warm_clinical',
  note_tone text default 'clinical',
  terminology_use text default 'mixed',
  voice_clone_enabled boolean default false,
  voice_clone_session_count int default 0,
  ebp_retrieval_source jsonb default '["engrams","peer_reviewed"]',
  surface_contradicting_evidence boolean default true,
  edit_threshold_pct int default 25,
  show_edit_ratio boolean default false,
  share_anonymized_telemetry boolean default false,
  parent_pdf_attribution text default 'footer',  -- 'footer' | 'inline' | 'both' (never 'none')
  internal_note_attribution text default 'inline',
  custom_disclaimer text,
  updated_at timestamptz default now()
);
-- v0.4 cuts from slp_ai_preferences: sentence_length (subsumed by reading_level in slp_clinical_defaults), edit_feedback_prompt (Phase 1.5+ research instrumentation)
-- ========================================
-- Audit log — with PII encryption
-- ========================================
create table settings_audit_log (
  id uuid primary key,
  slp_id uuid references slp_profiles(id),
  table_name text,
  field_name text,
  prev_value text,  -- base64-encoded ciphertext if is_pii=true, else plaintext
  new_value text,   -- same as above
  is_pii boolean default false,
  changed_at timestamptz default now()
);
create index idx_audit_slp_changed on settings_audit_log (slp_id, changed_at desc);
-- ========================================
-- Signed document snapshots (immutability)
-- ========================================
create table signed_document_snapshots (
  id uuid primary key,
  document_id uuid,
  slp_id uuid references slp_profiles(id),
  identity_snapshot jsonb,  -- full Block 1-5 state at sign time
  ai_preferences_snapshot jsonb,
  signed_at timestamptz default now()
);
create index idx_snapshot_doc on signed_document_snapshots (document_id);
```
### Application-layer notes for schema use
- **Setting `app.pii_key` per session:** Before any encrypted query, application calls `select set_config('app.pii_key', '<env_var>', false);`. Supabase client wrapper should do this on connection init.
- **Writing PII audit entries:**
  ```sql
  insert into settings_audit_log
    (slp_id, table_name, field_name, prev_value, new_value, is_pii)
  values
    ($1, 'slp_profiles', 'legal_first_name',
     encrypt_pii($2), encrypt_pii($3), true);
  ```
- **Reading PII for forensic queries:** Privileged path only. `select decrypt_pii(prev_value), decrypt_pii(new_value) from settings_audit_log where ...`
- **Soft-delete queries:** Every read query against `slp_qualifications`, `slp_certifications`, `slp_templates` must include `where deleted_at is null`. Add as default through application-layer query helpers.
---
## 7. Refused — Do NOT Build
These were considered and rejected. Do not add them back without a written design rationale:
- Theme toggles, font size sliders (do dark mode at OS level; accessibility done properly is not a "setting")
- AI personality sliders (gimmicky, violates clinical seriousness)
- User-editable certification taxonomy or framework vocabulary (governed by `CLAUDE.md`, not user-editable)
- Integrations buried in Settings (Cue Sense pairing, calendar sync, etc. — these belong in dedicated flows, not Settings)
- "About me" bio (performative; if needed, lives on a public profile screen)
- Auto-calculated years of experience (linear math is wrong half the time and patronizing the other half)
- Bank details on identity screen (belongs in Phase 2 billing flow)
- Linked social media (off-brand, off-purpose)
- Empty placeholder screens for Phase 2/3 features (Cue Sense, Cue Living) — better to have no screen than a "Coming soon" tile
- Soft warnings on professional designation enum (RCI gate does the filtering work at the artifact boundary; redundant friction on configuration screens is paternalistic)
- "None" option on parent-shared PDF AI attribution (fact of AI involvement is mandatory disclosure; only the wording is editable)
---
## 8. Phase Markers
- **Phase 1 (now):** All of Identity, all of Clinical Defaults, Block 1 + Block 3 + Block 5 of AI Behavior
- **Phase 1.5 (with AI feature ship):** Block 2 voice clone, Block 4 edit telemetry, Block 1 goal autodraft toggle (default OFF)
- **Phase 2+ (deferred):** Cue Sense pairing, Cue Living routine map, parent-portal-side preferences
---
## 9. Open Questions for Revision
1. **RCI regex specificity** — How strict should the format check be? Need Guru to confirm acceptable format patterns across RCI registration eras.
2. **Voice clone activation threshold** — 50 sessions is a guess. Should this be tied directly to edit-ratio convergence (e.g., activate when edit ratio drops below 10% sustained across 20 sessions) instead of session count?
3. **Certification taxonomy completeness** — Is the current list of 16 cert types exhaustive for the Indian SLP market? Notable omissions?
4. **Template ownership** — Cue ships default templates; what's the update cadence when EBP guidance shifts (e.g., new SCERTS revision)?
5. **Parent summary language stacking** — Side-by-side or stacked layout in PDFs? Affects letterhead width calculations.
6. **Edit feedback prompt frequency** — How often is "occasionally"? Every 10 sessions? Random sampling?
7. **Audit log retention** — Resolved via Privacy & Consent Block 4 with default 7 years (Indian medical record convention), SLP-configurable. Pre-production: confirm `retention_until` column vs. scheduled cleanup job approach.
8. **Granular consent for telemetry sharing** — Single toggle, or one-toggle-per-data-type?
9. **Hospital-embedded SLP letterhead** — Should Cue defer to hospital letterhead entirely (no Cue-generated letterhead) or generate Cue letterhead with hospital affiliation in the footer?
10. **Receipt numbering format after FY reset** — Counter restarts at `0001` with `FY26-27/` prefix, or continues with calendar-year prefix? Indian accounting convention varies.
11. **Holiday calendar maintenance** — Cue ships default Indian national + state lists, or punts entirely to SLP custom uploads? National list is small and stable; state lists are 28+8 = 36 separate lists, each with its own update cadence.
12. **Consent renewal cadence default** — Annual is conservative but creates admin overhead for SLPs with long-term clients. Should default be "On change of treatment plan" instead, which is more clinically meaningful?
13. **Engrams contribution consent surface** — When SLP opts a session note into Engrams corpus, what's the parent consent surface? Per-session consent, blanket consent at intake with opt-out, or two-stage (intake blanket + per-document confirmation)?
---
## 10. Build Order (recommended)
0. **Pre-req (cannot skip):**
   - Enable `pgcrypto` on Supabase project `cgnjbjbargkxtcnafxaa`
   - Set `PII_ENCRYPTION_KEY` env var
   - Verify framework chip renderer is mounted on `cue_popup.dart` (currently missing per `CLAUDE.md` May 2026)
   - Grep `CLAUDE.md` for section anchors cited in this brief (§11, §13, §controlled-vocab, AI success metric). Patch anchors or section names where they don't resolve.
1. **Schema migration** (Section 6) — all 11 tables + helper functions + indexes. Pure DDL, no UI.
2. **Settings module mount point** — Create route in AppLayout sidebar. Empty shell with five-card collapse pattern as the framework.
3. **Identity Block 1 + Block 2** — Lowest stakes, validates the five-card UI pattern + per-field-on-blur write pattern + PII audit encryption end-to-end.
4. **Identity Block 3** — RCI; unlocks signed PDFs.
5. **Identity Block 5** — Signature & signature attribution only (letterhead deferred to step 6).
6. **Practice Setup all blocks** — Unblocks Identity Block 5 letterhead composition. After this lands, return to Identity Block 5 and complete the letterhead header binding to live Practice Setup data.
7. **Clinical Defaults all blocks** — Foundation for AI Behavior. Section 2 array semantics live-tested here on `section_ordering`.
8. **AI Behavior Block 1 + Block 3 + Block 5** — Ships with Phase 1.
9. **Notifications all blocks** — Builds on Practice Setup (working days dependency) and AI Behavior (edit-threshold operational signal). Inbox table also serves as event substrate for future Today-view alerts.
10. **Privacy & Consent all blocks** — Resolves §9.7 audit retention default. Provides canonical home for sharing toggles. Account deletion grace-period scheduler is async job; ship the schema first, scheduler can follow.
11. **Security all blocks** — 2FA, session management, login history. Idle timeout enforcement is a Flutter app-shell concern (route guard + activity listener); ship Settings UI first, enforcement wrapper can follow.
12. **Audit Log screen** — Unified forensic viewer over `settings_audit_log` + `clinical_event_log` + `security_login_history`. Read-mostly UI. Re-auth-gated PII decryption. Hash chain integrity verification is schema-ready but UI deferred to Phase 1.5.
13. **Billing all blocks** — Razorpay (or equivalent processor) integration handles payment primitives; Cue stores only references and display fragments. Founding Clinician lock is application-layer enforcement, not just a flag. Fair-use usage counters update via scheduled aggregation job, not real-time writes.
14. **Legal & Help all blocks** — Legal document seed migration (BAA, ToS, Privacy, DPDP notice, Cookie policy as initial versions). Document re-acceptance flow at next login when version changes. Support ticket pipe routes to existing channels.
15. **Identity Block 4** — Education & certifications. Important but not blocking. Array semantics from Section 2 live-tested here.
**Pre-production gate (not blocking Phase 1 prototype):** Before any production deployment, resolve §9.7 (audit log retention policy). Resolution may require adding a `retention_until` column to `settings_audit_log` or a scheduled cleanup job. Phase 1 prototype runs with indefinite retention by default — acceptable for now, not acceptable at scale.
---
*End of v0.4. All 10 Settings screens specced with 27 critique cuts applied. Schema-migration ready except for Billing Block 3 invoice schema, which gates on B5 GST registration verification. Once Guru confirms GST status, schema migration can proceed end-to-end.*
