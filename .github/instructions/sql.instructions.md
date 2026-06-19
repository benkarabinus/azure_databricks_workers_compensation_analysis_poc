---
applyTo: "**/*.sql"
description: "Guidance for Spark SQL / Delta Lake SQL in the medallion pipeline"
---

# SQL coding instructions

- Target **Spark SQL** on **Delta Lake** tables managed by Unity Catalog.
- Reference tables with the full three-level namespace `catalog.schema.table` where applicable.
- Use `MERGE INTO` for idempotent upserts into Silver and Gold tables.
- Keep DDL explicit: declare column names, types, and constraints rather than relying on inference.
- Use uppercase for SQL keywords and `snake_case` for identifiers.
- Add comments describing the medallion layer and business purpose of each table/view.
- Avoid `SELECT *` in curated (Gold) layer outputs; project only the columns required for analytics.
- Do not embed credentials or environment-specific paths; parameterize via job parameters or views.
