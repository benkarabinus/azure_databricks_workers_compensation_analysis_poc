---
applyTo: "**/*.py"
description: "Guidance for PySpark/Python code in the medallion pipeline"
---

# PySpark coding instructions

These rules apply to all Python in the State Fund Lane 1 POC (serverless Azure Databricks). See [.github/copilot-instructions.md](../copilot-instructions.md) for the full architecture, Unity Catalog layout, and conventions.

## Platform & compute

- All compute is **serverless** — no classic clusters or cluster-config code. Author Serverless DLT (Lakeflow Pipelines), Serverless Jobs notebooks, and helper modules.
- Use the PySpark DataFrame API as the default; reserve Spark SQL for readability-heavy logic.
- Don't create a `SparkSession` manually in notebooks; use the provided `spark`. Don't call `spark.stop()`.

## Medallion layering

- Respect Bronze → Silver → Gold; never read raw source straight into Gold. Bronze is raw/append-only; Silver is cleansed/conformed/masked; Gold is curated features and aggregates.
- **Bronze:** CSV/JSON are ingested by a **Lakeflow SQL pipeline** (`CREATE OR REFRESH STREAMING TABLE` + `read_files`, which invokes Auto Loader) — see [sql.instructions.md](sql.instructions.md); Python here covers only the `.xlsx` source via an `openpyxl` Serverless Job notebook. Keep nested JSON arrays intact. Add `_source_file` and `_ingested_at`; do not drop them until Silver.
- **Silver:** clean, conform, deduplicate (latest `_ingested_at` wins), cast numerics, and parse dates to ISO `DATE`/`TIMESTAMP`. `silver.claims` is the hub; join spokes on `claim_id` (or `employee_id`).
- **Gold:** build `rtw_features` / `fraud_features` (one row per `claim_id`) and BI aggregates.

## Idempotency, schemas & quality

- Make every transformation **idempotent** and **re-runnable**. Use Delta `MERGE`/upsert for Silver and Gold rather than blind appends.
- Define explicit schemas (`StructType`) for ingestion instead of relying on schema inference in production paths.
- In DLT, enforce quality with **Expectations** (`@dlt.expect*`) at the Bronze→Silver boundary — fail on critical violations (`claim_id IS NOT NULL`), drop invalid rows (`claim_amount > 0`, future dates), and track warn-only checks as a quality %.

## Governance & security

- Apply PII masking via Unity Catalog column-mask functions (defined in the `security` schema) and row filters — do not hand-roll masking in PySpark for structured PII (SSN/DOB).
- Redact unstructured PII in adjuster notes via `ai_query`/Presidio; structure notes with `ai_extract` / `ai_classify`.
- Use Databricks **secret scopes** (or Key Vault-backed scopes) for any credentials. Never inline secrets, keys, or connection strings.

## Config, naming & ML

- Parameterize the catalog (`state_fund_poc`), schema, and ADLS paths via widgets or job parameters — never hard-code environment-specific values. Prefer the shared helpers in `common/config.py`.
- Use the three-level namespace `catalog.schema.table` (e.g., `state_fund_poc.silver.claims`); `snake_case` identifiers; Bronze tables prefixed `raw_`.
- ML: train with AutoML, track with MLflow, and register models to Unity Catalog (`state_fund_poc.ml.rtw_model`, `state_fund_poc.ml.fraud_model`). Evaluate RTW on RMSE/MAE and fraud on **PR-AUC** (not accuracy).
- Keep functions small and testable; isolate pure transformation logic from I/O.
- All data is synthetic — never use real claimant data.
