-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Session 5 — Row filter & column mask demo
-- MAGIC
-- MAGIC Confirms the Unity Catalog governance applied to `silver.claims` in Session 2: the SSN/DOB
-- MAGIC column masks and the `region` row filter. What you see depends on whether you are a member of
-- MAGIC `pii_authorized`. Run interactively on Serverless.
-- MAGIC
-- MAGIC Docs: [Row filters and column masks](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/)

-- COMMAND ----------

USE CATALOG state_fund_poc;

-- COMMAND ----------

-- Who am I, and am I authorized?
SELECT current_user() AS me, is_account_group_member('pii_authorized') AS pii_authorized;

-- COMMAND ----------

-- The masks and row filter bound to the table (see "Column Masks" / "Row Filter").
DESCRIBE EXTENDED silver.claims;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Row filter effect
-- MAGIC Authorized users see all regions; analysts cannot see `Southern CA` rows, so
-- MAGIC `southern_ca_rows` is 0 for them.

-- COMMAND ----------

SELECT
  count(*)                                          AS visible_rows,
  count(*) FILTER (WHERE region = 'Southern CA')    AS southern_ca_rows
FROM silver.claims;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Column mask effect
-- MAGIC Authorized users see real `ssn` / `dob`; analysts see `XXX-XX-####` and a Jan-1 birth year.

-- COMMAND ----------

SELECT claim_id, ssn, dob, region FROM silver.claims ORDER BY claim_id LIMIT 10;
