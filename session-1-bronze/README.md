# Session 1 — Foundations & Bronze Ingestion

**Goal:** Create the `state_fund_poc` catalog and its six schemas, then land all six synthetic
sources **append‑only** into `bronze.raw_*` — exactly as they arrive, adding only `_source_file`
and `_ingested_at`.

**Output:** Six Bronze tables — `raw_claims`, `raw_hr_records`, `raw_siu_labels`,
`raw_medical_treatments`, `raw_provider_billing` (Auto Loader) and `raw_adjuster_notes` (Excel) —
with the dirty patterns preserved for Silver to clean in Session 2.

This session is a **UI walkthrough**: you import the source files in this folder, then do each step
in the Databricks workspace. Every step links to the official Microsoft Learn documentation.

## Files in this folder

| File | What it is | How you use it |
| --- | --- | --- |
| [00_create_catalog_and_schemas.sql](00_create_catalog_and_schemas.sql) | SQL notebook — catalog + 6 schemas + raw‑landing external volume | Import as a notebook, then run |
| [bronze_autoloader_pipeline.sql](bronze_autoloader_pipeline.sql) | Lakeflow SDP pipeline (SQL) — `STREAMING TABLE` + `read_files` for the 5 CSV/JSON sources | Import, then attach to a serverless pipeline |
| [ingest_adjuster_notes_excel.py](ingest_adjuster_notes_excel.py) | Serverless notebook — `openpyxl` reads the `.xlsx` | Import, then run as a serverless job |

## Prerequisites

- **Session 0 complete** — a running workspace, and the Terraform outputs handy
  (`terraform output` in `session-0-setup/terraform/`). You need **`managed_catalog_location`** and
  **`landing_path`**.
- **Unity Catalog privileges** to create the catalog, the managed location, and the external volume:
  `CREATE CATALOG` on the metastore, `CREATE MANAGED STORAGE` on the `managed` external location, and
  `CREATE EXTERNAL VOLUME` on the `landing` external location — held by the account/metastore admin
  from Session 0. ([Admin privileges](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/manage-privileges/admin-privileges))
- **The synthetic data files** in [data/](../data/) (generated in Step 0 of the
  [Deployment Guide](../DEPLOYMENT_GUIDE.md)).

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

