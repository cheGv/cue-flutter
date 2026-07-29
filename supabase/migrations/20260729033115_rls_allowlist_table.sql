-- Single-source the RLS catalog-diff allowlist (follow-up 1, 2026-07-28).
-- Replaces test/rls/rls_allowlist.json and the copy inlined in the SQL
-- harness: both harness editions and the read-only catalog audit now
-- read THIS table. One source, no sync note.
--
-- The table itself is sealed with the reference shape (RLS on, SELECT
-- to authenticated, no write policies — owner/service-role writes via
-- migration only), so it never appears in its own diff.

create table public.rls_allowlist (
  table_name text primary key,
  reason     text not null,
  added_at   timestamptz not null default now()
);

comment on table public.rls_allowlist is
  'Catalog-diff allowlist for the RLS regression harness and the read-only catalog audit: every public table must be rowsecurity=true OR listed here with a reason. Rows are added/removed by migration in the same commit that creates/seals a table. Single source — replaces the repo json (removed 2026-07-28).';

insert into public.rls_allowlist (table_name, reason) values
  ('audit_log_saved_filters',          'Schema-ahead, zero code paths (audited 2026-07-28) — per-SLP saved filters, slp_owns_row candidate'),
  ('citations',                        'LIVE (citations_repository) — per-STG evidence ladder rows, ownership via short_term_goals; Tier 2 pending'),
  ('clinic_profile',                   'LIVE (settings upsert + goal-authoring read) — single-row clinic config; ownership shape undecided'),
  ('detection_failure_log',            'LIVE, proxy-written under service role — diagnostic log, ownership shape undecided'),
  ('detection_insufficient_input_log', 'LIVE, proxy-written under service role — diagnostic log, ownership shape undecided'),
  ('security_failed_attempts',         'Schema-ahead, zero code paths (audited 2026-07-28) — likely service-role-only shape'),
  ('security_login_history',           'Schema-ahead, zero code paths (audited 2026-07-28) — likely service-role-only shape'),
  ('settings_audit_log',               'Schema-ahead, zero code paths (audited 2026-07-28) — append-only shape likely'),
  ('stg_session_metrics',              'LIVE (stg_metrics_repository, chart sparklines) — ownership via short_term_goals.user_id; Tier 2 pending'),
  ('support_tickets',                  'Schema-ahead, zero code paths (audited 2026-07-28) — slp ownership plus support-staff read path undecided');

alter table public.rls_allowlist enable row level security;
drop policy if exists "authenticated_read_allowlist" on public.rls_allowlist;
create policy "authenticated_read_allowlist" on public.rls_allowlist
  as permissive for select to authenticated
  using (true);
