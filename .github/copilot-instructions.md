# State Fund Lane 1 POC — Copilot Instructions

This repository is the **California State Fund — Lane 1 POC**: an end-to-end medallion (Bronze → Silver → Gold) lakehouse on **Azure Databricks Serverless** delivering two use cases — **Return-to-Work (RTW) duration prediction** (regression) and **claims fraud investigation triage** (classification). All data is synthetic; all compute is serverless.

## Repository Structure

The repo is a **hands-on, session-based build** that doubles as a published tutorial (modeled on a hands-on deployment lab). `README.md` is the concise landing page, `DEPLOYMENT_GUIDE.md` is the full guided walkthrough, and `docs/` builds a GitHub Pages site. Each `session-N/` folder is a self-contained stage containing only the assets introduced in that session. Build the sessions in order — each depends on the catalog, schemas, and tables created earlier.

```
session-0-setup/                       ← Environment readiness (Terraform: workspace + ADLS External Location)
  README.md                            ← Step-by-step Terraform walkthrough (prereqs, init/plan/apply, verify, destroy)
  terraform/                           ← IaC: serverless workspace (azapi, computeMode=Serverless) + dedicated ADLS Gen2 as UC External Location
    versions.tf                        ← Terraform + provider constraints (azurerm, azapi, databricks, time)
    providers.tf                       ← azurerm + azapi + databricks (azure_workspace_resource_id) providers
    variables.tf                       ← prefix, location, create_resource_group toggle, landing/managed containers, explicit storage/workspace names, tags
    main.tf                            ← Resource group create-or-reuse + explicit naming locals
    storage.tf                         ← ADLS Gen2 account (is_hns_enabled) + landing & managed containers
    workspace.tf                       ← azapi_resource serverless workspace (computeMode=Serverless; no managed RG/VNet/DBFS; UC auto-enabled)
    unity_catalog.tf                   ← Access connector + role assignments + storage credential + landing & managed external locations
    outputs.tf                         ← workspace_url, external_location_url, landing_path, managed_catalog_location (matches common/config.py)
    terraform.tfvars.example           ← Copy to terraform.tfvars (gitignored)
session-1-bronze/                      ← Foundations & Bronze ingestion
  00_create_catalog_and_schemas.sql    ← CREATE CATALOG state_fund_poc (MANAGED LOCATION) + schemas bronze/silver/gold/config/security/ml + bronze.landing external volume
  bronze_autoloader_pipeline.sql       ← Lakeflow SDP (SQL): STREAMING TABLE + read_files (Auto Loader) for CSV + JSON → raw_* Bronze tables
  ingest_adjuster_notes_excel.py       ← Serverless Job notebook: openpyxl → raw_adjuster_notes (Auto Loader has no .xlsx)
  README.md
session-2-silver/                      ← Silver: cleaning, quality & PII governance
  security_masking_functions.sql       ← Interactive SQL: UC column-mask fns (mask_ssn, mask_dob) + region row filter (security schema) — run BEFORE the pipeline
  silver_pipeline.sql                  ← Lakeflow SDP (SQL): clean/conform/dedupe (MV + QUALIFY) + Expectations + inline UC masks/row filter → claims, employees, treatments, provider_billing, rtw_timeline
  silver_adjuster_notes_ai.sql         ← Lakeflow SDP (SQL): ai_query redaction + ai_classify + ai_extract → silver.adjuster_notes
  grants_and_validation.sql            ← Interactive SQL: grants to analysts/pii_authorized + masked-vs-unmasked validation
  README.md
session-3-gold/                        ← Gold features, lineage & self-service BI
  gold_pipeline.sql                    ← Lakeflow SDP (SQL): rtw_features, fraud_features, rtw_outcomes_summary (materialized views)
  data_quality_view.sql                ← Interactive SQL: gold.data_quality view over the Silver event log (Expectation pass rates)
  genie_space.md                       ← Genie Space config + sample NLQ questions
  dashboard/rtw_fraud.lvdash.json      ← AI/BI dashboard definition (starter)
  README.md
session-4-ml/                          ← AutoML + MLflow
  train_rtw_automl.py                  ← AutoML regression on gold.rtw_features (label days_to_rtw)
  train_fraud_automl.py                ← AutoML classification on gold.fraud_features (label is_fraud, PR-AUC)
  register_models.py                   ← Register best runs → state_fund_poc.ml.rtw_model / fraud_model
  README.md
session-5-serving/                     ← Serving, triage app, orchestration & governance
  batch_score_rtw.py                   ← Score RTW model → RTW predictions in Gold
  batch_score_fraud.py                 ← Score fraud model → gold.fraud_scores (ranked triage queue)
  vector_search_setup.py               ← Vector Search index for similar-claim lookup
  app/                                 ← Databricks App: Streamlit fraud triage queue UI
    app.py                             ← Streamlit entry point (reads gold.fraud_scores)
    app.yaml                           ← Databricks App config (command: streamlit run app.py)
    requirements.txt                   ← Pins streamlit + databricks-sdk
  workflow/end_to_end_job.json         ← Workflow: ingest → DLT → score → quality
  governance/                          ← audit_system_tables.sql, row_filter_demo.sql, time_travel_recovery.sql
  README.md
common/                                ← Shared helpers reused across sessions
  config.py                            ← Catalog/schema/path constants resolved from widgets or job params
data/                                  ← Synthetic source data + generator
  generate_synthetic_data.py           ← Seeded pandas/Faker generator for all six source files
  claims_core.csv                      ← Raw claims (simulates a claims DB)
  hr_records.csv                       ← HR / employment records (simulates an HR DB)
  medical_treatments.json              ← Nested treatment events per claim (simulates clinical feed)
  provider_billing.json                ← Nested billing lines per claim (simulates EDI 837)
  adjuster_notes.xlsx                  ← Free-text adjuster notes with embedded fake PII
  siu_labels.csv                       ← Confirmed SIU fraud labels (training subset)
docs/                                  ← Jekyll GitHub Pages tutorial site (just-the-docs theme)
  _config.yml                          ← Site config (theme, title, baseurl)
  Gemfile                              ← Jekyll + theme dependencies
  index.md                             ← Tutorial home page
  session-0.md … session-5.md          ← One published page per session
  diagrams/                            ← draw.io sources (.drawio) + exported .svg/.png architecture diagrams
  images/                              ← Screenshots referenced by the session pages
.github/                               ← Copilot customization
  copilot-instructions.md              ← Repo-wide guidance (this file)
  instructions/                        ← Path-scoped rules (pyspark.instructions.md, sql.instructions.md, diagrams.instructions.md)
DEPLOYMENT_GUIDE.md                    ← Full guided, step-by-step walkthrough (primary entry point)
README.md                              ← Concise landing page: About / Session Structure / Architecture / Quick Start
.gitignore
```

