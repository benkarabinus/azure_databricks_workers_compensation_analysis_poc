# Deployment Guide — State Fund Lane 1 POC

This is the full, guided walkthrough for building the **California State Fund — Lane 1 POC**: an end-to-end medallion (Bronze → Silver → Gold) lakehouse on **Azure Databricks Serverless** delivering Return-to-Work duration prediction and claims fraud investigation triage.

Work the sessions **in order** — each depends on the catalog, schemas, and tables created earlier. Every session has a self-contained folder (`session-N/`) with the notebooks and SQL it introduces, plus a `README.md`.

> **Status:** This guide is built up incrementally alongside the repository. Sessions are filled in with detailed, documentation-cited steps as each session's code is authored. Sections marked _(coming soon)_ are not yet implemented.

## Audience & prerequisites

- **Audience:** DBAs, data engineers, analytics SMEs, and security/compliance stakeholders. Familiarity with SQL and data concepts is assumed; Databricks-specific features (DLT, Unity Catalog, AutoML, Genie) are explained along the way.
- **Cloud:** This guide assumes **Azure Commercial**. AI/BI Genie, Vector Search, and Model Serving may have limited availability in Azure Government — confirm feature availability before building if you are in a MAG tenant.
- **You will need:**
  - An Azure subscription with permission to create an Azure Databricks workspace and an ADLS Gen2 storage account.
  - Microsoft Entra ID permission to create/assign groups for access control.
  - The synthetic source data generated locally (see below).

