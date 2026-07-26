-- Tier 1 RLS sealing, Task 2 — ssd_ family. Same versioned convention
-- as feeding (20260726120340) and the assessment siblings: parent owned
-- via clients.clinician_id ("slp_owns_via_client"), five children owned
-- via the parent join ("slp_owns_via_assessment"); as permissive for
-- all to authenticated, identical using / with check, no anon policies.
-- The nullable un-FK'd clinician_id on ssd_assessments is informational
-- only and is NOT the ownership anchor.

alter table public.ssd_assessments enable row level security;
drop policy if exists "slp_owns_via_client" on public.ssd_assessments;
create policy "slp_owns_via_client" on public.ssd_assessments
  as permissive for all to authenticated
  using (exists (select 1 from public.clients c
                 where c.id = ssd_assessments.client_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.clients c
                 where c.id = ssd_assessments.client_id and c.clinician_id = auth.uid()));

alter table public.ssd_target_sounds enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.ssd_target_sounds;
create policy "slp_owns_via_assessment" on public.ssd_target_sounds
  as permissive for all to authenticated
  using (exists (select 1 from public.ssd_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ssd_target_sounds.ssd_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.ssd_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ssd_target_sounds.ssd_assessment_id and c.clinician_id = auth.uid()));

alter table public.ssd_phonological_processes enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.ssd_phonological_processes;
create policy "slp_owns_via_assessment" on public.ssd_phonological_processes
  as permissive for all to authenticated
  using (exists (select 1 from public.ssd_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ssd_phonological_processes.ssd_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.ssd_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ssd_phonological_processes.ssd_assessment_id and c.clinician_id = auth.uid()));

alter table public.ssd_consistency_words enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.ssd_consistency_words;
create policy "slp_owns_via_assessment" on public.ssd_consistency_words
  as permissive for all to authenticated
  using (exists (select 1 from public.ssd_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ssd_consistency_words.ssd_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.ssd_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ssd_consistency_words.ssd_assessment_id and c.clinician_id = auth.uid()));

alter table public.ssd_length_effect enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.ssd_length_effect;
create policy "slp_owns_via_assessment" on public.ssd_length_effect
  as permissive for all to authenticated
  using (exists (select 1 from public.ssd_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ssd_length_effect.ssd_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.ssd_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ssd_length_effect.ssd_assessment_id and c.clinician_id = auth.uid()));

alter table public.ssd_whole_word enable row level security;
drop policy if exists "slp_owns_via_assessment" on public.ssd_whole_word;
create policy "slp_owns_via_assessment" on public.ssd_whole_word
  as permissive for all to authenticated
  using (exists (select 1 from public.ssd_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ssd_whole_word.ssd_assessment_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.ssd_assessments a join public.clients c on c.id = a.client_id
                 where a.id = ssd_whole_word.ssd_assessment_id and c.clinician_id = auth.uid()));
