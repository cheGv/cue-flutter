-- Cue Recall Assistant — instrumentation log table.
--
-- Mandatory per spec §6a: the two-tier resolver MUST log every real
-- query in beta (Tier 1 local + Tier 2 model). The Tier-1 / Tier-2
-- ratio is settled from this log, not from the design-conversation
-- working estimate (~75-80% Tier 1) — the estimate seeds initial
-- coverage, the log makes the decision real.
--
-- THIS IS CLINICAL-GRADE DATA, NOT ORDINARY TELEMETRY.
-- The raw query strings will contain patient names and clinical
-- detail ("what was Vamshi's regulatory state last month"). The
-- table is therefore:
--   1. Dedicated, not folded into a shared telemetry surface —
--      mixing patient-referencing strings into a general table
--      muddies the access model for exactly the data this project
--      exists to protect.
--   2. RLS-enabled FROM CREATION, never one of the "enable later"
--      tables. The project keystone rule applies: a clinician sees
--      only her own rows (clinician_id = auth.uid()).
--   3. Written by BOTH client (Tier 1) and edge function (Tier 2)
--      under the SLP's JWT — auth.uid() check applies to both
--      writers uniformly.
--   4. Subject to a DPDP retention policy that is an explicit TODO
--      before production beta. Not defaulted to indefinite.

create table if not exists public.recall_query_log (
  id                  uuid primary key default gen_random_uuid(),
  clinician_id        uuid not null references auth.users(id) on delete cascade,
  query_text          text not null,
  tier                text not null check (tier in ('tier1', 'tier2')),
  sub_classification  text check (sub_classification in (
                        'loose_language',
                        'relative_time',
                        'tier1_miss'
                      )),
  latency_ms          integer not null check (latency_ms >= 0),
  created_at          timestamptz not null default now()
);

create index if not exists recall_query_log_clinician_created_idx
  on public.recall_query_log (clinician_id, created_at desc);

alter table public.recall_query_log enable row level security;

create policy recall_query_log_clinician_select
  on public.recall_query_log
  for select
  using (clinician_id = auth.uid());

create policy recall_query_log_clinician_insert
  on public.recall_query_log
  for insert
  with check (clinician_id = auth.uid());

-- No update or delete policy. Rows are write-once instrumentation.
-- The retention TODO will be implemented as a scheduled cleanup job,
-- not as per-row mutation, so writers do not need DELETE either.