1. **Import the notebook:** in the sidebar click **Workspace**, choose a folder, then **⋮ ▸ Import**,
   and upload [00_create_catalog_and_schemas.sql](00_create_catalog_and_schemas.sql). It imports as a
   **SQL notebook** — one step per cell, with a markdown explanation above each.
   ([Import a notebook](https://learn.microsoft.com/azure/databricks/notebooks/notebooks-manage))
2. **Attach** it to **Serverless** compute (the compute selector, top right).
3. In the two `CREATE` cells, replace the placeholders with your Session 0 outputs:
   - `<MANAGED_CATALOG_LOCATION>` → the `managed_catalog_location` output
     (`abfss://state-fund-poc-managed@<storage>.dfs.core.windows.net/state_fund_poc`).
   - `<LANDING_LOCATION>` → the `landing_path` output
     (`abfss://landing@<storage>.dfs.core.windows.net/state-fund-poc`).
4. **Run all** cells. This creates the catalog (with catalog‑level managed storage), the six schemas,
   and the `bronze.landing` external volume; the last two cells verify them.

You can also confirm in **Catalog** that `state_fund_poc` shows the
`bronze/silver/gold/config/security/ml` schemas and a **Volumes ▸ landing** entry.

Docs: [Manage notebooks](https://learn.microsoft.com/azure/databricks/notebooks/notebooks-manage) ·
[Create catalogs](https://learn.microsoft.com/azure/databricks/catalogs/create-catalog) ·
[CREATE VOLUME](https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-syntax-ddl-create-volume)

### 2. Upload the six source files to the landing volume

You need `WRITE VOLUME` on `bronze.landing` (plus `USE CATALOG`/`USE SCHEMA`) — covered by the admin
role. ([Privileges reference](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/access-control/privileges-reference))

1. In the sidebar, click **Catalog**, then browse to **`state_fund_poc` ▸ `bronze` ▸ Volumes ▸
   `landing`**.
2. Click **Create directory** and add one folder per source: `claims`, `hr`, `siu_labels`,
   `treatments`, `billing`, `notes`.
3. Open each folder, click **Upload to this volume**, and upload the matching file from
   [data/](../data/) per the table above (e.g. `claims_core.csv` → `claims/`).

> Each source goes in its **own folder** because Auto Loader watches one directory per table. The
> folder names must match the table above (they map to `cfg.source_path(...)` in
> [common/config.py](../common/config.py)).

Docs: [Work with files in Unity Catalog volumes — upload](https://learn.microsoft.com/azure/databricks/volumes/volume-files#use-catalog-explorer)

### 3. Import the pipeline source and Excel notebook into your workspace

1. In the sidebar, click **Workspace**, pick a folder, then **⋮ (kebab) ▸ Import**.
2. Import [bronze_autoloader_pipeline.sql](bronze_autoloader_pipeline.sql) — it imports as a
   workspace **SQL file** (a plain Lakeflow pipeline source, not a notebook) — and
   [ingest_adjuster_notes_excel.py](ingest_adjuster_notes_excel.py), which imports as a **notebook**.

Docs: [Manage notebooks — import](https://learn.microsoft.com/azure/databricks/notebooks/notebooks-manage)

### 4. Create and run the Bronze Auto Loader pipeline

The SQL `read_files` function invokes Auto Loader to incrementally ingest the five CSV/JSON sources into streaming tables;
**Lakeflow manages the schema location and checkpoint for you** — no manual setup.
([What is Auto Loader?](https://learn.microsoft.com/azure/databricks/ingestion/cloud-object-storage/auto-loader/))

1. In the sidebar, click **Jobs & Pipelines ▸ Create ▸ ETL pipeline** (Lakeflow Declarative
   Pipeline).
2. Under **Source code**, select the imported `bronze_autoloader_pipeline.sql` file.
3. Set **Default catalog** = `state_fund_poc` and **Default schema** = `bronze`.
4. Click **Settings** and, in the **Configuration** section, add a key‑value pair so the pipeline
   can resolve `${landing_path}` — key `landing_path`, value
   `/Volumes/state_fund_poc/bronze/landing`. This is **required**: Serverless pipelines don't
   support a `SET` statement in the source, so the path must come from the pipeline configuration.
   (If you used a different catalog, set the value to `/Volumes/<your_catalog>/bronze/landing`.)
5. Leave compute **Serverless** (the default).
6. Click **Start**.

When it finishes, **Catalog ▸ `state_fund_poc` ▸ `bronze`** shows `raw_claims`, `raw_hr_records`,
`raw_siu_labels`, `raw_medical_treatments`, and `raw_provider_billing`.

Docs: [Tutorial: build an ETL pipeline with Lakeflow](https://learn.microsoft.com/azure/databricks/getting-started/data-pipeline-get-started) ·
[Develop Lakeflow SDP code with SQL](https://learn.microsoft.com/azure/databricks/ldp/developer/sql-dev) ·
[Use parameters with pipelines](https://learn.microsoft.com/azure/databricks/ldp/parameters) ·
[Load files from cloud object storage in pipelines](https://learn.microsoft.com/azure/databricks/ldp/load#load-files-from-cloud-object-storage) ·
[Auto Loader in Lakeflow pipelines](https://learn.microsoft.com/azure/databricks/ingestion/cloud-object-storage/auto-loader/#incremental-ingestion-using-auto-loader-with-lakeflow-spark-declarative-pipelines)

### 5. Run the Excel ingest as a serverless job

Auto Loader can't read `.xlsx`, so the adjuster notes are loaded by a notebook that reads the
workbook with `openpyxl` and overwrites `bronze.raw_adjuster_notes` (idempotent).

1. In the sidebar, click **Jobs & Pipelines ▸ Create ▸ Job**.
2. Add a **Notebook** task pointing at the imported `ingest_adjuster_notes_excel` notebook.
3. Leave **Compute = Serverless** (the default for notebook tasks).
4. Click **Run now**.

When it finishes, **`bronze.raw_adjuster_notes`** exists. (Re‑running is safe — it overwrites.)

Docs: [Run jobs on serverless compute](https://learn.microsoft.com/azure/databricks/jobs/run-serverless-jobs#create-a-job-using-serverless-compute) ·
[Serverless compute for notebooks](https://learn.microsoft.com/azure/databricks/compute/serverless/notebooks)

### 6. Verify Bronze

Open the SQL editor and confirm the six tables landed and carry the lineage columns:

```sql
USE CATALOG state_fund_poc;

SELECT 'raw_claims'             AS tbl, count(*) AS rows FROM bronze.raw_claims
UNION ALL SELECT 'raw_hr_records',             count(*) FROM bronze.raw_hr_records
UNION ALL SELECT 'raw_siu_labels',             count(*) FROM bronze.raw_siu_labels
UNION ALL SELECT 'raw_medical_treatments',     count(*) FROM bronze.raw_medical_treatments
UNION ALL SELECT 'raw_provider_billing',       count(*) FROM bronze.raw_provider_billing
UNION ALL SELECT 'raw_adjuster_notes',         count(*) FROM bronze.raw_adjuster_notes;

-- Lineage columns are present, and Bronze is still dirty (duplicates kept):
SELECT claim_id, _source_file, _ingested_at FROM bronze.raw_claims WHERE claim_id = 'CLM-00002';
```

You'll see `claim_id` `CLM-00002` (and the deliberately duplicated/dirty rows) preserved as‑landed —
Session 2 cleans, conforms, and masks them.

## Next

Continue to **Session 2 — Silver: Cleaning, Quality & PII Governance**. See the
[Deployment Guide](../DEPLOYMENT_GUIDE.md).

## References

- [What is Auto Loader?](https://learn.microsoft.com/azure/databricks/ingestion/cloud-object-storage/auto-loader/) ·
  [Lakeflow Declarative Pipelines](https://learn.microsoft.com/azure/databricks/ldp/)
- [Work with Unity Catalog volumes](https://learn.microsoft.com/azure/databricks/volumes/) ·
  [CREATE VOLUME](https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-syntax-ddl-create-volume)
- [Create catalogs](https://learn.microsoft.com/azure/databricks/catalogs/create-catalog) ·
  [Managed storage](https://learn.microsoft.com/azure/databricks/connect/unity-catalog/cloud-storage/managed-storage)
- [Run jobs on serverless compute](https://learn.microsoft.com/azure/databricks/jobs/run-serverless-jobs)
