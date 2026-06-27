-- =============================================================================
-- Session 2 - Silver adjuster notes (AI Functions) - Lakeflow SDP, SQL
-- =============================================================================
--
-- Second source file of the Silver Lakeflow pipeline. It turns the free-text
-- adjuster notes into a governed, structured table using Databricks AI Functions:
--   * ai_query   - redacts embedded PII (names, phones, DOBs) -> note_text_redacted
--   * ai_classify- buckets the note into routine / potential_fraud / disputed
--   * ai_extract - pulls injury severity, fraud indicators, and any attorney mention
--
-- The classification/extraction run on the ORIGINAL note (best signal); only the
-- REDACTED text is persisted, so silver.adjuster_notes carries no raw PII. Feeds
-- note_fraud_signal and attorney_flag in gold.fraud_features (Session 3).
--
-- Add this file to the same Serverless Lakeflow pipeline as silver_pipeline.sql
-- (target catalog state_fund_poc, schema silver).
--
-- NOTE: ai_query needs a model-serving endpoint that exists in your workspace.
-- 'databricks-meta-llama-3-3-70b-instruct' is a pay-per-token Foundation Model
-- endpoint; confirm/replace it via Serving in your workspace if needed. AI
-- Functions run on serverless and incur per-token cost.
--
-- Docs:
--   AI Functions overview: https://learn.microsoft.com/azure/databricks/large-language-models/ai-functions
--   ai_query:    https://learn.microsoft.com/azure/databricks/sql/language-manual/functions/ai_query
--   ai_classify: https://learn.microsoft.com/azure/databricks/sql/language-manual/functions/ai_classify
--   ai_extract:  https://learn.microsoft.com/azure/databricks/sql/language-manual/functions/ai_extract
-- =============================================================================

CREATE OR REFRESH MATERIALIZED VIEW adjuster_notes (
  CONSTRAINT valid_claim_id EXPECT (claim_id IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Silver: PII-redacted adjuster notes with AI-extracted fraud/severity signals.'
TBLPROPERTIES ('quality' = 'silver')
AS
WITH enriched AS (
  SELECT
    upper(trim(claim_id)) AS claim_id,
    upper(trim(adjuster_id)) AS adjuster_id,
    coalesce(try_to_date(trim(note_date), 'M/d/yyyy'),
             try_to_date(trim(note_date), 'yyyy-MM-dd')) AS note_date,
    -- Redact PII from the stored text.
    ai_query(
      'databricks-meta-llama-3-3-70b-instruct',
      concat(
        'Redact every piece of personally identifiable information (person names, ',
        'phone numbers, dates of birth, street addresses) in the following workers-',
        'compensation adjuster note by replacing each with the literal token [REDACTED]. ',
        'Return ONLY the redacted note text, with no preamble.\n\nNote: ',
        note_text
      )
    ) AS note_text_redacted,
    -- Classify the original note (richer signal than the redacted text).
    ai_classify(note_text, array('routine', 'potential_fraud', 'disputed')) AS note_category,
    -- Extract structured fields from the original note.
    ai_extract(note_text, array('injury_severity', 'fraud_indicators', 'attorney')) AS extracted,
    lower(trim(follow_up_required)) IN ('yes', 'y', 'true', '1') AS follow_up_required
  FROM bronze.raw_adjuster_notes
)
SELECT
  claim_id,
  adjuster_id,
  note_date,
  note_text_redacted,
  note_category,
  extracted.injury_severity  AS extracted_injury_severity,
  extracted.fraud_indicators AS extracted_fraud_indicators,
  CASE
    WHEN extracted.attorney IS NOT NULL AND length(trim(extracted.attorney)) > 0
    THEN 1 ELSE 0
  END AS attorney_flag,
  follow_up_required
FROM enriched;
