-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Session 2 — Unity Catalog masking functions & row filter
-- MAGIC
-- MAGIC Run this **interactively** (SQL notebook on Serverless) **before** you create the Silver
-- MAGIC pipeline. It defines three reusable Unity Catalog SQL UDFs in the `security` schema:
-- MAGIC
-- MAGIC | Function | Type | Applied to |
-- MAGIC | --- | --- | --- |
-- MAGIC | `security.mask_ssn` | column mask | `silver.claims.ssn` |
-- MAGIC | `security.mask_dob` | column mask | `silver.claims.dob` |
-- MAGIC | `security.claims_region_filter` | row filter | `silver.claims` (on `region`) |
-- MAGIC
-- MAGIC The Silver pipeline attaches these **inline** in its `CREATE MATERIALIZED VIEW claims`
-- MAGIC statement (`ssn STRING MASK security.mask_ssn`, `WITH ROW FILTER security.claims_region_filter
-- MAGIC ON (region)`). Materialized views require masks/filters to be declared in the `CREATE`
-- MAGIC statement — they **cannot** be added later with `ALTER TABLE` — so these functions must
-- MAGIC exist first.
-- MAGIC
-- MAGIC Each function checks `is_account_group_member('pii_authorized')`: members of that account
-- MAGIC group see the real value / all rows; everyone else sees the masked value / a filtered subset.
-- MAGIC `is_account_group_member` returns `false` (not an error) if the group does not exist yet, so
-- MAGIC these are safe to create before the group is provisioned.
-- MAGIC
-- MAGIC Docs: [Row filters and column masks](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/)
-- MAGIC · [CREATE FUNCTION (SQL)](https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-syntax-ddl-create-sql-function)
-- MAGIC · [is_account_group_member](https://learn.microsoft.com/azure/databricks/sql/language-manual/functions/is_account_group_member)

-- COMMAND ----------

USE CATALOG state_fund_poc;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Column mask — SSN
-- MAGIC Authorized users see the full SSN; everyone else sees only the last four digits
-- MAGIC (`XXX-XX-6789`). NULLs (invalid SSNs nulled out in Silver) stay NULL.

-- COMMAND ----------

CREATE OR REPLACE FUNCTION security.mask_ssn(ssn STRING)
  RETURNS STRING
  RETURN CASE
    WHEN is_account_group_member('pii_authorized') THEN ssn
    WHEN ssn IS NULL THEN NULL
    ELSE concat('XXX-XX-', substr(ssn, -4))
  END;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Column mask — date of birth
-- MAGIC Authorized users see the full date of birth; everyone else sees it generalized to
-- MAGIC January 1 of the birth year (enough to derive an age band without exposing the exact date).

-- COMMAND ----------

CREATE OR REPLACE FUNCTION security.mask_dob(dob DATE)
  RETURNS DATE
  RETURN CASE
    WHEN is_account_group_member('pii_authorized') THEN dob
    WHEN dob IS NULL THEN NULL
    ELSE make_date(year(dob), 1, 1)
  END;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Row filter — region
-- MAGIC A simple row-level security demo: authorized users see every claim; everyone else cannot
-- MAGIC see `Southern CA` claims. `coalesce` keeps rows whose region was nulled during cleaning
-- MAGIC visible to analysts. Swap in your own predicate (or a region-to-group mapping) as needed.

-- COMMAND ----------

CREATE OR REPLACE FUNCTION security.claims_region_filter(region STRING)
  RETURNS BOOLEAN
  RETURN is_account_group_member('pii_authorized')
      OR coalesce(region, '') <> 'Southern CA';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Verify
-- MAGIC Confirm the three functions exist in the `security` schema.

-- COMMAND ----------

SHOW FUNCTIONS IN security LIKE '*mask*';

-- COMMAND ----------

SHOW FUNCTIONS IN security LIKE '*filter*';
