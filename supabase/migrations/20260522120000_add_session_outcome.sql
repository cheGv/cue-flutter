-- Phase B chart redesign — session outcome category (A1)
-- Clinician-affirming categorical outcome for a session.
-- NOTE: Prompt A2 (next_session_intent) was intentionally NOT added — the
-- existing sessions.next_session_focus column serves the same plan-forward
-- purpose and is reused (decision Q2). No new next-session column exists.

CREATE TYPE session_outcome AS ENUM ('progress', 'plan_revised', 'holding');

ALTER TABLE sessions
  ADD COLUMN outcome session_outcome;

COMMENT ON COLUMN sessions.outcome IS 'Clinician-affirming session outcome category. progress = clinical work moved forward. plan_revised = clinician revised the plan based on what session revealed. holding = session consolidated current state, no progress made, no revision needed. Never "setback," "regression," or "failure" — Cue uses clinician-affirming language per §language discipline in CLAUDE.md.';