Reference: [Azure Databricks documentation](https://learn.microsoft.com/azure/databricks/).

## Step 0 — Generate the synthetic source data

Before Session 1, generate the six source files locally with the seeded Python generator (uses a project virtual environment):

**PowerShell**

```powershell
python -m venv .venv
.\.venv\Scripts\python -m pip install -r requirements.txt
.\.venv\Scripts\python data/generate_synthetic_data.py --num-claims 5000 --seed 42 --out data
```

**Bash**

```bash
python -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python data/generate_synthetic_data.py --num-claims 5000 --seed 42 --out data
```

The files are also committed to the repo, so you only need this to regenerate or resize the dataset. During the sessions you will upload these files to the ADLS Gen2 External Location to trigger the Bronze pipelines.

## Sessions

### Session 0 — Environment Readiness (Terraform)

**Goal:** Use Terraform to provision a serverless‑capable Azure Databricks workspace (Premium SKU, Unity Catalog auto‑enabled) and a **dedicated ADLS Gen2 account** with two containers — `landing` (raw source files, registered as an external location) and `managed` (catalog‑level managed storage for the Bronze/Silver/Gold managed tables). The access connector's managed identity (not account keys) grants Unity Catalog access to the storage.

**Output:** A running workspace with serverless compute available, a validated `landing` external location, and a `managed` external location ready to back the catalog's managed storage in Session 1.

**Steps:**

1. **Sign in to Azure:** `az login` and select your subscription. ([Azure CLI sign‑in](https://learn.microsoft.com/cli/azure/authenticate-azure-cli))
2. **Configure variables:** in `session-0-setup/terraform/`, copy `terraform.tfvars.example` to `terraform.tfvars` and set the required deterministic names — `subscription_id`, `storage_account_name` (globally unique), `workspace_name`, and `access_connector_name` — plus optional `prefix`, `location`, `resource_group_name`, and the `create_resource_group` toggle. Each name's constraint is documented inline in the file.
3. **Provision (two‑phase first run):** run `terraform init`, then create the workspace first with `terraform apply -target='azapi_resource.workspace'` — this bootstraps the Databricks account and the regional Unity Catalog metastore. If whoever runs the next step isn't already an account admin, have a Microsoft Entra ID Global Administrator sign into the [account console](https://accounts.azuredatabricks.net) and assign them the **Account admin** role ([establish the first account admin](https://learn.microsoft.com/en-us/azure/databricks/admin/admin-concepts#establish-first-account-admin)). Then run `terraform apply` to create the storage, access connector, credential, and external locations. ([Deploy a workspace with Terraform](https://learn.microsoft.com/azure/databricks/dev-tools/terraform/azure-workspace))
4. **Verify:** confirm the resources in the Azure portal, **Test connection** on the external location in Databricks Catalog, and check that **Serverless** is available in the compute selector. ([Serverless compute](https://learn.microsoft.com/azure/databricks/compute/serverless/))
5. **Record outputs:** note `workspace_url`, `landing_path` (matches the `landing_path` widget default in `common/config.py`), and `managed_catalog_location` (used as the catalog `MANAGED LOCATION` in Session 1).
6. **Teardown (later):** `terraform destroy` removes everything when you are finished with the POC.

Full step‑by‑step instructions and the design rationale are in [session-0-setup/README.md](session-0-setup/README.md).

> **Prerequisites:** `Owner` or `User Access Administrator` on the target scope (to create role assignments) and account/metastore admin privileges (to create the storage credential and external location). See the session README for details.

### Session 1 — Foundations & Bronze Ingestion

**Goal:** Create the `state_fund_poc` catalog and its six schemas, then land all six sources append‑only into `bronze.raw_*` (Auto Loader for CSV/JSON, an Excel notebook for the `.xlsx`), each carrying `_source_file` / `_ingested_at`.

**Output:** Six Bronze tables — `raw_claims`, `raw_hr_records`, `raw_siu_labels`, `raw_medical_treatments`, `raw_provider_billing`, and `raw_adjuster_notes` — with the dirty patterns preserved for Silver.

This session is a **UI walkthrough**; you import the source files in `session-1-bronze/` and complete each step in the workspace.

**Steps:**

1. **Create the catalog, schemas, and landing volume:** import [session-1-bronze/00_create_catalog_and_schemas.sql](session-1-bronze/00_create_catalog_and_schemas.sql) as a **SQL notebook**, attach Serverless, replace `<MANAGED_CATALOG_LOCATION>` and `<LANDING_LOCATION>` with the Session 0 `managed_catalog_location` and `landing_path` outputs, and **Run all**. ([Manage notebooks](https://learn.microsoft.com/azure/databricks/notebooks/notebooks-manage) · [Create catalogs](https://learn.microsoft.com/azure/databricks/catalogs/create-catalog) · [CREATE VOLUME](https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-syntax-ddl-create-volume))
2. **Upload the data:** in **Catalog ▸ `state_fund_poc` ▸ `bronze` ▸ Volumes ▸ `landing`**, create a folder per source (`claims`, `hr`, `siu_labels`, `treatments`, `billing`, `notes`) and upload the matching file into each. ([Upload files to a volume](https://learn.microsoft.com/azure/databricks/volumes/volume-files#use-catalog-explorer))
3. **Import** the pipeline source [bronze_autoloader_pipeline.sql](session-1-bronze/bronze_autoloader_pipeline.sql) (imports as a workspace **SQL file** — a plain Lakeflow pipeline source) and the [ingest_adjuster_notes_excel.py](session-1-bronze/ingest_adjuster_notes_excel.py) notebook into the workspace. ([Develop Lakeflow SDP code with SQL](https://learn.microsoft.com/azure/databricks/ldp/developer/sql-dev) · [Manage notebooks](https://learn.microsoft.com/azure/databricks/notebooks/notebooks-manage))
4. **Run the Bronze pipeline:** create a **Serverless ETL pipeline** with `bronze_autoloader_pipeline.sql` as its **source code**, default catalog `state_fund_poc` and schema `bronze`, add the **Configuration** key‑value pair `landing_path` = `/Volumes/state_fund_poc/bronze/landing` (required — Serverless pipelines don't support `SET` in source), then **Start**. ([Use parameters with pipelines](https://learn.microsoft.com/azure/databricks/ldp/parameters) · [Auto Loader](https://learn.microsoft.com/azure/databricks/ingestion/cloud-object-storage/auto-loader/) · [Build an ETL pipeline with Lakeflow](https://learn.microsoft.com/azure/databricks/getting-started/data-pipeline-get-started))
5. **Run the Excel ingest:** create a **Serverless job** with a notebook task on the Excel notebook and **Run now**. ([Serverless jobs](https://learn.microsoft.com/azure/databricks/jobs/run-serverless-jobs))
6. **Verify** the six `bronze.raw_*` tables and their `_source_file` / `_ingested_at` columns.

Full step‑by‑step instructions and doc links are in [session-1-bronze/README.md](session-1-bronze/README.md).

### Session 2 — Silver: Cleaning, Quality & PII Governance

**Goal:** Clean, conform, dedupe, enforce DLT Expectations, mask PII (SSN/DOB), redact notes, and structure adjuster notes with `ai_extract` / `ai_classify`.

**Output:** Governed `silver.*` tables (`claims`, `employees`, `treatments`, `provider_billing`, `rtw_timeline`, `adjuster_notes`) and a live PII masking + row-filter demo.

This session is a **UI walkthrough**; you run two interactive SQL notebooks and one Lakeflow SQL pipeline (two source files).

**Steps:**

1. **Create the masking functions & row filter:** import [session-2-silver/security_masking_functions.sql](session-2-silver/security_masking_functions.sql) as a **SQL notebook**, attach Serverless, and **Run all** — creates `security.mask_ssn`, `security.mask_dob`, and `security.claims_region_filter`. These must exist before the pipeline (MV masks/filters can only be declared in the `CREATE` statement). ([Row filters and column masks](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/) · [CREATE FUNCTION](https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-syntax-ddl-create-sql-function))
2. **Create account groups:** in the [account console](https://accounts.azuredatabricks.net), create `analysts` and `pii_authorized`, and add the **Silver pipeline owner** to `pii_authorized` (so the row filter doesn't drop rows from downstream/Gold tables). ([Manage groups](https://learn.microsoft.com/azure/databricks/admin/users-groups/groups))
3. **Import** [silver_pipeline.sql](session-2-silver/silver_pipeline.sql) and [silver_adjuster_notes_ai.sql](session-2-silver/silver_adjuster_notes_ai.sql) (both import as workspace SQL files). ([Manage notebooks](https://learn.microsoft.com/azure/databricks/notebooks/notebooks-manage))
4. **Run the Silver pipeline:** create a **Serverless ETL pipeline** with **both** SQL files as source code, default catalog `state_fund_poc` and schema `silver`; confirm the owner is in `pii_authorized`, then **Start**. Each table is a materialized view (dedupe via `QUALIFY`), with DLT Expectations and inline masks/row filter on `claims`. ([Develop SDP with SQL](https://learn.microsoft.com/azure/databricks/ldp/developer/sql-dev) · [Expectations](https://learn.microsoft.com/azure/databricks/ldp/expectations) · [AI Functions](https://learn.microsoft.com/azure/databricks/large-language-models/ai-functions)) — note `ai_query` needs a serving endpoint (`databricks-meta-llama-3-3-70b-instruct` or your own).
5. **Grant & validate:** import [grants_and_validation.sql](session-2-silver/grants_and_validation.sql) as a **SQL notebook** and **Run all** — grants analyst/`pii_authorized` read access and validates masked-vs-unmasked output and that the poison/duplicate rows were handled. ([GRANT](https://learn.microsoft.com/azure/databricks/sql/language-manual/security-grant))
6. **Verify** the six `silver.*` tables and the Expectation pass rates in the pipeline graph.

Full step‑by‑step instructions and doc links are in [session-2-silver/README.md](session-2-silver/README.md).

### Session 3 — Gold, Lineage & Self-Service BI

**Goal:** Engineer `gold.rtw_features` and `gold.fraud_features`, build BI aggregates, walk the lineage graph, configure a Genie Space, and build an AI/BI dashboard.

**Output:** ML-ready Gold tables (`rtw_features`, `fraud_features`, `rtw_outcomes_summary`), a `gold.data_quality` view, a Genie Space, and an AI/BI dashboard.

This session is a **UI walkthrough**: one Lakeflow SQL pipeline, one interactive SQL notebook, and two UI artifacts.

**Steps:**

1. **Run the Gold pipeline:** import [session-3-gold/gold_pipeline.sql](session-3-gold/gold_pipeline.sql) (workspace SQL file), create a **Serverless ETL pipeline** with it as source code, default catalog `state_fund_poc` and schema `gold`; confirm the owner is in `pii_authorized` (the `silver.claims` row filter evaluates as the invoker), then **Start**. Materialized views: `rtw_features` (closed claims + `days_to_rtw`), `fraud_features` (labeled SIU subset + `is_fraud`), `rtw_outcomes_summary` (aggregate). ([Develop SDP with SQL](https://learn.microsoft.com/azure/databricks/ldp/developer/sql-dev) · [Window functions](https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-window-functions))
2. **Create the data-quality view:** import [data_quality_view.sql](session-3-gold/data_quality_view.sql) as a **SQL notebook** and **Run all** — creates `gold.data_quality` from the Silver pipeline's event log (Expectation pass rates). Run as the Silver pipeline owner. ([Pipeline event log](https://learn.microsoft.com/azure/databricks/ldp/monitor-event-logs))
3. **Walk the lineage:** in **Catalog ▸ `gold` ▸ `rtw_features` ▸ Lineage**, trace each Gold table back through Silver to Bronze and the source files. ([Data lineage](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/data-lineage))
4. **Configure the Genie Space:** follow [genie_space.md](session-3-gold/genie_space.md) — add the three Gold tables, paste the instructions, seed the sample questions. ([AI/BI Genie](https://learn.microsoft.com/azure/databricks/genie/))
5. **Import the dashboard:** **Dashboards ▸ ▾ ▸ Import dashboard from file** ▸ [dashboard/rtw_fraud.lvdash.json](session-3-gold/dashboard/rtw_fraud.lvdash.json) (a starter — verify visuals and refine). ([Import a dashboard](https://learn.microsoft.com/azure/databricks/dashboards/automate/import-export))
6. **Verify** the three Gold tables, the `gold.data_quality` view, the Genie answers, and the dashboard.

Full step‑by‑step instructions and doc links are in [session-3-gold/README.md](session-3-gold/README.md).

### Session 4 — Model Training & MLflow

**Goal:** Train the RTW regression and fraud classification models on the Gold feature tables, track every candidate with MLflow, and register the best of each to Unity Catalog — all on **Serverless**.

**Output:** `state_fund_poc.ml.rtw_model` and `state_fund_poc.ml.fraud_model`, each with a `@champion` alias.

> **Why not AutoML?** Databricks AutoML regression/classification requires a classic Databricks-Runtime-ML cluster (unsupported on serverless, being removed in DBR 18.0 ML). We train scikit-learn candidates directly + MLflow to stay 100% serverless.

This session is a **notebook walkthrough**: two training notebooks, then a registration notebook (run all three as the **same user**).

**Steps:**

1. **Train RTW:** import [session-4-ml/train_rtw_model.py](session-4-ml/train_rtw_model.py), attach **Serverless**, **Run all** — trains RandomForest + HistGradientBoosting regressors on `gold.rtw_features`, logs to MLflow (`/Users/<you>/state_fund_poc_rtw`), best by **RMSE**. ([MLflow tracking](https://learn.microsoft.com/azure/databricks/mlflow/tracking))
2. **Train fraud:** import [train_fraud_model.py](session-4-ml/train_fraud_model.py), **Run all** — trains classifiers on `gold.fraud_features`, best by **PR-AUC** (labels are ~8–12% positive). ([PR-AUC](https://scikit-learn.org/stable/modules/generated/sklearn.metrics.average_precision_score.html))
3. **Compare runs:** in **Experiments**, sort RTW by `rmse` asc and fraud by `pr_auc` desc. ([Compare runs](https://learn.microsoft.com/azure/databricks/mlflow/runs))
4. **Register:** import [register_models.py](session-4-ml/register_models.py), **Run all** — registers the best run per experiment to `ml.rtw_model` / `ml.fraud_model`, assigns the **`@champion`** alias, and validates by scoring a sample. ([Models in UC](https://learn.microsoft.com/azure/databricks/machine-learning/manage-model-lifecycle/))
5. **Verify** both models in **Catalog ▸ `state_fund_poc` ▸ `ml`** with a `champion` alias.

Full step‑by‑step instructions and doc links are in [session-4-ml/README.md](session-4-ml/README.md).

### Session 5 — Serving, Fraud Triage App, Orchestration & Governance

**Goal:** Batch-score claims to `gold.fraud_scores` and RTW predictions, build the Streamlit Databricks App triage queue with Vector Search, orchestrate the pipeline end-to-end with Databricks Workflows, and verify governance (audit, row filters, time travel).

**Output:** `gold.fraud_scores` + `gold.rtw_predictions`, a Vector Search index, a live Streamlit App, an end-to-end Workflow, and governance demos.

> **POC scoring note:** we score the existing Gold feature tables (which the models also trained on) — a predicted-vs-actual demo. In production you'd score open/unlabeled claims by reusing the Gold feature SQL without the label join / closed filter.

**Steps:**

1. **Score fraud:** import [session-5-serving/batch_score_fraud.py](session-5-serving/batch_score_fraud.py), **Run all** on Serverless — loads `ml.fraud_model@champion`, writes the ranked **`gold.fraud_scores`** (`fraud_risk_score`, `risk_tier`, `top_contributing_factor`). ([Load UC models](https://learn.microsoft.com/azure/databricks/machine-learning/manage-model-lifecycle/))
2. **Score RTW:** import [batch_score_rtw.py](session-5-serving/batch_score_rtw.py), **Run all** — writes `gold.rtw_predictions` (predicted vs actual `days_to_rtw`).
3. **Vector Search:** import [vector_search_setup.py](session-5-serving/vector_search_setup.py), run cell by cell (the endpoint takes a few minutes to come ONLINE) — CDF source table from redacted notes → AI Search endpoint → delta-sync index → similarity query. ([Create AI Search indexes](https://learn.microsoft.com/azure/databricks/ai-search/create-ai-search))
4. **Deploy the app:** **Compute ▸ Apps ▸ Create app** (Streamlit), add a **SQL warehouse** resource keyed `sql-warehouse`, upload [app/](session-5-serving/app/), **Deploy**, and grant the app's service principal `SELECT` on `gold.fraud_scores`. ([Databricks Apps](https://learn.microsoft.com/azure/databricks/dev-tools/databricks-apps/))
5. **Orchestrate:** edit [workflow/end_to_end_job.yaml](session-5-serving/workflow/end_to_end_job.yaml) (replace the `<...>` pipeline IDs / notebook paths), create a job and paste it via the kebab (**...**) ▸ **Edit as YAML** (the Jobs UI imports YAML, not JSON) — ingest → Bronze → Silver → Gold → score → quality on Serverless. ([Lakeflow Jobs](https://learn.microsoft.com/azure/databricks/jobs/))
6. **Governance:** run the three [governance/](session-5-serving/governance/) notebooks — `row_filter_demo.sql` (masks/row filter), `audit_system_tables.sql` (access + lineage; needs `system.access` enabled), `time_travel_recovery.sql` (Delta history + `RESTORE`). ([Row filters & masks](https://learn.microsoft.com/azure/databricks/data-governance/unity-catalog/filters-and-masks/) · [System tables](https://learn.microsoft.com/azure/databricks/admin/system-tables/) · [Delta history](https://learn.microsoft.com/azure/databricks/delta/history))
7. **Verify** the triage app renders the ranked queue and the governance demos behave as expected.

Full step‑by‑step instructions and doc links are in [session-5-serving/README.md](session-5-serving/README.md).
