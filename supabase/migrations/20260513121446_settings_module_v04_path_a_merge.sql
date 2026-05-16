-- ===========================================================================
-- Settings Module v0.4 — Phase 1 schema migration (Path A: Merge)
-- ===========================================================================
-- Project:  cgnjbjbargkxtcnafxaa
-- Filed:    2026-05-13
-- Spec:     docs/settings-brief-v0.4.md
-- Pattern:  docs/settings-architecture.md (SECURITY DEFINER RPC mediation)
-- Path A:   docs/tech-debt/slp-profiles-schema-cleanup.md (Path B deferred)
--
-- ## Architectural decisions baked into this migration
--
-- 1. PII write architecture: SECURITY DEFINER RPCs read `pii_encryption_key`
--    from `vault.decrypted_secrets` internally. Flutter never holds the key.
--    Supersedes v0.4 §2 and §6 references to `set_config('app.pii_key', ...)`.
--
-- 2. Schema-collision resolution: Path A (Merge). The existing slp_profiles
--    table (Phase 4 clinical/voice-clone state) is extended in-place with
--    v0.4 identity columns. Where v0.4 §6 specifies a column whose meaning
--    is already covered by an existing slp_profiles column, the new column
--    is NOT created. See per-table comments. Path B reshape is deferred.
--
-- 3. FK direction: all child tables that v0.4 §6 specified
--    `references slp_profiles(id)` instead `references auth.users(id)`.
--    Reasoning: existing slp_profiles.id is gen_random_uuid (not auth.uid).
--    auth.users(id) is the canonical user identity. RPCs key on auth.uid()
--    directly. Decouples Settings from any future slp_profiles reshape.
--
-- 4. Billing invoice schema gate: cue_invoices and
--    subscription_cancellation_requests are NOT created in this migration.
--    GST registration of Cue Pvt Ltd must be verified before invoice column
--    shape locks (v0.4 Billing Block 3 carry-forward).
--
-- 5. Idempotency: CREATE TABLE IF NOT EXISTS / CREATE OR REPLACE FUNCTION /
--    CREATE INDEX IF NOT EXISTS / DROP TRIGGER IF EXISTS then CREATE.
--    Safe to re-run.
-- ===========================================================================

create extension if not exists pgcrypto;

-- ===========================================================================
-- 1. Helper functions for PII encryption (read key from vault)
-- ===========================================================================
-- Key: vault.secrets name='pii_encryption_key', ID cf1237b5-d382-4de5-82da-cb159f93079c

