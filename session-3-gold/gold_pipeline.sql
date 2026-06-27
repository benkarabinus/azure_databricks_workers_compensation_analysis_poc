-- =============================================================================
-- Session 3 - Gold features & aggregates (Lakeflow Spark Declarative Pipelines, SQL)
-- =============================================================================
--
-- SOURCE CODE for the Gold Lakeflow pipeline (plain .sql source, like Bronze/Silver).
-- It feature-engineers the governed silver.* entities into ML-ready Gold tables and
-- a BI aggregate:
--
--   gold.rtw_features          one row per CLOSED claim  -> RTW regression (label days_to_rtw)
--   gold.fraud_features        one row per LABELED claim -> fraud classification (label is_fraud)
--   gold.rtw_outcomes_summary  injury_type x region KPIs -> BI / Genie
--
-- Design:
--   * Materialized views that recompute from the Silver tables (and the SIU label
--     file). silver.claims is the hub; every feature joins back on claim_id (or
--     employee_id for the worker dimension).
--   * gold.rtw_features keeps closed claims only (rtw_date present), so the label
--     days_to_rtw is always populated for training. Open claims are scored in
--     Session 5 by reusing this feature logic.
--   * gold.fraud_features is the labeled SIU subset only (inner join to the labels),
--     because is_fraud exists only for investigated claims.
--
-- How to run: add this file as source code to a Serverless Lakeflow pipeline whose
-- target catalog is `state_fund_poc` and target schema is `gold`. The pipeline reads
-- the published Silver tables as `silver.*` (catalog default) and the SIU labels as
-- `bronze.raw_siu_labels`.
--
-- IMPORTANT: silver.claims has a row filter on region. The pipeline owner/run-as must
-- be a member of `pii_authorized` (Session 2), otherwise Southern CA claims are
-- silently dropped from every Gold table.
--
-- Docs:
--   Develop Lakeflow SDP code with SQL:
--     https://learn.microsoft.com/azure/databricks/ldp/developer/sql-dev
--   Window functions: https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-window-functions
--   Date functions:   https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-functions-builtin
-- =============================================================================


