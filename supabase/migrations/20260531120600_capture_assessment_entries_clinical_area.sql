-- ============================================================================
-- Capture: assessment_entries.clinical_area drift  (CAPTURE migration)
-- ============================================================================
-- The base assessment_entries table is created by
-- 20260502115740_phase_4_0_1_population_aware_schema.sql (already in the repo).
-- The LIVE sandbox table has since gained a `clinical_area` column + check
-- constraint + partial index that were never captured in a migration. This
-- file captures only that drift, so the repo reproduces the live table exactly.
--
-- Note: `population_type` (older, NOT NULL) remains; `clinical_area` (newer,
-- nullable) was added alongside it. Captured as-is — reconciling the two is a
-- separate later decision, not part of this capture.
-- Idempotent: ADD COLUMN IF NOT EXISTS / guarded ADD CONSTRAINT / INDEX IF NOT EXISTS.
-- ============================================================================
alter table public.assessment_entries
  add column if not exists clinical_area text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'assessment_entries_clinical_area_check'
      and conrelid = 'public.assessment_entries'::regclass
  ) then
    alter table public.assessment_entries
      add constraint assessment_entries_clinical_area_check
      check (clinical_area = any (array[
        'pediatric-language','autism-developmental','speech-sound-disorders',
        'pediatric-motor-speech','fluency','voice','adult-language-cognitive',
        'adult-motor-speech','dysphagia','aac','social-pragmatic',
        'hearing-aural-rehab','literacy','multilingual'
      ]));
  end if;
end $$;

create index if not exists idx_assessment_entries_clinical_area
  on public.assessment_entries (clinical_area) where clinical_area is not null;
