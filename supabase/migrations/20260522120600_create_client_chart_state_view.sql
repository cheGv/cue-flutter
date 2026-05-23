-- Phase B chart redesign — derived per-client chart state (A5, renamed)
--
-- Renamed from the spec name `chart_context` to `client_chart_state` to avoid
-- collision with lib/utils/chart_context.dart (an AI-prompt context builder).
--
-- Divergences from the prompt spec, all forced by the real schema:
--   * clients.dob               -> clients.date_of_birth (+ clients.age exposed)
--   * sessions.session_date     -> sessions.date (COALESCEd to created_at::date)
--   * stg.deleted_at / ltg.*    -> no such columns; active filter is status-based
--   * clients.caregiver_verified-> derived caregiver_present (email or whatsapp)
--   * last_next_session_intent  -> last_next_session_focus (sessions.next_session_focus)
--   * undocumented count uses clinician_attested IS NOT TRUE (treats NULL as not
--     yet attested = undocumented)

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
     WHERE s.client_id = c.id AND s.deleted_at IS NULL) AS total_session_count,
  (SELECT max(COALESCE(s.date, (s.created_at)::date)) FROM sessions s
     WHERE s.client_id = c.id AND s.deleted_at IS NULL) AS last_session_date,
  (SELECT count(*) FROM sessions s
     WHERE s.client_id = c.id AND s.deleted_at IS NULL
       AND s.clinician_attested IS NOT TRUE) AS undocumented_session_count,
  (SELECT s.next_session_focus FROM sessions s
     WHERE s.client_id = c.id AND s.deleted_at IS NULL
     ORDER BY COALESCE(s.date, (s.created_at)::date) DESC, s.created_at DESC
     LIMIT 1) AS last_next_session_focus,
  (c.caregiver_email IS NOT NULL OR c.guardian_whatsapp IS NOT NULL) AS caregiver_present,
  (SELECT count(*) FROM substrate_cells sc
     WHERE sc.client_id = c.id) AS substrate_cell_count
FROM clients c
WHERE c.deleted_at IS NULL;

COMMENT ON VIEW client_chart_state IS 'Derived per-client state for chart contextual logic. Read by the action-chip resolver to decide the primary chip (Author LTG vs Plan next session vs Document last session, etc.) and to drive the narrator state-voice line. Renamed from spec chart_context to avoid collision with lib/utils/chart_context.dart. caregiver_present is derived; last_next_session_focus sources sessions.next_session_focus.';
