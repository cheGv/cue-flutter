-- Goal lifecycle — soft-archive support for STGs and LTGs.
--
-- Adds a nullable `deleted_at` to both goal tables so goals created by mistake
-- can be ARCHIVED (hidden from the chart) WITHOUT a hard DELETE. Goals anchor
-- sessions, evidence, and trajectory data; prod has no backups, so hard deletes
-- and cascades are forbidden. Archiving = set deleted_at; restoring = null it.
--
-- This is ORTHOGONAL to the existing `status` column:
--   • status        — clinical lifecycle: 'active' | 'achieved' | 'discontinued'
--                     (an achieved/discontinued goal STAYS visible on the chart)
--   • deleted_at     — archival: non-null ⇒ goal hidden everywhere (reversible)
-- A goal is ACTIVE when status = 'active' AND deleted_at IS NULL.
--
-- Additive + reversible. No data backfill (default null = "not archived" for
-- every existing row). No FK/cascade changes — child STGs are archived by the
-- application layer in the same transaction-shaped batch (shared timestamp), so
-- restoring an LTG restores exactly the STGs archived with it.
--
-- ROLLBACK (reverse migration), if ever needed:
--   DROP INDEX IF EXISTS idx_short_term_goals_deleted_at;
--   DROP INDEX IF EXISTS idx_long_term_goals_deleted_at;
--   ALTER TABLE short_term_goals DROP COLUMN IF EXISTS deleted_at;
--   ALTER TABLE long_term_goals  DROP COLUMN IF EXISTS deleted_at;

ALTER TABLE short_term_goals
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE long_term_goals
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Partial-friendly lookup for the active/archived split (most reads filter
-- deleted_at IS NULL; the archived view filters IS NOT NULL).
CREATE INDEX IF NOT EXISTS idx_short_term_goals_deleted_at
  ON short_term_goals (deleted_at);

CREATE INDEX IF NOT EXISTS idx_long_term_goals_deleted_at
  ON long_term_goals (deleted_at);

COMMENT ON COLUMN short_term_goals.deleted_at IS
  'Soft-archive timestamp. NULL = live. Non-null = archived (hidden from chart, '
  'reversible by setting back to NULL). Orthogonal to status. When an LTG is '
  'archived, its child STGs are stamped with the SAME timestamp so an LTG '
  'restore re-activates exactly those children. Never hard-delete a goal.';

COMMENT ON COLUMN long_term_goals.deleted_at IS
  'Soft-archive timestamp. NULL = live. Non-null = archived (hidden from chart, '
  'reversible by setting back to NULL). Orthogonal to status. Archiving an LTG '
  'cascades (application-layer, reversible) to its child STGs. Never hard-delete.';
