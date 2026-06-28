---
title: Session 1 — Bronze
layout: default
nav_order: 4
---

# Session 1 — Foundations & Bronze Ingestion

**Goal:** Create the `state_fund_poc` catalog and its six schemas, then land all six synthetic
sources **append‑only** into `bronze.raw_*` exactly as they arrive, adding only `_source_file`
and `_ingested_at` columns to the sources.

**Output:** Six Bronze tables — `raw_claims`, `raw_hr_records`, `raw_siu_labels`,
`raw_medical_treatments`, `raw_provider_billing` (Auto Loader) and `raw_adjuster_notes` (Excel) —
with the dirty patterns preserved for Silver to clean in Session 2.

This session is a **UI walkthrough**. The source files live in `session-1-bronze/` in the repository. You import them, then do each step in the Azure Databricks workspace UI. Every step links to the official
Microsoft Learn documentation so users can read in depth about the different Azure Databricks features implemented in this session.

## Source files

| File | What it is | How you use it |
| --- | --- | --- |
| `00_create_catalog_and_schemas.sql` | SQL notebook that creates the state_fund_poc catalog + 6 schemas + raw‑landing external volume | Import as a notebook, then run |
| `bronze_autoloader_pipeline.sql` | Lakeflow SDP pipeline (SQL) — `STREAMING TABLE` + `read_files` for the 5 CSV/JSON sources | Import, attach to a serverless pipeline then run as a serverless pipeline|
| `ingest_adjuster_notes_excel.py` | Serverless notebook — `openpyxl` reads the `.xlsx` | Import, then run as a serverless job |

## Prerequisites

- **Session 0 complete** — a running workspace, with the Terraform outputs handy
  (`terraform output`). You need **`managed_catalog_location`** and **`landing_path`**.
- **Unity Catalog privileges** to create the catalog, managed location, and external volume:
  `CREATE CATALOG`, `CREATE MANAGED STORAGE` on the `managed` external location, and
  `CREATE EXTERNAL VOLUME` on the `landing` external location — held by the account/metastore admin
  from Session 0. ([Admin privileges](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/manage-privileges/admin-privileges))
- **The synthetic data files** (located in the **data** directory of the dowloaded git repository).

## The six sources

| Source file | Folder in the volume | Bronze table | Ingested by |
| --- | --- | --- | --- |
| `claims_core.csv` | `claims/` | `bronze.raw_claims` | Auto Loader (CSV) |
| `hr_records.csv` | `hr/` | `bronze.raw_hr_records` | Auto Loader (CSV) |
| `siu_labels.csv` | `siu_labels/` | `bronze.raw_siu_labels` | Auto Loader (CSV) |
| `medical_treatments.json` | `treatments/` | `bronze.raw_medical_treatments` | Auto Loader (JSON) |
| `provider_billing.json` | `billing/` | `bronze.raw_provider_billing` | Auto Loader (JSON) |
| `adjuster_notes.xlsx` | `notes/` | `bronze.raw_adjuster_notes` | Excel notebook (`openpyxl`) |

---

## Steps

### 1. Create the catalog, schemas, and landing volume

