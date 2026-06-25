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
3. **Provision (two‑phase first run):** run `terraform init`, then create the workspace first with `terraform apply -target='azurerm_databricks_workspace.this'` — this bootstraps the Databricks account and the regional Unity Catalog metastore. If whoever runs the next step isn't already an account admin, have a Microsoft Entra ID Global Administrator sign into the [account console](https://accounts.azuredatabricks.net) and assign them the **Account admin** role ([establish the first account admin](https://learn.microsoft.com/en-us/azure/databricks/admin/admin-concepts#establish-first-account-admin)). Then run `terraform apply` to create the storage, access connector, credential, and external locations. ([Deploy a workspace with Terraform](https://learn.microsoft.com/azure/databricks/dev-tools/terraform/azure-workspace))
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

1. **Create the catalog, schemas, and landing volume:** open the **SQL editor**, paste [session-1-bronze/00_create_catalog_and_schemas.sql](session-1-bronze/00_create_catalog_and_schemas.sql), replace `<MANAGED_CATALOG_LOCATION>` and `<LANDING_LOCATION>` with the Session 0 `managed_catalog_location` and `landing_path` outputs, and run it. ([Create catalogs](https://learn.microsoft.com/azure/databricks/catalogs/create-catalog) · [CREATE VOLUME](https://learn.microsoft.com/azure/databricks/sql/language-manual/sql-ref-syntax-ddl-create-volume))
2. **Upload the data:** in **Catalog ▸ `state_fund_poc` ▸ `bronze` ▸ Volumes ▸ `landing`**, create a folder per source (`claims`, `hr`, `siu_labels`, `treatments`, `billing`, `notes`) and upload the matching file into each. ([Upload files to a volume](https://learn.microsoft.com/azure/databricks/volumes/volume-files#use-catalog-explorer))
3. **Import** [bronze_autoloader_pipeline.py](session-1-bronze/bronze_autoloader_pipeline.py) and [ingest_adjuster_notes_excel.py](session-1-bronze/ingest_adjuster_notes_excel.py) into the workspace. ([Manage notebooks](https://learn.microsoft.com/azure/databricks/notebooks/notebooks-manage))
4. **Run the Bronze pipeline:** create a **Serverless ETL pipeline** from the imported pipeline notebook with default catalog `state_fund_poc` and schema `bronze`, then **Start**. ([Auto Loader](https://learn.microsoft.com/azure/databricks/ingestion/cloud-object-storage/auto-loader/) · [Build an ETL pipeline with Lakeflow](https://learn.microsoft.com/azure/databricks/getting-started/data-pipeline-get-started))
5. **Run the Excel ingest:** create a **Serverless job** with a notebook task on the Excel notebook and **Run now**. ([Serverless jobs](https://learn.microsoft.com/azure/databricks/jobs/run-serverless-jobs))
6. **Verify** the six `bronze.raw_*` tables and their `_source_file` / `_ingested_at` columns.

Full step‑by‑step instructions and doc links are in [session-1-bronze/README.md](session-1-bronze/README.md).

### Session 2 — Silver: Cleaning, Quality & PII Governance

**Goal:** Clean, conform, dedupe, enforce DLT Expectations, mask PII (SSN/DOB), redact notes, and structure adjuster notes with `ai_extract` / `ai_classify`.

**Output:** Governed `silver.*` tables and a live PII masking demo.

_Detailed steps: coming soon (see `session-2-silver/`)._

### Session 3 — Gold, Lineage & Self-Service BI

**Goal:** Engineer `gold.rtw_features` and `gold.fraud_features`, build BI aggregates, walk the lineage graph, configure a Genie Space, and build an AI/BI dashboard.

**Output:** ML-ready Gold tables plus self-service BI.

_Detailed steps: coming soon (see `session-3-gold/`)._

### Session 4 — Machine Learning with AutoML + MLflow

**Goal:** Train AutoML regression (RTW) and classification (fraud) models, track with MLflow, and register both to Unity Catalog.

**Output:** `state_fund_poc.ml.rtw_model` and `state_fund_poc.ml.fraud_model`.

_Detailed steps: coming soon (see `session-4-ml/`)._

### Session 5 — Serving, Fraud Triage App, Orchestration & Governance

**Goal:** Batch-score claims to `gold.fraud_scores` and RTW predictions, build the Streamlit Databricks App triage queue with Vector Search, orchestrate the pipeline end-to-end with Databricks Workflows, and verify governance (audit, row filters, time travel).

**Output:** A live fraud triage app and an automated end-to-end pipeline.

_Detailed steps: coming soon (see `session-5-serving/`)._
