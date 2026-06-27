-- =============================================================================
-- Session 2 - Silver transformation (Lakeflow Spark Declarative Pipelines, SQL)
-- =============================================================================
--
-- SOURCE CODE for the Silver Lakeflow pipeline (plain .sql source, like Bronze).
-- It cleans, conforms, deduplicates, and quality-checks the Bronze tables into the
-- governed `silver.*` entities, and applies PII protection on `silver.claims`.
--
-- Design (confirmed):
--   * Each Silver table is a MATERIALIZED VIEW that fully recomputes from Bronze.
--   * Deduplication keeps the latest row per business key with
--       QUALIFY ROW_NUMBER() OVER (PARTITION BY key ORDER BY _ingested_at DESC) = 1.
--   * Data quality is enforced with CONSTRAINT ... EXPECT (DLT Expectations).
--   * Structured PII is protected on `silver.claims` with Unity Catalog column
--     masks (security.mask_ssn / security.mask_dob) and a row filter
--     (security.claims_region_filter) declared INLINE in the CREATE statement -
--     MV masks/filters cannot be added later via ALTER TABLE. Create those UDFs
--     first by running security_masking_functions.sql.
--
-- How to run: add this file (plus silver_adjuster_notes_ai.sql) as source code to a
-- Serverless Lakeflow pipeline whose target catalog is `state_fund_poc` and target
-- schema is `silver`. Unqualified table names resolve to that catalog/schema; the
-- pipeline reads the published Bronze tables as `bronze.raw_*` (catalog default).
--
-- Docs:
--   Develop Lakeflow SDP code with SQL:
--     https://learn.microsoft.com/azure/databricks/ldp/developer/sql-dev
--   Manage data quality with pipeline expectations:
--     https://learn.microsoft.com/azure/databricks/ldp/expectations
--   CREATE MATERIALIZED VIEW (column MASK / WITH ROW FILTER):
--     https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-syntax-ddl-create-materialized-view
--   Row filters and column masks:
--     https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/
-- =============================================================================


-- -----------------------------------------------------------------------------
-- silver.claims  (the hub)
-- -----------------------------------------------------------------------------
-- Cleans dirty claims_core data: parses three date formats to ISO DATE, normalizes
-- categoricals, casts the amount, nulls invalid SSNs, normalizes claimant names,
-- and deduplicates CLM-* on the latest ingest. PII is masked via inline column
-- masks; a region row filter is attached. Expectations drop the poison row
-- (future-dated / non-positive amount) and fail the run on a missing claim_id.
CREATE OR REFRESH MATERIALIZED VIEW claims (
  claim_id        STRING  COMMENT 'Cleaned claim id (trimmed/uppercased).',
  claimant_name   STRING  COMMENT 'Normalized to "First Last".',
  ssn             STRING  MASK state_fund_poc.security.mask_ssn COMMENT 'Cleaned SSN; masked unless pii_authorized.',
  dob             DATE    MASK state_fund_poc.security.mask_dob COMMENT 'Parsed DOB; generalized to birth year unless pii_authorized.',
  injury_date     DATE,
  reported_date   DATE,
  injury_type     STRING,
  body_part       STRING,
  claim_status    STRING,
  adjuster_id     STRING,
  region          STRING,
  claim_amount    DECIMAL(12,2),
  employee_id     STRING,
  CONSTRAINT valid_claim_id    EXPECT (claim_id IS NOT NULL)           ON VIOLATION FAIL UPDATE,
  CONSTRAINT positive_amount   EXPECT (claim_amount > 0)               ON VIOLATION DROP ROW,
  CONSTRAINT not_future_injury EXPECT (injury_date <= current_date())  ON VIOLATION DROP ROW,
  CONSTRAINT has_valid_ssn     EXPECT (ssn IS NOT NULL)                -- warn-only: tracks % of rows with a valid SSN
)
COMMENT 'Silver: cleaned, conformed, deduplicated, PII-masked claims (hub; join key claim_id).'
TBLPROPERTIES ('quality' = 'silver')
WITH ROW FILTER state_fund_poc.security.claims_region_filter ON (region)
AS
WITH cleaned AS (
  SELECT
    upper(trim(claim_id)) AS claim_id,
    -- Normalize "Last, First" -> "First Last", collapse whitespace, title-case.
    initcap(regexp_replace(trim(
      CASE WHEN claimant_name LIKE '%,%'
           THEN concat_ws(' ', trim(element_at(split(claimant_name, ','), 2)),
                                trim(element_at(split(claimant_name, ','), 1)))
           ELSE claimant_name END
    ), '\\s+', ' ')) AS claimant_name,
    -- Keep only well-formed SSNs; everything else (e.g. 555-0100, 000000000) -> NULL.
    CASE WHEN trim(ssn) RLIKE '^[0-9]{3}-[0-9]{2}-[0-9]{4}$' AND trim(ssn) <> '000-00-0000'
         THEN trim(ssn) ELSE NULL END AS ssn,
    -- Three source date formats: ISO, US (M/d/yyyy), and DD-MON-YYYY.
    coalesce(try_to_date(trim(dob),           'yyyy-MM-dd'),
             try_to_date(trim(dob),           'M/d/yyyy'),
             try_to_date(trim(dob),           'dd-MMM-yyyy')) AS dob,
    coalesce(try_to_date(trim(injury_date),   'yyyy-MM-dd'),
             try_to_date(trim(injury_date),   'M/d/yyyy'),
             try_to_date(trim(injury_date),   'dd-MMM-yyyy')) AS injury_date,
    coalesce(try_to_date(trim(reported_date), 'yyyy-MM-dd'),
             try_to_date(trim(reported_date), 'M/d/yyyy'),
             try_to_date(trim(reported_date), 'dd-MMM-yyyy')) AS reported_date,
    initcap(lower(trim(injury_type))) AS injury_type,
    initcap(lower(trim(body_part)))   AS body_part,
    upper(trim(claim_status))         AS claim_status,
    upper(trim(adjuster_id))          AS adjuster_id,
    -- Map dirty region values to the canonical set; placeholders (-1, N/A, '') -> NULL.
    CASE lower(trim(region))
      WHEN 'bay area'       THEN 'Bay Area'
      WHEN 'southern ca'    THEN 'Southern CA'
      WHEN 'northern ca'    THEN 'Northern CA'
      WHEN 'central valley' THEN 'Central Valley'
      WHEN 'sacramento'     THEN 'Sacramento'
      WHEN 'inland empire'  THEN 'Inland Empire'
      ELSE NULL
    END AS region,
    try_cast(claim_amount AS DECIMAL(12,2)) AS claim_amount,
    upper(trim(employee_id))                AS employee_id,
    _ingested_at
  FROM bronze.raw_claims
)
SELECT
  claim_id, claimant_name, ssn, dob, injury_date, reported_date,
  injury_type, body_part, claim_status, adjuster_id, region, claim_amount, employee_id
