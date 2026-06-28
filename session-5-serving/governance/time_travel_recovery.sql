-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Session 5 — Delta time travel & recovery
-- MAGIC
-- MAGIC Demonstrates Delta Lake versioning on `gold.fraud_scores` (a regular managed table written by
-- MAGIC `batch_score_fraud.py`): inspect history, simulate an accidental delete, read a prior version,
-- MAGIC and recover with `RESTORE`. Run interactively on Serverless **after** batch scoring.
-- MAGIC
-- MAGIC Docs: [Work with Delta table history](https://learn.microsoft.com/azure/databricks/delta/history)
-- MAGIC · [RESTORE](https://learn.microsoft.com/azure/databricks/sql/language-manual/delta-restore)

-- COMMAND ----------

USE CATALOG state_fund_poc;

-- COMMAND ----------

-- Version history (each write/operation is a version).
DESCRIBE HISTORY gold.fraud_scores;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Simulate an accidental change

-- COMMAND ----------

DELETE FROM gold.fraud_scores WHERE risk_tier = 'Low';
SELECT count(*) AS rows_after_delete FROM gold.fraud_scores;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Read a previous version (time travel)
-- MAGIC Version 0 is the first write by the scoring job.

-- COMMAND ----------

SELECT count(*) AS rows_at_version_0 FROM gold.fraud_scores VERSION AS OF 0;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Recover

-- COMMAND ----------

RESTORE TABLE gold.fraud_scores TO VERSION AS OF 0;
SELECT count(*) AS rows_after_restore FROM gold.fraud_scores;
