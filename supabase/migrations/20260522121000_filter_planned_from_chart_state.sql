-- Phase B — exclude pre-session intents from chart state (Prompt 3, Bundle 2,
-- PART B). Sessions with status 'planned' (Plan-today drafts) or 'draft'
-- (capture-in-progress) are not "on record": they must not inflate the chart's
-- session count, last-seen date, undocumented count, or last-next-focus.
-- Only the four session-derived columns change; goal/substrate columns are
-- unchanged.

CREATE OR REPLACE VIEW client_chart_state AS
SELECT
  c.id   AS client_id,
  c.name AS client_name,
  c.age,
  c.date_of_birth,
  c.diagnosis,
  (SELECT count(*) FROM long_term_goals ltg
     WHERE ltg.client_id = c.id) AS ltg_count,
  (SELECT count(*) FROM short_term_goals stg
     JOIN long_term_goals ltg ON stg.long_term_goal_id = ltg.id
     WHERE ltg.client_id = c.id AND stg.status = 'active') AS active_stg_count,
  (SELECT count(*) FROM sessions s
     WHERE s.client_id = c.id AND s.deleted_at IS NULL
       AND s.status NOT IN ('planned', 'draft')) AS total_session_count,
  (SELECT max(COALESCE(s.date, (s.created_at)::date)) FROM sessions s
     WHERE s.client_id = c.id AND s.deleted_at IS NULL
       AND s.status NOT IN ('planned', 'draft')) AS last_session_date,
  (SELECT count(*) FROM sessions s
     WHERE s.client_id = c.id AND s.deleted_at IS NULL
       AND s.status NOT IN ('planned', 'draft')
       AND s.clinician_attested IS NOT TRUE) AS undocumented_session_count,
  (SELECT s.next_session_focus FROM sessions s
     WHERE s.client_id = c.id AND s.deleted_at IS NULL
       AND s.status NOT IN ('planned', 'draft')
     ORDER BY COALESCE(s.date, (s.created_at)::date) DESC, s.created_at DESC
     LIMIT 1) AS last_next_session_focus,
  (c.caregiver_email IS NOT NULL OR c.guardian_whatsapp IS NOT NULL) AS caregiver_present,
  (SELECT count(*) FROM substrate_cells sc
     WHERE sc.client_id = c.id) AS substrate_cell_count
FROM clients c
WHERE c.deleted_at IS NULL;

COMMENT ON VIEW client_chart_state IS 'Derived per-client state for chart contextual logic. Session-derived columns exclude status IN (planned, draft) — pre-session intents are not session records. caregiver_present is derived; last_next_session_focus sources sessions.next_session_focus. Renamed from spec chart_context to avoid collision with lib/utils/chart_context.dart.';
