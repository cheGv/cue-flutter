-- Phase B chart redesign — per-STG per-session metric for the sparkline (A3)
-- One numeric value per (STG, session). metric_label/unit carry the semantics
-- (e.g. "prompting level", "accuracy %") so the sparkline can render + label
-- across non-accuracy metrics that session_goal_data / stg_evidence don't store
-- cleanly (decision Q3).

CREATE TABLE stg_session_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  stg_id UUID NOT NULL REFERENCES short_term_goals(id) ON DELETE CASCADE,
  session_id BIGINT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  metric_value NUMERIC NOT NULL,
  metric_label TEXT NOT NULL,
  metric_unit TEXT,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID,
  UNIQUE (stg_id, session_id)
);

CREATE INDEX idx_stg_session_metrics_stg_id ON stg_session_metrics(stg_id);
CREATE INDEX idx_stg_session_metrics_session_id ON stg_session_metrics(session_id);

COMMENT ON TABLE stg_session_metrics IS 'Per-STG, per-session numeric progress data. Drives the sparkline inside the in-focus STG card on the chart. metric_label describes what is being measured (e.g., "prompting level", "accuracy %"). metric_unit is optional ("percent", "level", "count"). One row per STG per session — unique constraint enforces.';
