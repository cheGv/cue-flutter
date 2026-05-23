-- Phase B — session planning draft field (Prompt 3, Bundle 1, PART B4a).
-- The "Plan today's session" surface saves a plan-forward into a draft session
-- (status = 'planned'); planned_focus holds that clinician-authored text.

ALTER TABLE sessions
  ADD COLUMN planned_focus TEXT;

COMMENT ON COLUMN sessions.planned_focus IS 'Clinician-authored plan for an upcoming session, captured on the "Plan today''s session" surface. Lives on a draft session row (status = ''planned''); promoted into the session when it is run/documented.';