FROM cleaned
QUALIFY ROW_NUMBER() OVER (PARTITION BY claim_id ORDER BY _ingested_at DESC) = 1;


-- -----------------------------------------------------------------------------
-- silver.employees  (worker dimension)
-- -----------------------------------------------------------------------------
-- Cleans HR records into a per-worker dimension. PII (full_name) is intentionally
-- dropped - it is not needed downstream. tenure_years is claim-relative, so it is
-- derived later in Gold (joins injury_date to hire_date), not here.
CREATE OR REFRESH MATERIALIZED VIEW employees (
  CONSTRAINT valid_employee_id EXPECT (employee_id IS NOT NULL) ON VIOLATION FAIL UPDATE,
  CONSTRAINT valid_hire_date   EXPECT (hire_date <= current_date())  -- warn-only
)
COMMENT 'Silver: cleaned HR worker dimension (join key employee_id).'
TBLPROPERTIES ('quality' = 'silver')
AS
WITH cleaned AS (
  SELECT
    upper(trim(employee_id))          AS employee_id,
    initcap(lower(trim(job_class)))   AS job_class,
    coalesce(try_to_date(trim(hire_date), 'yyyy-MM-dd'),
             try_to_date(trim(hire_date), 'M/d/yyyy'),
             try_to_date(trim(hire_date), 'dd-MMM-yyyy')) AS hire_date,
    try_cast(annual_wage AS INT) AS annual_wage,
    upper(trim(employer_id))     AS employer_id,
    _ingested_at
  FROM bronze.raw_hr_records
)
SELECT
  employee_id,
  job_class,
  hire_date,
  annual_wage,
  CASE
    WHEN annual_wage IS NULL    THEN NULL
    WHEN annual_wage < 45000    THEN 'Low'
    WHEN annual_wage <= 90000   THEN 'Mid'
    ELSE 'High'
  END AS wage_band,
  employer_id
FROM cleaned
QUALIFY ROW_NUMBER() OVER (PARTITION BY employee_id ORDER BY _ingested_at DESC) = 1;


