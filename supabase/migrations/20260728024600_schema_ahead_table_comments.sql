-- Mark every schema-ahead-of-feature table as such (audited
-- 2026-07-28 across Dart lib/, the Render proxy, and all three edge
-- functions: zero readers, zero writers, zero rows for each table
-- below). clinic_profile is deliberately NOT in this set — the audit
-- found it LIVE (settings_screen upsert, goal_authoring read), so it
-- gets an accurate comment instead.

comment on table public.data_export_requests is
  'SCHEMA-AHEAD-OF-FEATURE: GDPR-style full-data-export requests (archive_url + expires_at imply a signed, expiring link). No code path reads or writes it yet (audited 2026-07-28). RLS slp_owns_row since 20260726144004.';
comment on table public.account_deletion_requests is
  'SCHEMA-AHEAD-OF-FEATURE: account-deletion workflow with scheduled_deletion_at + cancellation_token (bearer capability). No code path reads or writes it yet (audited 2026-07-28). RLS slp_owns_row since 20260726144004.';
comment on table public.security_trusted_devices is
  'SCHEMA-AHEAD-OF-FEATURE: trusted-device registry for auth step-down (device_fingerprint, trusted_until, revoked_at). No code path reads or writes it yet (audited 2026-07-28). RLS slp_owns_row since 20260726144655 — sealed BEFORE the feature so forged pre-trusted rows are impossible.';
comment on table public.legal_documents is
  'SCHEMA-AHEAD-OF-FEATURE: versioned legal document texts (ToS / privacy / consent). No code path reads or writes it yet (audited 2026-07-28). RLS read-only reference shape since 20260726131014; a future PRE-AUTH consent reader will need an anon SELECT policy or out-of-band delivery.';
comment on table public.signed_document_snapshots is
  'SCHEMA-AHEAD-OF-FEATURE: point-in-time identity/preferences snapshots taken at document signing. No code path reads or writes it yet (audited 2026-07-28). RLS slp_owns_row since 20260728024259.';
comment on table public.notification_inbox is
  'SCHEMA-AHEAD-OF-FEATURE: per-SLP in-app notification inbox (category, payload, read_at). No code path reads or writes it yet (audited 2026-07-28). RLS slp_owns_row since 20260728024259.';
comment on table public.clinical_event_log is
  'SCHEMA-AHEAD-OF-FEATURE: hash-chained clinical audit log (chain_hash). No code path reads or writes it yet (audited 2026-07-28). RLS INSERT/SELECT-only since 20260726144655 — rows immutable through PostgREST for every client role.';
comment on table public.audit_log_saved_filters is
  'SCHEMA-AHEAD-OF-FEATURE: per-SLP saved filters for a future audit-log viewer. No code path reads or writes it yet (audited 2026-07-28). RLS pending (allowlisted).';
comment on table public.settings_audit_log is
  'SCHEMA-AHEAD-OF-FEATURE: settings-change audit trail. No code path reads or writes it yet (audited 2026-07-28). RLS pending (allowlisted; append-only shape likely).';
comment on table public.security_failed_attempts is
  'SCHEMA-AHEAD-OF-FEATURE: failed-login counter store. No code path reads or writes it yet (audited 2026-07-28). RLS pending (allowlisted; likely service-role-only shape).';
comment on table public.security_login_history is
  'SCHEMA-AHEAD-OF-FEATURE: login event history. No code path reads or writes it yet (audited 2026-07-28). RLS pending (allowlisted; likely service-role-only shape).';
comment on table public.support_tickets is
  'SCHEMA-AHEAD-OF-FEATURE: in-app support tickets. No code path reads or writes it yet (audited 2026-07-28). RLS pending (allowlisted; slp ownership plus support-staff read path undecided).';
comment on table public.clinic_profile is
  'LIVE (not schema-ahead, corrected 2026-07-28): single-row clinic identity used by settings_screen (upsert) and goal_authoring_screen (read). RLS pending (allowlisted; single-row config shape undecided).';
