-- Tier 1 RLS sealing, Task 1 — feeding_ family. Mirrors the versioned
-- sibling convention exactly (20260531120400 ped_dysarthria /
-- 20260531120500 ald / 20260725105231 ped_language): parent owned via
-- clients.clinician_id ("slp_owns_via_client"), children owned via the
-- parent join ("slp_owns_via_assessment"); as permissive for all to
-- authenticated, identical using / with check. No anon policies.
-- feeding_ladder_bands and feeding_behaviors are per-assessment capture
-- rows (feeding_assessment_id NOT NULL), not reference data. The
-- nullable un-FK'd clinician_id on feeding_assessments is informational
-- only and is NOT the ownership anchor.

alter table public.feeding_assessments enable row level security;
drop policy if exists "slp_owns_via_client" on public.feeding_assessments;
create policy "slp_owns_via_client" on public.feeding_assessments
  as permissive for all to authenticated
  using (exists (select 1 from public.clients c
                 where c.id = feeding_assessments.client_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.clients c
                 where c.id = feeding_assessments.client_id and c.clinician_id = auth.uid()));

alter table public.feeding_ladder_bands enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.feeding_ladder_bands;
create policy "slp_owns_via_assessment" on public.feeding_ladder_bands
  as permissive for all to authenticated
  using (exists (select 1 from public.feeding_assessments a join public.clients c on c.id = a.client_id
                 where a.id = feeding_ladder_bands.feeding_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.feeding_assessments a join public.clients c on c.id = a.client_id
                 where a.id = feeding_ladder_bands.feeding_assessment_id and c.clinician_id = auth.uid()));

alter table public.feeding_behaviors enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.feeding_behaviors;
create policy "slp_owns_via_assessment" on public.feeding_behaviors
  as permissive for all to authenticated
  using (exists (select 1 from public.feeding_assessments a join public.clients c on c.id = a.client_id
                 where a.id = feeding_behaviors.feeding_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.feeding_assessments a join public.clients c on c.id = a.client_id
                 where a.id = feeding_behaviors.feeding_assessment_id and c.clinician_id = auth.uid()));
