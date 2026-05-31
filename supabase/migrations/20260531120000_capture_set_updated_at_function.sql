-- ============================================================================
-- Capture: shared set_updated_at() trigger function  (CAPTURE migration)
-- ============================================================================
-- Prerequisite for the BEFORE UPDATE triggers on the assessment parent tables
-- (assessment_visits, assessment_reports, voice_assessments,
-- ped_dysarthria_assessments, ald_assessments). This function exists in the
-- sandbox but was never captured in a migration file; reconstructed here from
-- its live definition so a fresh rebuild has it before any trigger references it.
--
-- NOTE: other (non-assessment) tables in the database also use this function.
-- It is captured here because the assessment triggers depend on it; a broader
-- "capture all shared functions" pass is out of scope for this step.
-- ============================================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$;
