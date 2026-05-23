-- Phase A — Substrate (clinical reasoning surface)
--
-- The structured clinical-evidence model behind the Substrate view.
-- Four tables: substrate_cells, substrate_sources, substrate_tags,
-- substrate_relations. Controlled vocabulary lives in
-- docs/substrate-taxonomy.md (v0.1, locked for Phase A).
--
-- CUE PRODUCT LAW: Cue assembles evidence; the clinician reasons. These
-- tables store evidence + source attribution + a global tag-relation
-- graph. Nothing here ranks, scores, concludes, or recommends.
--
-- NAMING NOTE (intentional collision, flagged per founder): the
-- substrate_cells.layer values are a SIX-DOMAIN clinical-evidence
-- taxonomy (safety_regulation, cognitive_linguistic,
-- communication_pragmatic, motor_speech, family_environment,
-- developmental_trajectory). This is DISTINCT from CLAUDE.md §14.9's
-- six-LAYER data-capture architecture (01 Core Profile -> 02 Case
-- History -> 03 Assessment -> 04 Pre-therapy Planning -> 05 Lesson Plan
-- Inputs -> 06 Progress Tracking). Two different "six" taxonomies,
-- deliberately. Do not conflate them in code or docs.
--
-- SCHEMA RECONCILIATION (founder-approved): the Phase A spec named
-- `patient_id -> patients`. There is no `patients` table (CLAUDE.md
-- §7.4 — deprecated, never migrated; §7.1 canonical roster is
-- `clients`). This migration uses `client_id uuid -> clients(id) on
-- delete cascade`, matching the §7.2 case_history_entries /
-- assessment_entries pattern. Every other field is the locked spec.
--
-- Enums are text + CHECK (codebase convention; not Postgres CREATE
-- TYPE — see assessment_entries.mode). RLS is DEFERRED per §11
-- (commented per-clinician policy at the foot of this file).
--
-- DEPLOY SCOPE: sandbox only (uuqhusmgoiaxdvtgbmwh). Production is
-- off-limits for new clinical tables until the §7 deploy chain is green.

-- ───────────────────────────────────────────────────────────────────
-- 1. substrate_cells — one row per (client, layer, sub_category)
-- ───────────────────────────────────────────────────────────────────

create table if not exists public.substrate_cells (
  id           uuid primary key default gen_random_uuid(),
  client_id    uuid not null references public.clients(id) on delete cascade,
  layer        text not null check (layer in (
                 'safety_regulation',
                 'cognitive_linguistic',
                 'communication_pragmatic',
                 'motor_speech',
                 'family_environment',
                 'developmental_trajectory'
               )),
  sub_category text not null,
  content      text,                                    -- NULL = "not yet on file" (open clinical question)
  attributes   jsonb not null default '[]'::jsonb,      -- array of: safety_flag | prognostic | age_conditional | assessment_fit
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid references auth.users(id)
);

comment on table public.substrate_cells is
  'Substrate evidence cells: one row per (client, layer, sub_category). content NULL = open clinical question ("not yet on file"), still rendered. attributes = jsonb array of safety_flag|prognostic|age_conditional|assessment_fit. Cue assembles; the clinician reasons — no ranking, scoring, or conclusions stored here.';

create index if not exists idx_substrate_cells_client_layer
  on public.substrate_cells(client_id, layer);

-- ───────────────────────────────────────────────────────────────────
-- 2. substrate_sources — source attribution per cell
-- ───────────────────────────────────────────────────────────────────

create table if not exists public.substrate_sources (
  id          uuid primary key default gen_random_uuid(),
  cell_id     uuid not null references public.substrate_cells(id) on delete cascade,
  source_type text not null check (source_type in ('session_note','intake','external_report','assessment')),
  source_ref  text,                                     -- narrator session id (sessions.id is bigint -> stored as text), intake form id, etc.
  excerpt     text,                                     -- verbatim quoted material
  date        date
);

comment on table public.substrate_sources is
  'Source attribution for a substrate cell. source_ref points at the origin (narrator session id [sessions.id is bigint, stored as text], intake form id, external report ref, assessment entry). excerpt = the verbatim quoted material that grounds the cell.';

create index if not exists idx_substrate_sources_cell
  on public.substrate_sources(cell_id);

-- ───────────────────────────────────────────────────────────────────
-- 3. substrate_tags — patient-specific clinical-concept tags
-- ───────────────────────────────────────────────────────────────────

create table if not exists public.substrate_tags (
  id      uuid primary key default gen_random_uuid(),
  cell_id uuid not null references public.substrate_cells(id) on delete cascade,
  tag     text not null
);

comment on table public.substrate_tags is
  'Patient-specific clinical-concept tags on a cell (e.g. joint-attention, co-regulation). Threading traverses these tags through the global substrate_relations graph.';

create index if not exists idx_substrate_tags_cell
  on public.substrate_tags(cell_id);
create index if not exists idx_substrate_tags_tag
  on public.substrate_tags(tag);

-- ───────────────────────────────────────────────────────────────────
-- 4. substrate_relations — GLOBAL clinical-knowledge graph (not per-patient)
-- ───────────────────────────────────────────────────────────────────

create table if not exists public.substrate_relations (
  id         uuid primary key default gen_random_uuid(),
  source_tag text not null,
  target_tag text not null,
  strength   text not null check (strength in ('strong','moderate','weak')),
  direction  text not null check (direction in ('mutual','source_to_target')),
  reasoning  text                                       -- one-line clinical rationale (authored, never generated)
);

comment on table public.substrate_relations is
  'GLOBAL clinical-knowledge graph (NOT per-patient). Each row is a hand-authored clinical claim linking two tags. direction=mutual is bidirectional; source_to_target is one-way. reasoning = one-line rationale. Authored by a clinician, never generated.';

create index if not exists idx_substrate_relations_source
  on public.substrate_relations(source_tag);
create index if not exists idx_substrate_relations_target
  on public.substrate_relations(target_tag);

-- ───────────────────────────────────────────────────────────────────
-- RLS — DEFERRED for prototype (matches case_history_entries /
-- assessment_entries; CLAUDE.md §11). NOT enabled in this migration.
-- Before external onboarding, enable per-clinician isolation scoped
-- through clients.clinician_id. substrate_relations stays global
-- (read for any authenticated clinician). Template:
-- ───────────────────────────────────────────────────────────────────
--
-- alter table public.substrate_cells enable row level security;
-- create policy substrate_cells_clinician_isolation on public.substrate_cells
--   using (client_id in (
--     select id from public.clients
--     where clinician_id = auth.uid() and deleted_at is null
--   ));
--
-- alter table public.substrate_sources enable row level security;
-- create policy substrate_sources_clinician_isolation on public.substrate_sources
--   using (cell_id in (
--     select sc.id from public.substrate_cells sc
--     join public.clients c on c.id = sc.client_id
--     where c.clinician_id = auth.uid() and c.deleted_at is null
--   ));
--
-- alter table public.substrate_tags enable row level security;
-- create policy substrate_tags_clinician_isolation on public.substrate_tags
--   using (cell_id in (
--     select sc.id from public.substrate_cells sc
--     join public.clients c on c.id = sc.client_id
--     where c.clinician_id = auth.uid() and c.deleted_at is null
--   ));
--
-- alter table public.substrate_relations enable row level security;
-- create policy substrate_relations_authenticated_read on public.substrate_relations
--   for select using (auth.role() = 'authenticated');