## Sessions

Goal and key outputs per session:

- **Session 0 — Setup:** Use Terraform to provision a true serverless workspace (azapi `azapi_resource` with `computeMode = "Serverless"` — no managed resource group/VNet/DBFS; Premium SKU backs Unity Catalog, which is auto-enabled) and a dedicated ADLS Gen2 account with two containers — `landing` (raw files, registered as a UC External Location) and `state-fund-poc-managed` (catalog-level managed storage for Bronze/Silver/Gold managed tables) — accessed via an access connector managed identity (separate from the metastore root). All resource names are set explicitly via tfvars (no autogenerated suffixes). Session 1 sets the catalog `MANAGED LOCATION` to the managed external location. Entra groups/grants are deferred to the sessions that first use them. → Working serverless workspace.
- **Session 1 — Bronze:** Create the catalog (with the Session 0 managed location) + schemas + the `bronze.landing` external volume; participants upload the six files to per-source folders in the volume, then land them append-only via Auto Loader (CSV/JSON, in a serverless Lakeflow pipeline) and an openpyxl serverless job (XLSX). → `bronze.raw_*` tables carrying `_source_file` / `_ingested_at`.
- **Session 2 — Silver:** A Serverless **Lakeflow SQL pipeline** cleans/conforms/dedupes (materialized views + `QUALIFY ROW_NUMBER()`), enforces DLT Expectations, and applies **inline** UC column masks (`mask_ssn`/`mask_dob`) + a region row filter on `silver.claims`; `ai_query` redacts note PII and `ai_classify`/`ai_extract` structure the notes. Masks/filters must be declared in the MV `CREATE` (not via `ALTER`), so the `security` UDFs are created first. → governed `silver.*`; live masking demo.
- **Session 3 — Gold:** A Serverless **Lakeflow SQL pipeline** engineers `gold.rtw_features` (closed claims) and `gold.fraud_features` (labeled SIU subset) plus the `gold.rtw_outcomes_summary` BI aggregate; a `gold.data_quality` view surfaces Silver Expectation pass rates from the event log; walk lineage, configure Genie + an AI/BI dashboard. → ML-ready Gold + self-service BI.
- **Session 4 — ML:** AutoML regression (RTW, RMSE/MAE) and classification (fraud, PR-AUC); track with MLflow; register both to Unity Catalog. → `ml.rtw_model`, `ml.fraud_model`.
- **Session 5 — Serving:** Batch-score to `gold.fraud_scores` and RTW predictions; build the Databricks App triage queue with Vector Search; orchestrate end-to-end with Workflows; verify governance (audit, row filters, time travel). → Live app + automated pipeline.

