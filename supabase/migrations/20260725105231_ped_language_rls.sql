-- Task 2 — RLS on the pediatric language tables. Mirrors the versioned
-- sibling convention exactly (20260531120400 ped_dysarthria /
-- 20260531120500 ald): parent table owned via clients.clinician_id
-- ("slp_owns_via_client"), child table owned via parent join
-- ("slp_owns_via_assessment"); as permissive for all to authenticated,
-- identical using / with check. No anon policies — anon gets nothing.
--
-- Proven on sandbox 2026-07-25: owning clinician (jwt sub =
-- clients.clinician_id) can insert/update/select both tables; a
-- different authenticated clinician sees zero rows; anon sees zero
-- rows and both insert attempts fail with 42501.

alter table public.ped_language_assessments enable row level security;
drop policy if exists "slp_owns_via_client" on public.ped_language_assessments;
create policy "slp_owns_via_client" on public.ped_language_assessments
  as permissive for all to authenticated
  using (exists (select 1 from public.clients c
                 where c.id = ped_language_assessments.client_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.clients c
                 where c.id = ped_language_assessments.client_id and c.clinician_id = auth.uid()));

alter table public.ped_language_milestones enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.ped_language_milestones;
create policy "slp_owns_via_assessment" on public.ped_language_milestones
  as permissive for all to authenticated
  using (exists (select 1 from public.ped_language_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ped_language_milestones.ped_language_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.ped_language_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ped_language_milestones.ped_language_assessment_id and c.clinician_id = auth.uid()));
