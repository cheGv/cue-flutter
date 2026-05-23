-- Phase A — substrate_relations unique-edge guard.
--
-- The global threading graph must never hold duplicate edges. Each
-- (source_tag, target_tag) pair is a single hand-authored clinical claim; a
-- second identical row would double-count a thread, and re-running the
-- curated seed would silently duplicate the whole batch. Enforce the
-- invariant at the schema level so it cannot be violated by any path.
--
-- Single ALTER TABLE. Safe on the currently-empty table. Sibling to
-- 20260521120000_phase_a_substrate_tables.sql.
--
-- NOTE on (source_tag, target_tag): this prevents an exact duplicate edge.
-- For a `mutual` relation, only one orientation is stored (the graph treats
-- it bidirectionally); the reversed tuple (target, source) is a distinct row
-- and is intentionally NOT blocked by this constraint.
--
-- DEPLOY SCOPE: sandbox only (uuqhusmgoiaxdvtgbmwh). Production stays
-- off-limits for new clinical tables until the §7 deploy chain is green.

alter table public.substrate_relations
  add constraint substrate_relations_edge_unique unique (source_tag, target_tag);
