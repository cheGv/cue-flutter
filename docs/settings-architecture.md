# PII Write Architecture — RPC Mediation Pattern

**Status:** Binding architectural decision.
**Decided:** 2026-05-13.
**Scope:** Cue Settings module and all subsequent writes that touch PII-flagged fields.
**Authority:** Overrides Settings brief v0.3 §2 audit-log pattern and §6 application-layer notes.

---

## Decision

Every write that touches a PII-flagged field is mediated by a `SECURITY DEFINER` Postgres function. Flutter calls the function via `supabase.rpc(...)`. The function — running with elevated privileges — reads the encryption key from `vault.decrypted_secrets`, encrypts the new value, and writes both the source row and the matching `settings_audit_log` entry in a single transaction.

Flutter does not hold the encryption key. Flutter cannot write to `settings_audit_log` directly. The Render proxy is not in this path.

## Why

The v0.3 brief's pattern — `select set_config('app.pii_key', '<env_var>', false)` from application context — requires whichever process calls Supabase to hold the key. Cue's current architecture writes to Supabase **directly from Flutter Web** for nearly every clinical surface (audited 2026-05-13; see `docs/tech-debt/flutter-direct-pii-writes.md`). Flutter Web ships to the user's browser. A key in that bundle is a key any user can extract from devtools.

Three options were on the table:

- **Route all PII writes through the Render proxy** — large refactor, new network hop on every edit, doesn't fit existing call patterns.
- **Accept the key on the client** — defeats the encryption entirely; not a real option.
- **`SECURITY DEFINER` RPCs** ← chosen. Key never leaves Postgres. No proxy hop. No client refactor. Fits the existing `supabase.rpc(...)` pattern Flutter already uses for AI calls.

## How it works

### Key storage

The PII encryption key lives in Supabase Vault.

- **Secret name:** `pii_encryption_key`
- **Secret ID:** `cf1237b5-d382-4de5-82da-cb159f93079c`
- **Generated:** 2026-05-13 via `encode(gen_random_bytes(32), 'base64')` inside `vault.create_secret(...)`. Plaintext never left Postgres.
- **Access:** only `SECURITY DEFINER` functions can read `vault.decrypted_secrets`. App roles (`anon`, `authenticated`) cannot.

### Helper functions

```sql
create or replace function encrypt_pii(plaintext text)
returns text
language sql
security definer
as $$
  select encode(
    pgp_sym_encrypt(
      plaintext,
      (select decrypted_secret from vault.decrypted_secrets where name = 'pii_encryption_key')
    ),
    'base64'
  )
$$;

create or replace function decrypt_pii(ciphertext text)
returns text
language sql
security definer
as $$
  select pgp_sym_decrypt(
    decode(ciphertext, 'base64'),
    (select decrypted_secret from vault.decrypted_secrets where name = 'pii_encryption_key')
  )
$$;
```

The `set_config('app.pii_key', ...)` pattern is **no longer used anywhere**. Both helpers read the key inline.

### Per-field RPCs

For every PII-flagged field in the v0.3 brief, there is a paired RPC. The RPC encapsulates: source-row update, audit-log entry with encrypted prev/new values, transactional consistency.

Naming convention: `update_slp_<field_group>` for writes, `delete_slp_<file_kind>` for DPDP erasure flows.

Reference shape:

```sql
create or replace function update_slp_legal_identity(
  p_first_name  text,
  p_middle_name text,
  p_last_name   text
)
returns void
language plpgsql
security definer
as $$
declare
  v_slp_id uuid := auth.uid();
  v_prev   record;
begin
  select legal_first_name, legal_middle_name, legal_last_name
    into v_prev
    from slp_profiles
    where id = v_slp_id;

  update slp_profiles
     set legal_first_name  = p_first_name,
         legal_middle_name = p_middle_name,
         legal_last_name   = p_last_name,
         updated_at        = now()
   where id = v_slp_id;

  -- One audit entry per field that actually changed
  if v_prev.legal_first_name is distinct from p_first_name then
    insert into settings_audit_log
      (slp_id, table_name, field_name, prev_value, new_value, is_pii)
    values
      (v_slp_id, 'slp_profiles', 'legal_first_name',
       encrypt_pii(v_prev.legal_first_name), encrypt_pii(p_first_name), true);
  end if;
  -- ... same pattern for middle_name, last_name
end;
$$;

revoke all on function update_slp_legal_identity(text, text, text) from public;
grant execute on function update_slp_legal_identity(text, text, text) to authenticated;
```