-- -----------------------------------------------------------------------------
-- gold.rtw_features  (Return-to-Work regression training set)
-- -----------------------------------------------------------------------------
-- One row per closed claim with the days_to_rtw label. age_band is bucketed from
-- dob at the injury date; tenure_years is injury_date - hire_date; prior_claims_count
-- counts the worker's earlier claims; treatment rollups come from silver.treatments.
CREATE OR REFRESH MATERIALIZED VIEW rtw_features (
  CONSTRAINT valid_claim_id EXPECT (claim_id IS NOT NULL)     ON VIOLATION DROP ROW,
  CONSTRAINT has_label      EXPECT (days_to_rtw IS NOT NULL)  -- warn-only
)
COMMENT 'Gold: one row per closed claim; RTW ML features + days_to_rtw label.'
TBLPROPERTIES ('quality' = 'gold')
AS
WITH base AS (
  SELECT
    claim_id, injury_type, body_part, region, employee_id, injury_date,
    CASE WHEN dob IS NULL THEN NULL
         ELSE floor(datediff(injury_date, dob) / 365.25) END AS age_years,
    count(*) OVER (
      PARTITION BY employee_id ORDER BY injury_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prior_claims_count
  FROM silver.claims
),
treat AS (
  SELECT
    claim_id,
    count(*)                      AS treatment_count,
    max(is_surgery)               AS surgery_flag,
    any_value(provider_specialty) AS provider_specialty
  FROM silver.treatments
  GROUP BY claim_id
)
SELECT
  b.claim_id,
  b.injury_type,
  b.body_part,
  CASE
    WHEN b.age_years IS NULL  THEN NULL
    WHEN b.age_years < 25     THEN '18-24'
    WHEN b.age_years < 35     THEN '25-34'
    WHEN b.age_years < 45     THEN '35-44'
    WHEN b.age_years < 55     THEN '45-54'
    ELSE '55-64'
  END AS age_band,
  e.job_class,
  round(datediff(b.injury_date, e.hire_date) / 365.25, 1) AS tenure_years,
  e.wage_band,
  coalesce(t.treatment_count, 0)                  AS treatment_count,
  datediff(rt.first_treatment_date, b.injury_date) AS days_to_first_treatment,
  coalesce(t.surgery_flag, 0)                     AS surgery_flag,
  t.provider_specialty,
  b.region,
  coalesce(b.prior_claims_count, 0)               AS prior_claims_count,
  datediff(rt.rtw_date, b.injury_date)            AS days_to_rtw
FROM base b
LEFT JOIN silver.employees    e  ON b.employee_id = e.employee_id
LEFT JOIN silver.rtw_timeline rt ON b.claim_id    = rt.claim_id
LEFT JOIN treat               t  ON b.claim_id    = t.claim_id
WHERE rt.rtw_date IS NOT NULL;   -- closed claims only (label present)


-- -----------------------------------------------------------------------------
-- gold.rtw_outcomes_summary  (BI aggregate)
-- -----------------------------------------------------------------------------
-- RTW KPIs by injury_type x region, aggregated from gold.rtw_features. Powers the
-- AI/BI dashboard and Genie ("which injury types have the longest average RTW?").
CREATE OR REFRESH MATERIALIZED VIEW rtw_outcomes_summary
COMMENT 'Gold: RTW KPIs by injury_type x region (BI aggregate).'
TBLPROPERTIES ('quality' = 'gold')
AS
SELECT
  injury_type,
  region,
  count(*)                        AS claim_count,
  round(avg(days_to_rtw), 1)      AS avg_days_to_rtw,
  round(avg(surgery_flag), 2)     AS pct_surgery,
  round(avg(treatment_count), 1)  AS avg_treatment_count
FROM rtw_features
GROUP BY injury_type, region;


-- -----------------------------------------------------------------------------
-- gold.fraud_features  (fraud classification training set)
-- -----------------------------------------------------------------------------
-- One row per LABELED claim (inner join to the SIU labels). Combines structured
-- billing/claim signals with the AI-derived note signals from silver.adjuster_notes.
-- is_fraud is the ground-truth label for the labeled subset only.
CREATE OR REFRESH MATERIALIZED VIEW fraud_features (
  CONSTRAINT valid_claim_id EXPECT (claim_id IS NOT NULL)  ON VIOLATION DROP ROW,
  CONSTRAINT valid_label    EXPECT (is_fraud IN (0, 1))    ON VIOLATION DROP ROW
)
COMMENT 'Gold: one row per labeled claim; fraud features + is_fraud label (SIU subset).'
TBLPROPERTIES ('quality' = 'gold')
AS
WITH labels AS (
  -- External SIU ground truth. Labels are reference data joined at the feature layer.
  SELECT upper(trim(claim_id)) AS claim_id, try_cast(is_fraud AS INT) AS is_fraud
  FROM bronze.raw_siu_labels
),
lines AS (
  SELECT claim_id, provider_npi, service_date, billed_amount
  FROM silver.provider_billing
),
billing AS (
  SELECT
    claim_id,
    sum(billed_amount)         AS billing_total,
    count(DISTINCT provider_npi) AS distinct_providers
  FROM lines
  GROUP BY claim_id
),
claim_ref AS (
  SELECT claim_id, min(service_date) AS ref_date
  FROM lines
  GROUP BY claim_id
),
claim_provider AS (
  SELECT DISTINCT claim_id, provider_npi FROM lines
),
prov_counts AS (
  -- For each (claim, provider), count distinct claims that provider billed within
  -- +/- 30 days of this claim's first service date (a provider-velocity signal).
  SELECT
    cp.claim_id,
    cp.provider_npi,
    count(DISTINCT l2.claim_id) AS prov_30d
  FROM claim_provider cp
  JOIN claim_ref cr ON cp.claim_id = cr.claim_id
  JOIN lines    l2 ON l2.provider_npi = cp.provider_npi
                   AND abs(datediff(l2.service_date, cr.ref_date)) <= 30
  GROUP BY cp.claim_id, cp.provider_npi
),
prov_window AS (
  SELECT claim_id, max(prov_30d) AS provider_claim_count_30d
  FROM prov_counts
  GROUP BY claim_id
),
notes AS (
  SELECT
    claim_id,
    max(CASE WHEN note_category = 'potential_fraud' THEN 1 ELSE 0 END) AS note_fraud_signal,
    max(attorney_flag)                                                 AS attorney_flag
  FROM silver.adjuster_notes
  GROUP BY claim_id
),
prior AS (
  SELECT
    claim_id,
    count(*) OVER (
      PARTITION BY employee_id ORDER BY injury_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
    ) AS prior_claims_count
  FROM silver.claims
)
SELECT
  c.claim_id,
  c.claim_amount,
  coalesce(b.billing_total, 0)                       AS billing_total,
  round(try_divide(b.billing_total, c.claim_amount), 2) AS billing_vs_claim_ratio,
  coalesce(pw.provider_claim_count_30d, 0)           AS provider_claim_count_30d,
  coalesce(b.distinct_providers, 0)                  AS distinct_providers,
  datediff(c.reported_date, c.injury_date)           AS days_injury_to_report,
  CASE WHEN dayofweek(c.injury_date) IN (1, 7) THEN 1 ELSE 0 END AS weekend_injury_flag,
  coalesce(n.note_fraud_signal, 0)                   AS note_fraud_signal,
  coalesce(p.prior_claims_count, 0)                  AS prior_claims_count,
  coalesce(n.attorney_flag, 0)                       AS attorney_flag,
  l.is_fraud
FROM labels l
JOIN silver.claims c  ON c.claim_id = l.claim_id
LEFT JOIN billing      b  ON c.claim_id = b.claim_id
LEFT JOIN prov_window  pw ON c.claim_id = pw.claim_id
LEFT JOIN notes        n  ON c.claim_id = n.claim_id
LEFT JOIN prior        p  ON c.claim_id = p.claim_id;
