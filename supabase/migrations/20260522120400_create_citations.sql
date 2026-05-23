-- Phase B chart redesign — academic / clinical evidence citations per STG (A4)
-- Distinct from stg_evidence (per-session clinical trial data) — this is the
-- literature ladder rendered beneath the in-focus STG.

CREATE TYPE evidence_tier AS ENUM ('level_1', 'level_2', 'level_3', 'practice');

CREATE TABLE citations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  stg_id UUID NOT NULL REFERENCES short_term_goals(id) ON DELETE CASCADE,
  tier evidence_tier NOT NULL,
  finding TEXT NOT NULL,
  author_year TEXT NOT NULL,
  source_url TEXT,
  display_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_citations_stg_id ON citations(stg_id);

COMMENT ON TABLE citations IS 'Academic and clinical evidence sources attached to each STG. Renders as the evidence ladder beneath the in-focus STG in the chart. tier is the evidence strength (level_1 = RCT/meta-analysis, level_2 = cohort study, level_3 = case series, practice = practice guidelines or framework documentation). finding is a one-line clinical claim. author_year is the in-text citation (e.g., "Porges · 2011"). source_url links to the article.';
