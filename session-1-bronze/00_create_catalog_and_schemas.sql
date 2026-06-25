-- =============================================================================
-- Session 1 - Foundations: catalog, schemas, and the raw-landing volume.
--
-- Run this in a Databricks SQL editor or a SQL notebook on Serverless SQL.
-- It is idempotent (IF NOT EXISTS), so it is safe to re-run.
--
-- Before running, replace the two placeholders with your Session 0 outputs:
--   <MANAGED_CATALOG_LOCATION>  ->  terraform output managed_catalog_location
--                                   e.g. abfss://state-fund-poc-managed@sfpoclakehouse.dfs.core.windows.net/state_fund_poc
--   <LANDING_LOCATION>          ->  terraform output landing_path
--                                   e.g. abfss://landing@sfpoclakehouse.dfs.core.windows.net/state-fund-poc
--
-- Requires: CREATE CATALOG on the metastore, CREATE MANAGED STORAGE on the
-- `managed` external location, and CREATE EXTERNAL VOLUME on the `landing`
-- external location (held by an account/metastore admin from Session 0).
-- =============================================================================

-- 1. Catalog. Its managed tables (Bronze/Silver/Gold) physically land in the
--    Session 0 `managed` container via this MANAGED LOCATION; the six schemas
--    below inherit it (catalog-level managed storage is the Databricks default).
CREATE CATALOG IF NOT EXISTS state_fund_poc
  MANAGED LOCATION '<MANAGED_CATALOG_LOCATION>'
  COMMENT 'California State Fund - Lane 1 POC (RTW + fraud triage).';

USE CATALOG state_fund_poc;

-- 2. The six medallion + supporting schemas.
CREATE SCHEMA IF NOT EXISTS bronze   COMMENT 'Raw, as-landed ingestion (append-only).';
CREATE SCHEMA IF NOT EXISTS silver   COMMENT 'Cleaned, conformed, governed tables.';
CREATE SCHEMA IF NOT EXISTS gold     COMMENT 'ML-ready features and BI aggregates.';
CREATE SCHEMA IF NOT EXISTS config   COMMENT 'Pipeline configuration and reference data.';
CREATE SCHEMA IF NOT EXISTS security COMMENT 'Column-mask and row-filter functions.';
CREATE SCHEMA IF NOT EXISTS ml       COMMENT 'Registered models.';

-- 3. External volume for the raw source files. Databricks best practice is to
--    register ingestion landing zones as external volumes (not direct path access
--    on the external location). Files uploaded here are read by the Bronze
--    pipelines from /Volumes/state_fund_poc/bronze/landing/<source>/.
--    The LOCATION is a sub-path of the Session 0 `landing` external location,
--    so it never sits at the external location root.
CREATE EXTERNAL VOLUME IF NOT EXISTS bronze.landing
  LOCATION '<LANDING_LOCATION>'
  COMMENT 'Raw source files uploaded for Bronze ingestion.';
