-- Task 4 — make the derived age band visible and auditable. The band
-- was already locked from a silent derivation (DOB exact; stated years
-- -> midpoint); this names that derivation in the schema so the record
-- says HOW the band was chosen, in the words the UI will render:
--   derived_age_months  — the months value the band lookup actually used
--   age_source          — 'dob' | 'stated_years_midpoint' (the honest
--                          name: a stated age never was exact)
-- Remodels the launch columns (age_months_at_capture / 'stated_years')
-- rather than duplicating them; sandbox holds zero rows (verified
-- 2026-07-25), the value migration is explicit anyway.

alter table public.ped_language_assessments
  rename column age_months_at_capture to derived_age_months;

alter table public.ped_language_assessments
  drop constraint ped_language_assessments_age_source_check;

update public.ped_language_assessments
  set age_source = 'stated_years_midpoint'
where age_source = 'stated_years';

alter table public.ped_language_assessments
  add constraint ped_language_assessments_age_source_check
  check (age_source in ('dob','stated_years_midpoint'));

comment on column public.ped_language_assessments.derived_age_months is
  'The age-in-months the band lookup actually used. dob: exact full '
  'months at creation. stated_years_midpoint: years*12 + 6. Rendered '
  'verbatim in the capture-surface header so the derivation is visible '
  'to the clinician judging against the band.';
comment on column public.ped_language_assessments.age_source is
  'How derived_age_months was derived: ''dob'' (exact, from '
  'clients.date_of_birth) or ''stated_years_midpoint'' (assumed midpoint '
  'of clients.age years). Rendered in the capture-surface header.';
