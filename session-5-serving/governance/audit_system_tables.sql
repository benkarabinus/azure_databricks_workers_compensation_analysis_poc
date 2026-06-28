-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Session 5 — Audit with system tables
-- MAGIC
-- MAGIC Unity Catalog records access and lineage in the `system` catalog. These queries show who
-- MAGIC touched the POC's tables and how data flows between them. Run interactively on Serverless.
-- MAGIC
-- MAGIC > The `system.access` schemas must be **enabled by an account admin** (and audit events can
-- MAGIC > take time to appear). See the docs link below.
-- MAGIC
-- MAGIC Docs: [Audit log system table](https://learn.microsoft.com/azure/databricks/admin/system-tables/audit-logs)
-- MAGIC · [Data lineage system tables](https://learn.microsoft.com/azure/databricks/admin/system-tables/lineage)

-- COMMAND ----------

-- Recent Unity Catalog access to state_fund_poc objects (last 7 days).
SELECT
  event_time,
  user_identity.email           AS user_email,
  action_name,
  request_params.full_name_arg  AS object_name
FROM system.access.audit
WHERE service_name = 'unityCatalog'
  AND event_time >= current_timestamp() - INTERVAL 7 DAYS
  AND request_params.full_name_arg LIKE 'state_fund_poc.%'
ORDER BY event_time DESC
LIMIT 100;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Table lineage
-- MAGIC Upstream/downstream tables for a Gold table (proves the medallion flow).

-- COMMAND ----------

SELECT DISTINCT
  source_table_full_name,
  target_table_full_name
FROM system.access.table_lineage
WHERE target_table_full_name = 'state_fund_poc.gold.fraud_features'
   OR source_table_full_name LIKE 'state_fund_poc.silver.%'
ORDER BY target_table_full_name
LIMIT 100;
