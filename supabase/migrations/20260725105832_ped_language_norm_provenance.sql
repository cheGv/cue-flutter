-- Task 3 — norm provenance on ped_language_milestones. Every persisted
-- milestone row must record which reference set its wording came from
-- (norm_reference) and which parsed dataset version stamped it
-- (library_version). NO column defaults — unknown provenance must fail
-- loudly at insert, never be papered over; the Dart service stamps both
-- at seed time from the loud-fail-parsed dataset.

alter table public.ped_language_milestones
  add column norm_reference  text,
  add column library_version text;

-- Explicit backfill of any pre-provenance rows (the sandbox holds zero
-- ped_language_milestones rows at migration time — verified 2026-07-25
-- — so this is expected to touch nothing; it exists so the NOT NULL
-- below can never fail on a row this migration did not account for).
-- Values match the shipped dataset exactly: version 1.0.0, source
-- sentence verbatim.
update public.ped_language_milestones
  set norm_reference  = 'Milestones sourced verbatim from ASHA Communication Milestones (asha.org/public/developmental-milestones). Examples authored by Cue in Indian English for familiarity. This is a structured developmental reference informing clinical judgment, not a standalone diagnostic tool.',
      library_version = '1.0.0'
where norm_reference is null or library_version is null;

alter table public.ped_language_milestones
  alter column norm_reference  set not null,
  alter column library_version set not null;

comment on column public.ped_language_milestones.norm_reference is
  'Which reference set this milestone''s wording came from — the dataset''s '
  'source sentence, snapshotted verbatim at seed time. NOT NULL, no default: '
  'a row without provenance is an insert-time error.';
comment on column public.ped_language_milestones.library_version is
  'Version of the parsed dataset (assets/data/asha_language_milestones_0_5.json '
  '`version`, loud-fail parsed) that stamped this row at seed time. NOT NULL, '
  'no default.';
