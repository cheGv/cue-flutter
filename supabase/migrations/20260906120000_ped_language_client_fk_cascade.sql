-- Step 1a (delete affordances) — ped_language_assessments.client_id must
-- cascade from clients like every sibling capture family: cas, voice, ssd,
-- feeding, ped_dysarthria and ald all declare ON DELETE CASCADE.
--
-- 20260725094455 declared this FK as a bare `references public.clients(id)`,
-- i.e. NO ACTION: a client holding a ped-language assessment could not be
-- deleted at all (23503), and the RLS regression harness had to delete the
-- ped-language row by hand before the client. That inconsistency is a bug,
-- fixed here. A client delete now removes its ped-language assessment and,
-- through the child FK that already cascades, its milestones.
--
-- One ALTER, so the drop and the re-add are atomic; constraint name kept.

alter table public.ped_language_assessments
  drop constraint ped_language_assessments_client_id_fkey,
  add constraint ped_language_assessments_client_id_fkey
    foreign key (client_id) references public.clients(id) on delete cascade;
