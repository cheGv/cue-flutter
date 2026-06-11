-- ============================================================================
-- Childhood Feeding — Phase 1 (capture): clinical_area 'pediatric-feeding'
-- ============================================================================
-- Adds the new clinical area to clients.clinical_area, AND captures the
-- clients_clinical_area_check constraint itself — which existed on the LIVE
-- sandbox but was never recorded in a repo migration (same drift situation
-- assessment_entries was in before 20260531120600 captured its check). This
-- file is therefore both the CAPTURE of the live 16-value constraint and its
-- EXTENSION to 17 values.
--
-- The value list below is the live sandbox order (verified 2026-06-11) with
-- 'pediatric-feeding' inserted at the end of the pediatric block, after
-- 'pediatric-dysarthria'. The Dart mirror is lib/constants/clinical_areas.dart
-- (kClinicalAreas) — the two MUST stay in step.
--
-- assessment_entries_clinical_area_check is intentionally NOT extended:
-- precedent — pediatric-cas / pediatric-dysarthria were never added there
-- either, and no assessment_entries rows are tagged with the new area.
--
-- Idempotent: guarded DO block drops the constraint if present and re-adds
-- the full 17-value definition; re-running converges on the same state.
-- All existing rows hold values from the prior 16-value set, so re-validation
-- on ADD CONSTRAINT cannot fail.
-- ============================================================================

do $$
begin
  if exists (
    select 1 from pg_constraint
    where conname = 'clients_clinical_area_check'
      and conrelid = 'public.clients'::regclass
  ) then
    alter table public.clients drop constraint clients_clinical_area_check;
  end if;

  alter table public.clients
    add constraint clients_clinical_area_check
    check (clinical_area = any (array[
      'pediatric-language','autism-developmental','speech-sound-disorders',
      'pediatric-motor-speech','pediatric-cas','pediatric-dysarthria',
      'pediatric-feeding',
      'fluency','voice','adult-language-cognitive','adult-motor-speech',
      'dysphagia','aac','social-pragmatic','hearing-aural-rehab',
      'literacy','multilingual'
    ]));
end $$;
