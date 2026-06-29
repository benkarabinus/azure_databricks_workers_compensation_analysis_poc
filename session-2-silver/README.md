# Session 2 — Silver: Cleaning, Quality & PII Governance

**Goal:** Transform the raw `bronze.raw_*` tables into governed `silver.*` entities — cleaned,
conformed, deduplicated, quality-checked with DLT Expectations, PII-masked, and (for the notes)
AI-structured.

**Output:** Six Silver tables — `claims` (the hub), `employees`, `treatments`,
`provider_billing`, `rtw_timeline`, and `adjuster_notes` — plus a live demo of Unity Catalog
column masks and a row filter on `silver.claims`.

This session is a **UI walkthrough**: you run two interactive SQL notebooks and one Lakeflow SQL
pipeline (two source files). Every step links to the official Microsoft Learn documentation.

## Files in this folder

| File | What it is | How you use it |
| --- | --- | --- |
| [security_masking_functions.sql](security_masking_functions.sql) | Interactive SQL notebook — UC column masks (`mask_ssn`, `mask_dob`) + row filter (`claims_region_filter`) in the `security` schema | Import as a notebook, run **before** the pipeline |
| [silver_pipeline.sql](silver_pipeline.sql) | Lakeflow SDP pipeline source (SQL) — the five conformed entities | Import as a SQL file, add as pipeline source code |
| [silver_adjuster_notes_ai.sql](silver_adjuster_notes_ai.sql) | Lakeflow SDP pipeline source (SQL) — AI-enriched notes | Import as a SQL file, add to the same pipeline |
| [grants_and_validation.sql](grants_and_validation.sql) | Interactive SQL notebook — grants + masked-vs-unmasked validation | Import as a notebook, run **after** the pipeline |

## Prerequisites

- **Session 1 complete** — the six `bronze.raw_*` tables exist and are populated.
- **Unity Catalog privileges** to create functions in `state_fund_poc.security` and the Silver
  tables: `CREATE FUNCTION` on the `security` schema and `CREATE MATERIALIZED VIEW` on `silver`
  (held by the metastore admin from Session 0).
  ([Privileges reference](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/access-control/privileges-reference))
