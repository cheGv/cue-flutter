-- Tier 1 RLS sealing, Task 4 — cas_ family (the risky one: the
-- session-resumption engine writes cas_session_progress and two
-- SECURITY INVOKER functions — assemble_cas_progress,
-- assemble_cas_progress_brief — read it with the caller's rights).
-- Both functions are pure reads, so with the ownership paths below the
-- owning clinician's brief output is unchanged and everyone else gets
-- a legal empty brief, never an error. Proven by before/after brief
-- JSON diff (excluding assembled_at) at apply time.
--
-- Shapes:
--   cas_assessments            for all, via clients ("slp_owns_via_client")
--   cas_length_gradient/cas_ddk for all, via parent ("slp_owns_via_assessment")
--   cas_session_progress       for all, via clients (direct client_id)
--   cas_progress_brief         SELECT ONLY via short_term_goals.user_id
--                              (amendment 3) — the SECURITY DEFINER
--                              trigger mark_cas_progress_brief_dirty is
--                              the only legitimate writer
--   cas_ddk_norms              reference shape (amendment 1): SELECT to
--                              authenticated, no write policies — writes
--                              stay with the table owner / service role

alter table public.cas_assessments enable row level security;
drop policy if exists "slp_owns_via_client" on public.cas_assessments;
create policy "slp_owns_via_client" on public.cas_assessments
  as permissive for all to authenticated
  using (exists (select 1 from public.clients c
                 where c.id = cas_assessments.client_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.clients c
                 where c.id = cas_assessments.client_id and c.clinician_id = auth.uid()));

alter table public.cas_length_gradient enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.cas_length_gradient;
create policy "slp_owns_via_assessment" on public.cas_length_gradient
  as permissive for all to authenticated
  using (exists (select 1 from public.cas_assessments a join public.clients c on c.id = a.client_id
                 where a.id = cas_length_gradient.cas_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.cas_assessments a join public.clients c on c.id = a.client_id
                 where a.id = cas_length_gradient.cas_assessment_id and c.clinician_id = auth.uid()));

alter table public.cas_ddk enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.cas_ddk;
create policy "slp_owns_via_assessment" on public.cas_ddk
  as permissive for all to authenticated
  using (exists (select 1 from public.cas_assessments a join public.clients c on c.id = a.client_id
                 where a.id = cas_ddk.cas_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.cas_assessments a join public.clients c on c.id = a.client_id
                 where a.id = cas_ddk.cas_assessment_id and c.clinician_id = auth.uid()));

alter table public.cas_session_progress enable row level security;
drop policy if exists "slp_owns_via_client" on public.cas_session_progress;
create policy "slp_owns_via_client" on public.cas_session_progress
  as permissive for all to authenticated
  using (exists (select 1 from public.clients c
                 where c.id = cas_session_progress.client_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.clients c
                 where c.id = cas_session_progress.client_id and c.clinician_id = auth.uid()));

alter table public.cas_progress_brief enable row level security;
drop policy if exists "stg_owner_reads_brief" on public.cas_progress_brief;
create policy "stg_owner_reads_brief" on public.cas_progress_brief
  as permissive for select to authenticated
  using (exists (select 1 from public.short_term_goals g
                 where g.id = cas_progress_brief.stg_id and g.user_id = auth.uid()));

alter table public.cas_ddk_norms enable row level security;
drop policy if exists "authenticated_reads_norms" on public.cas_ddk_norms;
create policy "authenticated_reads_norms" on public.cas_ddk_norms
  as permissive for select to authenticated
  using (true);
