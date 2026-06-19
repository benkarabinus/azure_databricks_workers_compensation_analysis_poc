---
applyTo: "**/*.py"
description: "Guidance for PySpark/Python code in the medallion pipeline"
---

# PySpark coding instructions

- Use the PySpark DataFrame API as the default; reserve Spark SQL for readability-heavy logic.
- Make every transformation **idempotent** and **re-runnable**. Use Delta `MERGE` for upserts
  into Silver and Gold rather than blind appends.
- Define explicit schemas (`StructType`) for ingestion instead of relying on schema inference
  in production code paths.
- Parameterize catalogs, schemas, paths, and run dates via Databricks widgets or job parameters—
  never hard-code environment-specific values.
- Keep functions small and testable; isolate pure transformation logic from I/O so it can be unit tested.
- Use `dbutils.secrets` / Key Vault-backed secret scopes for any credentials. Never inline secrets.
- Name DataFrames and columns descriptively; follow `snake_case` for Python identifiers and columns.
- Add data quality validations (null checks, ranges, uniqueness, referential integrity) when
  promoting data from Bronze to Silver.
