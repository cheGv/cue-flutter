-- Phase B — AI session headline cache (Prompt 3, Bundle 2, PART D1).
-- One-line AI summary per session, cached on the row. Generation (the proxy
-- call that fills this) is gated on new server-side proxy endpoints; the chart
-- already READS this column (falling back to next_session_focus when null).

ALTER TABLE sessions
  ADD COLUMN ai_headline TEXT;

COMMENT ON COLUMN sessions.ai_headline IS 'AI-generated one-line session summary. Cached per session. Regenerated when observation or assessment is edited.';
