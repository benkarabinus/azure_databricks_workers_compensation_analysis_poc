-- =============================================================================
-- Session 1 - Bronze ingestion (Lakeflow Spark Declarative Pipelines, SQL)
-- =============================================================================
--
-- This is the SOURCE CODE for a Lakeflow Spark Declarative pipeline, written as a
-- plain .sql source file It lands the five CSV/JSON sources into `bronze.raw_*` streaming
-- tables exactly as they arrive, adding only the lineage columns `_source_file`
-- and `_ingested_at`. Nested JSON arrays are kept intact and no cleaning happens
-- here -- that is Silver's job (Session 2).
--
-- How it works: each source is a `CREATE OR REFRESH STREAMING TABLE` whose query
-- reads `FROM STREAM read_files(...)`. In SQL pipelines, `read_files` invokes
-- Auto Loader functionality and the `STREAM` keyword configures the incremental
-- (streaming) read. SDP evaluates every dataset definition in this file and builds
-- the dataflow graph before running anything, so statement order does not dictate
-- execution order.
--
-- How to run: add this file as source code to a Serverless Lakeflow pipeline whose
-- target catalog is `state_fund_poc` and target schema is `bronze` (see the session
-- README), and add a pipeline Configuration entry for `landing_path` (see the
-- "Landing volume root" section below). The unqualified table names below resolve
-- to that catalog/schema automatically.
--
-- Docs:
--   Develop Lakeflow SDP code with SQL:
--     https://learn.microsoft.com/azure/databricks/ldp/developer/sql-dev
--   Load files with Auto Loader (read_files):
--     https://learn.microsoft.com/azure/databricks/ingestion/cloud-object-storage/auto-loader/
--   read_files table-valued function:
--     https://learn.microsoft.com/azure/databricks/sql/language-manual/functions/read_files
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Landing volume root
-- -----------------------------------------------------------------------------
-- Every table definition below reads the landing volume root via the
-- `${landing_path}` interpolation. Serverless SDP does not support a `SET`
-- statement in source code, so `landing_path` is supplied as a pipeline
-- Configuration key-value pair in the pipeline settings:
--
--     landing_path : /Volumes/state_fund_poc/bronze/landing
--
-- It points at the `bronze.landing` external volume created in
-- 00_create_catalog_and_schemas.sql. Set the value to match your catalog/schema/
-- volume if they differ. See "Reference parameters using the configuration field":
--   https://learn.microsoft.com/azure/databricks/ldp/parameters


-- -----------------------------------------------------------------------------
-- CSV sources: claims, hr, siu_labels
-- -----------------------------------------------------------------------------
-- `inferColumnTypes => false` keeps every column as a string so Bronze preserves
-- the data exactly as landed -- including the dirty patterns (mixed date formats,
-- placeholder nulls, casing) that Silver later cleans. `header => true` uses the
-- first row as column names.

CREATE OR REFRESH STREAMING TABLE raw_claims
  COMMENT 'Raw claims source (csv), as landed.'
  TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/claims',
  format           => 'csv',
  header           => true,
  inferColumnTypes => false
);

CREATE OR REFRESH STREAMING TABLE raw_hr_records
  COMMENT 'Raw HR / employment records source (csv), as landed.'
  TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/hr',
  format           => 'csv',
  header           => true,
  inferColumnTypes => false
);

CREATE OR REFRESH STREAMING TABLE raw_siu_labels
  COMMENT 'Raw SIU fraud labels source (csv), as landed.'
  TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/siu_labels',
  format           => 'csv',
  header           => true,
  inferColumnTypes => false
);


-- -----------------------------------------------------------------------------
-- JSON sources: treatments, billing
-- -----------------------------------------------------------------------------
-- These land as JSON with nested arrays of events per claim. `read_files` infers
-- and preserves the nested structure (arrays of structs) so Bronze keeps the
-- documents intact; Silver flattens them downstream.

CREATE OR REFRESH STREAMING TABLE raw_medical_treatments
  COMMENT 'Raw medical treatments source (json, nested), as landed.'
  TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/treatments',
  format => 'json'
);

CREATE OR REFRESH STREAMING TABLE raw_provider_billing
  COMMENT 'Raw provider billing source (json, nested), as landed.'
  TBLPROPERTIES ('quality' = 'bronze')
AS SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp() AS _ingested_at
FROM STREAM read_files(
  '${landing_path}/billing',
  format => 'json'
);