## Architecture

This POC is an end-to-end **medallion lakehouse** on **Azure Databricks Serverless** (no classic clusters). All compute is serverless: Serverless DLT (Lakeflow Pipelines), Serverless SQL Warehouse (Genie / Dashboards / AI Functions), Serverless Jobs (Excel ingest, batch scoring), and managed runtimes for Vector Search, Model Serving, and Databricks Apps.

Two use cases share a single source of truth (the `claims` and `adjuster_notes` tables flow into both):

- **Use Case 1 — Return-to-Work (RTW)**: regression predicting `days_to_rtw` so case managers can intervene earlier on claims at risk of prolonged disability.
- **Use Case 2 — Fraud Triage**: binary classification producing a `fraud_risk_score` that ranks open claims for SIU investigator review. Frame this as **investigation triage acceleration**, never "automated fraud detection."

### Data flow (medallion)

1. **Sources** — synthetic files in a dedicated ADLS Gen2 External Location: `claims_core.csv`, `hr_records.csv`, `medical_treatments.json`, `provider_billing.json`, `adjuster_notes.xlsx`, `siu_labels.csv`.
2. **Bronze** — raw, as-landed, append-only Delta. A **Lakeflow SQL pipeline** (`CREATE OR REFRESH STREAMING TABLE` + `read_files`, which invokes Auto Loader) for CSV/JSON; a Serverless Jobs notebook (`openpyxl`) for XLSX. Nested JSON arrays are kept intact. Add `_source_file` and `_ingested_at`; do not drop them until Silver.
3. **Silver** — a Serverless **Lakeflow SQL pipeline** cleans, conforms, deduplicates (latest `_ingested_at` wins via `QUALIFY`), masks PII (inline UC column masks + row filter on `silver.claims`), enforces DLT Expectations, and joins entities. `silver.claims` is the hub; `claim_id` is the join key.
4. **Gold** — a Serverless **Lakeflow SQL pipeline** builds ML-ready feature tables and BI aggregates (materialized views over Silver).
5. **ML / Serving / Governance** — Mosaic AI (AutoML, MLflow, Model Serving), AI/BI Genie + Dashboards, a Databricks App (fraud triage queue) with Vector Search, and Unity Catalog governance across all layers. Databricks Workflows (serverless) orchestrate ingest → DLT → score → quality.

### Unity Catalog layout

Single catalog **`state_fund_poc`** with these schemas:

| Schema | Contents |
| --- | --- |
| `bronze` | `raw_claims`, `raw_hr_records`, `raw_medical_treatments`, `raw_provider_billing`, `raw_adjuster_notes`, `raw_siu_labels` |
| `silver` | `claims`, `employees`, `treatments`, `rtw_timeline`, `provider_billing`, `adjuster_notes` |
| `gold` | `rtw_features`, `rtw_outcomes_summary`, `fraud_features`, `fraud_scores` |
| `ml` | Registered models: `rtw_model`, `fraud_model` |
| `config` | Pipeline/config tables and reference data |
| `security` | Masking functions and row-filter functions |

### Key data model

- `silver.claims` is the hub; every spoke (`employees`, `treatments`, `provider_billing`, `adjuster_notes`, `rtw_timeline`) joins on `claim_id` (or `employee_id` for the worker dimension).
- `gold.rtw_features` is one row per claim with the `days_to_rtw` label (closed claims only); `gold.fraud_features` is one row per claim with the `is_fraud` label on the labeled SIU subset only.
- `gold.fraud_scores` is the Model Serving output that drives the triage queue (`fraud_risk_score`, `risk_tier`, `top_contributing_factor`).
- The **same claim IDs flow through every layer** (e.g., follow `CLM-00002` from dirty Bronze → masked Silver → engineered Gold → fraud score). Preserve that end-to-end traceability when adding rows or columns.

## Environment & Configuration

- **Catalog/paths**: never hard-code; parameterize the catalog (`state_fund_poc`), schema, and ADLS paths through Databricks widgets or job parameters. Keep notebooks idempotent and re-runnable.
- **Storage**: POC data lives in a **dedicated ADLS Gen2 account**, registered as a Unity Catalog **External Location** with a storage credential / managed identity — kept separate from the metastore's default (root) storage.
- **Secrets**: use **Databricks secret scopes** (or Azure Key Vault-backed scopes). Never inline connection strings, keys, or tokens in notebooks or code.
- **GCC vs Commercial**: this plan assumes Azure Commercial. Genie, Vector Search, and Model Serving may have limited availability in Azure Government — confirm before building and flag any MAG requirement.

## Conventions

