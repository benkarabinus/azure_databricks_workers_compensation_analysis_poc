-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Session 1 — Foundations: catalog, schemas, and the raw-landing volume
-- MAGIC
-- MAGIC This SQL notebook creates the `state_fund_poc` catalog, its six schemas, and the
-- MAGIC `bronze.landing` external volume that the Bronze pipelines read from. It is **idempotent**
-- MAGIC (`IF NOT EXISTS` everywhere), so it is safe to re-run.
-- MAGIC
-- MAGIC **Run on:** a Serverless SQL warehouse, or attach this notebook to Serverless compute.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Before you run
-- MAGIC
-- MAGIC Replace the two placeholders in the `CREATE` cells below with your **Session 0 Terraform
-- MAGIC outputs** (run `terraform output` in `session-0-setup/terraform/`):
-- MAGIC
-- MAGIC | Placeholder | Terraform output | Example |
-- MAGIC | --- | --- | --- |
-- MAGIC | `<MANAGED_CATALOG_LOCATION>` | `managed_catalog_location` | `abfss://state-fund-poc-managed@sfpoclakehouse.dfs.core.windows.net/state_fund_poc` |
-- MAGIC | `<LANDING_LOCATION>` | `landing_path` | `abfss://landing@sfpoclakehouse.dfs.core.windows.net/state-fund-poc` |
-- MAGIC
-- MAGIC **Requires** (from the Session 0 account/metastore admin): `CREATE CATALOG` on the metastore,
-- MAGIC `CREATE MANAGED STORAGE` on the `managed` external location, and `CREATE EXTERNAL VOLUME` on
-- MAGIC the `landing` external location.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 1. Create the catalog
-- MAGIC
-- MAGIC The catalog's managed tables (Bronze/Silver/Gold) physically land in the Session 0 `managed`
-- MAGIC container via this `MANAGED LOCATION`. The six schemas below **inherit** it — catalog-level
-- MAGIC managed storage is the Databricks-recommended default unit of data isolation.

-- COMMAND ----------

CREATE CATALOG IF NOT EXISTS state_fund_poc
  MANAGED LOCATION '<MANAGED_CATALOG_LOCATION>'
  COMMENT 'California State Fund - Lane 1 POC (RTW + fraud triage).';

-- COMMAND ----------

-- Make state_fund_poc the active catalog for the statements that follow.
USE CATALOG state_fund_poc;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 2. Create the six schemas
-- MAGIC
-- MAGIC The three medallion layers (`bronze`/`silver`/`gold`) plus three supporting schemas:
-- MAGIC `config` (reference data), `security` (masking & row-filter functions), and `ml`
-- MAGIC (registered models).

-- COMMAND ----------

CREATE SCHEMA IF NOT EXISTS bronze   COMMENT 'Raw, as-landed ingestion (append-only).';
CREATE SCHEMA IF NOT EXISTS silver   COMMENT 'Cleaned, conformed, governed tables.';
CREATE SCHEMA IF NOT EXISTS gold     COMMENT 'ML-ready features and BI aggregates.';
CREATE SCHEMA IF NOT EXISTS config   COMMENT 'Pipeline configuration and reference data.';
CREATE SCHEMA IF NOT EXISTS security COMMENT 'Column-mask and row-filter functions.';
CREATE SCHEMA IF NOT EXISTS ml       COMMENT 'Registered models.';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 3. Create the raw-landing external volume
-- MAGIC
-- MAGIC Databricks best practice is to register ingestion landing zones as **external volumes**
-- MAGIC (not direct path access on an external location). You'll upload the six source files here in
-- MAGIC the next step, and the Bronze pipelines read them from
-- MAGIC `/Volumes/state_fund_poc/bronze/landing/<source>/`.
-- MAGIC
-- MAGIC The `LOCATION` is a **sub-path** of the Session 0 `landing` external location, so the volume
-- MAGIC never sits at the external location root.

-- COMMAND ----------

CREATE EXTERNAL VOLUME IF NOT EXISTS bronze.landing
  LOCATION '<LANDING_LOCATION>'
  COMMENT 'Raw source files uploaded for Bronze ingestion.';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 4. Verify
-- MAGIC
-- MAGIC Confirm the six schemas and the landing volume exist.

-- COMMAND ----------

SHOW SCHEMAS IN state_fund_poc;

-- COMMAND ----------

DESCRIBE VOLUME state_fund_poc.bronze.landing;