1. **Import the notebook:** click **Workspace**, choose a folder, then **⋮ ▸ Import**, and upload
   `00_create_catalog_and_schemas.sql`. It imports as a **SQL notebook** — one step per cell, with a
   markdown explanation above each.
   ([Import a notebook](https://learn.microsoft.com/azure/databricks/notebooks/notebooks-manage))
2. Attach it to Serverless compute.
3. In the two `CREATE` cells, replace the placeholders with your Session 0 outputs:
   - `<MANAGED_CATALOG_LOCATION>` → `managed_catalog_location`
     (`abfss://state-fund-poc-managed@<storage>.dfs.core.windows.net/state_fund_poc`).
   - `<LANDING_LOCATION>` → `landing_path`
     (`abfss://landing@<storage>.dfs.core.windows.net/state-fund-poc`).
4. **Run all** cells. The last two cells verify the schemas and volume.

Confirm in **Catalog** that `state_fund_poc` shows the six schemas and a **Volumes ▸ landing** entry.

Docs: [Manage notebooks](https://learn.microsoft.com/azure/databricks/notebooks/notebooks-manage) ·
[Create catalogs](https://learn.microsoft.com/azure/databricks/catalogs/create-catalog) ·
[Create and manage Unity Catalog Volumes](https://learn.microsoft.com/en-us/azure/databricks/volumes/utility-commands)

### 2. Upload the six source files to the landing volume

1. Click **Catalog**, then browse to **`state_fund_poc` ▸ `bronze` ▸ Volumes ▸ `landing`**.
2. Click **Create directory** and add one folder per source: `claims`, `hr`, `siu_labels`,
   `treatments`, `billing`, `notes`.
3. Open each folder, click **Upload to this volume**, and upload the matching file per the table
   above.

> Each source goes in its own folder because Auto Loader watches one directory per table. The
> folder names must match the table above.

Docs: [Work with files in Unity Catalog volumes — upload](https://learn.microsoft.com/azure/databricks/volumes/volume-files#use-catalog-explorer) ·
[Privileges reference](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/access-control/privileges-reference)

### 3. Import the pipeline source and Excel notebook

1. Click **Workspace**, pick a folder, then **⋮ ▸ Import**.
2. Import `bronze_autoloader_pipeline.sql` (it imports as a workspace SQL file for use in a Lakeflow
   pipeline source, not a notebook) and `ingest_adjuster_notes_excel.py` (it imports as a notebook whic is fine since it will be run via a Databricks job).

Docs: [Manage notebooks — import](https://learn.microsoft.com/azure/databricks/notebooks/notebooks-manage)

### 4. Create and run the Bronze Auto Loader pipeline

The SQL `read_files` function invokes Auto Loader to incrementally ingest the five CSV/JSON sources into streaming tables. Lakeflow manages the schema location and checkpoint for you.
([What is Auto Loader?](https://learn.microsoft.com/azure/databricks/ingestion/cloud-object-storage/auto-loader/))

1. Click **Jobs & Pipelines ▸ Create ▸ ETL pipeline**.
2. Move the imported `bronze_autoloader_pipeline.sql` file int to the **transformations** folder in the new pipeline.
3. Set **Default catalog** = `state_fund_poc` and **Default schema** = `bronze`.
4. Click **Settings** and, in the **Configuration** section, add the key‑value pair
   `landing_path` = `/Volumes/state_fund_poc/bronze/landing` so the pipeline can resolve
5. Click **Dry run** to test the pipeline.
6. If the Dry run completes successfully click **Start** to run the pipeline and create the bronze tables.

`bronze` now shows `raw_claims`, `raw_hr_records`, `raw_siu_labels`, `raw_medical_treatments`, and
`raw_provider_billing`.

Docs: [Tutorial: build an ETL pipeline with Lakeflow](https://learn.microsoft.com/azure/databricks/getting-started/data-pipeline-get-started) ·
[Develop Lakeflow SDP code with SQL](https://learn.microsoft.com/azure/databricks/ldp/developer/sql-dev) ·
[Use parameters with pipelines](https://learn.microsoft.com/azure/databricks/ldp/parameters) ·
[Load files from cloud object storage in pipelines](https://learn.microsoft.com/azure/databricks/ldp/load#load-files-from-cloud-object-storage)

### 5. Run the Excel ingest as a serverless job

Auto Loader can't read `.xlsx`, so a notebook reads the workbook with `openpyxl` and overwrites
`bronze.raw_adjuster_notes` (idempotent).

1. Click **Jobs & Pipelines ▸ Create ▸ Job**.
2. Add a **Notebook** task pointing at `ingest_adjuster_notes_excel`.
3. Leave **Compute = Serverless**.
4. Click **Run now**.

Docs: [Run jobs on serverless compute](https://learn.microsoft.com/azure/databricks/jobs/run-serverless-jobs#create-a-job-using-serverless-compute) ·
[Serverless compute for notebooks](https://learn.microsoft.com/azure/databricks/compute/serverless/notebooks)

### 6. Verify Bronze

In the SQL editor:

```sql
USE CATALOG state_fund_poc;

SELECT 'raw_claims' AS tbl, count(*) AS rows FROM bronze.raw_claims
UNION ALL SELECT 'raw_hr_records',         count(*) FROM bronze.raw_hr_records
UNION ALL SELECT 'raw_siu_labels',         count(*) FROM bronze.raw_siu_labels
UNION ALL SELECT 'raw_medical_treatments', count(*) FROM bronze.raw_medical_treatments
UNION ALL SELECT 'raw_provider_billing',   count(*) FROM bronze.raw_provider_billing
UNION ALL SELECT 'raw_adjuster_notes',     count(*) FROM bronze.raw_adjuster_notes;

SELECT claim_id, _source_file, _ingested_at FROM bronze.raw_claims WHERE claim_id = 'CLM-00002';
```

`CLM-00002` (and the deliberately duplicated/dirty rows) are preserved as‑landed — Session 2 cleans,
conforms, and masks them.

## Next

Continue to **Session 2 — Silver: Cleaning, Quality & PII Governance**.

## References

- [What is Auto Loader?](https://learn.microsoft.com/azure/databricks/ingestion/cloud-object-storage/auto-loader/) ·
  [Lakeflow Declarative Pipelines](https://learn.microsoft.com/azure/databricks/ldp/)
- [Work with Unity Catalog volumes](https://learn.microsoft.com/azure/databricks/volumes/) ·
  [CREATE VOLUME](https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-syntax-ddl-create-volume)
- [Create catalogs](https://learn.microsoft.com/azure/databricks/catalogs/create-catalog) ·
  [Run jobs on serverless compute](https://learn.microsoft.com/azure/databricks/jobs/run-serverless-jobs)
