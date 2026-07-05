-- Self-declared pronoun pair for UI copy, e.g. 'he/him', 'she/her',
-- 'they/them'. Nullable on purpose: when null the UI falls back to the
-- client's first name. NEVER derived from clients.gender — gender is a
-- demographic/clinical field; pronouns are self-declared or absent.
--
-- Applied to sandbox 2026-07-05 via MCP (history version 20260705145250).
alter table public.clients add column if not exists pronoun text;
