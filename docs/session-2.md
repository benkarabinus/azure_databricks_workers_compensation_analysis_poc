---
title: Session 2 — Silver
layout: default
nav_order: 5
---

# Session 2 — Silver: Cleaning, Quality & PII Governance

**Goal:** Transform the raw `bronze.raw_*` tables into governed `silver.*` entities — cleaned,
conformed, deduplicated, quality-checked with DLT Expectations, PII-masked, and (for the notes)
AI-structured.

**Output:** Six Silver tables — `claims`, `employees`, `treatments`, `provider_billing`,
`rtw_timeline`, and `adjuster_notes` — plus a live Unity Catalog column-mask and row-filter demo on
`silver.claims`.

All assets live under `session-2-silver/`. You run two interactive SQL notebooks and one Lakeflow
SQL pipeline.

## Source files

| File | What it is | How you use it |
| --- | --- | --- |
| `security_masking_functions.sql` | SQL notebook that creates Unity Catalog functions to protect sensitive information, (`mask_ssn`, `mask_dob`) + row filter | Import as a notebook, run **before** the pipeline |
| `silver_pipeline.sql` | Lakeflow SDP source (SQL), creates the 5 silver tables | Import as a SQL file, add as pipeline source code |
| `silver_adjuster_notes_ai.sql` | Lakeflow SDP source (SQL), creates AI-enriched notes | Import as a SQL file, add to the same pipeline |
| `grants_and_validation.sql` | SQL notebook, creates Unity Catalog grants for masked vs unmasked permissions on sensitive data and validates the masks work as expected | Import as a notebook, run **after** the pipeline |

## The six Silver tables

| Table | Built from | What happens |
| --- | --- | --- |
| `silver.claims` | `bronze.raw_claims` | Parse 3 date formats, normalize, cast amounts to proper types, null invalid SSNs, dedupe data, **mask SSN/DOB + add a region row filter** |
| `silver.employees` | `bronze.raw_hr_records` | Normalize job class, parse hire date, derive `wage_band`, dedupe records |
| `silver.treatments` | `bronze.raw_medical_treatments` | Explode `events[]`, parse dates, derive `is_surgery` flag|
| `silver.provider_billing` | `bronze.raw_provider_billing` | Explode `billing_lines[]`, cast amounts to proper type |
| `silver.rtw_timeline` | `silver.claims` + treatment events | Derive injury → first-treatment → RTW milestones |
| `silver.adjuster_notes` | `bronze.raw_adjuster_notes` | `ai_query` redaction + `ai_classify` + `ai_extract` |

## Prerequisites

- **Session 1 complete** — the six `bronze.raw_*` tables exist and are populated.
- **UC privileges** to create functions in `state_fund_poc.security` and materialized views in
  `silver`. ([Privileges reference](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/access-control/privileges-reference))
- **Account groups** `analysts` and `pii_authorized`, with the pipeline owner added to
  `pii_authorized`. ([Manage groups](https://learn.microsoft.com/azure/databricks/admin/users-groups/groups))
- **An `ai_query` endpoint** (`databricks-meta-llama-3-3-70b-instruct` or your own) under
  **Serving**. ([Foundation Model APIs](https://learn.microsoft.com/azure/databricks/machine-learning/foundation-model-apis/))

---

## Steps

### 1. Create the masking functions and row filter

Import `security_masking_functions.sql` as an **SQL notebook**, attach to Serverless compute, and run each cell. This creates `security.mask_ssn`, `security.mask_dob`, and `security.claims_region_filter`.
They must exist before the pipeline, which references them inline.

Docs: [Row filters and column masks](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/) ·
[CREATE FUNCTION](https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-syntax-ddl-create-sql-function)

### 2. Create the account groups

In the [account console](https://accounts.azuredatabricks.net) ▸ **Identity and access ▸ Groups**,
create `analysts` and `pii_authorized`. **Add the Silver pipeline's owner to `pii_authorized`.** The row filter checks membership as the pipline invoker identity, so an unauthorized ETL identity would silently drop
`Southern CA` rows from `rtw_timeline` and the Gold features.

Docs: [Manage groups](https://learn.microsoft.com/azure/databricks/admin/users-groups/groups)

### 3. Import the two pipeline source files

Click **Workspace ▸ ⋮ ▸ Import** and import `silver_pipeline.sql` and
`silver_adjuster_notes_ai.sql`.

### 4. Create and run the Silver pipeline

1. Click **Jobs & Pipelines ▸ Create ▸ ETL pipeline**.
2. Copy both SQL files into the new pipeline's **transformations** folder.
3. Set **Default catalog** = `state_fund_poc` and **Default schema** = `silver`.
4. Leave compute **Serverless**.
5. Confirm the pipeline owner/run-as is in `pii_authorized`.
6. Click **Dry run** to test the pipeline.
7. If Dry run completes successfully then click **Start** to run the pipeline.

`silver` now shows the six tables; the pipeline graph shows Expectation pass rates per table.

Docs: [Develop Lakeflow SDP code with SQL](https://learn.microsoft.com/azure/databricks/ldp/developer/sql-dev) ·
[Manage data quality with expectations](https://learn.microsoft.com/azure/databricks/ldp/expectations) ·
[CREATE MATERIALIZED VIEW (MASK / ROW FILTER)](https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-syntax-ddl-create-materialized-view) ·
[AI Functions](https://learn.microsoft.com/azure/databricks/large-language-models/ai-functions)

### 5. Grant access and validate masking

Import `grants_and_validation.sql` as a **SQL notebook** and run each cell. The grants give
`analysts` and `pii_authorized` read access. The validation queries show authorized users seeing
full `ssn`/`dob` and `Southern CA` rows while analysts see `XXX-XX-####`, a Jan-1 birth year, and no
`Southern CA` rows — and confirm the poison row `CLM-00099` and the duplicate `CLM-00006` are gone.

Docs: [GRANT](https://learn.microsoft.com/azure/databricks/sql/language-manual/security-grant) ·
[Row filters and column masks](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/)

---

## Design notes

- **Materialized views + `QUALIFY ROW_NUMBER()`** give simple, correct "latest `_ingested_at` wins"
  dedupe with a full recompute from Bronze. This is a powerfull ETL tool when scanning an entire table to dedupe data or create aggregated tables.
- **Inline masks/filters**: Materialized view column masks and row filters must be declared in the `CREATE`
  statement; the reusable User Defined Functions (UDFs) live once in the `security` schema.
- **PII never lands in the open**: SSN/DOB masked at query time, PII in the adjuster notes is redacted by `ai_query`
  before storage.
- **`silver.claims` is the central facts table** — every everyone joins on `claim_id`. Session 3 builds Gold from here.

## Next

Continue to **Session 3 — Gold, Lineage & Self-Service BI**.