-- -----------------------------------------------------------------------------
-- silver.treatments  (exploded treatment events)
-- -----------------------------------------------------------------------------
-- Explodes the nested events[] array to one row per treatment event, parses dates,
-- and derives is_surgery. The return_to_work milestone is excluded here (it feeds
-- silver.rtw_timeline instead). treatment_id is a deterministic surrogate.
CREATE OR REFRESH MATERIALIZED VIEW treatments (
  CONSTRAINT valid_claim_id  EXPECT (claim_id IS NOT NULL)   ON VIOLATION DROP ROW,
  CONSTRAINT valid_event_date EXPECT (event_date IS NOT NULL)  -- warn-only
)
COMMENT 'Silver: one row per treatment event (excludes return_to_work).'
TBLPROPERTIES ('quality' = 'silver')
AS
WITH exploded AS (
  SELECT
    upper(trim(t.claim_id))                AS claim_id,
    try_to_date(e.event_date, 'yyyy-MM-dd') AS event_date,
    lower(trim(e.treatment_type))          AS treatment_type,
    trim(e.provider_npi)                   AS provider_npi,
    trim(e.provider_specialty)             AS provider_specialty
  FROM bronze.raw_medical_treatments t
  LATERAL VIEW explode(t.events) ev AS e
)
SELECT
  concat('TRT-', lpad(cast(
    row_number() OVER (ORDER BY claim_id, event_date, provider_npi, treatment_type) AS STRING), 8, '0')) AS treatment_id,
  claim_id,
  event_date,
  treatment_type,
  provider_npi,
  provider_specialty,
  CASE WHEN treatment_type = 'surgery' THEN 1 ELSE 0 END AS is_surgery
FROM exploded
WHERE treatment_type <> 'return_to_work';


-- -----------------------------------------------------------------------------
-- silver.provider_billing  (exploded billing lines)
-- -----------------------------------------------------------------------------
-- Explodes the nested billing_lines[] array to one row per billing line, casts the
-- amount, and parses the service date. billing_line_id is a deterministic surrogate.
CREATE OR REFRESH MATERIALIZED VIEW provider_billing (
  CONSTRAINT valid_claim_id    EXPECT (claim_id IS NOT NULL)    ON VIOLATION DROP ROW,
  CONSTRAINT positive_amount   EXPECT (billed_amount > 0)       ON VIOLATION DROP ROW
)
COMMENT 'Silver: one row per provider billing line.'
TBLPROPERTIES ('quality' = 'silver')
AS
WITH exploded AS (
  SELECT
    upper(trim(b.claim_id))                   AS claim_id,
    trim(l.billing_code)                      AS billing_code,
    trim(l.provider_npi)                      AS provider_npi,
    try_cast(l.billed_amount AS DECIMAL(12,2)) AS billed_amount,
    try_to_date(l.service_date, 'yyyy-MM-dd')  AS service_date
  FROM bronze.raw_provider_billing b
  LATERAL VIEW explode(b.billing_lines) bl AS l
)
SELECT
  concat('BIL-', lpad(cast(
    row_number() OVER (ORDER BY claim_id, service_date, provider_npi, billing_code) AS STRING), 8, '0')) AS billing_line_id,
  claim_id,
  billing_code,
  provider_npi,
  billed_amount,
  service_date
FROM exploded;


-- -----------------------------------------------------------------------------
-- silver.rtw_timeline  (per-claim RTW milestones)
-- -----------------------------------------------------------------------------
-- One row per claim: injury_date (from silver.claims) plus first_treatment_date and
-- rtw_date derived from the treatment events (the return_to_work event carries the
-- RTW date). rtw_status is OPEN where there is no RTW event. Feeds the days_to_rtw
-- label and days_to_first_treatment feature in Gold.
CREATE OR REFRESH MATERIALIZED VIEW rtw_timeline (
  CONSTRAINT valid_claim_id EXPECT (claim_id IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Silver: per-claim RTW milestones (injury -> first treatment -> return to work).'
TBLPROPERTIES ('quality' = 'silver')
AS
WITH events AS (
  SELECT
    upper(trim(t.claim_id))                AS claim_id,
    lower(trim(e.treatment_type))          AS treatment_type,
    try_to_date(e.event_date, 'yyyy-MM-dd') AS event_date
  FROM bronze.raw_medical_treatments t
  LATERAL VIEW explode(t.events) ev AS e
),
first_treatment AS (
  SELECT claim_id, min(event_date) AS first_treatment_date
  FROM events
  WHERE treatment_type <> 'return_to_work'
  GROUP BY claim_id
),
rtw AS (
  SELECT claim_id, min(event_date) AS rtw_date
  FROM events
  WHERE treatment_type = 'return_to_work'
  GROUP BY claim_id
)
SELECT
  c.claim_id,
  c.injury_date,
  ft.first_treatment_date,
  r.rtw_date,
  CASE WHEN r.rtw_date IS NOT NULL THEN 'RETURNED' ELSE 'OPEN' END AS rtw_status
FROM claims c
LEFT JOIN first_treatment ft ON c.claim_id = ft.claim_id
LEFT JOIN rtw            r  ON c.claim_id = r.claim_id;
