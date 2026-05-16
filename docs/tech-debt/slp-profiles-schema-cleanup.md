# Tech Debt — `slp_profiles` schema cleanup (deferred Path B)

**Filed:** 2026-05-13
**Source:** Settings v0.4 migration design (Path A: Merge chosen; Path B deferred to this entry)
**Companion:** `docs/settings-architecture.md`, `docs/settings-brief-v0.4.md` §6

---

## Why this exists

When Cue Settings v0.4 was migrated on 2026-05-13, the existing `slp_profiles` table (Phase 4) was found to collide with v0.4 §6's expected shape. Three problems:

1. **Identity vs. mixed-state:** v0.4 §6 wanted `slp_profiles` to hold identity only (legal name, RCI link, etc.). The existing Phase 4 table mixes identity + clinical defaults (`note_format`, `note_tone`, `note_detail`, `report_format`, `family_involvement`) + AI preferences (`voice_sample_count`, `voice_model_ready`, `response_style`).
2. **PK shape:** v0.4 expected `id uuid primary key references auth.users(id)`. Existing `id` is `gen_random_uuid()`; the auth link is via a separate `clinician_id` column.
3. **Certifications collision:** existing `slp_profiles.certifications text[]` (array on the SLP row) predates v0.4's separate `slp_certifications` table.

Path A (Merge) was chosen for the v0.4 migration to avoid breaking working Phase 4 features. This entry tracks the eventual Path B work — reshaping `slp_profiles` to its v0.4-intended shape — as deferred technical debt.

---

## What Path A did (current state, post-2026-05-13 migration)

- Added v0.4 identity columns to existing `slp_profiles` in-place via `ALTER TABLE ADD COLUMN IF NOT EXISTS`:
  - `display_name`, `profile_photo_url`, `legal_first_name`, `legal_middle_name`, `legal_last_name`, `salutation`, `designation`, `degree_suffix_override`, `primary_contact_email`
- New Settings tables created as **slim** versions of v0.4 §6 — fields whose meaning was already covered by an existing `slp_profiles` column were dropped from the new table to avoid duplication. Specifically:
  - `slp_clinical_defaults` omits `note_format` (lives on `slp_profiles.note_format`)
  - `slp_ai_preferences` omits `note_tone` (lives on `slp_profiles.note_tone`) and `voice_clone_session_count` (lives on `slp_profiles.voice_sample_count`)
- All new child tables FK to `auth.users(id)` directly rather than to `slp_profiles.id` or `slp_profiles.clinician_id`. This decouples Settings from `slp_profiles`' eventual reshape.
- Existing Phase 4 columns (`years_experience`, `primary_setting`, `specializations[]`, `certifications[]`, `primary_population`, `therapy_languages[]`, `theoretical_orientation[]`, `family_involvement`, `note_detail`, `includes_home_program`, `report_format`, `transcription_language_mode`, `transcription_script_mode`, `response_style`, `voice_model_ready`) remain in place untouched.

---

## What Path B would eventually do

Reshape `slp_profiles` into a pure identity table, separating clinical and AI state into the v0.4-intended slim tables.

### Step 1 — Migrate overlap state into Settings tables

| Source on `slp_profiles` | Destination | Notes |
|---|---|---|
| `note_format` | `slp_clinical_defaults.note_format` | Add column; copy values via `INSERT … FROM slp_profiles`. |
| `note_tone` | `slp_ai_preferences.note_tone` | Same pattern. |
| `voice_sample_count` | `slp_ai_preferences.voice_clone_session_count` | Same. |
| `report_format` | `slp_clinical_defaults.report_format` | Decide first whether `report_format` ('SOAP', etc.) and v0.4's `report_formality` ('warm_clinical', etc.) are the same field or two distinct ones. |
| `note_detail`, `includes_home_program`, `family_involvement`, `theoretical_orientation[]` | `slp_clinical_defaults` (new columns) | Each one's home is a real design call — they may belong elsewhere. |
| `voice_model_ready`, `response_style` | `slp_ai_preferences` (new columns) | Same — design call before mechanical move. |
| `certifications text[]` | `slp_certifications` rows | Per-array-entry insert; status='active' for non-null entries. |
| `specializations text[]`, `therapy_languages text[]`, `primary_population jsonb` | TBD | These are Phase 4 onboarding concepts that may or may not have v0.4 homes. Defer decisions. |

### Step 2 — Update Phase 4 code to read from new tables

Every site in `lib/` that currently reads `note_format`, `note_tone`, `voice_sample_count`, etc. from `slp_profiles` is rewritten to read from the new home. Audit grep targets:

```
.from('slp_profiles').select(...)   # narrow to ones touching the migrated columns
.from('slp_profiles').update(...)   # same — these now route through Settings RPCs (or remain direct for non-PII)
```

Approximately the screens audited in `docs/tech-debt/flutter-direct-pii-writes.md` are the affected set.

### Step 3 — Drop the moved columns from `slp_profiles`

```sql
alter table slp_profiles drop column note_format;
alter table slp_profiles drop column note_tone;
alter table slp_profiles drop column voice_sample_count;
-- ... etc per the table above
```

Only safe after step 2 ships and the moved columns are confirmed unused.

### Step 4 — Reshape PK

Change `slp_profiles.id` from `gen_random_uuid()` to `references auth.users(id)`. This is the destructive step — all existing `slp_profiles` rows would need their `id` rewritten to match `clinician_id`. Every FK that currently references `slp_profiles.id` would break.

In practice this step may never happen — keeping `id` autogenerated and `clinician_id` as the auth link is a defensible long-term shape too. The v0.4 brief assumed identity-only `slp_profiles` with `id = auth.uid()`; the live codebase has carried the dual-PK pattern through Phase 4 without obvious harm.

---

## Open question (to resolve before Path B starts)

Is `slp_profiles.id` even worth reshaping, or is the dual-PK pattern (`id` autogenerated + `clinician_id` = auth link) acceptable long-term? If the latter, Path B reduces to steps 1–3 only.

---

## Related debt

- `docs/tech-debt/flutter-direct-pii-writes.md` — direct Flutter writes to Supabase that should migrate to RPC pattern. Path B step 2 overlaps with that backlog.
- `clinic_profile` (Phase 4 settings predecessor) — retain vs. migrate-into-`slp_practice_setup` decision deferred. Tracked in the flutter-direct-pii-writes doc's open-question section.

---

## Not blocking

This is Phase 5+ debt. Phase 1 Settings ships on Path A. Path B happens when the cost of carrying mixed-state `slp_profiles` exceeds the cost of the refactor — likely around the time Phase 4 voice-clone or transcription features are next significantly touched.
