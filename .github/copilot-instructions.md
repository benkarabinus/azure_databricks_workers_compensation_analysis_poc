# GitHub Copilot Instructions

These instructions apply to the entire repository and give GitHub Copilot context about
how to work in this codebase.

## Project overview

This repository is a proof of concept that demonstrates an end-to-end workflow for
ingesting, transforming, curating, and serving **workers' compensation** data for
analysis. It uses **Azure Databricks** and follows a **medallion architecture**
(Bronze → Silver → Gold).

- **Bronze**: Raw, immutable landing of source data exactly as ingested.
- **Silver**: Cleansed, conformed, and de-duplicated data with enforced schema and data quality.
- **Gold**: Curated, business-ready aggregates and dimensional models for analytics and reporting.

## Tech stack & conventions

- **Platform**: Azure Databricks (Spark).
- **Languages**: Python (PySpark) and SQL. Prefer PySpark DataFrame APIs; use Spark SQL where it improves clarity.
- **Storage format**: Delta Lake tables stored in ADLS Gen2 / Unity Catalog.
- **Orchestration**: Databricks Workflows / Jobs.
- Use the **three-level Unity Catalog namespace** (`catalog.schema.table`) where applicable.
- Keep notebooks idempotent and re-runnable; avoid hard-coded absolute paths—parameterize with widgets or config.

## Coding guidelines

- Write clear, well-structured PySpark following the existing layer (bronze/silver/gold) the file belongs to.
- Make transformations deterministic and idempotent (use `MERGE`/upsert patterns for Silver/Gold).
- Enforce and document schemas explicitly rather than relying on inference for production paths.
- Add data quality checks (null, range, referential, and uniqueness) when promoting Bronze → Silver.
- Never commit secrets. Use Databricks secret scopes or Azure Key Vault references.
- Prefer configuration (widgets, job parameters, config files) over hard-coded values for catalogs, schemas, paths, and dates.

## What to avoid

- Do not introduce credentials, connection strings, or tokens into code or notebooks.
- Do not bypass the medallion layering (e.g., reading raw source directly into Gold).
- Do not add heavyweight dependencies or refactor unrelated code unless requested.
