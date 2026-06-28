# State Fund Lane 1 POC — Azure Databricks Medallion Lakehouse

An end-to-end, **hands-on tutorial** that builds a medallion (Bronze → Silver → Gold) lakehouse on **Azure Databricks Serverless** for the California State Fund, delivering two machine-learning use cases on synthetic workers'-compensation data:

- **Return-to-Work (RTW) duration prediction** — regression on `days_to_rtw` so case managers can intervene earlier.
- **Claims fraud investigation triage** — classification producing a `fraud_risk_score` that ranks open claims for SIU review.

> All data is **synthetic**. All compute is **serverless**. Fraud is framed as **investigation triage acceleration**, never automated fraud detection.

## About this tutorial

The build is split into ordered **sessions**, each a self-contained stage in its own `session-N/` folder. Work them in order — each depends on the catalog, schemas, and tables created earlier.

- **Start here:** [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) — the full guided, step-by-step walkthrough.
- **Published site:** the `docs/` folder builds a GitHub Pages version of this tutorial.

## Session structure

| Session | Focus | Key outputs |
| --- | --- | --- |
| **0 — Setup** | Workspace, Unity Catalog metastore, serverless enablement, dedicated ADLS Gen2 External Location, access | Working serverless workspace |
| **1 — Bronze** | Catalog/schemas; Auto Loader DLT (CSV/JSON) + Excel ingest | `bronze.raw_*` tables |
| **2 — Silver** | Cleaning, DLT Expectations, PII masking, AI Functions on adjuster notes | governed `silver.*` |
| **3 — Gold** | Feature tables, BI aggregates, lineage, Genie, AI/BI dashboard | ML-ready `gold.*` + self-service BI |
| **4 — ML** | AutoML (RTW regression + fraud classification), MLflow, register to UC | `ml.rtw_model`, `ml.fraud_model` |
| **5 — Serving** | Batch scoring, Streamlit triage app, Vector Search, Workflow, governance | live app + automated pipeline |

## Architecture

The POC is an end-to-end medallion lakehouse. Synthetic source files land in a dedicated ADLS Gen2 account (registered as a Unity Catalog **External Location**), and flow Bronze → Silver → Gold, then into ML, serving, and governance — all on serverless compute.

![Medallion architecture — Sources → Bronze → Silver → Gold → ML / Serving / BI, governed by Unity Catalog](docs/diagrams/medallion-architecture.svg)

A single Unity Catalog catalog, **`state_fund_poc`**, holds six schemas:

| Schema | Contents |
| --- | --- |
| `bronze` | `raw_claims`, `raw_hr_records`, `raw_medical_treatments`, `raw_provider_billing`, `raw_adjuster_notes`, `raw_siu_labels` |
| `silver` | `claims`, `employees`, `treatments`, `rtw_timeline`, `provider_billing`, `adjuster_notes` |
| `gold` | `rtw_features`, `rtw_outcomes_summary`, `fraud_features`, `fraud_scores`, `rtw_predictions`, `data_quality` (view), `claim_notes` |
| `ml` | Registered models: `rtw_model`, `fraud_model` |
| `config` | Pipeline/config tables and reference data |
| `security` | Masking functions and row-filter functions |

`silver.claims` is the hub; every spoke joins on `claim_id`. See the [Azure Databricks documentation](https://learn.microsoft.com/azure/databricks/) for platform concepts.

## Quick start

### 1. Generate the synthetic source data (local)

The six source files are produced by a seeded Python generator. Use a project virtual environment so dependencies stay isolated.

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

This writes `claims_core.csv`, `hr_records.csv`, `medical_treatments.json`, `provider_billing.json`, `adjuster_notes.xlsx`, and `siu_labels.csv` into `data/`. The files are committed to the repo, so this step is only needed to regenerate or resize the dataset.

> **Understand the data first.** See [data/README.md](data/README.md) for the source-file overview and [docs/data-dictionary.md](docs/data-dictionary.md) for the full Bronze → Silver → Gold data dictionary and ERD.

### 2. Build the lakehouse

Follow [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) starting with **Session 0** to stand up the workspace, then upload the generated files to the ADLS Gen2 External Location to trigger the Bronze pipelines, and continue through Session 5.

## Repository layout

```
session-0-setup/ … session-5-serving/   Ordered, self-contained build stages
common/                                  Shared config helpers (catalog/schema/paths)
data/                                    Synthetic source files + generator
docs/                                    Jekyll GitHub Pages tutorial site
DEPLOYMENT_GUIDE.md                      Full guided walkthrough
```

Repo-wide conventions live in [.github/copilot-instructions.md](.github/copilot-instructions.md).
