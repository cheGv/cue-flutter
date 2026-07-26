-- Reference-shape RLS (extension of the cas_ddk_norms pattern, approved
-- Task C): RLS on, ONE select policy to authenticated, NO write
-- policies — writes stay with the table owner / service role.
--
--   substrate_relations — GLOBAL hand-authored clinical-knowledge graph
--     (tag -> tag claims; no per-patient data). Read-only reference for
--     substrate threading.
--   legal_documents — versioned legal/consent texts (doc_type, version,
--     effective windows). Zero runtime readers today (verified: no
--     Dart, proxy, or edge-function reference; only the creating
--     migration). NOTE for the future signup-consent reader: this
--     policy is authenticated-only — a pre-auth consent screen would
--     need either an anon select policy on current docs or delivery
--     outside PostgREST.
--
-- substrate_cells / substrate_sources / substrate_tags are NOT included
-- deliberately: they are per-patient (cells.client_id; sources/tags via
-- cell_id) and take the ownership shape, not the reference shape — see
-- the Task C report.

alter table public.substrate_relations enable row level security;
drop policy if exists "authenticated_reads_relations" on public.substrate_relations;
create policy "authenticated_reads_relations" on public.substrate_relations
  as permissive for select to authenticated
  using (true);

alter table public.legal_documents enable row level security;
drop policy if exists "authenticated_reads_legal_documents" on public.legal_documents;
create policy "authenticated_reads_legal_documents" on public.legal_documents
  as permissive for select to authenticated
  using (true);
