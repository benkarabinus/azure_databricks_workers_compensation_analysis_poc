---
applyTo: "**/*.sql"
description: "Guidance for Spark SQL / Delta Lake SQL in the medallion pipeline"
---

# SQL coding instructions

These rules apply to all SQL in the State Fund Lane 1 POC (serverless Azure Databricks). See [.github/copilot-instructions.md](../copilot-instructions.md) for the full architecture, Unity Catalog layout, and conventions.

## Target & namespace

- Target **Spark SQL** on **Delta Lake** tables governed by Unity Catalog, executed on a **Serverless SQL Warehouse**.
- Single catalog **`state_fund_poc`** with schemas `bronze`, `silver`, `gold`, `config`, `security`, `ml`. Reference tables with the full three-level namespace `catalog.schema.table` (e.g., `state_fund_poc.silver.claims`).
- Use uppercase for SQL keywords and `snake_case` for identifiers; Bronze tables are prefixed `raw_`.

## DDL, DML & layering

- Respect Bronze → Silver → Gold; never read raw source straight into Gold.
- Keep DDL explicit: declare column names, types, and constraints rather than relying on inference. Cast numerics and parse dates to ISO `DATE`/`TIMESTAMP` in Silver.
- Use `MERGE INTO` for idempotent upserts into Silver and Gold; avoid blind appends that break re-runs.
- Avoid `SELECT *` in curated (Gold) outputs; project only the columns required for analytics.
- Add comments describing the medallion layer and business purpose of each table/view.

## Lakeflow Spark Declarative Pipelines (SQL)

- Author pipeline datasets with `CREATE OR REFRESH STREAMING TABLE` (incremental sources) or `CREATE OR REFRESH MATERIALIZED VIEW` (derived/aggregated). Use the `STREAM` keyword to read a source with streaming semantics.
- Ingest files from the landing volume with `FROM STREAM read_files(<path>, format => '<csv|json>', ...)` — `read_files` invokes Auto Loader, and Lakeflow manages the schema location and checkpoint.
- Keep Bronze raw: read CSV with `inferColumnTypes => false` (all strings, as-landed) and preserve nested JSON structure; add `_source_file` (`_metadata.file_path`) and `_ingested_at` (`current_timestamp()`).
- Use **unqualified** table names so writes resolve to the pipeline's target catalog/schema; parameterize paths via the pipeline **Configuration** field (key-value) referenced with `${key}` in SQL — Serverless pipelines do **not** support a `SET` statement in source — never hard-coded environment paths.
- Enforce data quality at the Bronze→Silver boundary with `CONSTRAINT … EXPECT (…) ON VIOLATION {DROP ROW|FAIL UPDATE}`.

## Governance & security

- Define PII protection as Unity Catalog **column-mask functions** (`mask_ssn`, `mask_dob`) and **row-filter functions** in the `security` schema, then attach them to columns/tables — do not embed masking logic inline in every query.
- Validate masking by querying as an analyst vs. a `pii_authorized` member.
- Surface DLT Expectation pass rates as a Gold quality view.
- Use AI Functions (`ai_extract`, `ai_classify`, `ai_query`) on adjuster notes to produce structured fraud/severity signals.
- Do not embed credentials or environment-specific paths; parameterize via job parameters, widgets, or views. Never inline secrets.
