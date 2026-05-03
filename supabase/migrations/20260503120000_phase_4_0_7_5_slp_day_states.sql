-- Phase 4.0.7.5 — SLP-controlled Today day state.
-- Per (slp_id, date) audit trail. Default (no row) means state=open.
-- Reopening preserves the closed row's last_closed_at and flips state back
-- to 'open' with last_reopened_at set. Date-keyed lookup makes midnight
-- reset implicit (no row exists for the new date until the SLP closes it).

create table if not exists public.slp_day_states (
  slp_id           uuid not null references auth.users(id) on delete cascade,
  date             date not null,
  state            text not null check (state in ('open', 'closed')),
  last_closed_at   timestamptz,
  last_reopened_at timestamptz,
  updated_at       timestamptz not null default now(),
  primary key (slp_id, date)
);
