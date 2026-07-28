-- Final sealing pass (approved 2026-07-26) — five tables.
--
-- substrate_cells: per-patient clinical evidence cells, owned via the
-- client ("slp_owns_via_client" — the versioned assessment-parent
-- shape; created_by stays informational). LIVE DATA: 18 rows, all
-- verified to resolve to active clients of one clinician (no orphans).
-- substrate_sources / substrate_tags: children of a cell, owned via
-- the cell -> client join ("slp_owns_via_cell"). LIVE DATA: 30 / 36
-- rows. NOTE substrate_relations is NOT here — it is the GLOBAL
-- knowledge graph, sealed read-only in 20260726131014.
--
-- signed_document_snapshots / notification_inbox: slp_owns_row
-- (slp_id = auth.uid()). Both verified schema-ahead-of-feature:
-- 0 rows and zero readers/writers across Dart, the Render proxy, and
-- all three edge functions (which are JWT-forwarded, never service
-- role).

alter table public.substrate_cells enable row level security;
drop policy if exists "slp_owns_via_client" on public.substrate_cells;
create policy "slp_owns_via_client" on public.substrate_cells
  as permissive for all to authenticated
  using (exists (select 1 from public.clients c
                 where c.id = substrate_cells.client_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.clients c
                 where c.id = substrate_cells.client_id and c.clinician_id = auth.uid()));

alter table public.substrate_sources enable row level security;
drop policy if exists "slp_owns_via_cell" on public.substrate_sources;
create policy "slp_owns_via_cell" on public.substrate_sources
  as permissive for all to authenticated
  using (exists (select 1 from public.substrate_cells sc join public.clients c on c.id = sc.client_id
                 where sc.id = substrate_sources.cell_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.substrate_cells sc join public.clients c on c.id = sc.client_id
                 where sc.id = substrate_sources.cell_id and c.clinician_id = auth.uid()));

alter table public.substrate_tags enable row level security;
drop policy if exists "slp_owns_via_cell" on public.substrate_tags;
create policy "slp_owns_via_cell" on public.substrate_tags
  as permissive for all to authenticated
  using (exists (select 1 from public.substrate_cells sc join public.clients c on c.id = sc.client_id
                 where sc.id = substrate_tags.cell_id and c.clinician_id = auth.uid()))
  with check (exists (select 1 from public.substrate_cells sc join public.clients c on c.id = sc.client_id
                 where sc.id = substrate_tags.cell_id and c.clinician_id = auth.uid()));

alter table public.signed_document_snapshots enable row level security;
drop policy if exists "slp_owns_row" on public.signed_document_snapshots;
create policy "slp_owns_row" on public.signed_document_snapshots
  as permissive for all to authenticated
  using (slp_id = auth.uid())
  with check (slp_id = auth.uid());

alter table public.notification_inbox enable row level security;
drop policy if exists "slp_owns_row" on public.notification_inbox;
create policy "slp_owns_row" on public.notification_inbox
  as permissive for all to authenticated
  using (slp_id = auth.uid())
  with check (slp_id = auth.uid());
