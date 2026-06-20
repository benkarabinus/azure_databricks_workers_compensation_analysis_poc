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

### Session 0 — Kickoff & Environment Readiness

**Goal:** Stand up the Azure Databricks account, workspace, and Unity Catalog metastore; enable serverless; provision a **dedicated ADLS Gen2 account** registered as a Unity Catalog External Location (separate from the metastore root); and assign Entra ID groups and UC grants.

**Output:** A working serverless workspace with the External Location and access in place.

_Detailed steps: coming soon (see `session-0-setup/`)._

### Session 1 — Foundations & Bronze Ingestion

**Goal:** Create the catalog and schemas, then land all six sources append-only via Auto Loader (CSV/JSON) and an Excel ingest notebook.

**Output:** `bronze.raw_*` tables carrying `_source_file` / `_ingested_at`.

_Detailed steps: coming soon (see `session-1-bronze/`)._

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