### Medallion & pipeline patterns

- **Respect the layering.** Never read raw source straight into Gold; data must pass Bronze → Silver → Gold. Bronze is raw/append-only; Silver is cleansed/conformed/masked; Gold is curated features and aggregates.
- **Idempotent & deterministic.** Use Delta `MERGE`/upsert for Silver and Gold; avoid blind appends that break re-runs.
- **Explicit schemas.** Declare schemas (`StructType` / DDL) for production paths instead of relying on inference. Cast numerics and parse all dates to ISO `DATE`/`TIMESTAMP` in Silver.
- **Data quality at the Bronze→Silver boundary** via DLT Expectations — e.g. `EXPECT (claim_id IS NOT NULL) ON VIOLATION FAIL UPDATE`, `EXPECT (claim_amount > 0) ON VIOLATION DROP ROW`, warn-only length checks tracked as quality %. Surface Expectation pass rates as a Gold quality view.
- **PII governance.** Mask structured PII (SSN, DOB) with Unity Catalog **column-masking functions** defined once in the `security` schema; apply **row filters** (e.g. by region); redact unstructured PII in notes via `ai_query`/Presidio. Validate masking by querying as an analyst vs. a `pii_authorized` member.
- **AI Functions.** Use `ai_extract` / `ai_classify` on adjuster notes to produce structured fraud/severity signals that feed `gold.fraud_features` and `gold.rtw_features`.
- **Databricks App.** The fraud triage UI is a **Streamlit** app deployed as a Databricks App. It reads `gold.fraud_scores` (never raw/PII tables), runs under the app's service principal subject to Unity Catalog grants, and uses `app.yaml` (`command: streamlit run app.py`) with `streamlit` + `databricks-sdk` pinned in `requirements.txt`.

### Coding style

- **Languages**: Python (PySpark) and Spark SQL. Prefer the PySpark DataFrame API; use Spark SQL where it improves clarity. Follow the layer-specific guidance in [.github/instructions/pyspark.instructions.md](.github/instructions/pyspark.instructions.md) and [.github/instructions/sql.instructions.md](.github/instructions/sql.instructions.md).
- **Naming**: three-level Unity Catalog namespace `catalog.schema.table` (`state_fund_poc.silver.claims`); `snake_case` for tables, columns, and Python identifiers; Bronze tables prefixed `raw_`.
- **Models**: register to Unity Catalog (`state_fund_poc.ml.rtw_model`, `state_fund_poc.ml.fraud_model`); track with MLflow. Evaluate RTW regression on RMSE/MAE and fraud classification on **PR-AUC** (accuracy is misleading on the ~8–12% imbalanced fraud labels).

### Synthetic data

- All data is **fully synthetic** — never use real claimant data. Generate with **Python (pandas/Faker)**, seed the RNG for reproducibility, and commit the generator scripts under `data/` so they can be regenerated/extended.
- Maintain referential integrity across the five source files, then deliberately inject a small share (~2–5%) of dirty patterns (mixed date formats, casing/whitespace, placeholder nulls, invalid SSNs, duplicate `claim_id`, orphan FKs, embedded fake PII in notes) so cleaning and governance demos have something to do.

### Authoring & docs

- **Pause for tradeoffs.** When multiple valid approaches exist (e.g., Model Serving endpoint vs. batch scoring, regression vs. secondary classification for RTW), present options with pros/cons before committing.
- **Audience**: assume familiarity with SQL/data concepts but explain Databricks-specific features (DLT, Unity Catalog, AutoML, Genie) — the "why" as well as the "what."
- Keep `session-N/` folders **self-contained and ordered**; later sessions build on earlier catalogs/tables.
- **Cite verified docs for every step.** Every step in a session's instructions (`session-N/README.md`, `docs/session-N.md`, and `DEPLOYMENT_GUIDE.md`) must link to the **official Microsoft Learn / Databricks documentation** that documents how to complete that step. Use real, verified documentation pages — never invent or guess URLs — so each instruction is backed by an authoritative source.
- **Architecture diagrams.** Author diagrams as `.drawio` sources under `docs/diagrams/` (with exported `.svg`/`.png`) using official Azure/Databricks icons, and reference the exported image — not the `.drawio` — in Markdown. Follow [.github/instructions/diagrams.instructions.md](instructions/diagrams.instructions.md).
- **Keep docs in sync.** Every session change must be reflected in that session's `session-N/README.md`, the published `docs/session-N.md` page, and the `DEPLOYMENT_GUIDE.md` walkthrough.
- **Verify volatile docs links.** Databricks restructures URLs (e.g., the Lakeflow rebrand); if a link 404s, search the feature name at [docs.databricks.com](https://docs.databricks.com).