-- search_path includes `extensions` because pgcrypto's pgp_sym_* live there
-- on Supabase (extensions are not in `public`).
create or replace function encrypt_pii(plaintext text)
returns text
language sql
security definer
set search_path = public, vault, extensions
as $$
  select encode(
    extensions.pgp_sym_encrypt(
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
set search_path = public, vault, extensions
as $$
  select extensions.pgp_sym_decrypt(
    decode(ciphertext, 'base64'),
    (select decrypted_secret from vault.decrypted_secrets where name = 'pii_encryption_key')
  )
$$;

revoke execute on function encrypt_pii(text) from public;
revoke execute on function decrypt_pii(text) from public;
-- App roles cannot call these directly. Only SECURITY DEFINER RPCs (§16) do.

-- Internal helper — write one encrypted audit row. Not exposed to public.
create or replace function _audit_pii(
  p_slp_id uuid,
  p_table  text,
  p_field  text,
  p_prev   text,
  p_new    text
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into settings_audit_log (slp_id, table_name, field_name, prev_value, new_value, is_pii)
  values (
    p_slp_id, p_table, p_field,
    case when p_prev is null then null else encrypt_pii(p_prev) end,
    case when p_new  is null then null else encrypt_pii(p_new)  end,
    true
  );
$$;
revoke execute on function _audit_pii(uuid, text, text, text, text) from public;

-- ===========================================================================
-- 2. slp_profiles — extend with v0.4 identity columns (Path A)
-- ===========================================================================
-- Existing columns NOT touched: clinician_id, full_name, years_experience,
-- primary_setting, specializations, certifications, primary_population,
-- therapy_languages, note_format, note_tone, note_detail, includes_home_program,
-- theoretical_orientation, family_involvement, voice_sample_count,
-- voice_model_ready, report_format, transcription_language_mode,
-- transcription_script_mode, response_style.

alter table slp_profiles add column if not exists display_name text;
alter table slp_profiles add column if not exists profile_photo_url text;
alter table slp_profiles add column if not exists legal_first_name text;   -- PII
alter table slp_profiles add column if not exists legal_middle_name text;  -- PII
alter table slp_profiles add column if not exists legal_last_name text;    -- PII
alter table slp_profiles add column if not exists salutation text;
alter table slp_profiles add column if not exists designation text;
alter table slp_profiles add column if not exists degree_suffix_override text;
alter table slp_profiles add column if not exists primary_contact_email text;

-- ===========================================================================
-- 3. Audit log — created early because helpers and RPCs depend on it
-- ===========================================================================
create table if not exists settings_audit_log (
  id uuid primary key default gen_random_uuid(),
  slp_id uuid not null references auth.users(id),  -- NO CASCADE: forensic record
  table_name text,
  field_name text,
  prev_value text,
  new_value text,
  is_pii boolean default false,
  severity text default 'routine',
  chain_hash text,
  changed_at timestamptz default now()
);
alter table settings_audit_log add column if not exists severity text default 'routine';
alter table settings_audit_log add column if not exists chain_hash text;
create index if not exists idx_audit_slp_changed on settings_audit_log (slp_id, changed_at desc);
create index if not exists idx_audit_severity on settings_audit_log (slp_id, severity, changed_at desc);

revoke insert, update, delete on settings_audit_log from public;
revoke insert, update, delete on settings_audit_log from anon, authenticated;
-- Only SECURITY DEFINER RPCs (owned by postgres) may insert.

-- ===========================================================================
-- 4. Identity Block 3 — RCI registration
-- ===========================================================================
create table if not exists slp_rci_registration (
  id uuid primary key default gen_random_uuid(),
  slp_id uuid not null references auth.users(id) on delete cascade,
  rci_category text,
  rci_number text,              -- PII
  date_of_registration date,
  renewal_due_date date,
  certificate_url text,         -- PII
  certificate_hash text,        -- plaintext sha256
  updated_at timestamptz default now()
);
create unique index if not exists ux_slp_rci_one_per_slp on slp_rci_registration (slp_id);

-- ===========================================================================
-- 5. Identity Block 4 — Qualifications + Certifications
-- ===========================================================================
create table if not exists slp_qualifications (
  id uuid primary key default gen_random_uuid(),
  slp_id uuid not null references auth.users(id) on delete cascade,
  is_primary boolean default false,
  status text default 'draft',
  degree text,
  institution text,
  year_of_completion int,
  deleted_at timestamptz,
  created_at timestamptz default now()
);
create index if not exists idx_slp_qualifications_slp on slp_qualifications (slp_id) where deleted_at is null;

create table if not exists slp_certifications (
  id uuid primary key default gen_random_uuid(),
  slp_id uuid not null references auth.users(id) on delete cascade,
  status text default 'draft',
  cert_type text,
  cert_level text,
  date_earned date,
  expiry date,
  certificate_url text,         -- PII
  certificate_hash text,
  deleted_at timestamptz,
  created_at timestamptz default now()
);
create index if not exists idx_slp_certifications_slp on slp_certifications (slp_id) where deleted_at is null;

-- ===========================================================================
-- 6. Identity Block 5 — Signature & Letterhead
-- ===========================================================================
create table if not exists slp_signature_letterhead (
  slp_id uuid primary key references auth.users(id) on delete cascade,
  signature_mode text default 'none',
  signature_svg text,            -- PII
  signature_png_url text,        -- PII
  signature_hash text,
  auto_attach_signature boolean default true,
  render_printed_name boolean default true,
  letterhead_style text default 'minimal',
  -- Logo NOT here — single source of truth in slp_practice_setup.clinic_logo_url
  footer_disclaimer text,
  show_rci_on_letterhead boolean default true,
  updated_at timestamptz default now()
);

-- ===========================================================================
-- 7. Screen 4 — Practice Setup
-- ===========================================================================
create table if not exists slp_practice_setup (
  slp_id uuid primary key references auth.users(id) on delete cascade,
  clinic_legal_name text,
  clinic_display_name text,
  clinic_type text default 'solo',
  year_established int,
  clinic_logo_url text,          -- PII
  clinic_logo_hash text,
  clinic_tagline text,
  address_line1 text,
  address_line2 text,
  area text,
  city text,
  state text,
  pincode text,
  country text default 'IN',
  map_lat numeric,
  map_lng numeric,
  clinic_phone text,
  clinic_email text,
  whatsapp_business text,
  website text,
  working_days jsonb default '["mon","tue","wed","thu","fri","sat"]'::jsonb,
  working_hours jsonb default '{"start":"09:00","end":"18:00","break_start":"13:00","break_end":"14:00"}'::jsonb,
  time_zone text default 'Asia/Kolkata',
  holiday_calendar_source text default 'none',
  custom_holidays jsonb default '[]'::jsonb,
  business_display_name text,
  default_session_fee int,
  receipt_prefix text default 'CUE-',
  receipt_counter int default 1,
  fy_reset_enabled boolean default true,
  updated_at timestamptz default now()
);

-- Receipt counter blocking trigger
-- WEAKNESS NOTE: with RLS disabled (per CLAUDE.md), a Flutter client could
-- defeat this trigger via `select set_config('app.role','system',false)`.
-- True hardening requires routing increments through an RPC owned by a
-- non-authenticated role. Tracked in slp-profiles-schema-cleanup.md.
create or replace function block_receipt_counter_update()
returns trigger language plpgsql as $$
begin
  if NEW.receipt_counter is distinct from OLD.receipt_counter
     and coalesce(current_setting('app.role', true), '') != 'system' then
    raise exception 'receipt_counter is system-managed and cannot be user-edited';
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_block_receipt_counter on slp_practice_setup;
create trigger trg_block_receipt_counter
  before update on slp_practice_setup
  for each row execute function block_receipt_counter_update();

-- ===========================================================================
-- 8. Screen 5 — Notifications
-- ===========================================================================
create table if not exists slp_notification_preferences (
  slp_id uuid primary key references auth.users(id) on delete cascade,
  push_enabled boolean default true,
  email_digest_enabled boolean default false,
  -- digest_email omitted (v0.4): uses slp_profiles.primary_contact_email
  session_cycle_loudness text default 'in_app',
  clinical_lifecycle_loudness text default 'push',
  credential_compliance_loudness text default 'push',
  operational_loudness text default 'in_app',
  dnd_start time default '21:00',
  dnd_end time default '07:00',
  working_days_only boolean default true,
  digest_frequency text default 'daily_9am',
  updated_at timestamptz default now()
);

create table if not exists notification_inbox (
  id uuid primary key default gen_random_uuid(),
  slp_id uuid not null references auth.users(id),  -- NO CASCADE per v0.4
  category text,
  subcategory text,
  payload jsonb,
  is_critical_override boolean default false,
  read_at timestamptz,
  created_at timestamptz default now()
);
create index if not exists idx_inbox_slp_unread on notification_inbox (slp_id, created_at desc) where read_at is null;
create index if not exists idx_inbox_slp_all on notification_inbox (slp_id, created_at desc);

-- ===========================================================================
-- 9. Screen 6 — Privacy & Consent
-- ===========================================================================
create table if not exists slp_privacy_preferences (
  slp_id uuid primary key references auth.users(id) on delete cascade,
  data_principal_nominee_name text,
  data_principal_nominee_email text,
  consent_renewal_cadence text default 'annual',
  consent_withdrawal_workflow text default 'pause_30day',
  share_anonymized_telemetry boolean default false,
  share_crash_reports boolean default true,
  product_update_emails boolean default false,
  engrams_contribution boolean default false,
  audit_log_retention_years int default 7,
  soft_delete_purge_days int default 90,
  discharged_client_archive_years int default 0,
  updated_at timestamptz default now()
);

create table if not exists data_export_requests (
  id uuid primary key default gen_random_uuid(),
  slp_id uuid not null references auth.users(id),  -- NO CASCADE
  status text default 'pending',
  archive_url text,
  expires_at timestamptz,
  requested_at timestamptz default now(),
  ready_at timestamptz
);

create table if not exists account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  slp_id uuid not null references auth.users(id),  -- NO CASCADE
  status text default 'grace_period',
  scheduled_deletion_at timestamptz,
  cancellation_token text,
  requested_at timestamptz default now()
);

-- ===========================================================================
-- 10. Screen 7 — Security
-- ===========================================================================
create table if not exists slp_security_preferences (
  slp_id uuid primary key references auth.users(id) on delete cascade,
  totp_enabled boolean default false,
  totp_secret_encrypted text,
  recovery_codes_hash jsonb,
  trusted_device_window_days int default 30,
  idle_timeout_minutes int default 15,
  remember_me_duration text default '7_days',
  alert_new_device boolean default true,
  alert_new_location boolean default true,
  updated_at timestamptz default now()
);

create table if not exists security_trusted_devices (
  id uuid primary key default gen_random_uuid(),
  slp_id uuid not null references auth.users(id) on delete cascade,
  device_fingerprint text,
  device_label text,
  trusted_until timestamptz,
  created_at timestamptz default now(),
  revoked_at timestamptz
);
create index if not exists idx_trusted_active on security_trusted_devices (slp_id, trusted_until) where revoked_at is null;

create table if not exists security_login_history (
  id uuid primary key default gen_random_uuid(),
  slp_id uuid not null references auth.users(id),  -- NO CASCADE
  attempted_at timestamptz default now(),
  success boolean,
  ip text,
  city text,
  country text,
  device_label text,
  failure_reason text
);
create index if not exists idx_login_history_slp on security_login_history (slp_id, attempted_at desc);

create table if not exists security_failed_attempts (
  slp_id uuid primary key references auth.users(id) on delete cascade,
  attempts_24h int default 0,
  window_started_at timestamptz default now(),
  locked_until timestamptz
);

-- ===========================================================================
-- 11. Screen 8 — Audit (clinical event log + saved filters)
-- ===========================================================================
create table if not exists clinical_event_log (
  id uuid primary key default gen_random_uuid(),
  slp_id uuid not null references auth.users(id),  -- NO CASCADE: forensic
  event_type text,
  client_id uuid,
  document_id uuid,
  severity text default 'routine',
  metadata jsonb,
  occurred_at timestamptz default now(),
  chain_hash text
);
create index if not exists idx_clinical_event_slp on clinical_event_log (slp_id, occurred_at desc);
create index if not exists idx_clinical_event_client on clinical_event_log (client_id, occurred_at desc);

create table if not exists audit_log_saved_filters (
  id uuid primary key default gen_random_uuid(),
  slp_id uuid not null references auth.users(id) on delete cascade,
  filter_name text,
  filter_definition jsonb,
  created_at timestamptz default now()
);

-- ===========================================================================
-- 12. Screen 9 — Billing (subscription + usage; invoices/cancellation gated)
-- ===========================================================================
create table if not exists slp_subscription (
  slp_id uuid primary key references auth.users(id) on delete cascade,
  plan_tier text default 'trial',
  plan_price_inr int,
  billing_cycle text default 'monthly',
  is_founding_locked boolean default false,
  current_period_start timestamptz,
  current_period_end timestamptz,
  auto_renew boolean default true,
  processor_customer_id_encrypted text,
  processor_subscription_id text,
  primary_payment_method_display text,
  billing_email text,
  slp_gstin text,
  status text default 'active',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists slp_usage_counters (
  slp_id uuid not null references auth.users(id) on delete cascade,
  period_start date,
  active_clients int default 0,
  total_sessions int default 0,
  ai_generations int default 0,
  signed_pdfs int default 0,
  storage_bytes bigint default 0,
  primary key (slp_id, period_start)
);
create index if not exists idx_usage_counters on slp_usage_counters (slp_id, period_start desc);

-- ---------------------------------------------------------------------------
-- SKIPPED: cue_invoices + subscription_cancellation_requests
-- Awaiting GST verification (v0.4 Billing Block 3 schema gate).
-- Open questions blocking lock:
--   (1) Is Cue Pvt Ltd GST-registered as a service provider?
--   (2) Does SaaS-at-18% apply to Cue's invoices to SLPs?
-- Once Guru's CA confirms, these tables are created in a follow-up
-- migration with the correct GST column shape (or non-GST shape if exempt).
-- ---------------------------------------------------------------------------
-- create table if not exists cue_invoices (...);
-- create table if not exists subscription_cancellation_requests (...);

-- ===========================================================================
-- 13. Screen 10 — Legal & Help
-- ===========================================================================
create table if not exists legal_documents (
  id uuid primary key default gen_random_uuid(),
  doc_type text,
  version text,
  content text,
  effective_from timestamptz,
  effective_until timestamptz,
  created_at timestamptz default now()
);
create index if not exists idx_legal_current on legal_documents (doc_type, effective_from desc) where effective_until is null;

create table if not exists slp_legal_acceptances (
  id uuid primary key default gen_random_uuid(),
  slp_id uuid not null references auth.users(id),  -- NO CASCADE
  doc_type text,
  doc_version text,
  accepted_at timestamptz default now(),
  ip text,
  user_agent text
);
create index if not exists idx_slp_acceptances on slp_legal_acceptances (slp_id, accepted_at desc);

create table if not exists support_tickets (
  id uuid primary key default gen_random_uuid(),
  slp_id uuid not null references auth.users(id),  -- NO CASCADE
  category text,
  subject text,
  body text,
  system_info jsonb,
  status text default 'open',
  priority text default 'normal',
  created_at timestamptz default now(),
  resolved_at timestamptz
);
create index if not exists idx_support_tickets_slp on support_tickets (slp_id, created_at desc);
create index if not exists idx_support_tickets_open on support_tickets (status, priority, created_at desc) where status = 'open';

-- ===========================================================================
-- 14. Clinical Defaults (SLIM per Path A merge)
-- ===========================================================================
-- DROPPED from v0.4 §6 because already on slp_profiles:
--   - note_format  (already on slp_profiles.note_format)
-- Other v0.4 columns retained — semantically distinct from slp_profiles state.

create table if not exists slp_clinical_defaults (
  slp_id uuid primary key references auth.users(id) on delete cascade,
  primary_language text default 'en',
  parent_summary_languages jsonb default '["en"]'::jsonb,
  report_formality text default 'warm_clinical',
  reading_level text default 'grade_8',
  -- note_format: already on slp_profiles.note_format; not duplicated here
  section_ordering jsonb default '["S","O","A","P"]'::jsonb,
  pre_session_brief_enabled boolean default true,
  auto_include_previous_summary boolean default true,
  goal_hierarchy_depth text default 'ltg_stg',
  default_ebp_frameworks jsonb default '["NDBI","ImPACT"]'::jsonb,
  default_mastery_criterion text default '80_3',
  auto_suggest_next_stg boolean default false,
  default_session_duration int default 45,
  default_session_type text default 'direct_intervention',
  default_attendance text default 'in_person',
  updated_at timestamptz default now()
);

create table if not exists slp_templates (
  id uuid primary key default gen_random_uuid(),
  slp_id uuid not null references auth.users(id) on delete cascade,
  template_type text,
  content text,
  language text,
  is_default boolean default false,
  deleted_at timestamptz,
  updated_at timestamptz default now()
);
create index if not exists idx_slp_templates_slp on slp_templates (slp_id) where deleted_at is null;

-- ===========================================================================
-- 15. AI Preferences (SLIM per Path A merge)
-- ===========================================================================
-- DROPPED from v0.4 §6 because already on slp_profiles:
--   - note_tone                  (already on slp_profiles.note_tone)
--   - voice_clone_session_count  (already on slp_profiles.voice_sample_count)
-- voice_clone_enabled retained: distinct from slp_profiles.voice_model_ready
-- (user opt-in flag vs. system-set model-readiness flag).

create table if not exists slp_ai_preferences (
  slp_id uuid primary key references auth.users(id) on delete cascade,
  autodraft_soap boolean default true,
  autodraft_parent_summary boolean default true,
  autodraft_goals boolean default false,
  autodraft_session_brief boolean default true,
  autodraft_scope text default 'current_session',
  parent_summary_tone text default 'warm_clinical',
  -- note_tone: already on slp_profiles.note_tone; not duplicated here
  terminology_use text default 'mixed',
  voice_clone_enabled boolean default false,
  -- voice_clone_session_count: see slp_profiles.voice_sample_count
  ebp_retrieval_source jsonb default '["engrams","peer_reviewed"]'::jsonb,
  surface_contradicting_evidence boolean default true,
  edit_threshold_pct int default 25,
  show_edit_ratio boolean default false,
  share_anonymized_telemetry boolean default false,
  parent_pdf_attribution text default 'footer',
  internal_note_attribution text default 'inline',
  custom_disclaimer text,               -- PII (via update_ai_custom_disclaimer RPC)
  updated_at timestamptz default now()
);

-- ===========================================================================
-- 16. Signed document snapshots (immutability)
-- ===========================================================================
create table if not exists signed_document_snapshots (
  id uuid primary key default gen_random_uuid(),
  document_id uuid,
  slp_id uuid not null references auth.users(id),  -- NO CASCADE: legal record
  identity_snapshot jsonb,
  ai_preferences_snapshot jsonb,
  signed_at timestamptz default now()
);
create index if not exists idx_snapshot_doc on signed_document_snapshots (document_id);

-- ===========================================================================
-- 17. SECURITY DEFINER RPCs for PII writes
-- ===========================================================================
-- Each RPC: writes source row + paired settings_audit_log entries in one
-- transaction; reads key via encrypt_pii() (which reads vault internally).
-- REVOKE EXECUTE from public; GRANT EXECUTE to authenticated.
-- Flutter calls: await supabase.rpc('update_slp_legal_identity', params: {...});

-- 17.1 update_slp_legal_identity --------------------------------------------
create or replace function update_slp_legal_identity(
  p_first_name  text,
  p_middle_name text,
  p_last_name   text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slp_id uuid := auth.uid();
  v_prev_first  text;
  v_prev_middle text;
  v_prev_last   text;
begin
  if v_slp_id is null then raise exception 'auth.uid() is null'; end if;

  select legal_first_name, legal_middle_name, legal_last_name
    into v_prev_first, v_prev_middle, v_prev_last
    from slp_profiles
    where clinician_id = v_slp_id
    limit 1;

  update slp_profiles
     set legal_first_name  = p_first_name,
         legal_middle_name = p_middle_name,
         legal_last_name   = p_last_name,
         updated_at        = now()
   where clinician_id = v_slp_id;

  if v_prev_first  is distinct from p_first_name  then perform _audit_pii(v_slp_id, 'slp_profiles', 'legal_first_name',  v_prev_first,  p_first_name);  end if;
  if v_prev_middle is distinct from p_middle_name then perform _audit_pii(v_slp_id, 'slp_profiles', 'legal_middle_name', v_prev_middle, p_middle_name); end if;
  if v_prev_last   is distinct from p_last_name   then perform _audit_pii(v_slp_id, 'slp_profiles', 'legal_last_name',   v_prev_last,   p_last_name);   end if;
end;
$$;
revoke execute on function update_slp_legal_identity(text, text, text) from public;
grant  execute on function update_slp_legal_identity(text, text, text) to authenticated;

-- 17.2 update_slp_rci_number ------------------------------------------------
create or replace function update_slp_rci_number(
  p_rci_category text,
  p_rci_number   text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slp_id uuid := auth.uid();
  v_prev_number text;
begin
  if v_slp_id is null then raise exception 'auth.uid() is null'; end if;

  select rci_number into v_prev_number
    from slp_rci_registration where slp_id = v_slp_id limit 1;

  insert into slp_rci_registration (slp_id, rci_category, rci_number, updated_at)
       values (v_slp_id, p_rci_category, p_rci_number, now())
  on conflict (slp_id) do update
       set rci_category = excluded.rci_category,
           rci_number   = excluded.rci_number,
           updated_at   = now();

  if v_prev_number is distinct from p_rci_number then
    perform _audit_pii(v_slp_id, 'slp_rci_registration', 'rci_number', v_prev_number, p_rci_number);
  end if;
end;
$$;
revoke execute on function update_slp_rci_number(text, text) from public;
grant  execute on function update_slp_rci_number(text, text) to authenticated;

-- 17.3 update_slp_signature -------------------------------------------------
create or replace function update_slp_signature(
  p_mode      text,
  p_svg       text,
  p_png_url   text,
  p_hash      text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slp_id uuid := auth.uid();
  v_prev_svg text;
  v_prev_url text;
begin
  if v_slp_id is null then raise exception 'auth.uid() is null'; end if;

  select signature_svg, signature_png_url into v_prev_svg, v_prev_url
    from slp_signature_letterhead where slp_id = v_slp_id limit 1;

  insert into slp_signature_letterhead
    (slp_id, signature_mode, signature_svg, signature_png_url, signature_hash, updated_at)
  values
    (v_slp_id, p_mode, p_svg, p_png_url, p_hash, now())
  on conflict (slp_id) do update
    set signature_mode    = excluded.signature_mode,
        signature_svg     = excluded.signature_svg,
        signature_png_url = excluded.signature_png_url,
        signature_hash    = excluded.signature_hash,
        updated_at        = now();

  if v_prev_svg is distinct from p_svg     then perform _audit_pii(v_slp_id, 'slp_signature_letterhead', 'signature_svg',     v_prev_svg, p_svg);     end if;
  if v_prev_url is distinct from p_png_url then perform _audit_pii(v_slp_id, 'slp_signature_letterhead', 'signature_png_url', v_prev_url, p_png_url); end if;
end;
$$;
revoke execute on function update_slp_signature(text, text, text, text) from public;
grant  execute on function update_slp_signature(text, text, text, text) to authenticated;

-- 17.4 update_slp_profile_photo ---------------------------------------------
create or replace function update_slp_profile_photo(
  p_url  text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slp_id uuid := auth.uid();
  v_prev_url text;
begin
  if v_slp_id is null then raise exception 'auth.uid() is null'; end if;

  select profile_photo_url into v_prev_url
    from slp_profiles where clinician_id = v_slp_id limit 1;

  update slp_profiles set profile_photo_url = p_url, updated_at = now()
    where clinician_id = v_slp_id;

  if v_prev_url is distinct from p_url then
    perform _audit_pii(v_slp_id, 'slp_profiles', 'profile_photo_url', v_prev_url, p_url);
  end if;
end;
$$;
revoke execute on function update_slp_profile_photo(text) from public;
grant  execute on function update_slp_profile_photo(text) to authenticated;

-- 17.5 update_slp_practice_logo ---------------------------------------------
create or replace function update_slp_practice_logo(
  p_logo_url  text,
  p_logo_hash text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slp_id uuid := auth.uid();
  v_prev_url text;
begin
  if v_slp_id is null then raise exception 'auth.uid() is null'; end if;

  select clinic_logo_url into v_prev_url
    from slp_practice_setup where slp_id = v_slp_id limit 1;

  insert into slp_practice_setup (slp_id, clinic_logo_url, clinic_logo_hash, updated_at)
       values (v_slp_id, p_logo_url, p_logo_hash, now())
  on conflict (slp_id) do update
       set clinic_logo_url = excluded.clinic_logo_url,
           clinic_logo_hash = excluded.clinic_logo_hash,
           updated_at = now();

  if v_prev_url is distinct from p_logo_url then
    perform _audit_pii(v_slp_id, 'slp_practice_setup', 'clinic_logo_url', v_prev_url, p_logo_url);
  end if;
end;
$$;
revoke execute on function update_slp_practice_logo(text, text) from public;
grant  execute on function update_slp_practice_logo(text, text) to authenticated;

-- 17.6 update_slp_credential_file -------------------------------------------
-- Single RPC covering both qualification and certification upload paths,
-- discriminated by p_target ('qualification' | 'certification').
create or replace function update_slp_credential_file(
  p_target  text,
  p_row_id  uuid,
  p_url     text,
  p_hash    text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slp_id uuid := auth.uid();
  v_prev_url text;
  v_table_name text;
begin
  if v_slp_id is null then raise exception 'auth.uid() is null'; end if;

  if p_target = 'qualification' then
    v_table_name := 'slp_qualifications';
    select certificate_url into v_prev_url
      from slp_qualifications where id = p_row_id and slp_id = v_slp_id;
    if not found then raise exception 'qualification % not owned by caller', p_row_id; end if;
    update slp_qualifications
       set certificate_url = p_url
     where id = p_row_id and slp_id = v_slp_id;
    -- hash stored plaintext
    update slp_qualifications set deleted_at = deleted_at where id = p_row_id;  -- no-op to bump nothing
  elsif p_target = 'certification' then
    v_table_name := 'slp_certifications';
    select certificate_url into v_prev_url
      from slp_certifications where id = p_row_id and slp_id = v_slp_id;
    if not found then raise exception 'certification % not owned by caller', p_row_id; end if;
    update slp_certifications
       set certificate_url = p_url,
           certificate_hash = p_hash
     where id = p_row_id and slp_id = v_slp_id;
  else
    raise exception 'p_target must be ''qualification'' or ''certification''';
  end if;

  if v_prev_url is distinct from p_url then
    perform _audit_pii(v_slp_id, v_table_name, 'certificate_url', v_prev_url, p_url);
  end if;
end;
$$;
revoke execute on function update_slp_credential_file(text, uuid, text, text) from public;
grant  execute on function update_slp_credential_file(text, uuid, text, text) to authenticated;

-- 17.7 update_ai_custom_disclaimer ------------------------------------------
create or replace function update_ai_custom_disclaimer(
  p_text text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slp_id uuid := auth.uid();
  v_prev text;
begin
  if v_slp_id is null then raise exception 'auth.uid() is null'; end if;

  select custom_disclaimer into v_prev
    from slp_ai_preferences where slp_id = v_slp_id limit 1;

  insert into slp_ai_preferences (slp_id, custom_disclaimer, updated_at)
       values (v_slp_id, p_text, now())
  on conflict (slp_id) do update
       set custom_disclaimer = excluded.custom_disclaimer,
           updated_at = now();

  if v_prev is distinct from p_text then
    perform _audit_pii(v_slp_id, 'slp_ai_preferences', 'custom_disclaimer', v_prev, p_text);
  end if;
end;
$$;
revoke execute on function update_ai_custom_disclaimer(text) from public;
grant  execute on function update_ai_custom_disclaimer(text) to authenticated;

-- 17.8 delete_slp_uploaded_file --------------------------------------------
-- DPDP erasure path: soft-deletes the row + writes a single PII-encrypted
-- audit entry with the prior URL. The actual Storage object hard-delete is
-- application-layer (RPC cannot make HTTP calls); the caller is responsible
-- for invoking the Storage delete before/after calling this RPC.
-- p_target: 'qualification' | 'certification' | 'signature' | 'profile_photo' | 'practice_logo'
create or replace function delete_slp_uploaded_file(
  p_target text,
  p_row_id uuid  -- ignored for single-row tables
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slp_id uuid := auth.uid();
  v_prev_url text;
begin
  if v_slp_id is null then raise exception 'auth.uid() is null'; end if;

  if p_target = 'qualification' then
    select certificate_url into v_prev_url
      from slp_qualifications where id = p_row_id and slp_id = v_slp_id;
    if not found then raise exception 'qualification % not owned by caller', p_row_id; end if;
    update slp_qualifications
       set certificate_url = null, deleted_at = now()
     where id = p_row_id and slp_id = v_slp_id;
    perform _audit_pii(v_slp_id, 'slp_qualifications', 'certificate_url', v_prev_url, null);

  elsif p_target = 'certification' then
    select certificate_url into v_prev_url
      from slp_certifications where id = p_row_id and slp_id = v_slp_id;
    if not found then raise exception 'certification % not owned by caller', p_row_id; end if;
    update slp_certifications
       set certificate_url = null, deleted_at = now()
     where id = p_row_id and slp_id = v_slp_id;
    perform _audit_pii(v_slp_id, 'slp_certifications', 'certificate_url', v_prev_url, null);

  elsif p_target = 'signature' then
    select signature_png_url into v_prev_url
      from slp_signature_letterhead where slp_id = v_slp_id;
    update slp_signature_letterhead
       set signature_mode = 'none', signature_svg = null, signature_png_url = null, signature_hash = null, updated_at = now()
     where slp_id = v_slp_id;
    perform _audit_pii(v_slp_id, 'slp_signature_letterhead', 'signature_png_url', v_prev_url, null);

  elsif p_target = 'profile_photo' then
    select profile_photo_url into v_prev_url
      from slp_profiles where clinician_id = v_slp_id;
    update slp_profiles set profile_photo_url = null, updated_at = now()
      where clinician_id = v_slp_id;
    perform _audit_pii(v_slp_id, 'slp_profiles', 'profile_photo_url', v_prev_url, null);

  elsif p_target = 'practice_logo' then
    select clinic_logo_url into v_prev_url
      from slp_practice_setup where slp_id = v_slp_id;
    update slp_practice_setup
       set clinic_logo_url = null, clinic_logo_hash = null, updated_at = now()
     where slp_id = v_slp_id;
    perform _audit_pii(v_slp_id, 'slp_practice_setup', 'clinic_logo_url', v_prev_url, null);

  else
    raise exception 'p_target must be one of: qualification, certification, signature, profile_photo, practice_logo';
  end if;
end;
$$;
revoke execute on function delete_slp_uploaded_file(text, uuid) from public;
grant  execute on function delete_slp_uploaded_file(text, uuid) to authenticated;

-- ===========================================================================
-- End of migration.
-- Re-run safe: every DDL guarded by IF NOT EXISTS / OR REPLACE / DROP IF EXISTS.
-- ===========================================================================