- **Two account groups** — `analysts` and `pii_authorized` — created in the
  [account console](https://accounts.azuredatabricks.net). Add the **pipeline owner** to
  `pii_authorized` (see Step 4). ([Manage groups](https://learn.microsoft.com/azure/databricks/admin/users-groups/groups))
- **A model-serving endpoint for `ai_query`** (the notes redaction). The pipeline uses the
  pay-per-token `databricks-meta-llama-3-3-70b-instruct`; confirm it exists (or substitute one)
  under **Serving**. ([Foundation Model APIs](https://learn.microsoft.com/azure/databricks/machine-learning/foundation-model-apis/))

## The six Silver tables

| Table | Built from | What happens |
| --- | --- | --- |
| `silver.claims` | `bronze.raw_claims` | Parse 3 date formats, normalize categoricals, cast amount, null invalid SSNs, dedupe, **mask SSN/DOB + region row filter** |
| `silver.employees` | `bronze.raw_hr_records` | Normalize job class, parse hire date, derive `wage_band`, dedupe; drop unused PII |
| `silver.treatments` | `bronze.raw_medical_treatments` | Explode `events[]`, parse dates, derive `is_surgery` (excludes `return_to_work`) |
| `silver.provider_billing` | `bronze.raw_provider_billing` | Explode `billing_lines[]`, cast amounts, parse dates |
| `silver.rtw_timeline` | `silver.claims` + treatment events | Derive injury → first-treatment → RTW milestones + `rtw_status` |
| `silver.adjuster_notes` | `bronze.raw_adjuster_notes` | `ai_query` PII redaction + `ai_classify` + `ai_extract` |

---

## Steps

### 1. Create the masking functions and row filter

These Unity Catalog UDFs must exist **before** the pipeline runs, because `silver.claims`
references them inline (materialized-view masks/filters can only be declared in the `CREATE`
statement, not added later with `ALTER TABLE`).

1. Import [security_masking_functions.sql](security_masking_functions.sql) as a **SQL notebook**
   and attach **Serverless**.
2. **Run all** cells. This creates `security.mask_ssn`, `security.mask_dob`, and
   `security.claims_region_filter`, then lists them.

Docs: [Row filters and column masks](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/) ·
[CREATE FUNCTION](https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-syntax-ddl-create-sql-function) ·
[is_account_group_member](https://learn.microsoft.com/azure/databricks/sql/language-manual/functions/is_account_group_member)

### 2. Create the account groups

In the [account console](https://accounts.azuredatabricks.net) ▸ **Identity and access ▸ Groups**,
create `analysts` and `pii_authorized`. Add the identity that will **own/run the Silver pipeline**
(you) to `pii_authorized` — the row filter evaluates group membership as the invoker, so an
unauthorized ETL identity would silently drop `Southern CA` rows from every downstream table.

Docs: [Manage groups](https://learn.microsoft.com/azure/databricks/admin/users-groups/groups) ·
[Manually apply row filters and column masks](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/manually-apply)

### 3. Import the two pipeline source files

1. In the sidebar, click **Workspace**, pick a folder, then **⋮ (kebab) ▸ Import**.
2. Import [silver_pipeline.sql](silver_pipeline.sql) and
   [silver_adjuster_notes_ai.sql](silver_adjuster_notes_ai.sql) — both import as workspace **SQL
   files** (plain Lakeflow pipeline sources).

Docs: [Manage notebooks — import](https://learn.microsoft.com/azure/databricks/notebooks/notebooks-manage)

### 4. Create and run the Silver pipeline

Each Silver table is a **materialized view** that recomputes from Bronze and dedupes with
`QUALIFY ROW_NUMBER()`; DLT Expectations drop/flag bad rows; `silver.claims` carries the inline
column masks and row filter.

1. In the sidebar, click **Jobs & Pipelines ▸ Create ▸ ETL pipeline** (Lakeflow Declarative
   Pipeline).
2. Copy **both** `silver_pipeline.sql` and `silver_adjuster_notes_ai.sql` into the new pipeline's **transformations** folder.
3. Set **Default catalog** = `state_fund_poc` and **Default schema** = `silver`.
4. Leave compute **Serverless** (the default).
5. Confirm the pipeline **owner / run-as** identity is a member of `pii_authorized` (Step 2).
6. Click **Dry run** to validate the pipeline.
7. If the dry run succeeds, click **Start** to run it.

When it finishes, **Catalog ▸ `state_fund_poc` ▸ `silver`** shows the six tables. Open the pipeline
graph to see the dataflow and the Expectation pass rates per table.

Docs: [Develop Lakeflow SDP code with SQL](https://learn.microsoft.com/azure/databricks/ldp/developer/sql-dev) ·
[Manage data quality with expectations](https://learn.microsoft.com/azure/databricks/ldp/expectations) ·
[CREATE MATERIALIZED VIEW (MASK / ROW FILTER)](https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-syntax-ddl-create-materialized-view) ·
[AI Functions](https://learn.microsoft.com/azure/databricks/large-language-models/ai-functions)

### 5. Grant access and validate masking

1. Import [grants_and_validation.sql](grants_and_validation.sql) as a **SQL notebook**, attach
   Serverless, and **Run all**.
2. The grants give `analysts` and `pii_authorized` read access. The validation queries show:
   - As a `pii_authorized` member (you): full `ssn`/`dob` and `Southern CA` rows.
   - As an `analysts` member: `XXX-XX-####`, a Jan-1 birth year, and no `Southern CA` rows.
   - `CLM-00099` (poison) and the duplicate `CLM-00006` are gone; invalid SSNs are `NULL`.

Docs: [GRANT](https://learn.microsoft.com/azure/databricks/sql/language-manual/security-grant) ·
[Row filters and column masks](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/)

---

## Design notes

- **Why materialized views?** Silver fully recomputes from Bronze each run, so dedupe (`QUALIFY
  ROW_NUMBER() OVER (PARTITION BY key ORDER BY _ingested_at DESC) = 1`) is simple and correct. MVs
  with Expectations always full-refresh — fine for a POC.
- **Why inline masks?** Materialized-view column masks and row filters must be declared in the
  `CREATE` statement; they can't be attached afterward with `ALTER TABLE`. The reusable UDFs live
  once in the `security` schema and are referenced from the pipeline.
- **PII never lands in the open.** Structured PII (SSN, DOB) is masked at query time; unstructured
  PII in notes is redacted by `ai_query` before it is stored, so `silver.adjuster_notes` holds no
  raw identifiers.
- **`silver.claims` is the hub.** Every spoke joins back on `claim_id` (or `employee_id` for the
  worker dimension). Session 3 builds Gold features off these tables.

## Next

Continue to **Session 3 — Gold, Lineage & Self-Service BI**. See the
[Deployment Guide](../DEPLOYMENT_GUIDE.md).