Flutter side:

```dart
await supabase.rpc('update_slp_legal_identity', params: {
  'p_first_name':  firstName,
  'p_middle_name': middleName,
  'p_last_name':   lastName,
});
```

### RPCs required for Settings v0.3 PII scope

One per PII-flagged field group from brief §2:

| RPC | Underlying field(s) |
|---|---|
| `update_slp_legal_identity` | `legal_first_name`, `legal_middle_name`, `legal_last_name` |
| `update_slp_rci_number` | `rci_number` (and `rci_category` if changed concurrently) |
| `update_slp_signature` | `signature_svg`, `signature_png_url`, `signature_hash` |
| `update_slp_profile_photo` | `profile_photo_url` (+ hash) |
| `update_slp_certificate_upload` | `certificate_url`, `certificate_hash` on a `slp_qualifications` or `slp_certifications` row |
| `update_slp_practice_logo` | `clinic_logo_url`, `clinic_logo_hash` |
| `update_ai_custom_disclaimer` | `slp_ai_preferences.custom_disclaimer` |
| `delete_slp_uploaded_file` | DPDP erasure flow — hard-deletes Storage object, soft-deletes row, writes a single audit entry with full prior state encrypted |

### Non-PII Settings writes

Toggles, enums, integer durations, framework codes, working-days arrays, etc. — these are **not** PII and **can stay direct Flutter writes** for now. Their audit log entries are written by the Flutter client with `is_pii=false` and plaintext prev/new values. A later consistency pass may consolidate everything under RPCs, but it is not required for encryption integrity.

### Read path (Audit Log decryption)

Per-row PII reveal in the Audit Log screen uses a paired `SECURITY DEFINER` function gated by app-layer re-auth (per brief §5D Block 4):

```sql
create or replace function read_audit_pii_value(
  p_log_entry_id uuid,
  p_field        text  -- 'prev_value' | 'new_value'
)
returns text
language plpgsql
security definer
as $$
  -- Caller responsibility: re-auth check before invoking
  -- ...
$$;
```

Bulk export (Audit Log Block 3) decrypts server-side in one privileged context and returns an archive URL after async generation. Plaintext never streams to the browser row-by-row.

### Privilege locks (enforce at migration time)

```sql
revoke insert, update, delete on settings_audit_log from anon, authenticated;
revoke insert, update, delete on settings_audit_log from public;
-- Only SECURITY DEFINER functions owned by the migration role can write the audit log.
```

## What this replaces in the v0.3 brief

- **§2 "Audit log behavior" encryption rule** — replaced by `encrypt_pii(value)` called from inside `SECURITY DEFINER` RPCs. `current_setting('app.pii_key')` is no longer used.
- **§6 "Application-layer notes"** — "Setting `app.pii_key` per session" is obsolete. PII audit entries are not written from application code at all; they are written from inside RPCs.
- **§10 Build Order step 0** — "Set `PII_ENCRYPTION_KEY` in Supabase env" is replaced by the Vault secret `pii_encryption_key` (already created).

The v0.4 brief should reference this document and update §2, §6, §10 accordingly before being locked.

## Out of scope

- **Client PHI** (`clients`, `case_history_entries`, `sessions`, assessment tables, goal tables) currently writes directly from Flutter and is not encrypted at the column level. That is a separate, larger refactor — see `docs/tech-debt/flutter-direct-pii-writes.md`. The Settings RPC pattern is the template for that future migration but is not in this scope.
- **Storage object encryption** — uploaded PDFs and PNGs rely on Supabase Storage's default at-rest encryption. The DB column stores only the path (treated as PII), not the file bytes.
- **Key rotation** — single symmetric key, no rotation in Phase 1. Production key-rotation strategy is a separate decision.

## References

- Supabase project: `cgnjbjbargkxtcnafxaa`
- Vault secret: name `pii_encryption_key`, ID `cf1237b5-d382-4de5-82da-cb159f93079c`
- Companion: `docs/tech-debt/flutter-direct-pii-writes.md`
- Source brief: Settings brief v0.3 (held in conversation; v0.4 pending the critique-walk pass)
