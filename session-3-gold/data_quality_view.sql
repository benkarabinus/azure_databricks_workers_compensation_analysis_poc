-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Session 3 — Data quality view (Expectation pass rates)
-- MAGIC
-- MAGIC Run this **interactively** (SQL notebook on Serverless) **after** the Silver pipeline has run
-- MAGIC at least once. It creates `gold.data_quality`, a view that surfaces the DLT Expectation
-- MAGIC pass/fail counts from the Silver pipeline's **event log** so analysts can monitor data
-- MAGIC quality without opening the pipeline UI.
-- MAGIC
-- MAGIC `event_log(TABLE(...))` returns the event log for the pipeline that produces the given table.
-- MAGIC We point it at `silver.claims` (any table from the Silver pipeline works — the log covers the
-- MAGIC whole pipeline). The Expectation metrics live in
-- MAGIC `details:flow_progress:data_quality:expectations` on `flow_progress` events.
-- MAGIC
-- MAGIC > **Permissions:** `event_log()` is queryable only by the pipeline's run-as/owner by default,
-- MAGIC > so create this view as that identity (or grant accordingly). To monitor the **Gold**
-- MAGIC > pipeline too, repoint `TABLE(...)` at `gold.fraud_features`.
-- MAGIC
-- MAGIC Docs: [Pipeline event log](https://learn.microsoft.com/azure/databricks/ldp/monitor-event-logs)
-- MAGIC · [event_log function](https://learn.microsoft.com/azure/databricks/sql/language-manual/functions/event_log)
-- MAGIC · [Manage data quality with expectations](https://learn.microsoft.com/azure/databricks/ldp/expectations)

-- COMMAND ----------

USE CATALOG state_fund_poc;

-- COMMAND ----------

CREATE OR REPLACE VIEW gold.data_quality AS
WITH evt AS (
  SELECT
    event_type,
    timestamp,
    origin.update_id AS update_id,
    details
  FROM event_log(TABLE(state_fund_poc.silver.claims))
),
latest_update AS (
  SELECT update_id
  FROM evt
  WHERE event_type = 'create_update'
  ORDER BY timestamp DESC
  LIMIT 1
),
expectations AS (
  SELECT
    explode(
      from_json(
        details:flow_progress:data_quality:expectations,
        'array<struct<name: string, dataset: string, passed_records: bigint, failed_records: bigint>>'
      )
    ) AS e
  FROM evt
  WHERE event_type = 'flow_progress'
    AND update_id = (SELECT update_id FROM latest_update)
)
SELECT
  e.dataset                              AS dataset,
  e.name                                 AS expectation,
  sum(e.passed_records)                  AS passed_records,
  sum(e.failed_records)                  AS failed_records,
  round(100.0 * sum(e.passed_records)
        / nullif(sum(e.passed_records) + sum(e.failed_records), 0), 2) AS pass_rate_pct
FROM expectations e
GROUP BY e.dataset, e.name
ORDER BY e.dataset, e.name;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Review
-- MAGIC Each row is one Expectation: how many records passed/failed in the latest Silver update and
-- MAGIC the pass rate. `FAIL UPDATE` expectations should be 100%; `DROP ROW` expectations show how
-- MAGIC many bad rows were removed; warn-only expectations (e.g. `has_valid_ssn`) track quality %.

-- COMMAND ----------

SELECT * FROM gold.data_quality;
